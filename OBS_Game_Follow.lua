-- OBS GameFlow v1.0.0
-- Pure OBS LuaJIT script: Windows foreground -> Discord/SRM games -> one Game Capture.
-- Optional EXE allowlist -> one reusable Window Capture, without restarting Replay Buffer.
-- No Python process, no WebSocket, no native DLL to install.
-- Configure capture sources before enabling Auto-switch games.

local obs = obslua
local ffi_ok, ffi = pcall(require, "ffi")
local user32, kernel32
local win32_error = nil

if ffi_ok then
    local ok, err = pcall(function()
        ffi.cdef[[
            void* GetForegroundWindow(void);
            unsigned long GetWindowThreadProcessId(void* hwnd, unsigned long* pid);
            int GetWindowTextW(void* hwnd, uint16_t* text, int max_count);
            int GetClassNameW(void* hwnd, uint16_t* text, int max_count);
            void* OpenProcess(unsigned long access, int inherit, unsigned long pid);
            int QueryFullProcessImageNameW(void* process, unsigned long flags,
                uint16_t* path, unsigned long* count);
            int CloseHandle(void* handle);
            void* CreateToolhelp32Snapshot(unsigned long flags, unsigned long pid);
            typedef struct {
                unsigned long dwSize, cntUsage, th32ProcessID;
                uintptr_t th32DefaultHeapID;
                unsigned long th32ModuleID, cntThreads, th32ParentProcessID;
                long pcPriClassBase;
                unsigned long dwFlags;
                uint16_t szExeFile[260];
            } OGF_PROCESSENTRY32W;
            int Process32FirstW(void* snapshot, OGF_PROCESSENTRY32W* entry);
            int Process32NextW(void* snapshot, OGF_PROCESSENTRY32W* entry);
            unsigned long GetLastError(void);
            void* GetTopWindow(void* hwnd);
            void* GetWindow(void* hwnd, unsigned int command);
            int IsWindowVisible(void* hwnd);
            int WideCharToMultiByte(unsigned int cp, unsigned long flags,
                const uint16_t* wide, int wide_len, char* out, int out_size,
                const char* default_char, int* used_default);
        ]]
        user32 = ffi.load("user32")
        kernel32 = ffi.load("kernel32")
    end)
    if not ok then win32_error = tostring(err) end
else
    win32_error = "LuaJIT FFI is unavailable"
end

-- Presentation only: stored names, capture rules and replay control are unchanged.
local ui_language = "auto"
local ui_show_advanced, ui_show_diagnostics = false, false

local function english_ui()
    if ui_language == "en-US" then return true end
    if ui_language == "zh-CN" then return false end
    local locale = "en-US"
    if obs.obs_get_locale then
        local ok, value = pcall(obs.obs_get_locale)
        if ok and type(value) == "string" then locale = value end
    end
    return not locale:lower():match("^zh")
end

local function tr(zh, en)
    return english_ui() and en or zh
end

local message_text = {
    ["尚未识别"] = {"等待识别", "Waiting for a game"},
    ["尚未设置捕获目标"] = {"未设置", "Not set"},
    ["无"] = {"无", "None"},
    ["未启用"] = {"未启用", "Disabled"},
    ["等待初始化"] = {"等待初始化", "Starting up"},
    ["未配置"] = {"未配置", "Not configured"},
    ["等待扫描"] = {"等待扫描", "Waiting for scan"},
    ["未选择场景或窗口采集源"] = {"请选择场景和窗口采集源", "Select a scene and a Window Capture source"},
    ["所选目标不是场景"] = {"请选择场景", "Select a scene"},
    ["选中的源不是窗口采集"] = {"请选择窗口采集源", "Select a Window Capture source"},
    ["正在显示客户端窗口采集"] = {"显示", "Visible"},
    ["已隐藏客户端窗口采集"] = {"隐藏", "Hidden"},
    ["no foreground window"] = {"无前台窗口", "No foreground window"},
    ["no process"] = {"无进程信息", "No process information"},
    ["process access denied"] = {"无权读取进程", "Process access denied"},
    ["process path unavailable"] = {"无法读取进程路径", "Process path unavailable"},
    ["LuaJIT FFI is unavailable"] = {"LuaJIT FFI 不可用", "LuaJIT FFI is unavailable"},
    ["Discord JSON could not be parsed"] = {"无法读取 Discord 游戏库", "Could not parse the Discord game database"},
    ["no-executable"] = {"无进程信息", "No executable"},
    ["excluded"] = {"已忽略", "Excluded"},
    ["unknown"] = {"未识别", "Not recognized"},
    ["source properties missing"] = {"无法读取源属性", "Source properties unavailable"},
    ["window property missing"] = {"无法读取窗口列表", "Window list unavailable"},
    ["not present in OBS capture window list"] = {"窗口尚未出现在 OBS 列表中", "Window not yet listed by OBS"},
    ["ambiguous capture windows"] = {"找到多个匹配窗口", "Multiple matching windows"},
    ["selected source is not Game Capture"] = {"请选择游戏采集源", "Select a Game Capture source"},
    ["settings unavailable"] = {"无法读取源设置", "Source settings unavailable"},
    ["窗口采集设置不可用"] = {"无法读取窗口采集设置", "Window Capture settings unavailable"},
    ["process snapshot unavailable"] = {"无法读取进程列表", "Process list unavailable"},
    ["请配置显示器采集源并加入场景（多个源时需指定）"] = {"请选择显示器采集源，并加入当前场景", "Select a Display Capture source and add it to the current scene"},
    ["已隐藏"] = {"已隐藏", "Hidden"},
    ["运行中"] = {"开启", "On"},
    ["已停止"] = {"关闭", "Off"},
    ["已请求启动（需在 OBS 启用回放缓存）"] = {"正在开启，请确认 OBS 已启用回放缓存", "Starting; check that Replay Buffer is enabled in OBS"},
    ["已请求停止"] = {"正在关闭", "Stopping"},
    ["无游戏，等待 5 秒确认"] = {"无游戏，等待退出确认", "No game; waiting for exit confirmation"},
    ["无游戏运行"] = {"无游戏", "No game"},
    ["自动回放已关闭（手动控制）"] = {"手动控制", "Manual control"},
    ["只读检查已完成；可点击“刷新状态”查看结果。"] = {"检查完成，点击“刷新”查看结果", "Check complete. Select Refresh to view the result."},
    ["将在 3 秒后只读检查前台窗口，请立即切回游戏。"] = {"3 秒后检查前台窗口，请切回游戏", "Checking the foreground window in 3 seconds. Switch to your game."},
    ["Inspection-only mode. No OBS inputs will be changed."] = {"自动切换已关闭", "Game switching is off"},
    ["Replay Buffer: start"] = {"回放缓存：请求开启", "Replay buffer: start requested"},
    ["Replay Buffer: stop"] = {"回放缓存：请求关闭", "Replay buffer: stop requested"},
    ["英雄联盟"] = {"英雄联盟", "League of Legends"},
    ["英雄联盟客户端"] = {"英雄联盟客户端", "League client"},
 }
local message_prefix = {
    {"找不到场景：", "找不到场景：", "Scene not found: "},
    {"Discord database unavailable: ", "无法读取 Discord 游戏库：", "Discord database unavailable: "},
    {"SRM file unavailable: ", "无法读取 SRM 文件：", "SRM file unavailable: "},
    {"Ignored invalid client EXE rule: ", "已忽略无效客户端规则：", "Ignored invalid client rule: "},
    {"Foreground unavailable: ", "无法读取前台窗口：", "Foreground window unavailable: "},
    {"前台读取失败：", "无法读取前台窗口：", "Foreground window unavailable: "},
    {"客户端窗口已匹配：", "客户端：", "Client: "},
    {"配置异常：", "请检查设置：", "Check settings: "},
    {"窗口目标定位失败：", "无法匹配窗口：", "Window unavailable: "},
    {"只读检查：识别到名单中的客户端 ", "识别到客户端：", "Client detected: "},
    {"目标定位失败：", "无法匹配采集目标：", "Capture target unavailable: "},
    {"只读检查通过：", "检查通过：", "Check passed: "},
    {"已设为：", "采集：", "Capture: "},
    {"已保持：", "采集：", "Capture: "},
    {"已保持目标：", "采集：", "Capture: "},
    {"Game Capture source not found: ", "找不到游戏采集源：", "Game Capture source not found: "},
    {"incomplete process snapshot: ", "进程扫描未完成：", "Incomplete process scan: "},
    {"扫描失败：", "扫描失败：", "Scan failed: "},
    {"显示：", "显示：", "Visible: "},
    {"Automatic following ENABLED; target source: ", "自动切换已开启，采集源：", "Game switching enabled; source: "},
 }

local function display_text(value)
    local raw = tostring(value or "")
    local pair = message_text[raw]
    if pair then return tr(pair[1], pair[2]) end
    for _, item in ipairs(message_prefix) do
        if raw:sub(1, #item[1]) == item[1] then
            return tr(item[2], item[3]) .. display_text(raw:sub(#item[1] + 1))
        end
    end
    local source, scene = raw:match('^请将“(.-)”直接加入“(.-)”场景$')
    if source then return string.format(tr('将“%s”加入“%s”场景', 'Add "%s" directly to scene "%s"'), source, scene) end
    local games, records, mappings, ignored, clients, ffi_state = raw:match(
        '^Ready: Discord (%d+) games / (%d+) EXE records, SRM (%d+) mappings / (%d+) ignored, clients (%d+), FFI (.*)$')
    if games then
        return string.format(tr('数据库已加载：Discord %s 个游戏 / %s 条进程，SRM %s 条规则 / %s 条忽略，客户端 %s，FFI %s',
            'Databases loaded: Discord %s games / %s executables; SRM %s rules / %s exclusions; clients: %s; FFI %s'),
            games, records, mappings, ignored, clients, ffi_state)
    end
    local path, reason = raw:match('^Skipped (.-) %((.-)%)$')
    if path then return string.format(tr('已忽略 %s（%s）', 'Skipped %s (%s)'), path, display_text(reason)) end
    local detected, rest = raw:match('^Detected %[(.-)%] (.*)$')
    if detected then return string.format(tr('已识别 [%s] %s', 'Detected [%s] %s'), detected, display_text(rest)) end
    local exe, why = raw:match('^(.-) %(([^()]*)%)$')
    if exe and message_text[why] then return exe .. ' (' .. display_text(why) .. ')' end
    raw = raw:gsub('%[would switch%]', tr('[可切换]', '[would switch]'))
        :gsub('%[switched%]', tr('[已切换]', '[switched]'))
        :gsub('%[unchanged%]', tr('[未变]', '[unchanged]'))
    return raw
end

local function update_ui_settings(settings)
    ui_language = obs.obs_data_get_string(settings, "ui_language")
    if ui_language ~= "zh-CN" and ui_language ~= "en-US" then ui_language = "auto" end
    ui_show_advanced = obs.obs_data_get_bool(settings, "ui_show_advanced")
    ui_show_diagnostics = obs.obs_data_get_bool(settings, "ui_show_diagnostics")
end

local function log(level, message)
    if obs and obs.script_log then
        obs.script_log(level or obs.LOG_INFO, "[OBS GameFlow] " .. display_text(message))
    else
        print("[OBS GameFlow] " .. display_text(message))
    end
end

local function folder_of_script()
    if type(script_path) == "function" then
        local folder = script_path()
        if type(folder) == "string" and folder ~= "" then
            if folder:lower():match("%.lua$") then
                return folder:match("^(.*)[/\\][^/\\]+$") or "."
            end
            return folder
        end
    end
    return "."
end

local function join_path(folder, name)
    local tail = folder:sub(-1)
    if tail == "\\" or tail == "/" then return folder .. name end
    return folder .. "\\" .. name
end

local function read_text(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local text = f:read("*a")
    f:close()
    if text and text:sub(1, 3) == "\239\187\191" then
        text = text:sub(4)
    end
    return text
end

local function normalized_path(path)
    return tostring(path or ""):gsub("\\", "/"):lower()
end

local function basename_no_ext(path)
    local name = normalized_path(path):match("([^/]+)$") or ""
    return (name:gsub("%.exe$", ""))
end

local function utf8_wide(wide)
    if not kernel32 then return "" end
    local n = kernel32.WideCharToMultiByte(65001, 0, wide, -1, nil, 0, nil, nil)
    if n <= 0 or n > 65536 then return "" end
    local out = ffi.new("char[?]", n)
    if kernel32.WideCharToMultiByte(65001, 0, wide, -1, out, n, nil, nil) <= 0 then
        return ""
    end
    return ffi.string(out)
end

local function foreground_window()
    if not user32 or not kernel32 then return nil, win32_error end
    local hwnd = user32.GetForegroundWindow()
    if hwnd == nil or hwnd == ffi.NULL then return nil, "no foreground window" end
    local pid = ffi.new("unsigned long[1]", 0)
    user32.GetWindowThreadProcessId(hwnd, pid)
    if pid[0] == 0 then return nil, "no process" end

    -- PROCESS_QUERY_LIMITED_INFORMATION, no injection or memory reading.
    local process = kernel32.OpenProcess(0x1000, 0, pid[0])
    if process == nil or process == ffi.NULL then return nil, "process access denied" end
    local image = ffi.new("uint16_t[?]", 32768)
    local image_len = ffi.new("unsigned long[1]", 32768)
    local queried = kernel32.QueryFullProcessImageNameW(process, 0, image, image_len)
    kernel32.CloseHandle(process)
    if queried == 0 then return nil, "process path unavailable" end

    local title = ffi.new("uint16_t[?]", 4096)
    local class = ffi.new("uint16_t[?]", 512)
    user32.GetWindowTextW(hwnd, title, 4096)
    user32.GetClassNameW(hwnd, class, 512)
    return {
        path = utf8_wide(image),
        title = utf8_wide(title),
        class = utf8_wide(class),
        pid = tonumber(pid[0]),
    }
end

local BLOCKED = {}
for item in ([[
explorer obs64 obs32 obs chrome msedge firefox discord steam steamwebhelper
epicgameslauncher bsglauncher taskmgr cmd powershell pwsh conhost
applicationframehost shellexperiencehost searchhost notepad code devenv
excel winword powerpnt outlook onenote runtimebroker systemsettings
startmenuexperiencehost ctfmon dwm
leagueclient leagueclientux leagueclientuxrender riotclientservices
riotclientux riotclientuxrender leaguecrashhandler64 wegame
]]):gmatch("%S+") do BLOCKED[item] = true end

local GENERIC = {}
for item in ([[
game launcher start client app program main shipping win64-shipping
unity unityplayer java javaw python pythonw hl2 data setup update updater
crashreporter bootstrap bootstrapper helper
]]):gmatch("%S+") do GENERIC[item] = true end

local discord = {}
local srm = {}
local ignored = {}
local overrides = {}
local source_name = "游戏采集"
local discord_file = join_path(folder_of_script(), "discord_games.json")
local srm_file = [[D:\Portable\OBS Addons\Smart_Replay_Mover\Smart_Replay_Mover.lua]]
local override_text = ""
local enabled = false
local interval_ms = 1000
local debug_log = false
local loaded = false
local current_paths = ""
local last_status = ""
local last_target = ""
-- UI status is diagnostic only: it never proves that frames were captured.
-- Preserve the last recognized game while OBS itself is in the foreground.
local status_game = "尚未识别"
local status_capture = "尚未设置捕获目标"
local status_switched = "无"
local status_ignored = "无"
local lol_client_enabled = false
local lol_scene_name = "游戏"
local lol_source_name = ""
local lol_original_visibility = nil
local status_lol = "未启用"
local client_rules_text = "LeagueClientUx.exe=英雄联盟客户端"
local window_clients = {}
local record_desktop = false
local auto_replay = false
local desktop_source_name = ""
local tracked_games = {}
local recent_order = 0
local no_game_since = nil
local replay_pending, replay_requested_at = nil, 0
local status_replay = "等待初始化"
local status_desktop = "未配置"
local status_running = "等待扫描"

local function status_description()
    return display_text(status_capture)
        .. "\n" .. tr("客户端：", "Client: ") .. display_text(status_lol)
        .. "\n" .. tr("最近切换：", "Last switch: ") .. display_text(status_switched)
        .. "\n" .. tr("最近忽略：", "Last skipped: ") .. display_text(status_ignored)
        .. "\n" .. tr("运行进程：", "Running processes: ") .. display_text(status_running)
        .. "\n" .. tr("桌面采集：", "Desktop capture: ") .. display_text(status_desktop)
        .. "\n" .. tr("回放详情：", "Replay details: ") .. display_text(status_replay)
end

local function summary_description()
    local capture = tr("等待识别", "Waiting for a game")
    if status_game == "无游戏运行" then
        capture = status_desktop:sub(1, #"显示：") == "显示："
            and tr("桌面", "Desktop") or tr("无", "None")
    elseif status_game ~= "尚未识别" then
        capture = display_text(status_game:match("^(.-) / ") or status_game)
        if status_capture:sub(1, #"目标定位失败：") == "目标定位失败：" then
            capture = tr("等待采集：", "Waiting for capture: ") .. capture
        end
    end
    local state = "—"
    if obs.obs_frontend_replay_buffer_active then
        local ok, active = pcall(obs.obs_frontend_replay_buffer_active)
        if ok then state = active and tr("开启", "On") or tr("关闭", "Off") end
    end
    return tr("当前采集：", "Current capture: ") .. capture
        .. "\n" .. tr("回放状态：", "Replay buffer: ") .. state
end

-- Only modify the selected Window Capture scene item. Never touch recording,
-- replay-buffer state, other scenes or the selected Game Capture source.
local function lol_scene_item(scene_name, client_name)
    if scene_name == "" or client_name == "" then return nil, nil, "未选择场景或窗口采集源" end
    local scene_source = obs.obs_get_source_by_name(scene_name)
    if not scene_source then return nil, nil, "找不到场景：" .. scene_name end
    if obs.obs_source_get_id(scene_source) ~= "scene" then
        obs.obs_source_release(scene_source)
        return nil, nil, "所选目标不是场景"
    end
    local scene = obs.obs_scene_from_source(scene_source)
    local item = scene and obs.obs_scene_find_source(scene, client_name)
    if not item then
        obs.obs_source_release(scene_source)
        return nil, nil, "请将“" .. client_name .. "”直接加入“" .. scene_name .. "”场景"
    end
    local client_source = obs.obs_sceneitem_get_source(item)
    if not client_source or obs.obs_source_get_id(client_source) ~= "window_capture" then
        obs.obs_source_release(scene_source)
        return nil, nil, "选中的源不是窗口采集"
    end
    return item, scene_source
end

local function restore_lol_visibility()
    local original = lol_original_visibility
    lol_original_visibility = nil
    if not original then return end
    local item, scene_source = lol_scene_item(original.scene, original.source)
    if not item then return end
    if obs.obs_sceneitem_visible(item) ~= original.visible then
        obs.obs_sceneitem_set_visible(item, original.visible)
    end
    obs.obs_source_release(scene_source)
end

local function set_lol_visible(visible)
    local item, scene_source, err = lol_scene_item(lol_scene_name, lol_source_name)
    if not item then return false, err end
    local was_visible = obs.obs_sceneitem_visible(item)
    if not lol_original_visibility then
        lol_original_visibility = {
            scene = lol_scene_name, source = lol_source_name, visible = was_visible
        }
    end
    local changed = was_visible ~= visible
    if changed then obs.obs_sceneitem_set_visible(item, visible) end
    obs.obs_source_release(scene_source)
    status_lol = visible and "正在显示客户端窗口采集" or "已隐藏客户端窗口采集"
    return true, changed
end

local function add_discord(exe, name, pattern)
    local key = basename_no_ext(exe)
    if key == "" then return end
    local list = discord[key]
    if not list then
        list = {}
        discord[key] = list
    end
    list[#list + 1] = { name = name, pattern = pattern }
end

local function load_discord()
    discord = {}
    local text, err = read_text(discord_file)
    if not text then
        log(obs.LOG_WARNING, "Discord database unavailable: " .. tostring(err))
        return 0, 0
    end
    -- OBS data JSON parser requires an object root, so wrap the cached array.
    local root = obs.obs_data_create_from_json('{"apps":' .. text .. '}')
    if not root then
        log(obs.LOG_WARNING, "Discord JSON could not be parsed")
        return 0, 0
    end
    local apps = obs.obs_data_get_array(root, "apps")
    local count, records = 0, 0
    if apps then
        for i = 0, obs.obs_data_array_count(apps) - 1 do
            local app = obs.obs_data_array_item(apps, i)
            if app then
                local name = obs.obs_data_get_string(app, "name")
                local exes = obs.obs_data_get_array(app, "executables")
                if name ~= "" and exes then
                    local matched = false
                    for j = 0, obs.obs_data_array_count(exes) - 1 do
                        local exe = obs.obs_data_array_item(exes, j)
                        if exe then
                            local pattern = normalized_path(obs.obs_data_get_string(exe, "name"))
                            local os_name = obs.obs_data_get_string(exe, "os")
                            local is_launcher = obs.obs_data_get_bool(exe, "is_launcher")
                            if pattern:match("%.exe$") and not is_launcher
                                and (os_name == "" or os_name == "win32" or os_name == "windows") then
                                add_discord(pattern, name, pattern)
                                records = records + 1
                                matched = true
                            end
                            obs.obs_data_release(exe)
                        end
                    end
                    if matched then count = count + 1 end
                end
                if exes then obs.obs_data_array_release(exes) end
                obs.obs_data_release(app)
            end
        end
        obs.obs_data_array_release(apps)
    end
    obs.obs_data_release(root)
    return count, records
end

local function load_srm()
    srm, ignored = {}, {}
    local text, err = read_text(srm_file)
    if not text then
        log(obs.LOG_WARNING, "SRM file unavailable: " .. tostring(err))
        return 0, 0
    end
    local db = text:match("local%s+GAME_DATABASE%s*=%s*%{(.-)\r?\n%}")
    local ignore = text:match("local%s+IGNORE_LIST%s*=%s*%{(.-)\r?\n%}")
    local mappings, exclusions = 0, 0
    if db then
        for line in db:gmatch("[^\r\n]+") do
            -- SRM's database is a literal table; do not execute its code.
            local key, name = line:match('^%s*%["([^"]+)"%]%s*=%s*"([^"]+)"')
            if key and name then
                local base = basename_no_ext(key)
                if base ~= "" then
                    srm[base] = name
                    mappings = mappings + 1
                end
            end
        end
    end
    if ignore then
        ignore = ignore:gsub("%-%-[^\r\n]*", "")
        for key in ignore:gmatch('"([^"]+)"') do
            local base = basename_no_ext(key)
            if base ~= "" then
                ignored[base] = true
                exclusions = exclusions + 1
            end
        end
    end
    return mappings, exclusions
end

local function load_manual_rules()
    overrides = {}
    for line in (override_text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        local key, name = line:match("^%s*(.-)%s*=%s*(.-)%s*$")
        if key and name and name ~= "" and not key:match("^#") then
            overrides[normalized_path(key)] = name
        end
    end
end

local function load_window_client_rules()
    window_clients = {}
    local count = 0
    for line in (client_rules_text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
            local exe, label = trimmed:match("^([^=]+)=(.*)$")
            if not exe then exe, label = trimmed, "" end
            exe = exe:match("^%s*(.-)%s*$"):lower()
            label = label:match("^%s*(.-)%s*$")
            if exe:match("%.exe$") and not exe:find("/", 1, true)
                and not exe:find("\\", 1, true) then
                local base = basename_no_ext(exe)
                if window_clients[base] == nil then count = count + 1 end
                window_clients[base] = label ~= "" and label or base
            else
                log(obs.LOG_WARNING, "Ignored invalid client EXE rule: " .. trimmed)
            end
        end
    end
    return count
end

local function load_databases()
    local games, records = load_discord()
    local mappings, excludes = load_srm()
    load_manual_rules()
    local client_count = load_window_client_rules()
    log(obs.LOG_INFO, string.format(
        "Ready: Discord %d games / %d EXE records, SRM %d mappings / %d ignored, clients %d, FFI %s",
        games, records, mappings, excludes, client_count, user32 and "OK" or tostring(win32_error)))
    loaded = true
end

local function one_name(list, predicate)
    if not list then return nil end
    local unique = nil
    for _, item in ipairs(list) do
        if predicate(item) then
            if unique and unique ~= item.name then return nil end
            unique = item.name
        end
    end
    return unique
end

local function game_for_window(w)
    local path = normalized_path(w.path)
    local base = basename_no_ext(path)
    if base == "" then return nil, "no-executable" end
    if overrides[path] then return overrides[path], "manual-path" end
    if overrides[base] then return overrides[base], "manual-exe" end
    if overrides[base .. ".exe"] then return overrides[base .. ".exe"], "manual-exe" end
    if BLOCKED[base] or ignored[base] then return nil, "excluded" end
    -- Reliable fallback for the actual LoL match executable, independent of
    -- whether Discord/SRM currently knows this particular installation.
    if base == "league of legends" then return "英雄联盟", "lol-game" end
    local candidates = discord[base]

    -- Most accurate: exact Discord executable suffix incl. directory.
    local exact = one_name(candidates, function(item)
        local pattern = item.pattern
        return pattern:find("/", 1, true)
           and path:sub(-#pattern - 1) == "/" .. pattern
    end)
    if exact then return exact, "discord-path" end

    if not GENERIC[base] then
        local simple = one_name(candidates, function(item)
            return not item.pattern:find("/", 1, true)
        end)
        if simple then return simple, "discord-exe" end
        local contextual = one_name(candidates, function(item)
            local name = item.name:lower()
            return path:find(name, 1, true)
                or normalized_path(w.title):find(name, 1, true)
        end)
        if contextual then return contextual, "discord-context" end
        if srm[base] then return srm[base], "srm" end
    end
    return nil, "unknown"
end

local function capture_option(source, window)
    local props = obs.obs_source_properties(source)
    if not props then return nil, "source properties missing" end
    local p = obs.obs_properties_get(props, "window")
    if not p then
        obs.obs_properties_destroy(props)
        return nil, "window property missing"
    end
    local exe = (normalized_path(window.path):match("([^/]+)$") or "")
    local exact, single, matches = nil, nil, 0
    for i = 0, obs.obs_property_list_item_count(p) - 1 do
        local value = obs.obs_property_list_item_string(p, i)
        if type(value) == "string" and value:lower():sub(-#exe - 1) == ":" .. exe then
            matches = matches + 1
            single = value
            local title, class = value:match("^(.*):([^:]*):[^:]*$")
            if title == window.title and class == window.class then
                exact = value
                break
            end
        end
    end
    obs.obs_properties_destroy(props)
    if exact then return exact end
    if matches == 1 then return single end
    return nil, matches == 0 and "not present in OBS capture window list"
        or "ambiguous capture windows"
end

local function update_capture(window, game_name, apply)
    local source = obs.obs_get_source_by_name(source_name)
    if not source then return false, "Game Capture source not found: " .. source_name end
    local kind = obs.obs_source_get_id(source)
    if kind ~= "game_capture" then
        obs.obs_source_release(source)
        return false, "selected source is not Game Capture"
    end
    local target, reason = capture_option(source, window)
    if not target then
        obs.obs_source_release(source)
        return false, reason
    end
    local settings = obs.obs_source_get_settings(source)
    if not settings then
        obs.obs_source_release(source)
        return false, "settings unavailable"
    end
    local prev_mode = obs.obs_data_get_string(settings, "capture_mode")
    local prev_target = obs.obs_data_get_string(settings, "window")
    local prev_priority = obs.obs_data_get_int(settings, "priority")
    local changed = prev_mode ~= "window" or prev_target ~= target or prev_priority ~= 2
    if changed and apply then
        obs.obs_data_set_string(settings, "capture_mode", "window")
        obs.obs_data_set_string(settings, "window", target)
        obs.obs_data_set_int(settings, "priority", 2)
        obs.obs_source_update(source, settings)
        last_target = target
    end
    obs.obs_data_release(settings)
    obs.obs_source_release(source)
    return true, string.format("%s: %s -> %s%s", game_name, window.path,
        target, changed and (apply and " [switched]" or " [would switch]") or " [unchanged]")
end

-- Retarget the one selected Window Capture source to whichever allowlisted
-- client is foreground. Retain its capture method, size and other settings.
local function update_client_window(window, apply)
    local item, holder, err = lol_scene_item(lol_scene_name, lol_source_name)
    if not item then return false, err end
    local source = obs.obs_sceneitem_get_source(item)
    local target, reason = capture_option(source, window)
    local settings = obs.obs_source_get_settings(source)
    if not settings then
        obs.obs_source_release(holder)
        return false, "窗口采集设置不可用"
    end
    local previous = obs.obs_data_get_string(settings, "window")
    if not target then
        -- If the existing target is already this EXE, keep the working value
        -- when OBS temporarily omits it from the selector (e.g. during load).
        local exe = normalized_path(window.path):match("([^/]+)$") or ""
        if exe ~= "" and previous:lower():sub(-#exe - 1) == ":" .. exe then
            target = previous
        end
    end
    if not target then
        obs.obs_data_release(settings)
        obs.obs_source_release(holder)
        return false, reason
    end
    local changed = target ~= previous
    if changed and apply then
        obs.obs_data_set_string(settings, "window", target)
        obs.obs_source_update(source, settings)
    end
    obs.obs_data_release(settings)
    obs.obs_source_release(holder)
    return true, changed
end

local function inspect_or_switch(force_log, apply)
    if not loaded then load_databases() end
    local w, err = foreground_window()
    if not w then
        status_ignored = "前台读取失败：" .. tostring(err)
        if force_log then log(obs.LOG_WARNING, "Foreground unavailable: " .. tostring(err)) end
        return
    end
    local exe = normalized_path(w.path):match("([^/]+)$") or "未知进程"
    local base = basename_no_ext(w.path)
    local fingerprint = w.path .. "|" .. w.title
    local client_name = lol_client_enabled and window_clients[base]
    if client_name then
        status_game = client_name .. " / " .. exe
        if apply then
            local target_ok, target_result = update_client_window(w, true)
            if target_ok then
                local show_ok, show_result = set_lol_visible(true)
                if show_ok then
                    status_capture = "客户端窗口已匹配：" .. exe
                    if target_result or show_result then
                        status_switched = os.date("%H:%M:%S") .. " " .. client_name .. " / " .. exe
                    end
                else
                    status_lol = "配置异常：" .. tostring(show_result)
                    status_capture = status_lol
                end
            else
                status_lol = "窗口目标定位失败：" .. tostring(target_result)
                status_capture = status_lol
            end
            if force_log or fingerprint ~= last_status then
                log(target_ok and obs.LOG_INFO or obs.LOG_WARNING, status_capture)
            end
        else
            status_capture = "只读检查：识别到名单中的客户端 " .. exe
        end
        last_status = fingerprint
        return
    end
    local game, reason = game_for_window(w)
    fingerprint = fingerprint .. "|" .. tostring(game)
    if not game then
        status_ignored = exe .. " (" .. reason .. ")"
        if (force_log or debug_log) and (force_log or fingerprint ~= last_status) then
            log(obs.LOG_INFO, "Skipped " .. w.path .. " (" .. reason .. ")")
        end
        last_status = fingerprint
        return
    end
    status_game = game .. " / " .. exe
    local ok, result = update_capture(w, game, apply)
    -- Hide the client overlay only once a valid game-capture target is found.
    -- The OBS Replay Buffer itself runs continuously across this change.
    if ok and apply and lol_client_enabled then
        local client_ok, client_result = set_lol_visible(false)
        if not client_ok then status_lol = "配置异常：" .. tostring(client_result) end
    end
    if not ok then
        status_capture = "目标定位失败：" .. result
    elseif not apply then
        status_capture = "只读检查通过：" .. exe
    elseif result:find("[switched]", 1, true) then
        status_capture = "已设为：" .. exe
        status_switched = os.date("%H:%M:%S") .. " " .. game .. " / " .. exe
    else
        status_capture = "已保持：" .. exe
    end
    if force_log or fingerprint ~= last_status or (ok and apply and result:find("[switched]", 1, true)) then
        log(ok and obs.LOG_INFO or obs.LOG_WARNING,
            "Detected [" .. reason .. "] " .. game .. ": " .. result)
    end
    last_status = fingerprint
end

function obs_game_follow_probe()
    -- Read-only helper for diagnostics; does not invoke OBS.
    local w, err = foreground_window()
    if not w then return nil, err end
    return w.path, w.title, w.class, w.pid
end

-- Process lifetime is independent of foreground focus and OBS's hook state.
-- Keep the existing recognizer and capture selectors above unchanged.
local function native_process_windows()
    if not kernel32 or not user32 then return nil, win32_error end
    local snapshot = kernel32.CreateToolhelp32Snapshot(2, 0)
    if snapshot == ffi.cast("void*", -1) or snapshot == nil then
        return nil, "process snapshot unavailable"
    end
    local entries = {}
    local entry = ffi.new("OGF_PROCESSENTRY32W[1]")
    entry[0].dwSize = ffi.sizeof(entry[0])
    local more = kernel32.Process32FirstW(snapshot, entry)
    while more ~= 0 do
        local pid = tonumber(entry[0].th32ProcessID)
        local process = kernel32.OpenProcess(0x1000, 0, pid)
        local path
        if process ~= nil and process ~= ffi.NULL then
            local image = ffi.new("uint16_t[32768]")
            local size = ffi.new("unsigned long[1]", 32768)
            if kernel32.QueryFullProcessImageNameW(process, 0, image, size) ~= 0 then
                path = utf8_wide(image)
            end
            kernel32.CloseHandle(process)
        end
        -- Access denied is not proof of exit. Retain only an already known PID
        -- with the same executable name; new inaccessible processes are ignored.
        local old = tracked_games[pid]
        if not path and old and basename_no_ext(old.window.path)
            == basename_no_ext(utf8_wide(entry[0].szExeFile)) then
            path = old.window.path
        end
        if path then entries[pid] = { path = path, title = "", class = "", pid = pid } end
        more = kernel32.Process32NextW(snapshot, entry)
    end
    local scan_error = tonumber(kernel32.GetLastError())
    kernel32.CloseHandle(snapshot)
    if scan_error ~= 18 then return nil, "incomplete process snapshot: " .. scan_error end

    -- GetTopWindow/GW_HWNDNEXT avoids FFI callbacks and includes minimized games.
    local hwnd = user32.GetTopWindow(nil)
    local visited = 0
    while hwnd ~= nil and hwnd ~= ffi.NULL and visited < 10000 do
        local pid = ffi.new("unsigned long[1]")
        user32.GetWindowThreadProcessId(hwnd, pid)
        local w = entries[tonumber(pid[0])]
        if w and w.title == "" and user32.IsWindowVisible(hwnd) ~= 0 then
            local title, class = ffi.new("uint16_t[4096]"), ffi.new("uint16_t[512]")
            user32.GetWindowTextW(hwnd, title, 4096)
            user32.GetClassNameW(hwnd, class, 512)
            w.title, w.class = utf8_wide(title), utf8_wide(class)
        end
        hwnd = user32.GetWindow(hwnd, 2)
        visited = visited + 1
    end
    return entries
end

local function refresh_running(foreground)
    local processes, err = native_process_windows()
    if not processes then return nil, err end
    -- Foreground query may succeed just after a process starts (or after a
    -- transient access failure in the snapshot). It is also live evidence.
    if foreground then processes[foreground.pid] = foreground end
    local next_games, best_game, best_client = {}, nil, nil
    local count = 0
    for pid, window in pairs(processes) do
        local old = tracked_games[pid]
        if old and normalized_path(old.window.path) ~= normalized_path(window.path) then old = nil end
        if window.title == "" and old then
            window.title, window.class = old.window.title, old.window.class
        end
        local client = lol_client_enabled and window_clients[basename_no_ext(window.path)]
        local game = not client and game_for_window(window) or nil
        if client or game then
            local order = old and old.order or 0
            if foreground and foreground.pid == pid then
                recent_order = recent_order + 1
                order = recent_order
            end
            local item = { window = window, name = client or game, client = client, order = order }
            next_games[pid] = item
            count = count + 1
            local best
            if client then best = best_client else best = best_game end
            if not best or item.order > best.order
                or (item.order == best.order and pid < best.window.pid) then
                if client then best_client = item else best_game = item end
            end
        end
    end
    tracked_games = next_games
    status_running = tostring(count)
    -- Actual games outrank launchers/clients, including a lingering LoL client.
    return best_game or best_client, nil, true
end

local function set_capture_visibility(has_game, show_desktop)
    local selected = desktop_source_name
    if selected == "" then
        local sources = obs.obs_enum_sources()
        local count = 0
        if sources then
            for _, source in ipairs(sources) do
                if obs.obs_source_get_id(source) == "monitor_capture" then
                    selected, count = obs.obs_source_get_name(source), count + 1
                end
            end
            obs.source_list_release(sources)
        end
        if count ~= 1 then selected = "" end
    end
    local found = 0
    local function visit(scene)
        local items = obs.obs_scene_enum_items(scene)
        if not items then return end
        for _, item in ipairs(items) do
            local source = obs.obs_sceneitem_get_source(item)
            local name, kind = obs.obs_source_get_name(source), obs.obs_source_get_id(source)
            local visible
            if kind == "monitor_capture" then
                -- Hide every display-capture item while games are present, even
                -- in nested groups or other scenes. Never show an unselected one.
                visible = show_desktop and name == selected
                if name == selected then found = found + 1 end
            elseif kind == "game_capture" and name == source_name then
                visible = has_game
            end
            if visible ~= nil and obs.obs_sceneitem_visible(item) ~= visible then
                obs.obs_sceneitem_set_visible(item, visible)
            end
            if obs.obs_sceneitem_is_group(item) then
                visit(obs.obs_sceneitem_group_get_scene(item))
            end
        end
        obs.sceneitem_list_release(items)
    end
    local scenes = obs.obs_frontend_get_scenes()
    if scenes then
        for _, source in ipairs(scenes) do
            local scene = obs.obs_scene_from_source(source)
            if scene then visit(scene) end
        end
        obs.source_list_release(scenes)
    end
    -- A configured source in an unrelated scene cannot record this output.
    local function in_program(scene, seen)
        if seen[scene] then return false end
        seen[scene] = true
        local items = obs.obs_scene_enum_items(scene)
        if not items then return false end
        local present = false
        for _, item in ipairs(items) do
            local source = obs.obs_sceneitem_get_source(item)
            if obs.obs_source_get_id(source) == "monitor_capture"
                and obs.obs_source_get_name(source) == selected then
                present = true
            elseif obs.obs_sceneitem_visible(item) then
                local child
                if obs.obs_sceneitem_is_group(item) then
                    child = obs.obs_sceneitem_group_get_scene(item)
                elseif obs.obs_source_get_id(source) == "scene" then
                    child = obs.obs_scene_from_source(source)
                end
                if child and in_program(child, seen) then present = true end
            end
        end
        obs.sceneitem_list_release(items)
        return present
    end
    local program = obs.obs_frontend_get_current_scene()
    local program_ok = false
    if program then
        local scene = obs.obs_scene_from_source(program)
        program_ok = scene and in_program(scene, {})
        obs.obs_source_release(program)
    end
    if show_desktop and (found == 0 or not program_ok) then
        status_desktop = "请配置显示器采集源并加入场景（多个源时需指定）"
        return false
    end
    status_desktop = show_desktop and ("显示：" .. selected) or "已隐藏"
    return true
end

local function manage_replay(wanted, now)
    -- Manual mode must never start/stop the buffer, even after a game exits.
    if not auto_replay then return end
    local active = obs.obs_frontend_replay_buffer_active()
    if active == wanted then
        replay_pending = nil
        status_replay = active and "运行中" or "已停止"
        return
    end
    local action = wanted and "start" or "stop"
    if replay_pending == action and now - replay_requested_at < 5 then return end
    replay_pending, replay_requested_at = action, now
    if wanted then obs.obs_frontend_replay_buffer_start()
    else obs.obs_frontend_replay_buffer_stop() end
    status_replay = wanted and "已请求启动（需在 OBS 启用回放缓存）" or "已请求停止"
    log(obs.LOG_INFO, "Replay Buffer: " .. action)
end

local function on_timer()
    if not enabled then return end
    -- Also works when the script is loaded into an already running OBS instance.
    -- At startup, wait until the frontend has a real scene before changing output.
    local scene = obs.obs_frontend_get_current_scene()
    if not scene then return end
    obs.obs_source_release(scene)
    if not loaded then load_databases() end
    local foreground = foreground_window()
    local target, err, scanned = refresh_running(foreground)
    if not scanned then
        status_running = "扫描失败：" .. tostring(err)
        set_capture_visibility(true, false)
        -- Unknown lifetime must not become a false "last game exited".
        no_game_since = nil
        return
    end
    local now = obs.os_gettime_ns() / 1000000000
    if target then
        no_game_since = nil
        set_capture_visibility(not target.client, false)
        local ok, result
        if target.client then
            ok, result = update_client_window(target.window, true)
            if ok then ok, result = set_lol_visible(true) end
        else
            ok, result = update_capture(target.window, target.name, true)
            if lol_client_enabled then set_lol_visible(false) end
        end
        status_game = target.name .. " / " .. target.window.path
        status_capture = ok and ("已保持目标：" .. target.name) or ("目标定位失败：" .. tostring(result))
        local key = tostring(target.window.pid) .. "|" .. status_capture
        if key ~= current_paths then
            current_paths = key
            status_switched = os.date("%H:%M:%S") .. " " .. target.name
            log(ok and obs.LOG_INFO or obs.LOG_WARNING, status_capture)
        end
        manage_replay(true, now)
    else
        if lol_client_enabled then set_lol_visible(false) end
        local desktop_ok = set_capture_visibility(false, record_desktop)
        no_game_since = no_game_since or now
        if record_desktop and desktop_ok then
            manage_replay(true, now)
        elseif now - no_game_since >= 5 then
            manage_replay(false, now)
        elseif auto_replay then
            status_replay = "无游戏，等待 5 秒确认"
        end
        status_game = "无游戏运行"
    end
end

local inspect_pending = false
local function inspect_after_delay()
    obs.timer_remove(inspect_after_delay)
    inspect_pending = false
    inspect_or_switch(true, false)
    log(obs.LOG_INFO, "只读检查已完成；可点击“刷新状态”查看结果。")
end

local function on_inspect_clicked(props, prop)
    if inspect_pending then obs.timer_remove(inspect_after_delay) end
    inspect_pending = true
    log(obs.LOG_INFO, "将在 3 秒后只读检查前台窗口，请立即切回游戏。")
    obs.timer_add(inspect_after_delay, 3000)
    return false
end

local function on_reload_clicked(props, prop)
    load_databases()
    return true
end

local property_labels = {
    ui_language = {"语言", "Language"},
    capture_section = {"常用设置", "General"},
    enabled = {"自动切换", "Auto-switch games"},
    auto_replay = {"自动回放", "Automatic replay"},
    record_desktop = {"录制桌面", "Record desktop"},
    status_section = {"状态", "Status"},
    refresh_status = {"刷新", "Refresh"},
    ui_show_advanced = {"高级设置", "Advanced"},
    source_section = {"采集源", "Capture sources"},
    source_name = {"游戏采集源", "Game Capture"},
    desktop_source_name = {"显示器采集源", "Display Capture"},
    interval_ms = {"检测间隔（毫秒）", "Check interval (ms)"},
    lol_client_section = {"客户端", "Clients"},
    lol_client_enabled = {"采集客户端", "Capture clients"},
    lol_client_scene = {"所属场景", "Scene"},
    lol_client_source = {"窗口采集源", "Window Capture"},
    client_rules_text = {"客户端规则", "Client rules"},
    lol_client_help = {"每行一条：程序.exe=名称\n窗口采集源放在游戏采集源上方。",
        "One rule per line: program.exe=name\nPlace Window Capture above Game Capture."},
    database_section = {"游戏规则", "Game rules"},
    discord_file = {"Discord 游戏库", "Discord database"},
    srm_file = {"SRM 脚本", "SRM script"},
    override_text = {"补充游戏规则", "Custom game rules"},
    reload_db = {"重载游戏库", "Reload databases"},
    ui_show_diagnostics = {"诊断", "Diagnostics"},
    inspect_now = {"3 秒后检查窗口", "Check window in 3 seconds"},
    debug_log = {"详细日志", "Verbose logging"},
}

local property_help = {
    enabled = {"自动识别游戏并切换采集源。", "Detect games and switch the capture source."},
    auto_replay = {"自动管理回放缓存。", "Manage the replay buffer automatically."},
    record_desktop = {"没有游戏时录制桌面。", "Record the desktop when no game is running."},
    desktop_source_name = {"只有一个显示器采集源时可自动选择。", "Auto-select works when there is one Display Capture source."},
    override_text = {"每行一条：game.exe=游戏名", "One rule per line: game.exe=Game name"},
    inspect_now = {"只读检查，不切换采集目标。", "Read-only check; capture settings stay unchanged."},
    ui_show_advanced = {"采集源、客户端和游戏规则。", "Sources, clients and game rules."},
    ui_show_diagnostics = {"详细状态和只读检查。", "Detailed status and read-only checks."},
}

local property_groups = {"capture_section", "status_section", "ui_show_advanced",
    "source_section", "lol_client_section", "database_section", "ui_show_diagnostics"}

local function find_property(props, name)
    local property = obs.obs_properties_get(props, name)
    if property then return property end
    for _, group_name in ipairs(property_groups) do
        local group = obs.obs_properties_get(props, group_name)
        if group and obs.obs_property_group_content then
            local content = obs.obs_property_group_content(group)
            if content then
                property = find_property(content, name)
                if property then return property end
            end
        end
    end
end

local function source_names(kind)
    local names = {}
    local sources = obs.obs_enum_sources()
    if sources then
        for _, source in ipairs(sources) do
            if obs.obs_source_get_id(source) == kind then
                names[#names + 1] = obs.obs_source_get_name(source)
            end
        end
        obs.source_list_release(sources)
    end
    table.sort(names)
    return names
end

local function refresh_status_properties(props)
    local summary = find_property(props, "summary_info")
    local details = find_property(props, "status_info")
    if summary then obs.obs_property_set_description(summary, summary_description()) end
    if details then obs.obs_property_set_description(details, status_description()) end
end

local function apply_ui(props)
    for name, pair in pairs(property_labels) do
        local property = find_property(props, name)
        if property then obs.obs_property_set_description(property, tr(pair[1], pair[2])) end
    end
    if obs.obs_property_set_long_description then
        for name, pair in pairs(property_help) do
            local property = find_property(props, name)
            if property then obs.obs_property_set_long_description(property, tr(pair[1], pair[2])) end
        end
    end
    local language = find_property(props, "ui_language")
    obs.obs_property_list_clear(language)
    obs.obs_property_list_add_string(language, tr("跟随 OBS", "Follow OBS"), "auto")
    obs.obs_property_list_add_string(language, "简体中文", "zh-CN")
    obs.obs_property_list_add_string(language, "English", "en-US")
    for _, spec in ipairs({{"desktop_source_name", "monitor_capture"}, {"lol_client_source", "window_capture"}}) do
        local list = find_property(props, spec[1])
        obs.obs_property_list_clear(list)
        obs.obs_property_list_add_string(list,
            spec[1] == "desktop_source_name" and tr("自动选择", "Auto-select") or tr("未选择", "None"), "")
        for _, name in ipairs(source_names(spec[2])) do
            obs.obs_property_list_add_string(list, name, name)
        end
    end
    for _, name in ipairs({"source_section", "lol_client_section", "database_section"}) do
        obs.obs_property_set_visible(find_property(props, name), ui_show_advanced)
    end
    for _, name in ipairs({"status_info", "inspect_now", "debug_log"}) do
        obs.obs_property_set_visible(find_property(props, name), ui_show_diagnostics)
    end
    refresh_status_properties(props)
end

local function on_ui_changed(props, property, settings)
    update_ui_settings(settings)
    apply_ui(props)
    return true
end

local function on_status_clicked(props, property)
    refresh_status_properties(props)
    return true
end

function script_description()
    return "<b>OBS GameFlow</b><br>" .. tr(
        "自动识别游戏并切换 OBS 采集源，支持桌面录制和回放自动管理。",
        "Detects games and switches OBS capture sources, with desktop capture and automatic replay buffer management.")
end

function script_defaults(settings)
    obs.obs_data_set_default_string(settings, "source_name", "游戏采集")
    obs.obs_data_set_default_string(settings, "discord_file",
        join_path(folder_of_script(), "discord_games.json"))
    obs.obs_data_set_default_string(settings, "srm_file",
        [[D:\Portable\OBS Addons\Smart_Replay_Mover\Smart_Replay_Mover.lua]])
    obs.obs_data_set_default_string(settings, "override_text", "")
    obs.obs_data_set_default_bool(settings, "enabled", false)
    obs.obs_data_set_default_bool(settings, "record_desktop", false)
    obs.obs_data_set_default_bool(settings, "auto_replay", false)
    obs.obs_data_set_default_string(settings, "desktop_source_name", "")
    obs.obs_data_set_default_int(settings, "interval_ms", 1000)
    obs.obs_data_set_default_bool(settings, "debug_log", false)
    obs.obs_data_set_default_bool(settings, "lol_client_enabled", false)
    obs.obs_data_set_default_string(settings, "lol_client_scene", "游戏")
    obs.obs_data_set_default_string(settings, "lol_client_source", "")
    obs.obs_data_set_default_string(settings, "client_rules_text", "LeagueClientUx.exe=英雄联盟客户端")
    obs.obs_data_set_default_string(settings, "ui_language", "auto")
    obs.obs_data_set_default_bool(settings, "ui_show_advanced", false)
    obs.obs_data_set_default_bool(settings, "ui_show_diagnostics", false)
end


function script_properties()
    local props = obs.obs_properties_create()
    local function info(parent, name, value)
        local property = obs.obs_properties_add_text(parent, name, value, obs.OBS_TEXT_INFO)
        if obs.obs_property_text_set_info_word_wrap then
            obs.obs_property_text_set_info_word_wrap(property, true)
        end
        return property
    end
    local function list(parent, name)
        return obs.obs_properties_add_list(parent, name, "", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    end
    local language = list(props, "ui_language")
    obs.obs_property_set_modified_callback(language, on_ui_changed)

    local common = obs.obs_properties_create()
    obs.obs_properties_add_bool(common, "enabled", "")
    obs.obs_properties_add_bool(common, "auto_replay", "")
    obs.obs_properties_add_bool(common, "record_desktop", "")
    obs.obs_properties_add_group(props, "capture_section", "", obs.OBS_GROUP_NORMAL, common)

    local status = obs.obs_properties_create()
    info(status, "summary_info", summary_description())
    obs.obs_properties_add_button(status, "refresh_status", "", on_status_clicked)
    obs.obs_properties_add_group(props, "status_section", "", obs.OBS_GROUP_NORMAL, status)

    local advanced = obs.obs_properties_create()
    local sources = obs.obs_properties_create()
    local game_list = list(sources, "source_name")
    for _, name in ipairs(source_names("game_capture")) do
        obs.obs_property_list_add_string(game_list, name, name)
    end
    list(sources, "desktop_source_name")
    obs.obs_properties_add_int(sources, "interval_ms", "", 500, 5000, 100)
    obs.obs_properties_add_group(advanced, "source_section", "", obs.OBS_GROUP_NORMAL, sources)

    local clients = obs.obs_properties_create()
    obs.obs_properties_add_bool(clients, "lol_client_enabled", "")
    local scene_list = list(clients, "lol_client_scene")
    local scenes = obs.obs_frontend_get_scenes()
    local names = {}
    if scenes then
        for _, scene in ipairs(scenes) do names[#names + 1] = obs.obs_source_get_name(scene) end
        obs.source_list_release(scenes)
    end
    table.sort(names)
    for _, name in ipairs(names) do obs.obs_property_list_add_string(scene_list, name, name) end
    list(clients, "lol_client_source")
    obs.obs_properties_add_text(clients, "client_rules_text", "", obs.OBS_TEXT_MULTILINE)
    info(clients, "lol_client_help", "")
    obs.obs_properties_add_group(advanced, "lol_client_section", "", obs.OBS_GROUP_NORMAL, clients)

    local rules = obs.obs_properties_create()
    obs.obs_properties_add_path(rules, "discord_file", "", obs.OBS_PATH_FILE, "JSON (*.json)", nil)
    obs.obs_properties_add_path(rules, "srm_file", "", obs.OBS_PATH_FILE, "Lua (*.lua)", nil)
    obs.obs_properties_add_text(rules, "override_text", "", obs.OBS_TEXT_MULTILINE)
    obs.obs_properties_add_button(rules, "reload_db", "", on_reload_clicked)
    obs.obs_properties_add_group(advanced, "database_section", "", obs.OBS_GROUP_NORMAL, rules)
    local advanced_toggle = obs.obs_properties_add_group(props, "ui_show_advanced", "", obs.OBS_GROUP_CHECKABLE, advanced)
    obs.obs_property_set_modified_callback(advanced_toggle, on_ui_changed)

    local diagnostics = obs.obs_properties_create()
    info(diagnostics, "status_info", status_description())
    obs.obs_properties_add_button(diagnostics, "inspect_now", "", on_inspect_clicked)
    obs.obs_properties_add_bool(diagnostics, "debug_log", "")
    local diagnostics_toggle = obs.obs_properties_add_group(props, "ui_show_diagnostics", "", obs.OBS_GROUP_CHECKABLE, diagnostics)
    obs.obs_property_set_modified_callback(diagnostics_toggle, on_ui_changed)
    apply_ui(props)
    return props
end


function script_update(settings)
    update_ui_settings(settings)
    local next_source = obs.obs_data_get_string(settings, "source_name")
    local next_discord = obs.obs_data_get_string(settings, "discord_file")
    local next_srm = obs.obs_data_get_string(settings, "srm_file")
    local next_overrides = obs.obs_data_get_string(settings, "override_text")
    local next_interval = obs.obs_data_get_int(settings, "interval_ms")
    local next_enabled = obs.obs_data_get_bool(settings, "enabled")
    local next_desktop = obs.obs_data_get_bool(settings, "record_desktop")
    local desktop_changed = next_desktop ~= record_desktop
    local next_lol_enabled = obs.obs_data_get_bool(settings, "lol_client_enabled")
    local next_lol_scene = obs.obs_data_get_string(settings, "lol_client_scene")
    local next_lol_source = obs.obs_data_get_string(settings, "lol_client_source")
    local next_client_rules = obs.obs_data_get_string(settings, "client_rules_text")
    if lol_original_visibility and (
        not next_enabled or not next_lol_enabled
        or next_lol_scene ~= lol_scene_name or next_lol_source ~= lol_source_name
        or next_client_rules ~= client_rules_text) then
        restore_lol_visibility()
    end
    local should_reload = not loaded or next_discord ~= discord_file
        or next_srm ~= srm_file or next_overrides ~= override_text
    local should_reload_clients = next_client_rules ~= client_rules_text

    source_name = next_source
    discord_file = next_discord
    srm_file = next_srm
    override_text = next_overrides
    enabled = next_enabled
    auto_replay = obs.obs_data_get_bool(settings, "auto_replay")
    if not auto_replay then
        replay_pending = nil
        status_replay = "自动回放已关闭（手动控制）"
    end
    record_desktop = next_desktop
    desktop_source_name = obs.obs_data_get_string(settings, "desktop_source_name")
    if desktop_changed and not record_desktop then
        -- The five-second exit debounce does not delay an explicit OFF toggle.
        no_game_since = obs.os_gettime_ns() / 1000000000 - 5
    end
    debug_log = obs.obs_data_get_bool(settings, "debug_log")
    interval_ms = math.max(500, math.min(5000, next_interval))
    lol_client_enabled = next_lol_enabled
    lol_scene_name = next_lol_scene
    lol_source_name = next_lol_source
    client_rules_text = next_client_rules
    if should_reload then
        load_databases()
    elseif should_reload_clients then
        load_window_client_rules()
    end
    if not lol_client_enabled then
        status_lol = "未启用"
    elseif enabled and not lol_original_visibility then
        -- OBS has focus while editing script settings, so begin with the
        -- client overlay hidden until its real foreground window appears.
        local w = foreground_window()
        local is_client = w and window_clients[basename_no_ext(w.path)] ~= nil
        local ok, why = set_lol_visible(is_client and true or false)
        if not ok then status_lol = "配置异常：" .. tostring(why) end
    end

    obs.timer_remove(on_timer)
    if enabled then
        obs.timer_add(on_timer, interval_ms)
        on_timer()
        log(obs.LOG_INFO, "Automatic following ENABLED; target source: " .. source_name)
    else
        tracked_games, no_game_since, replay_pending = {}, nil, nil
        log(obs.LOG_INFO, "Inspection-only mode. No OBS inputs will be changed.")
    end
end

function script_unload()
    if obs and obs.timer_remove then
        obs.timer_remove(on_timer)
        obs.timer_remove(inspect_after_delay)
    end
    restore_lol_visibility()
end
