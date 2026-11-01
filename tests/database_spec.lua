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
obslua={LOG_INFO=200,LOG_WARNING=300,timer_remove=function() end,
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
script_path=function() return os.getenv("OGF_DATABASE_DIR") end
dofile(os.getenv("OGF_SCRIPT_FILE"))
local settings=lib.obs_data_create()
script_defaults(settings)
assert(lib.obs_data_get_bool(settings,"auto_replay")==false,"automatic replay default must be OFF")
lib.obs_data_set_bool(settings,"auto_replay",true)
local saved=lib.obs_data_create_from_json(lib.obs_data_get_json(settings))
script_defaults(saved)
assert(lib.obs_data_get_bool(saved,"auto_replay")==true,"automatic replay must persist in OBS JSON")
lib.obs_data_release(saved)
lib.obs_data_set_bool(settings,"auto_replay",false)
lib.obs_data_set_string(settings,"srm_file",os.getenv("OGF_SRM_FILE"))
script_update(settings)
local function up(fn,name)
    for i=1,100 do
        local k,v=debug.getupvalue(fn,i)
        if k==name then return v end
        if not k then break end
    end
    error(name)
end
local recognize=up(up(up(script_update,"on_timer"),"refresh_running"),"game_for_window")
local function check(path,title,expected)
    local got=recognize({path=path,title=title or ""})
    assert(got==expected,path..": "..tostring(got).." != "..tostring(expected))
end
check([[D:\Games\DeadByDaylight\Binaries\Win64\DeadByDaylight-Win64-Shipping.exe]],"", "Dead by Daylight")
check([[D:\Games\EscapeFromTarkov.exe]],"", "Escape from Tarkov")
check([[C:\Riot Games\League of Legends\Game\League of Legends.exe]],"", "英雄联盟")
check([[C:\Riot Games\LeagueClientUx.exe]],"",nil)
check([[C:\Steam\steam.exe]],"",nil)
check([[C:\Windows\explorer.exe]],"",nil)
local mappings,exclusions=up(recognize,"srm"),up(recognize,"ignored")
local count,ignored=0,0
for _ in pairs(mappings) do count=count+1 end
for _ in pairs(exclusions) do ignored=ignored+1 end
assert(count>1000 and ignored>100,"database mappings not loaded")
lib.obs_data_release(settings)
print("RESULT real libobs JSON / existing Discord and SRM: 6 recognition cases passed")
print("RESULT real libobs JSON: automatic replay default and persisted ON value passed")
