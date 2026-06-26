# VoxFree 0.4.0 — ReadLoud Indicator & Core Decoupling

## Goal
Add a Gnome system tray indicator (AppIndicator/Ayatana) for ReadLoud (TTS)
while decoupling the core engine from the UI via a well-defined state file.

## Architecture

```
┌─────────────────────┐     writes    ┌─────────────────────┐
│    Core (Bash)      │ ────────────→ │   State File        │
│  voxfree-readloud   │               │  /tmp/voxfree/state │
│  voxfree-stop-all   │               │  STATE=idle|playing  │
│  voxfree-readloud-  │               │  PID=1234            │
│    last (new)       │               │  LAST_TEXT=...       │
└─────────┬───────────┘               └──────────┬────────────┘
          │                                      │
          │ calls (subprocess)                   │ reads (polls 1s)
          │                                      │
          └──────────────────┬───────────────────┘
                             │
                    ┌────────▼────────┐
                    │  UI (Python)    │
                    │  Indicator      │
                    │  (swappable)    │
                    └─────────────────┘
```

**Key principle:** Core never imports or knows about the UI. The UI only calls
public API commands and reads the state file. Either can be replaced independently.

---

## Files to Create

### `lib/state.sh` — State file library (shared bash)
- `state_init` — create `/tmp/voxfree/state` with defaults
- `state_set KEY VAL` — write `key=val` to state file
- `state_get KEY` — read key from state file (for other scripts)
- `state_set_playing` — writes STATE=playing, PID=$$, LAST_TEXT=...
- `state_set_idle` — writes STATE=idle, clears PID
- State file format: simple `KEY=VALUE` lines

### `ReadLoud/voxfree-readloud-last.sh` — Replay command
- Read `LAST_TEXT` from `/tmp/voxfree/state`
- Pipe to `mimic3 --voice "$VOICE" --stdout | aplay -q`
- Update state file to playing

### `ReadLoud/voxfree-indicator` — Python3 indicator script
- **Imports:** `gi.repository.Gtk`, `gi.repository.GLib`,
  `gi.repository.AyatanaAppIndicator3` (fallback `AppIndicator3`)
- **Behavior:**
  - Polls `/tmp/voxfree/state` every 1 second via `GLib.timeout_add_seconds`
  - Shows icon in system tray:
    - Idle: `audio-speakers`
    - Playing: `media-playback-stop`
  - Menu items:
    - **"Read Aloud"** (idle) / **"Stop Reading"** (playing)
      → calls `voxfree-readloud` / `voxfree-stop-all` via subprocess
    - **"Replay Last"** → calls `voxfree-readloud-last`
      (grayed out if `LAST_TEXT` is empty in state file)
    - Separator
    - **"Quit"** → exits the indicator
  - Single-instance guard via `/tmp/voxfree/indicator.pid`
  - Graceful fallback: if AppIndicator libs missing, show `notify-send` error
- **Dependencies:** `python3-gi`, `gir1.2-ayatanaappindicator3-0.1`

---

## Files to Modify

### `ReadLoud/voxfree-readloud.sh` — Core TTS toggle
Changes:
- Source `lib/state.sh` at top
- On Toggle ON: save `LAST_TEXT` to state, call `state_set_playing`
- On Toggle OFF (PID found): call `state_set_idle`
- On completion (background `rm -f $PIDFILE`): call `state_set_idle`
- Also save text to `/tmp/voxfree/state LAST_TEXT` for replay
- Keep `/tmp/voxfree-readloud.pid` for backward compatibility (indicator
  uses the new state file, but old PID file is kept for existing behavior)

### `ReadLoud/voxfree-readloud-stop.sh` — Force-stop
Changes:
- Call `state_set_idle` before killing processes

### `ReadLoud/voxfree-stop-all.sh` — Universal stop
Changes:
- Call `state_set_idle` before killing processes

### `ReadLoud/readloud.sh` — ReadLoud installer
Changes:
- Install `voxfree-indicator` to `$BIN_DIR` (alongside other scripts)
- Install `voxfree-readloud-last` to `$BIN_DIR`
- Create autostart `.desktop` file:
  - System mode: `/etc/xdg/autostart/voxfree-indicator.desktop`
  - User mode: `~/.config/autostart/voxfree-indicator.desktop`
- Ask user: "Start VoxFree indicator in system tray at login? [Y/n]"
- Optionally register shortcut `Super+Shift+T` to launch indicator
- Copy `lib/state.sh` to data dir

### `deps.sh` — Dependency installer
Changes:
- Add `gir1.2-ayatanaappindicator3-0.1` to `TTS_PKGS`
- Add `python3-gi` to `COMMON_PKGS`

### `install.sh` — Main installer
Changes:
- During TTS setup, offer: "Install system tray indicator? [Y/n]"
- Ensure `lib/state.sh` is copied to `$WRAPPER_DATA_DIR/lib/`
- Ensure `ReadLoud/voxfree-indicator` is copied to data dir
- Add `--indicator` flag to install only indicator (future use)

### `uninstall.sh` — Uninstaller
Changes:
- Remove `voxfree-indicator` from bin dirs (both system and user mode)
- Remove `voxfree-readloud-last` from bin dirs
- Remove autostart `.desktop` file:
  - System: `/etc/xdg/autostart/voxfree-indicator.desktop`
  - User: `~/.config/autostart/voxfree-indicator.desktop`
- Kill any running indicator process (`pkill -f voxfree-indicator`)
- Remove `/tmp/voxfree/` state directory
- Clean up GNOME shortcut for indicator if registered

### `packaging/DEBIAN/control` — Debian package metadata
Changes:
- `Depends:` add `python3-gi, gir1.2-ayatanaappindicator3-0.1`
- Bump `Installed-Size`

### `packaging/DEBIAN/postinst` — Post-install script
Changes:
- Add `ReadLoud/voxfree-indicator:voxfree-indicator` to the list
- Add `ReadLoud/voxfree-readloud-last.sh:voxfree-readloud-last` to list
- Add `lib/state.sh:lib/state.sh` handling

### `build-deb.sh` — .deb builder
Changes:
- Add `voxfree-indicator` to ReadLoud file copy list
- Add `voxfree-readloud-last.sh` to ReadLoud file copy list
- Add `lib/state.sh` to lib file copy list
- Bump version handling

### `VERSION`
- Change from `0.3.4` to `0.4.0`

### `voxfree-doctor.sh` — Health checker
Changes:
- Add new check section: "Indicator"
  - Check `python3-gi` installed
  - Check `gir1.2-ayatanaappindicator3-0.1` installed
  - Check `voxfree-indicator` is installed in bin dir
  - Check if indicator process is currently running

### `voxfree-switch.sh` — Keyboard layout switcher
Changes (minor):
- If indicator launch shortcut was registered, include it in dconf profile

---

## State File Format

File: `/tmp/voxfree/state`

```
# VoxFree ReadLoud state — written by core, read by any UI consumer
STATE=playing          # idle | playing
PID=1234               # process ID of mimic3 pipeline (empty when idle)
LAST_TEXT=Hello world  # last text that was read aloud (empty if none)
STARTED_AT=1712345678  # unix timestamp of when reading started
```

The file is atomic-write via `echo` redirect to a temp file + `mv`.
This prevents the UI from reading a half-written file.

---

## Indicator Behavior Details

### Icon switching
- **Idle state:** `audio-speakers` (or `audio-x-generic` fallback)
- **Playing state:** `media-playback-stop` (red tinted via overlay if possible)
- Icon updates every 1s poll cycle

### Menu item states
| Item | Idle | Playing | No Last Text |
|------|------|---------|--------------|
| Read Aloud | Enabled | Hidden | Enabled |
| Stop Reading | Hidden | Enabled | Hidden |
| Replay Last | Enabled | Disabled | Disabled (gray) |
| Quit | Enabled | Enabled | Enabled |

### Error handling
- If `voxfree-readloud` returns non-zero (no text selected), indicator
  shows a brief "No text selected" tooltip via `notify-send`
- If Python dependencies missing, script prints to stderr and exits
- Indicator auto-exits if `/tmp/voxfree/state` becomes unreadable

---

## Edge Cases

1. **Indicator launched twice** — second instance detects `/tmp/voxfree/indicator.pid`,
   brings existing window to front (via D-Bus activate), then exits
2. **Core script crashes** — `state_set_idle` is called on next state change;
   indicator shows stale state for at most 1s then corrects
3. **Reboot/crash** — `/tmp/` is cleaned on boot, so state is clean
4. **No text selected on "Read Aloud"** — indicator shows notification from
   core script's exit; no special handling needed
5. **Replay during active reading** — "Replay Last" is disabled while playing
6. **Non-Gnome desktop** — indicator works with any AppIndicator-compatible
   panel (KDE, XFCE, Budgie, etc.)

---

## Verification

After implementation:
1. `sudo bash deps.sh --tts` — verify gir1.2-ayatanaappindicator3-0.1 installed
2. `bash ReadLoud/readloud.sh --standard` — verify indicator installed + autostart
3. Run `voxfree-indicator` — verify icon appears in system tray
4. Select text → click "Read Aloud" in menu — verify TTS starts
5. Click "Stop Reading" — verify TTS stops, icon returns to idle
6. Click "Replay Last" — verify last text is re-read
7. `voxfree --doctor` — verify indicator checks pass
8. Verify state file: `cat /tmp/voxfree/state` shows correct state
9. Test uninstall: `sudo bash uninstall.sh` — verify indicator removed
10. `voxfree-readloud` keyboard shortcut still works (backward compat)
