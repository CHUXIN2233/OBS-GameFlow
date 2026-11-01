# OBS GameFlow

[简体中文](README.zh-CN.md) · English

Detects games and switches OBS capture sources, with desktop capture and automatic replay buffer management.

[Download script](https://github.com/CHUXIN2233/OBS-GameFlow/releases/latest/download/OBS_Game_Follow.lua) · [Releases](https://github.com/CHUXIN2233/OBS-GameFlow/releases)

## Install

1. Download `OBS_Game_Follow.lua` and keep it in a permanent folder.
2. In OBS, open **Tools → Scripts** and add that file.
3. Check the capture source, then enable **Auto-switch games**, **Automatic replay** and **Record desktop** as needed. All three start off when the script is first added.

The game library is built in. No SRM installation, database download or database path setup is required. The Lua file is the only runtime file; no ASS, Python, WebSocket connection or background helper is needed.

On first use, OGF selects the sole existing native Game Capture source. Create one in your recording scene if none exists, or select one under **Advanced → Capture sources** if there are several. Scenes and sources are not created automatically.

To upgrade, keep the filename and location, replace the script and reload its existing OBS entry. Your settings are retained. Keep only one automatic switching script loaded.

## Settings

- **Auto-switch games** follows the game you're using. Alt+Tab keeps the game selected; closing it falls back to another running game.
- **Automatic replay** manages the replay buffer. It is off by default. With it off, capture switching continues while you control the buffer manually. Turning it off leaves a running buffer running.
- **Record desktop** captures the desktop when no game is running. Games take priority. Automatic replay controls automatic buffer start and stop.
- **Current capture / Replay buffer** show the selected target and the actual On / Off state. Select **Refresh** to update them.

With Automatic replay enabled:

| Record desktop | Buffer behavior |
| --- | --- |
| Off | Starts when a game is detected; stops about five seconds after all games exit. |
| On | Starts once OBS is ready and desktop capture is configured; captures games first, then returns to the desktop. |

Switching games and Alt+Tab do not restart the buffer. Enable Replay Buffer under **Settings → Output** in OBS and assign a Save Replay hotkey. Stopping the buffer discards unsaved footage.

For desktop recording, add a Display Capture source to the current scene below the game and client sources. A single available source can be selected automatically; choose one manually if there are several.

## Library and rules

The built-in library contains 11,054 distinct display names, 13,023 matching rules and 348 exclusions. Names can include aliases, so this is not a count of distinct games. Data is updated with script releases; the running script does not download it.

Add one entry per line under **Advanced → Library and rules → Custom game rules**:

```text
mygame.exe=My game
```

Custom rules take priority. Path matching, ambiguity checks, exclusions and League handling are retained.

External Discord JSON and compatible SRM Lua paths are optional. Most users can leave them empty. Valid configured paths load as before; missing or unreadable optional imports use the built-in library. Existing setting keys remain compatible.

## League of Legends and SRM

For the League client, add a Window Capture source directly to the game scene above Game Capture. Under **Advanced → Clients**, select its scene and source, then enable Capture clients. The default rule is `LeagueClientUx.exe=英雄联盟客户端`; the label can be changed to `League client`. Matches and other recognized games take priority, with fallback to the client when a match exits.

SRM remains optional for saving, naming and organizing replays. If OGF manages the buffer, disable SRM's automatic buffer start and restart-after-save options.

## Language and diagnostics

The UI follows OBS by default, with manual Simplified Chinese and English options. Source names, paths and custom rules stay as configured. Advanced and Diagnostics start collapsed.

To investigate detection, select **Check window in 3 seconds**, switch to your game, then refresh the results. The check reads window information without changing the capture target. Normal startup waits no longer open Script Log; configuration errors still produce warnings.

Windows native Game Capture, Window Capture and Display Capture are supported. Recognition does not guarantee that OBS can capture every game. Minimized games may stop rendering.

## License and acknowledgements

From v1.1.0, this program and the SRM-derived portions use [GPL-3.0-or-later](LICENSE). The original GameFlow [MIT notice](LICENSE-MIT.txt) is retained. Earlier MIT releases are unchanged.

The built-in records are compiled from Discord detection metadata and [Smart Replay Mover](https://github.com/SlonickLab/Smart-Replay-Mover) game mappings and exclusions. They are not claimed as original project data. Third-party data retain their rights and applicable terms; the project license grants no additional data rights. See [source and copyright notices](THIRD_PARTY_NOTICES.md).
