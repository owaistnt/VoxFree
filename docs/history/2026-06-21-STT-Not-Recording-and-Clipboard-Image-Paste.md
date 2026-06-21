# 2026-06-21-STT-Not-Recording-and-Clipboard-Image-Paste

## Overview

Two issues discovered during STT (SpeakToType) testing on a multi-user system:

1. STT would not record or paste — F11 showed "Nothing active" or "Nothing recognised"
2. Transcribed text was pasted as an image placeholder `[Image 1]` with error: `ERROR: Cannot read "clipboard" (this model does not support image input)`

---

## Issue 1: STT Not Recording

### Symptoms

- Pressing F10 (start dictation) did not show "REC" notification
- Pressing F11 showed "Nothing active."
- No WAV files were created in `/tmp/`
- The error message `ERROR: Cannot read "clipboard"` appeared (not from VoxFree — from an AI assistant reading clipboard)

### Root Cause Analysis

**Primary cause: Shortcut path mismatch.**

GNOME shortcuts in dconf pointed to `~/.local/bin/voxfree-dictate` and `~/.local/bin/voxfree-stop-all`:

```
dconf read /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-dictate/command
→ '/home/developer/.local/bin/voxfree-dictate'
```

But these were **old user-level scripts** (installed via `install.sh --user`) that used fragile PID file checks.

The `.deb` install only updated scripts in `/usr/local/bin/`. The `postinst` script never touched `~/.local/bin/`. So when GNOME triggered the shortcuts, it ran the **old broken scripts**.

**Secondary causes:**

- Stale recording files owned by a different user (`owais`) in `/tmp/` — `rm -f` failed silently due to ownership mismatch
- PID-based detection failed because scripts were triggered by GNOME (different process context)

### Approaches Tried

| # | Approach | Result |
|---|----------|--------|
| 1 | Fixed `wl-copy` to use `-t text/plain` | ✅ Fixed image paste issue. Did not fix recording. |
| 2 | Made WAV filenames unique (`stt-recording-<PID>-<timestamp>.wav`) | ✅ Prevents cross-user file conflicts. Did not fix recording. |
| 3 | Made stop script find WAV file via `ls -t` | ✅ Finds correct WAV. Did not fix recording. |
| 4 | Replaced PID file checks with `fuser`-based detection | ✅ More reliable detection of active recording. Did not fix recording. |
| 5 | Replaced `kill -TERM $PID` with `pkill -TERM -f "arecord.*file"` | ✅ Stops arecord without PID dependency. Did not fix recording. |
| 6 | **Replaced `~/.local/bin/` scripts with updated `/usr/local/bin/` versions** | ✅ **Fixed — shortcuts now point to working scripts.** |

### Final Fix

**Three parts:**

1. **`postinst` update** — scans for active user sessions (`/run/user/*`) and updates `~/.local/bin/` scripts on `.deb` install/upgrade. This ensures shortcuts always point to current scripts.

2. **`fuser`-based detection** — `voxfree-stop-all.sh` and `voxfree-dictate-stop.sh` use `fuser` to detect if a WAV file is actively being written to, instead of relying on PID files. This works regardless of how scripts are launched (terminal, GNOME shortcut, multi-user).

3. **Unique WAV filenames** — `stt-recording-<PID>-<timestamp>.wav` — prevents cross-user file conflicts. Old files are auto-cleaned after 1 hour.

### Related Files

| File | Change |
|------|--------|
| `packaging/DEBIAN/postinst` | Added user-level script sync loop |
| `SpeakToType/voxfree-dictate.sh` | Unique WAV filename + non-blocking cleanup |
| `SpeakToType/voxfree-dictate-stop.sh` | `fuser` detection, `pkill` for arecord, unique WAV discovery |
| `ReadLoud/voxfree-stop-all.sh` | `fuser`-based STT detection |
| `releases/voxfree_0.3.0_all.deb` | Updated with all fixes |

---

## Issue 2: Clipboard Image Paste

### Symptoms

- After successful transcription, text was pasted as `[Image 1]` in target app
- AI assistant showed: `ERROR: Cannot read "clipboard" (this model does not support image input)`

### Root Cause Analysis

`wl-copy` without explicit MIME type inherits the clipboard's existing content type. If an image (screenshot, copied image) was already on the clipboard, the target app treated the transcription text as image data.

### Fix

```bash
# Before:
echo -n "$TRANSCRIPT" | wl-copy 2>/dev/null

# After:
printf '%s' "$TRANSCRIPT" | wl-copy -t text/plain 2>/dev/null
```

The `-t text/plain` flag forces the clipboard content to be treated as plain text.

### Related Files

| File | Change |
|------|--------|
| `SpeakToType/voxfree-dictate-stop.sh` | Added `-t text/plain` to `wl-copy` |
