# Local verification

The lifecycle suite simulates the OBS frontend and uses the real Windows LuaJIT / Win32 FFI. UI checks cover language selection, labels, help, folding and replay status. Database checks use real libobs JSON parsing with files supplied by the tester.

From the repository root, with Python 3 installed for testing only:

```powershell
python tests/run_tests.py --lua-dll "C:/Program Files/obs-studio/bin/64bit/lua51.dll"
```

Optional database checks:

```powershell
python tests/run_tests.py --lua-dll "C:/Program Files/obs-studio/bin/64bit/lua51.dll" --database-dir "C:/path/to/your/database-folder" --srm-file "C:/path/to/Smart_Replay_Mover.lua"
```

The database directory must contain `discord_games.json`. No database is distributed here. Tests do not launch OBS or change its configuration. They do not replace live-game acceptance.

Release validation completed on Windows with OBS 33.0.1: 34 lifecycle checks, 6 UI checks and 6 recognition cases passed. Native OBS property callbacks, bilingual text and UI preference persistence were also checked in an isolated OBS instance. User acceptance covered Tarkov, Slay the Spire 2 and League of Legends, Alt+Tab, game fallback, desktop capture, OBS restart and SRM saving. The final Chinese UI was observed in the production instance; a separate visual inspection of its English UI was not performed.

Version 1.0.1 adds regressions for delayed game/client window enumeration, read-only inspection and genuine configuration warnings. The startup issue was reproduced in the old suite; the fixed script was loaded into production OBS with the existing Tarkov target and replay buffer retained. A fresh live-game launch after the fix has not yet been confirmed by the user.
