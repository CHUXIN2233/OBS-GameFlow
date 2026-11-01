-- Uses OBS's actual LuaJIT and Win32 FFI. Frontend output is simulated here.
local function eq(a, b, label)
    assert(a == b, (label or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end
local total = 0
local function test(name, fn)
    fn()
    total = total + 1
    print("PASS " .. name)
end
local function up(fn, name, replacement)
    for i = 1, 100 do
        local key, value = debug.getupvalue(fn, i)
        if not key then break end
        if key == name then
            if replacement ~= nil then debug.setupvalue(fn, i, replacement) end
            return value
        end
    end
    error("missing upvalue " .. name)
end

local now, active, starts, stops, ready = 0, false, 0, 0, true
local async = false
local foreground, processes, scan_error = nil, {}, nil
local timer, settings
local sources, scene, group, desktop_item, game_item, client_item, other_item
local logs = {}
obslua = {
    LOG_INFO = 200, LOG_WARNING = 300,
    script_log = function(_, message) logs[#logs+1] = message end,
    os_gettime_ns = function() return now * 1e9 end,
    obs_data_get_string = function(s,k) return s[k] or "" end,
    obs_data_get_bool = function(s,k) return s[k] == true end,
    obs_data_get_int = function(s,k) return s[k] or 0 end,
    obs_data_set_string = function(s,k,v) s[k] = v end,
    obs_data_set_int = function(s,k,v) s[k] = v end,
    obs_data_release = function() end,
    obs_get_source_by_name = function(name) return sources[name] end,
    obs_source_get_id = function(s) return s.kind end,
    obs_source_get_name = function(s) return s.name end,
    obs_source_release = function() end,
    obs_source_get_settings = function(s)
        local copy = {}; for k,v in pairs(s.settings or {}) do copy[k]=v end; return copy
    end,
    obs_source_update = function(s,v) s.settings = v end,
    obs_source_properties = function(s) return s end,
    obs_properties_get = function(s) return s end,
    obs_properties_destroy = function() end,
    obs_property_list_item_count = function(p) return #(p.windows or {}) end,
    obs_property_list_item_string = function(p,i) return p.windows[i+1] end,
    obs_frontend_get_current_scene = function() return ready and scene or nil end,
    obs_frontend_get_scenes = function() return {scene} end,
    obs_enum_sources = function()
        local list={}; for _,s in pairs(sources) do list[#list+1]=s end; return list
    end,
    source_list_release = function() end,
    obs_scene_from_source = function(s) return s end,
    obs_scene_enum_items = function(s) return s.items end,
    sceneitem_list_release = function() end,
    obs_sceneitem_get_source = function(i) return i.source end,
    obs_sceneitem_visible = function(i) return i.visible end,
    obs_sceneitem_set_visible = function(i,v) i.visible = v end,
    obs_sceneitem_is_group = function(i) return i.source.kind == "group" end,
    obs_sceneitem_group_get_scene = function(i) return i.source end,
    obs_scene_find_source = function(s,name)
        for _,i in ipairs(s.items) do if i.source.name == name then return i end end
    end,
    obs_frontend_replay_buffer_active = function() return active end,
    obs_frontend_replay_buffer_start = function() starts=starts+1; if not async then active=true end end,
    obs_frontend_replay_buffer_stop = function() stops=stops+1; if not async then active=false end end,
    timer_remove = function() end,
    timer_add = function(fn,ms) if ms ~= 3000 then timer=fn end end,
}
for _,kind in ipairs({"string", "int", "bool"}) do
    obslua["obs_data_set_default_"..kind] = function(s,k,v) if s[k]==nil then s[k]=v end end
end
script_path = function() return "work/nonexistent/" end
dofile(os.getenv("OGF_SCRIPT_FILE") or "outputs/OGF-v0.4/OBS_Game_Follow.lua")
local lifecycle = up(script_update, "on_timer")
local refresh = up(lifecycle, "refresh_running")
local native_scan = up(refresh, "native_process_windows")
local native_foreground = up(lifecycle, "foreground_window")

test("native Win32 process snapshot and foreground FFI", function()
    local snapshot, err = native_scan()
    assert(snapshot, err)
    local ffi = require("ffi")
    ffi.cdef("unsigned long GetCurrentProcessId(void);")
    local pid = tonumber(ffi.C.GetCurrentProcessId())
    assert(snapshot[pid] and snapshot[pid].path:lower():match("python.*%.exe$"))
    assert(ffi.sizeof("OGF_PROCESSENTRY32W") == 568)
    local w, why = native_foreground()
    -- A protected/elevated foreground may be inaccessible; the failure must be explicit.
    assert((w and w.pid and w.path ~= "") or type(why)=="string")
end)

up(refresh, "native_process_windows", function()
    if scan_error then return nil, scan_error end
    local copy={}
    for pid,w in pairs(processes) do
        copy[pid]={}; for k,v in pairs(w) do copy[pid][k]=v end
    end
    return copy
end)
up(lifecycle, "foreground_window", function() return foreground end)
up(script_update, "foreground_window", function() return foreground end)

local function window(pid,exe,title)
    return {pid=pid,path="C:/Games/"..exe,title=title or exe,class="GameWindow"}
end
local A, B = window(101,"a.exe"), window(202,"b.exe")
local client = window(303,"LeagueClientUx.exe")
local match = window(404,"League of Legends.exe")
local function reset(extra)
    script_unload()
    up(refresh,"tracked_games",{})
    up(lifecycle,"no_game_since",false) -- reset below via script_update's disabled branch
    now,active,starts,stops,ready,async=0,false,0,0,true,false
    foreground,processes,scan_error=nil,{},nil
    sources={}
    local function source(name,kind)
        local s={name=name,kind=kind,settings={}}; sources[name]=s; return s
    end
    scene=source("Game","scene")
    local game=source("Capture","game_capture")
    local desk=source("Display","monitor_capture")
    local other=source("Other Display","monitor_capture")
    local wc=source("Client","window_capture")
    game.windows={"a.exe:GameWindow:a.exe","b.exe:GameWindow:b.exe",
        "League of Legends.exe:GameWindow:League of Legends.exe"}
    wc.windows={"LeagueClientUx.exe:GameWindow:LeagueClientUx.exe"}
    group=source("Group","group")
    desktop_item={source=desk,visible=true}
    game_item={source=game,visible=true}
    client_item={source=wc,visible=true}
    other_item={source=other,visible=true}
    group.items={desktop_item,other_item}
    scene.items={game_item,client_item,{source=group,visible=true}}
    settings={}
    script_defaults(settings)
    eq(settings.auto_replay,false,"automatic replay defaults OFF")
    -- Existing lifecycle regressions exercise the opt-in automatic mode.
    settings.auto_replay=true
    settings.source_name="Capture"
    settings.desktop_source_name="Display"
    settings.discord_file="work/nonexistent/discord.json"
    settings.srm_file="work/nonexistent/srm.lua"
    settings.override_text="a.exe=Game A\nb.exe=Game B"
    settings.lol_client_scene="Game"
    settings.lol_client_source="Client"
    settings.lol_client_enabled=true
    if extra then for k,v in pairs(extra) do settings[k]=v end end
    settings.enabled=false
    script_update(settings)
    eq(settings.record_desktop,false,"desktop default")
end
local function enable()
    settings.enabled=true
    script_update(settings)
end
local function tick(seconds)
    now=now+(seconds or 1)
    timer()
end
local function toggle(value)
    settings.record_desktop=value
    script_update(settings)
end
local function target()
    return sources.Capture.settings.window
end

test("idle default off hides displays, stays stopped",function()
    reset(); enable(); tick(5)
    eq(active,false); eq(starts,0); eq(stops,0)
    eq(desktop_item.visible,false); eq(other_item.visible,false)
end)
test("desktop ON/OFF applies immediately and saves through settings",function()
    reset(); enable(); toggle(true)
    eq(active,true); eq(desktop_item.visible,true); eq(game_item.visible,false)
    toggle(false)
    eq(active,false); eq(stops,1); eq(desktop_item.visible,false)
    eq(settings.record_desktop,false)
end)
test("A -> Alt+Tab -> B -> close B restores A -> close A five seconds",function()
    reset(); processes={[101]=A}; foreground=A; enable()
    eq(starts,1); eq(target(),"a.exe:GameWindow:a.exe")
    foreground=window(999,"chrome.exe"); tick()
    eq(active,true); eq(target(),"a.exe:GameWindow:a.exe"); eq(desktop_item.visible,false)
    processes[202]=B; foreground=B; tick()
    eq(target(),"b.exe:GameWindow:b.exe"); eq(starts,1); eq(stops,0)
    processes[202]=nil; foreground=nil; tick()
    eq(target(),"a.exe:GameWindow:a.exe"); eq(starts,1); eq(stops,0)
    processes={}; tick()
    eq(active,true); tick(4.9); eq(active,true)
    tick(0.1); eq(active,false); eq(stops,1)
end)
test("desktop ON gives games priority then returns to desktop without restart",function()
    reset(); enable(); toggle(true)
    processes={[101]=A}; foreground=A; tick()
    eq(desktop_item.visible,false); eq(other_item.visible,false); eq(game_item.visible,true)
    foreground=nil; tick(); eq(desktop_item.visible,false)
    processes={}; tick()
    eq(desktop_item.visible,true); eq(game_item.visible,false); eq(starts,1); eq(stops,0)
end)
test("startup discovers a background game without a foreground match",function()
    reset(); processes={[202]=B}; enable()
    eq(target(),"b.exe:GameWindow:b.exe"); eq(starts,1)
end)
test("foreground process starting after snapshot still hides desktop",function()
    reset(); enable(); toggle(true); processes={}; foreground=A; tick()
    eq(target(),"a.exe:GameWindow:a.exe"); eq(desktop_item.visible,false); eq(starts,1)
end)
test("PID reused by unrelated executable is not retained as a game",function()
    reset(); processes={[101]=A}; enable()
    processes={[101]=window(101,"chrome.exe")}; tick(); tick(5)
    eq(active,false); eq(stops,1)
end)
test("MRU outranks PID and only running entries can be restored",function()
    reset(); processes={[101]=A,[202]=B}; foreground=B; enable()
    foreground=A; tick(); eq(target(),"a.exe:GameWindow:a.exe")
    foreground=nil; tick(); eq(target(),"a.exe:GameWindow:a.exe")
    processes[101]=nil; tick(); eq(target(),"b.exe:GameWindow:b.exe")
end)
test("transient disappearance and new game cancel exit debounce",function()
    reset(); processes={[101]=A}; enable()
    processes={}; tick(); tick(4)
    processes={[202]=B}; tick(); eq(stops,0); eq(starts,1)
    processes={}; tick(); tick(4); eq(active,true); tick(); eq(active,false)
end)
test("LoL client -> match -> client -> exit, no replay restart",function()
    reset(); processes={[303]=client}; foreground=client; enable()
    eq(client_item.visible,true); eq(active,true)
    processes[404]=match; foreground=match; tick()
    eq(client_item.visible,false); eq(target(),"League of Legends.exe:GameWindow:League of Legends.exe")
    foreground=client; tick(); eq(client_item.visible,false)
    processes[404]=nil; foreground=nil; tick()
    eq(client_item.visible,true); eq(stops,0); eq(starts,1)
    processes={}; tick(); eq(client_item.visible,false); tick(5); eq(active,false)
end)
test("disabled LoL client does not count as a running game",function()
    reset({lol_client_enabled=false}); processes={[303]=client}; enable(); tick(5)
    eq(starts,0)
end)
test("incomplete process scan never triggers stop or desktop exposure",function()
    reset(); processes={[101]=A}; enable(); toggle(true)
    scan_error="snapshot failed"; tick(10)
    eq(active,true); eq(stops,0); eq(desktop_item.visible,false)
    scan_error=nil; processes={}; toggle(false); eq(active,false)
end)
test("missing/ambiguous/unreachable desktop gives configuration status",function()
    reset(); settings.desktop_source_name="missing"; enable(); toggle(true)
    eq(starts,0); eq(desktop_item.visible,false)
    settings.desktop_source_name=""; script_update(settings); eq(starts,0)
    settings.desktop_source_name="Display"; scene.items={game_item,client_item}
    script_update(settings); eq(starts,0)
end)
test("single display source auto selection works inside nested groups",function()
    reset(); sources["Other Display"]=nil; group.items={desktop_item}
    settings.desktop_source_name=""; enable(); toggle(true)
    eq(starts,1); eq(desktop_item.visible,true)
end)
test("OBS startup waits for ready scene, initializes existing buffer",function()
    reset(); ready=false; active=true; enable(); tick(10)
    eq(stops,0)
    ready=true; tick(); tick(5); eq(stops,1)
    processes={[101]=A}; tick(); eq(starts,1)
end)
test("async requests do not repeat on every poll; failed start can retry",function()
    reset(); processes={[101]=A}; async=true; enable()
    tick(); tick(); tick(); tick(); eq(starts,1)
    tick(); eq(starts,2)
    active=true; tick(); eq(starts,2)
    processes={}; tick(); tick(5); eq(stops,1)
    tick(); eq(stops,1); active=false; tick(); eq(stops,1)
end)
test("late async start is stopped after explicit desktop OFF",function()
    reset(); enable(); async=true; toggle(true); eq(starts,1)
    toggle(false); active=true; tick(); eq(stops,1)
end)
test("missing game selector keeps desktop hidden and replay alive",function()
    reset(); sources.Capture.windows={}; processes={[101]=A}; enable()
    eq(active,true); eq(desktop_item.visible,false); tick(20); eq(stops,0)
end)
test("inspection-only update never changes output or visibility",function()
    reset(); processes={[101]=A}; tick(10)
    eq(starts,0); eq(stops,0); eq(desktop_item.visible,true)
end)
test("source priority and generic/browser filters still apply",function()
    reset(); local recognizer=up(refresh,"game_for_window")
    local name,why=recognizer(window(700,"chrome.exe")); eq(name,nil); eq(why,"excluded")
    name,why=recognizer(window(701,"LeagueClientUx.exe")); eq(name,nil); eq(why,"excluded")
    name=recognizer(match); eq(name,"英雄联盟")
    name=recognizer(A); eq(name,"Game A")
end)
test("saved desktop flag survives settings reload and disable/re-enable",function()
    -- This tests settings handling; an actual OBS restart is a separate live test.
    reset(); settings.record_desktop=true; enable()
    eq(active,true); eq(desktop_item.visible,true)
    settings.enabled=false; script_update(settings)
    starts=0; active=false; enable()
    eq(starts,1); eq(desktop_item.visible,true)
end)
test("automatic replay OFF still follows games, Alt+Tab and fallback",function()
    reset({auto_replay=false}); processes={[101]=A}; foreground=A; enable()
    eq(target(),"a.exe:GameWindow:a.exe"); eq(starts,0); eq(stops,0)
    foreground=window(999,"chrome.exe"); tick(); eq(target(),"a.exe:GameWindow:a.exe")
    processes[202]=B; foreground=B; tick(); eq(target(),"b.exe:GameWindow:b.exe")
    processes[202]=nil; foreground=nil; tick(); eq(target(),"a.exe:GameWindow:a.exe")
    eq(active,false); eq(starts,0); eq(stops,0)
end)
test("automatic replay OFF preserves a manually running buffer after all games exit",function()
    reset({auto_replay=false}); active=true; processes={[101]=A}; enable()
    processes={}; tick(); tick(20)
    eq(active,true); eq(starts,0); eq(stops,0)
    toggle(true); toggle(false); eq(active,true); eq(starts,0); eq(stops,0)
end)
test("automatic replay OFF allows manual start and stop while a game runs",function()
    reset({auto_replay=false}); processes={[101]=A}; enable()
    active=true; tick(10); eq(active,true)
    active=false; tick(10); eq(active,false); eq(starts,0); eq(stops,0)
end)
test("automatic replay OFF keeps desktop selection independent of buffer state",function()
    reset({auto_replay=false}); enable(); toggle(true); tick(10)
    eq(desktop_item.visible,true); eq(active,false); eq(starts,0); eq(stops,0)
    processes={[101]=A}; tick(); eq(desktop_item.visible,false)
    processes={}; tick(); eq(desktop_item.visible,true); eq(starts,0); eq(stops,0)
end)
test("disabling automatic replay does not stop a running buffer; re-enable applies rules",function()
    reset(); processes={[101]=A}; enable(); eq(starts,1)
    settings.auto_replay=false; script_update(settings); eq(active,true); eq(stops,0)
    processes={}; tick(); tick(10); eq(active,true); eq(stops,0)
    settings.auto_replay=true; script_update(settings); eq(active,false); eq(stops,1)
    processes={[101]=A}; tick(); eq(active,true); eq(starts,2)
end)
test("disabling automatic replay clears pending retries without undoing late native start",function()
    reset(); async=true; processes={[101]=A}; enable(); eq(starts,1)
    settings.auto_replay=false; script_update(settings); tick(10); eq(starts,1); eq(stops,0)
    active=true; processes={}; tick(); tick(10); eq(active,true); eq(stops,0)
end)
test("automatic replay OFF retains LoL client and match transitions",function()
    reset({auto_replay=false}); processes={[303]=client}; foreground=client; enable()
    eq(client_item.visible,true)
    processes[404]=match; foreground=match; tick(); eq(client_item.visible,false)
    eq(target(),"League of Legends.exe:GameWindow:League of Legends.exe")
    processes[404]=nil; foreground=nil; tick(); eq(client_item.visible,true)
    eq(starts,0); eq(stops,0)
end)
test("saved automatic replay setting survives defaults and settings reload",function()
    reset({auto_replay=false}); settings.auto_replay=true
    script_defaults(settings); eq(settings.auto_replay,true)
    processes={[101]=A}; enable(); eq(starts,1)
    settings.enabled=false; script_update(settings); active=false
    script_defaults(settings); enable(); eq(starts,2)
end)
print(string.format("RESULT %d tests passed; frontend simulation + real Windows LuaJIT/FFI",total))

-- UI-only model: nested lookup deliberately does not recurse, matching the
-- strictest OBS binding behavior. Capture and replay tests above remain intact.
local old_get=obslua.obs_properties_get
local locale='zh-CN'
obslua.obs_get_locale=function() return locale end
obslua.OBS_TEXT_INFO=1; obslua.OBS_TEXT_MULTILINE=2
obslua.OBS_GROUP_NORMAL=0; obslua.OBS_GROUP_CHECKABLE=1
local function add(parent,name,description,kind)
    local p={name=name,description=description,kind=kind,visible=true,items={}}
    parent.fields[name]=p; parent.order[#parent.order+1]=name
    return p
end
obslua.obs_properties_create=function() return {fields={},order={}} end
obslua.obs_properties_get=function(p,n) return p.fields and p.fields[n] or (not p.fields and old_get(p,n)) end
obslua.obs_property_group_content=function(p) return p.content end
for _,kind in ipairs({'bool','list','text','int','path'}) do
    obslua['obs_properties_add_'..kind]=function(p,n,d) return add(p,n,d,kind) end
end
obslua.obs_properties_add_button=function(p,n,d,cb) local x=add(p,n,d,'button'); x.callback=cb; return x end
obslua.obs_properties_add_group=function(p,n,d,k,c) local x=add(p,n,d,'group'); x.content=c; x.group_type=k; return x end
obslua.obs_property_set_description=function(p,d) p.description=d end
obslua.obs_property_set_long_description=function(p,d) p.help=d end
obslua.obs_property_set_modified_callback=function(p,cb) p.callback=cb end
obslua.obs_property_set_visible=function(p,v) p.visible=v end
obslua.obs_property_text_set_info_word_wrap=function() end
obslua.obs_property_list_clear=function(p) p.items={} end
obslua.obs_property_list_add_string=function(p,n,v) p.items[#p.items+1]={label=n,value=v} end
local function find(props,name)
    if props.fields[name] then return props.fields[name] end
    for _,p in pairs(props.fields) do if p.content then local found=find(p.content,name); if found then return found end end end
end
local props
test('UI follows OBS Chinese and defaults to compact folded sections',function()
    reset(); props=script_properties()
    eq(find(props,'enabled').description,'自动切换')
    eq(find(props,'auto_replay').description,'自动回放')
    eq(find(props,'auto_replay').help,'自动管理回放缓存。')
    eq(find(props,'source_section').visible,false)
    eq(find(props,'status_info').visible,false)
    eq(props.order[1],'ui_language'); eq(props.order[2],'capture_section')
    assert(script_description():find('OBS GameFlow',1,true))
end)
test('manual English updates labels, tooltips, list options and description',function()
    settings.ui_language='en-US'
    local language=find(props,'ui_language'); language.callback(props,language,settings)
    eq(find(props,'enabled').description,'Auto-switch games')
    eq(find(props,'auto_replay').help,'Manage the replay buffer automatically.')
    eq(find(props,'record_desktop').help,'Record the desktop when no game is running.')
    eq(find(props,'desktop_source_name').items[1].label,'Auto-select')
    eq(find(props,'lol_client_source').items[1].label,'None')
    eq(language.items[1].label,'Follow OBS')
    assert(script_description():find('Detects games',1,true))
    assert(not script_description():find('自动识别',1,true))
end)
test('manual Chinese overrides English OBS, automatic language tracks locale',function()
    locale='en-US'; settings.ui_language='auto'
    find(props,'ui_language').callback(props,find(props,'ui_language'),settings)
    eq(find(props,'auto_replay').description,'Automatic replay')
    settings.ui_language='zh-CN'
    find(props,'ui_language').callback(props,find(props,'ui_language'),settings)
    eq(find(props,'auto_replay').description,'自动回放')
end)
test('folding advanced and diagnostics changes only visibility',function()
    local before={}; for k,v in pairs(settings) do before[k]=v end
    local start_before,stop_before=starts,stops
    settings.ui_show_advanced=true; settings.ui_show_diagnostics=true
    find(props,'ui_show_advanced').callback(props,find(props,'ui_show_advanced'),settings)
    eq(find(props,'source_section').visible,true); eq(find(props,'database_section').visible,true)
    eq(find(props,'status_info').visible,true); eq(find(props,'inspect_now').visible,true)
    for k,v in pairs(before) do if not k:match('^ui_') then eq(settings[k],v,'setting preserved '..k) end end
    eq(starts,start_before); eq(stops,stop_before)
end)
test('summary shows actual replay state even in manual mode and translates desktop',function()
    settings.ui_language='en-US'; settings.auto_replay=false
    up(lifecycle,'status_game','无游戏运行'); up(up(lifecycle,'set_capture_visibility'),'status_desktop','显示：Display')
    active=true
    find(props,'ui_language').callback(props,find(props,'ui_language'),settings)
    eq(find(props,'summary_info').description,'Current capture: Desktop\nReplay buffer: On')
    active=false
    find(props,'refresh_status').callback(props,find(props,'refresh_status'))
    assert(find(props,'summary_info').description:find('Replay buffer: Off',1,true))
end)
test('detailed messages translate nested errors without changing source names',function()
    local apply=up(script_properties,'apply_ui')
    local refresh_ui=up(apply,'refresh_status_properties')
    local details=up(refresh_ui,'status_description')
    local display=up(details,'display_text')
    eq(display('目标定位失败：not present in OBS capture window list'),
        'Capture target unavailable: Window not yet listed by OBS')
    eq(display('请将“我的源”直接加入“游戏”场景'),'Add "我的源" directly to scene "游戏"')
    eq(display('扫描失败：incomplete process snapshot: 5'),'Scan failed: Incomplete process scan: 5')
    eq(display('自动回放已关闭（手动控制）'),'Manual control')
    eq(find(props,'source_name').items[1].value,'Capture')
end)
print('RESULT UI language, folding, status and compatibility checks passed')
