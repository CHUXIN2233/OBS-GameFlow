# Verification

The LuaJIT suite simulates the OBS frontend and uses real Windows Win32 FFI. The library equivalence suite uses real libobs JSON parsing to compare the built-in records against the accepted external-library version.

Python is needed only for development tests, not to run OBS GameFlow.

```powershell
python tests/run_tests.py --lua-dll "C:/Program Files/obs-studio/bin/64bit/lua51.dll"
```

Optional external-data and full-reference checks:

```powershell
python tests/run_tests.py --lua-dll "C:/Program Files/obs-studio/bin/64bit/lua51.dll" --database-dir "C:/path/to/existing/database-folder" --srm-file "C:/path/to/Smart_Replay_Mover.lua" --reference-script "C:/path/to/OGF-v1.0.1/OBS_Game_Follow.lua"
```

The database folder must contain discord_games.json. These inputs are supplied by the tester. Tests do not launch production OBS or modify its configuration.

Validation for v1.1.0: 37 lifecycle/source-selection checks, 6 UI checks, 6 external-data cases and 24,503 recognition comparisons passed. Complete path/name mappings, exclusions, missing/invalid optional import fallback, legacy configured imports and manual-rule precedence were compared.

An isolated OBS 33.0.1 checked bilingual native properties, settings persistence, sole-source selection, no guessing with multiple sources and legacy default-source migration. The built-in version was loaded in the installed OBS: the existing Tarkov target and scene visibility were retained, the buffer stayed active without restarting, and no Lua loading errors were seen. These checks do not claim new live-game coverage beyond the previously accepted workflows.
