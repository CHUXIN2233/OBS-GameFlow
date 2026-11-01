# Changelog

## 1.1.0

- Embed a unified game library in the Lua script; no database download or SRM path is required.
- Preserve path matching, ambiguity handling, exclusions, custom-rule priority, existing configured imports and missing-file fallback.
- Select the sole existing Game Capture source on first use; retain explicit choices and legacy default-source settings.
- Retain capture, League, desktop and replay behavior, including the v1.0.1 startup logging fix.
- Update English/Chinese installation guidance, add a direct single-file download and retain source attribution.
- Adopt GPL-3.0-or-later for this bundled edition and SRM-derived portions; retain the original MIT notice and third-party data terms. Earlier releases remain unchanged.

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
