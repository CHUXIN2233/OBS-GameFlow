-- Test the unchanged parsers with the real OBS JSON implementation and existing
-- local databases. No third-party database is copied into the delivered package.
local ffi=require("ffi")
ffi.cdef[[
void* obs_data_create(void);
void* obs_data_create_from_json(const char* json);
void obs_data_release(void* data);
void* obs_data_get_array(void* data, const char* name);
size_t obs_data_array_count(void* array);
void* obs_data_array_item(void* array, size_t idx);
void obs_data_array_release(void* array);
const char* obs_data_get_string(void* data, const char* name);
bool obs_data_get_bool(void* data, const char* name);
long long obs_data_get_int(void* data, const char* name);
void obs_data_set_string(void* data, const char* name, const char* value);
void obs_data_set_int(void* data, const char* name, long long value);
void obs_data_set_bool(void* data, const char* name, bool value);
void obs_data_set_default_string(void* data, const char* name, const char* value);
void obs_data_set_default_int(void* data, const char* name, long long value);
void obs_data_set_default_bool(void* data, const char* name, bool value);
const char* obs_data_get_json(void* data);
]]
local lib=ffi.load(os.getenv("OGF_OBS_DLL"))
obslua={LOG_INFO=300,LOG_WARNING=200,timer_remove=function() end,
    obs_enum_sources=function() return {} end,source_list_release=function() end,
    script_log=function(_,msg) print(msg) end}
for _,name in ipairs({"obs_data_create_from_json","obs_data_release","obs_data_get_array",
    "obs_data_array_item","obs_data_array_release","obs_data_get_bool",
    "obs_data_set_string","obs_data_set_int","obs_data_set_bool",
    "obs_data_set_default_string","obs_data_set_default_int","obs_data_set_default_bool"}) do
    obslua[name]=lib[name]
end
obslua.obs_data_array_count=function(a) return tonumber(lib.obs_data_array_count(a)) end
obslua.obs_data_get_int=function(a,k) return tonumber(lib.obs_data_get_int(a,k)) end
obslua.obs_data_get_string=function(a,k) return ffi.string(lib.obs_data_get_string(a,k)) end
-- Match OBS's Lua binding: C NULL pointers become nil, not truthy FFI values.
for _,name in ipairs({'obs_data_create_from_json','obs_data_get_array','obs_data_array_item'}) do
    local native=lib[name]
    obslua[name]=function(...)
        local value=native(...)
        if value==nil then return nil end
        return value
    end
end
local function up(fn,name)
    for i=1,100 do
        local key,value=debug.getupvalue(fn,i)
        if key==name then return value end
        if not key then break end
    end
    error('missing upvalue '..name)
end
obslua.obs_enum_sources=function() return {} end
obslua.source_list_release=function() end
local records={}
obslua.script_log=function(level,message) records[#records+1]={level=level,message=message} end
script_path=function() return os.getenv('OGF_DATABASE_DIR') end
dofile(os.getenv('OGF_REFERENCE_SCRIPT_FILE'))
local previous=lib.obs_data_create()
script_defaults(previous)
lib.obs_data_set_string(previous,'discord_file',os.getenv('OGF_DATABASE_DIR')..'/discord_games.json')
lib.obs_data_set_string(previous,'srm_file',os.getenv('OGF_SRM_FILE'))
script_update(previous)
local old=up(up(up(script_update,'on_timer'),'refresh_running'),'game_for_window')
local old_d,old_s,old_i=up(old,'discord'),up(old,'srm'),up(old,'ignored')
dofile(os.getenv('OGF_SCRIPT_FILE'))
local settings=lib.obs_data_create()
script_defaults(settings)
assert(ffi.string(lib.obs_data_get_string(settings,'discord_file'))=='')
assert(ffi.string(lib.obs_data_get_string(settings,'srm_file'))=='')
assert(ffi.string(lib.obs_data_get_string(settings,'source_name'))=='')
script_update(settings)
local new=up(up(up(script_update,'on_timer'),'refresh_running'),'game_for_window')
local new_d,new_s,new_i=up(new,'discord'),up(new,'srm'),up(new,'ignored')
local checked=0
local function check(path,title)
    local window={path=path,title=title or ''}
    local before,why_before=old(window)
    local after,why_after=new(window)
    assert(after==before and why_after==why_before,'recognition differs: '..path..' / '..tostring(before)..' / '..tostring(after))
    checked=checked+1
end
local function pairs_set(list)
    local result={}
    for _,v in ipairs(list or {}) do result[v.pattern..'\0'..v.name]=true end
    return result
end
local function same_map(a,b,label)
    for k,v in pairs(a) do assert(b[k]==v,label..' missing or changed '..k) end
    for k,v in pairs(b) do assert(a[k]==v,label..' unexpectedly added '..k) end
end
for exe,list in pairs(old_d) do
    same_map(pairs_set(list),pairs_set(new_d[exe]),'path/name records')
    for _,entry in ipairs(list) do
        check('C:/OGF/'..entry.pattern,entry.name)
        check('C:/OGF/'..exe..'.exe',entry.name)
    end
end
for exe in pairs(new_d) do assert(old_d[exe],'unexpected executable') end
same_map(old_s,new_s,'SRM mappings'); same_map(old_i,new_i,'exclusions')
for exe in pairs(old_s) do check('C:/OGF/'..exe..'.exe') end
for exe in pairs(old_i) do check('C:/OGF/'..exe..'.exe') end

-- Missing optional imports retain the complete built-in library and stay quiet.
local first=#records
lib.obs_data_set_string(settings,'discord_file','C:/OGF-missing/discord_games.json')
lib.obs_data_set_string(settings,'srm_file','C:/OGF-missing/Smart_Replay_Mover.lua')
script_update(settings)
for i=first+1,#records do assert(records[i].level>obslua.LOG_WARNING,'missing optional import would show Script Log') end
check('C:/OGF/EscapeFromTarkov.exe')
same_map(old_s,up(new,'srm'),'fallback SRM'); same_map(old_i,up(new,'ignored'),'fallback exclusions')

-- Valid JSON of the wrong shape must not erase the internal library.
local external_loader=up(up(script_update,'load_databases'),'load_discord')
local original_reader=up(external_loader,'read_text')
local reader_index
for i=1,100 do if debug.getupvalue(external_loader,i)=='read_text' then reader_index=i; break end end
debug.setupvalue(external_loader,reader_index,function() return '{}' end)
lib.obs_data_set_string(settings,'discord_file','C:/OGF-test/wrong-shape.json')
script_update(settings)
for exe,list in pairs(old_d) do same_map(pairs_set(list),pairs_set(up(new,'discord')[exe]),'invalid JSON fallback') end
debug.setupvalue(external_loader,reader_index,original_reader)

-- Existing configured external paths keep their original loading behavior.
lib.obs_data_set_string(settings,'discord_file',os.getenv('OGF_DATABASE_DIR')..'/discord_games.json')
lib.obs_data_set_string(settings,'srm_file',os.getenv('OGF_SRM_FILE'))
script_update(settings)
for exe,list in pairs(old_d) do same_map(pairs_set(list),pairs_set(up(new,'discord')[exe]),'legacy import') end
same_map(old_s,up(new,'srm'),'legacy SRM'); same_map(old_i,up(new,'ignored'),'legacy exclusions')

-- Manual rules still override built-ins and the exclusion list.
lib.obs_data_set_string(settings,'override_text','EscapeFromTarkov.exe=My Tarkov\nsteam.exe=Explicit exception')
script_update(settings)
assert(new({path='C:/OGF/EscapeFromTarkov.exe',title=''})=='My Tarkov')
assert(new({path='C:/OGF/steam.exe',title=''})=='Explicit exception')
lib.obs_data_release(previous); lib.obs_data_release(settings)
print('RESULT built-in vs accepted reference: '..checked..' recognition comparisons passed')
print('RESULT complete path/name mappings, exclusions, no-file defaults, optional-import fallback, legacy imports and manual priority passed')
