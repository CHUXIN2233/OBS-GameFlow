# Changelog

## 1.0.1

- Keep expected game/client startup waits in ordinary logs so OBS does not open Script Log while waiting for a capture window.
- Keep warnings for configuration errors; capture retries and replay behavior are unchanged.
- Add four logging regressions and use the actual OBS log-level values in the test frontend.

## 1.0.0

First public release of OBS GameFlow.

- Follow recognized games with one reusable Game Capture source. Keep the target across Alt+Tab and restore another running game when the current one exits.
- Optional desktop capture when no game remains, with games taking priority.
- Default-off automatic replay buffer management, independent of capture switching. Game changes do not restart the buffer.
- League client and match transitions, with optional SRM mapping and replay organization compatibility.
- Compact settings with collapsible advanced options and diagnostics.
- Simplified Chinese and English, following the OBS language by default with a manual override.
- Retain the `OBS_Game_Follow.lua` filename and existing setting keys for upgrades.

The earlier v0.4 plan and v0.5.1 source labels were internal development references. The first public release is 1.0.0.
