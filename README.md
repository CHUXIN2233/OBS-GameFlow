# OBS GameFlow

[简体中文](README.zh-CN.md) · English

I switch between games a lot and got tired of picking a new capture window in OBS every time. This script follows the game I'm playing. It can also handle desktop capture and the replay buffer if I want it to.

[Download](https://github.com/CHUXIN2233/OBS-GameFlow/releases/latest/download/OBS_Game_Follow.lua) · [Releases](https://github.com/CHUXIN2233/OBS-GameFlow/releases)

## Install

1. Download `OBS_Game_Follow.lua` and keep it somewhere permanent.
2. In OBS, go to **Tools → Scripts** and add the file.
3. Pick your Game Capture source if needed, then turn on the switches you want.

All three main switches are off by default. If there's only one existing Game Capture source, GameFlow picks it automatically. Otherwise, select one under **Advanced → Capture sources**. It won't create scenes or sources for you.

The game list is built in. The Lua file is enough to run GameFlow; no other plugin or background app is required.

## Settings

- **Auto-switch games:** follows the game you're using. Alt+Tab keeps the game selected; when it closes, another running game can take over.
- **Automatic replay:** starts and stops the replay buffer based on the settings below. When off, OBS's manual replay controls still work. Disabling it doesn't stop a buffer that's already running.
- **Record desktop:** uses Display Capture only when no game is running. If a game is still open, it stays on the game.

With **Automatic replay** on:

- **Record desktop off:** replay starts when a game is found and stops about 5 seconds after the last game exits.
- **Record desktop on:** replay stays on while OBS is ready and desktop capture is set up. Games still take priority.

Switching games or using Alt+Tab won't restart the replay buffer. To save clips, enable **Replay Buffer** in **OBS Settings → Output** and set a save hotkey. Stopping the buffer loses anything you haven't saved.

## A few things to set up

- **Desktop:** add a Display Capture source to the same scene, below the game/client capture sources. If you have more than one, choose it under **Advanced → Capture sources**.
- **League of Legends:** add a Window Capture source above Game Capture. Choose it under **Advanced → Clients** and enable client capture. The client and the match are handled separately.
- **Unrecognized game:** add a rule under **Advanced → Library and rules → Custom game rules**. One per line, for example:

  ```text
  mygame.exe=My Game
  ```

GameFlow has a built-in game list and exclusions, so you usually won't need custom rules or external data paths. The UI follows OBS's language, or you can choose Chinese or English. Advanced settings and diagnostics are collapsed by default.

Windows only. A game being recognized doesn't guarantee OBS can hook it; minimized games may stop rendering. When updating, replace the Lua file at the same path so your existing settings are kept.

## Optional tools and thanks

- [Smart Replay Mover](https://github.com/SlonickLab/Smart-Replay-Mover) — sorts saved clips into game folders and handles filenames. It's optional. If GameFlow is managing the buffer, disable its auto-start and restart-after-save options so they don't fight over the buffer.
- [OBS Notifier](https://github.com/DmitriySalnikov/OBSNotifier) — shows desktop notifications for OBS events, including replay saves. Also optional.

The built-in matching data uses Discord game detection metadata and game mappings/exclusions from Smart Replay Mover. Those records aren't claimed as original GameFlow data. Copyright and source details are in [Third-party notices](THIRD_PARTY_NOTICES.md).

## License

From v1.1.0, this bundled edition is licensed under [GPL-3.0-or-later](LICENSE), with the original GameFlow [MIT notice](LICENSE-MIT.txt) retained. Earlier MIT releases keep their original license. The project license doesn't change third-party data rights.
