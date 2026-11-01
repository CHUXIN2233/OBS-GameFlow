"""Disposable hidden-window regression; never touches the user's OBS process."""
from pathlib import Path
import argparse,ctypes,os,subprocess,sys,threading,time
from ctypes import wintypes

parser=argparse.ArgumentParser()
parser.add_argument('script',type=Path)
parser.add_argument('--lua-dll',type=Path,required=True,help='OBS bin/64bit/lua51.dll')
parser.add_argument('--child',action='store_true')
args=parser.parse_args()
if not args.child:
    startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
    try:
        result=subprocess.run([sys.executable,str(Path(__file__).resolve()),str(args.script.resolve()),'--lua-dll',str(args.lua_dll.resolve()),'--child'],capture_output=True,text=True,timeout=6,startupinfo=startup)
        print(result.stdout,end='');print(result.stderr,end='')
        sys.exit(result.returncode)
    except subprocess.TimeoutExpired as exc:
        stdout=exc.stdout.decode(errors='replace') if isinstance(exc.stdout,bytes) else (exc.stdout or '')
        print(stdout,end='')
        assert 'SAME_PROCESS_WM_GETTEXT_WAITING_FOR_SCRIPT_LOCK' in stdout,'unexpected test timeout'
        print('REPRODUCED: background window title read and UI script callback deadlock')
        sys.exit(2)

user32=ctypes.WinDLL('user32',use_last_error=True)
kernel32=ctypes.WinDLL('kernel32',use_last_error=True)
kernel32.GetModuleHandleW.argtypes=[wintypes.LPCWSTR];kernel32.GetModuleHandleW.restype=wintypes.HMODULE
WNDPROC=ctypes.WINFUNCTYPE(ctypes.c_ssize_t,wintypes.HWND,wintypes.UINT,wintypes.WPARAM,wintypes.LPARAM)
lock=threading.Lock();armed=False;window_reads=0
user32.DefWindowProcW.argtypes=[wintypes.HWND,wintypes.UINT,wintypes.WPARAM,wintypes.LPARAM]
user32.DefWindowProcW.restype=ctypes.c_ssize_t
@WNDPROC
def procedure(hwnd,message,wparam,lparam):
    global window_reads
    if armed and message==0x000D:
        window_reads+=1
        print('SAME_PROCESS_WM_GETTEXT_WAITING_FOR_SCRIPT_LOCK',flush=True)
        # Mirrors OBS's UI callback waiting for its Lua mutex while the timer owns it.
        with lock: pass
    return user32.DefWindowProcW(hwnd,message,wparam,lparam)
class WNDCLASS(ctypes.Structure):
    _fields_=[('style',wintypes.UINT),('lpfnWndProc',WNDPROC),('cbClsExtra',ctypes.c_int),('cbWndExtra',ctypes.c_int),
              ('hInstance',wintypes.HINSTANCE),('hIcon',wintypes.HICON),('hCursor',wintypes.HANDLE),('hbrBackground',wintypes.HBRUSH),
              ('lpszMenuName',wintypes.LPCWSTR),('lpszClassName',wintypes.LPCWSTR)]
instance=kernel32.GetModuleHandleW(None)
cls=WNDCLASS();cls.lpfnWndProc=procedure;cls.hInstance=instance;cls.lpszClassName='OGFHiddenDeadlockRegression'
user32.RegisterClassW.argtypes=[ctypes.POINTER(WNDCLASS)];assert user32.RegisterClassW(ctypes.byref(cls))
user32.CreateWindowExW.argtypes=[wintypes.DWORD,wintypes.LPCWSTR,wintypes.LPCWSTR,wintypes.DWORD,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_int,wintypes.HWND,wintypes.HMENU,wintypes.HINSTANCE,ctypes.c_void_p]
user32.CreateWindowExW.restype=wintypes.HWND
hwnd=user32.CreateWindowExW(0,cls.lpszClassName,'OGF test window',0,0,0,10,10,None,None,instance,None)
assert hwnd
os.environ['OGF_TEST_HWND']=str(hwnd)
folder=args.lua_dll.resolve().parent
cookie=os.add_dll_directory(str(folder));lua=ctypes.CDLL(str(folder/'lua51.dll'))
lua.luaL_newstate.restype=ctypes.c_void_p
lua.luaL_openlibs.argtypes=[ctypes.c_void_p]
lua.luaL_loadbuffer.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_size_t,ctypes.c_char_p]
lua.lua_pcall.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int]
lua.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lua.lua_tolstring.restype=ctypes.c_char_p
lua.lua_close.argtypes=[ctypes.c_void_p]
state=lua.luaL_newstate();lua.luaL_openlibs(state)
setup=b'obslua={LOG_INFO=300,LOG_WARNING=200}\n'+args.script.read_bytes()+b'''
local function up(fn,name,value)
 for i=1,100 do local key,old=debug.getupvalue(fn,i);if key==name then if value then debug.setupvalue(fn,i,value) end;return old end;if not key then break end end
 error(name)
end
local foreground=up(up(script_update,'on_timer'),'foreground_window')
local native=up(foreground,'user32')
local proxy=setmetatable({GetForegroundWindow=function() return ffi.cast('void*',tonumber(os.getenv('OGF_TEST_HWND'))) end},{__index=function(_,name)return native[name] end})
up(foreground,'user32',proxy)
local window,reason=foreground()
assert(window,reason)
assert(window.title=='' and window.class=='','own window should have no synchronous text read')
'''
errors=[]
def worker():
    with lock:
        result=lua.luaL_loadbuffer(state,setup,len(setup),b'@deadlock-regression')
        if result==0:result=lua.lua_pcall(state,0,-1,0)
        if result:errors.append(lua.lua_tolstring(state,-1,None).decode(errors='replace'))
armed=True
thread=threading.Thread(target=worker);thread.start()
user32.PeekMessageW.argtypes=[ctypes.POINTER(wintypes.MSG),wintypes.HWND,wintypes.UINT,wintypes.UINT,wintypes.UINT]
user32.DispatchMessageW.argtypes=[ctypes.POINTER(wintypes.MSG)];user32.DispatchMessageW.restype=ctypes.c_ssize_t
message=wintypes.MSG()
while thread.is_alive():
    while user32.PeekMessageW(ctypes.byref(message),None,0,0,1):
        user32.TranslateMessage(ctypes.byref(message));user32.DispatchMessageW(ctypes.byref(message))
    time.sleep(.005)
thread.join();lua.lua_close(state)
if errors:raise RuntimeError(errors[0])
assert window_reads==0
print('PASS: same-process window skipped; UI and script complete without waiting',flush=True)
