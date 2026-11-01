# OBS GameFlow

[简体中文](README.zh-CN.md) · English

Detects games and switches OBS capture sources, with desktop capture and automatic replay buffer management.

For Windows versions of OBS Studio with LuaJIT scripting support. No ASS, Python, WebSocket connection or background helper is required.

## Install

1. Extract the release into a permanent folder.
2. Set up game detection: run the included `Update-GameDatabase.ps1` to download the Discord database, or use custom rules or a compatible SRM Lua mapping as described below.
3. In OBS, open **Tools → Scripts** and add `OBS_Game_Follow.lua`.
4. Add a native **Game Capture** source to your recording scene. Expand **Advanced** in the script settings, select that source and check the database paths. If using SRM mappings, select your own Lua file; otherwise clear the SRM path. The inherited default path may need adjusting.
5. Enable **Auto-switch games**, open a game and check the capture. Enable **Automatic replay** and **Record desktop** as needed. All three switches are off when the script is first added.

To update an existing installation, keep the filename and location, replace `OBS_Game_Follow.lua` and reload its existing OBS entry. Your settings are retained. Keep only one copy loaded.

## Settings

- **Auto-switch games** follows the game you're using. Alt+Tab keeps the game selected; closing it falls back to another running game.
- **Automatic replay** manages the replay buffer. It is off by default. With it off, capture switching continues while you control the buffer manually. Turning it off leaves a running buffer running.
- **Record desktop** captures the desktop when no game is running. Games take priority. This controls the captured picture; **Automatic replay** controls automatic buffer start and stop.
- **Current capture / Replay buffer** show the selected target and the buffer's actual On / Off state. Select **Refresh** to update them.

With **Automatic replay** enabled:

| Record desktop | Buffer behavior |
| --- | --- |
| Off | Starts when a game is detected; stops about five seconds after all games exit. |
| On | Starts once OBS is ready and desktop capture is configured; captures games first and returns to the desktop when none remain. |

Switching games, Alt+Tab and saving a replay do not cause OGF to restart the buffer when changing targets. Enable Replay Buffer under **Settings → Output** in OBS and assign a Save Replay hotkey. Stopping the buffer discards unsaved footage.

For desktop recording, add a **Display Capture** source to the current scene below the game and client sources, then select it under **Advanced → Capture sources**. A single available Display Capture source can be selected automatically.

## Game detection

`Update-GameDatabase.ps1` downloads `discord_games.json` from the [Discord detection endpoint](https://discord.com/api/v9/applications/detectable). It connects only when you run it; the OBS script reads local files. After downloading, select **Advanced → Game rules → Reload databases**. No third-party game database is included in the release.

If PowerShell script execution is restricted, you can save the endpoint's JSON into the script folder yourself and select it under **Discord database**. The endpoint may change. Use custom rules if the download is unavailable.

Add one entry per line under **Custom game rules**:

```text
mygame.exe=My game
```

You can also select a compatible local [Smart Replay Mover](https://github.com/SlonickLab/Smart-Replay-Mover) Lua file to read its embedded game mappings and exclusions. OGF does not execute or modify SRM, and SRM is optional. Data formats can differ between SRM versions.

## League of Legends and other clients

Add a **Window Capture** source directly to your game scene, above Game Capture. Under **Advanced → Clients**, select its scene and source, then enable **Capture clients**. The default rule is:

```text
LeagueClientUx.exe=英雄联盟客户端
```

The name after `=` is a custom display name; you can change it to `League client`. OGF handles the transition between the League client and a match. Matches and other recognized games take priority over clients. After a match exits, the client can resume; after the client closes, the desktop setting applies.

If you use SRM to save and organize replays while OGF manages the buffer, disable SRM's automatic buffer start and restart-after-save options.

## Language and diagnostics

The default is **Follow OBS**. You can select **简体中文** or **English** manually. Language and section visibility are saved with the script settings. Source names, paths and custom rules stay as configured.

**Advanced** and **Diagnostics** start collapsed. To investigate detection, expand Diagnostics, select **Check window in 3 seconds**, switch to your game, then refresh the results. This check reads window information without changing the capture target.

Windows native Game Capture, Window Capture and Display Capture sources are supported. Recognition does not guarantee that OBS can capture a game. For a black or frozen picture, check the game's capture compatibility. Minimized games may stop rendering.

## License and sources

Released under the [MIT License](LICENSE). OBS, the Discord database and SRM code are not included. This project is not affiliated with those projects or game publishers.
