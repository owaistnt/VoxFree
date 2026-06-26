# ReadLoud Indicator & Core Decoupling

## Problem

ReadLoud (TTS) had no persistent UI — the only way to start/stop reading
was via keyboard shortcuts (F9 / Super+Shift+R). Users wanted:

1. Visual feedback showing whether TTS is currently playing
2. A clickable way to start/stop reading without remembering shortcuts
3. Ability to replay the last spoken text
4. The core engine and UI to be decoupled so either can be replaced

## Envisioning

From the user's perspective:
- A small icon appears in the Gnome system tray (top bar)
- When idle: icon shows a speaker; clicking opens a menu with "Read Aloud"
- When reading: icon changes to a stop symbol; menu shows "Stop Reading"
- "Replay Last" re-speaks the most recently read text
- Keyboard shortcuts continue to work exactly as before

Architecturally:
- Core bash scripts emit state via a file (not via UI-specific mechanisms)
- UI reads state file + calls public API commands only
- Neither side imports or depends on the other's internals

## Solution

### Architecture

```
Core (Bash)  ──writes──→  /tmp/voxfree/state  ←──reads──  UI (Python)
  voxfree-readloud          STATE=playing         │         AppIndicator
  voxfree-stop-all          PID=1234              │
  voxfree-readloud-last     LAST_TEXT=...         │
                           ──calls──→  subprocess
```

### New Files

| File | Purpose |
|------|---------|
| `lib/state.sh` | Bash library for atomic state file operations: `state_set_playing`, `state_set_idle`, `state_get`, etc. |
| `ReadLoud/voxfree-readloud-last.sh` | Re-read the last spoken text from state file |
| `ReadLoud/voxfree-indicator` | Python3 GTK3+AppIndicator system tray icon with dynamic menu |

### Modified Files

| File | Change |
|------|--------|
| `ReadLoud/voxfree-readloud.sh` | Sources `lib/state.sh`; calls `state_set_playing`/`state_set_idle` on start/stop |
| `ReadLoud/voxfree-readloud-stop.sh` | Sources `lib/state.sh`; calls `state_set_idle` before kill |
| `ReadLoud/voxfree-stop-all.sh` | Sources `lib/state.sh`; calls `state_set_idle` when TTS stopped |
| `ReadLoud/readloud.sh` | Installs indicator + replay + `lib/state.sh`; creates autostart `.desktop`; asks about autostart |
| `deps.sh` | Adds `gir1.2-ayatanaappindicator3-0.1` and `python3-gi` to APT packages |
| `install.sh` | Ensures `lib/state.sh` is copied with proper permissions |
| `uninstall.sh` | Removes indicator, replay, `lib/`, state dir, autostart; kills indicator process |
| `build-deb.sh` | Includes `voxfree-indicator`, `voxfree-readloud-last.sh`, `state.sh` in .deb |
| `packaging/DEBIAN/control` | Adds `python3-gi, gir1.2-ayatanaappindicator3-0.1` to Depends |
| `packaging/DEBIAN/postinst` | Copies indicator + replay + `lib/state.sh` on upgrades |
| `voxfree-doctor.sh` | New "Indicator" section with 6 checks (libs, scripts, process, state) |
| `VERSION` | 0.3.4 → 0.4.0 |

### State File Format (`/tmp/voxfree/state`)

```
STATE=playing|idle
PID=1234
LAST_TEXT=Hello world
STARTED_AT=1712345678
```

### Indicator Behavior

| State | Icon | Menu (visible items) |
|-------|------|----------------------|
| Idle | `audio-speakers` | Read Aloud, Replay Last, Quit |
| Playing | `media-playback-stop` | Stop Reading, Replay Last (disabled), Quit |

- Polls state file every 1 second via `GLib.timeout_add_seconds`
- Falls back from `AyatanaAppIndicator3` to `AppIndicator3`
- Single-instance guard via `/tmp/voxfree/indicator.pid`

## Related Files

| File | Purpose |
|------|---------|
| `lib/state.sh` | State file library |
| `ReadLoud/voxfree-readloud.sh` | Core TTS toggle (updated) |
| `ReadLoud/voxfree-readloud-stop.sh` | Force-stop TTS (updated) |
| `ReadLoud/voxfree-stop-all.sh` | Universal stop (updated) |
| `ReadLoud/voxfree-readloud-last.sh` | Replay last text |
| `ReadLoud/voxfree-indicator` | Python AppIndicator |
| `ReadLoud/readloud.sh` | Installer (updated) |
| `deps.sh` | Dependency installer (updated) |
| `install.sh` | Main installer (updated) |
| `uninstall.sh` | Uninstaller (updated) |
| `build-deb.sh` | .deb builder (updated) |
| `packaging/DEBIAN/control` | Package metadata (updated) |
| `packaging/DEBIAN/postinst` | Post-install script (updated) |
| `voxfree-doctor.sh` | Health checker (updated) |
| `VERSION` | Version bump to 0.4.0 |
| `.opencode/plans/indicator-and-decoupling.md` | Implementation plan |
