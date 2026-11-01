"""Local LuaJIT tests; never launches OBS or changes its configuration."""
import argparse
import ctypes
import os
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--lua-dll', type=Path, required=True, help='OBS bin/64bit/lua51.dll')
parser.add_argument('--database-dir', type=Path, help='Existing OGF folder with discord_games.json')
parser.add_argument('--srm-file', type=Path, help='Existing Smart_Replay_Mover.lua')
parser.add_argument('--reference-script', type=Path, help='Accepted script for complete built-in database equivalence checks')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
os.environ['OGF_SCRIPT_FILE'] = str(root / 'OBS_Game_Follow.lua')
if args.database_dir:
    os.environ['OGF_DATABASE_DIR'] = str(args.database_dir.resolve())
if args.srm_file:
    os.environ['OGF_SRM_FILE'] = str(args.srm_file.resolve())
if args.reference_script:
    os.environ['OGF_REFERENCE_SCRIPT_FILE'] = str(args.reference_script.resolve())
cookie = os.add_dll_directory(str(args.lua_dll.resolve().parent))
lua = ctypes.CDLL(str(args.lua_dll.resolve()))
lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadbuffer.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
lua.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_close.argtypes = [ctypes.c_void_p]
os.environ['OGF_OBS_DLL'] = str(args.lua_dll.resolve().with_name('obs.dll'))
if args.database_dir and args.srm_file:
    # ctypes uses modern dependency search flags; FFI can reuse the loaded DLL.
    libobs = ctypes.CDLL(os.environ['OGF_OBS_DLL'])
specs = ['lifecycle_spec.lua']
if args.database_dir and args.srm_file:
    specs.append('database_spec.lua')
    if args.reference_script:
        specs.append('builtin_equivalence_spec.lua')
for spec in specs:
    state = lua.luaL_newstate()
    lua.luaL_openlibs(state)
    try:
        # Read with Python's Unicode path handling; Windows LuaJIT's fopen does
        # not accept the UTF-8 absolute filename when this folder has Chinese text.
        source = Path(__file__).with_name(spec).read_bytes()
        code = lua.luaL_loadbuffer(state, source, len(source), ('@' + spec).encode('utf-8'))
        if code == 0:
            code = lua.lua_pcall(state, 0, -1, 0)
        if code:
            raise RuntimeError(lua.lua_tolstring(state, -1, None).decode('utf-8', errors='replace'))
    finally:
        lua.lua_close(state)
