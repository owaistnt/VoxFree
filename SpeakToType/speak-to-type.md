# Speak to Type — Speech-to-Text (STT) for Ubuntu 24.04

Press **F10** (ThinkPad) / **Super+Shift+M** (Standard) → speak → press **F11** / **Super+Shift+K** (Standard) → your words appear at the cursor.
Fully offline. No cloud APIs. Works on GNOME Wayland with all apps.

---

## How It Works

```
Press F10 / Super+Shift+M
    ↓
Mic unmuted automatically (ThinkPad LED turns OFF = recording active)
    ↓
GNOME sound plays (message-new-instant.oga) ← "start speaking now"
    ↓
arecord captures mic at 16kHz mono via ALSA → pipewire-alsa
    ↓
Speak for as long as needed (no time limit)
    ↓
Press F11 / Super+Shift+K
    ↓
GNOME sound plays (complete.oga) ← "processing"
arecord stops, WAV file finalised
    ↓
Sox noise reduction (profiles first 0.5s as noise floor)
    ↓
Whisper base.en + int8 transcribes (~2 seconds)
    ↓
Text copied to clipboard
    ↓
Smart paste:
  - Terminal window focused → ydotool key ctrl+shift+v
  - Any other app          → ydotool key ctrl+v
  - ydotool unavailable    → xdotool fallback
    ↓
Notification: "✅ Typed in app: your words here"
          or: "✅ Typed in terminal: your words here"
          or: "📋 Copied — paste with Ctrl+V (apps) or Ctrl+Shift+V (terminal)"
```

**ThinkPad mic LED:**
- LED **ON** (red) = mic muted → NOT recording
- LED **OFF** = mic active → **recording in progress**

---

## Setup on a New Ubuntu System

```bash
# From the VoxFree project directory:
sudo bash install.sh --stt

# Log out and log back in
# (required for ydotool auto-paste to activate)

# Test: open any app, click inside, press F10 / Super+Shift+M, speak, press F11 / Super+Shift+K
```

---

## Keyboard Shortcuts

### Lenovo ThinkPad (verified via `wev`)

| Key | Keysym | Action |
|-----|--------|--------|
| **F10** (▶ go icon) | `XF86Go` | Start recording |
| **F11** (✕ cancel icon) | `Cancel` | Stop recording → transcribe → paste |

> **F10 and F11 are separate keys** (not a toggle). This is intentional — using a single key caused a race condition where key repeat events would start multiple recordings simultaneously.

F11 / Super+Shift+K is handled by `voxfree-stop-all`, which detects an active recording and delegates to `voxfree-dictate-stop` for stop + transcribe + paste. If TTS was also playing, it stops that first.

### Standard (any Linux/GNOME machine)

| Shortcut | Action |
|----------|--------|
| **Super+Shift+M** | Start recording |
| **Super+Shift+K** | Stop recording → transcribe → paste |

> Switch layouts after install: `voxfree --switch thinkpad` or `voxfree --switch standard`

---

## Dependencies

```bash
sudo apt install -y \
    alsa-utils sox libsox-fmt-all \
    wl-clipboard xdotool ydotool \
    python3-venv ffmpeg libnotify-bin wev
```

### Critical: ydotool setup (enables auto-paste)

```bash
# Add user to input group
sudo usermod -aG input $USER

# Create udev rule for /dev/uinput
echo 'KERNEL=="uinput", GROUP="input", MODE="0660"' | \
    sudo tee /etc/udev/rules.d/99-uinput.rules

sudo udevadm trigger

# Log out and back in — group change requires new session
```

After relogin, `ydotool key ctrl+v` pastes directly into **any app** — native Wayland, XWayland, GTK4, GTK3, Qt, terminals, everything.

### Whisper — Speech Recognition

> **Do NOT** use `python3-whisper` from apt — that is the Graphite time-series database tool, not OpenAI Whisper.

Install in a system Python venv:
```bash
sudo python3 -m venv /opt/openai-whisper
sudo /opt/openai-whisper/bin/pip install whisper-ctranslate2 --quiet
sudo ln -sf /opt/openai-whisper/bin/whisper-ctranslate2 /usr/local/bin/whisper
```

**whisper-ctranslate2** uses CTranslate2 (not PyTorch) — 4× faster, ~300MB vs 2GB.

### Download base.en model to shared cache

```bash
sudo mkdir -p /var/cache/huggingface
sudo HF_HOME=/var/cache/huggingface whisper /dev/null \
    --model base.en --language en --compute_type int8 \
    --output_format txt --output_dir /tmp --verbose False 2>/dev/null
sudo chmod -R a+rX /var/cache/huggingface
```

**Why `base.en` + `int8`?**

| Model | Size | Speed | Use |
|-------|------|-------|-----|
| `tiny.en` | 75MB | ~1.3s | Too inaccurate for natural speech |
| **`base.en`** | 145MB | ~2s | **Best balance — this setup** |
| `small.en` | 244MB | ~4s | Higher accuracy if needed |

### Why `arecord` not `sox`?

`sox -d` uses PulseAudio which fails silently from GNOME keyboard shortcuts — the PulseAudio socket is inaccessible in that execution context. `arecord -D default` uses ALSA → pipewire-alsa which works reliably from all contexts including GNOME shortcuts.

---

## Scripts

### `/usr/local/bin/voxfree-dictate` (bound to F10 / Super+Shift+M)
1. Checks if already recording — if yes, shows "Already recording" and exits (prevents key-repeat race condition)
2. Auto-detects PipeWire session socket (works even when `XDG_RUNTIME_DIR` is not set in GNOME shortcut context)
3. Unmutes microphone
4. Plays GNOME start sound
5. Starts `arecord -D default` in background
6. Saves PID to `/tmp/stt-recording.pid`
7. Shows "🔴 REC — Speak now!" notification

### `/usr/local/bin/voxfree-dictate-stop` (called by F11 / Super+Shift+K via voxfree-stop-all)
1. Reads PID from `/tmp/stt-recording.pid` — exits early if not recording
2. Checks recording is ≥1 second (32 000 bytes at 16kHz); rejects too-short recordings
3. Sends SIGTERM to arecord → WAV file finalised
4. Plays GNOME stop sound
5. Saves debug copy to `/tmp/last-stt-recording.wav`
6. Applies sox noise reduction (profiles first 0.5s)
7. Runs `whisper base.en --compute_type int8`
8. Copies transcript to clipboard via `wl-copy`
9. Smart paste: detects focused window class; uses `ctrl+shift+v` for terminals, `ctrl+v` for all other apps
10. Paste via ydotool → fallback xdotool → clipboard notification

### `/usr/local/bin/voxfree-stop-all` (bound to F11 / Super+Shift+K)
- Stops TTS (mimic3 + aplay) if running
- If STT recording is active: calls `voxfree-dictate-stop` so the audio is transcribed
- If nothing is running: shows "Nothing active."

---

## GNOME Shortcut Infrastructure

Shortcuts require `gsd-media-keys` running. **Always start via `.target`** — direct start is blocked on Wayland:

```bash
systemctl --user start org.gnome.SettingsDaemon.MediaKeys.target
pgrep -a gsd-media-keys
```

System-wide dconf at `/etc/dconf/db/local.d/00-voice-shortcuts` applies to all users on login.

---

## Troubleshooting

### Text pasted but wrong words / hallucinations ("You", "So", numbers)
Recording is too short (< 1 second). Press F10 / Super+Shift+M, wait for start sound, **then** speak.
```bash
# Check last recording length
sox /tmp/last-stt-recording.wav -n stat 2>&1 | grep Length
# Should be 2+ seconds
```

### Nothing recognised
```bash
# Check mic level
wpctl get-volume @DEFAULT_AUDIO_SOURCE@   # should NOT show MUTED
wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0  # unmute

# Listen to what was captured
aplay /tmp/last-stt-recording.wav
```

### Auto-paste not working (have to press Ctrl+V manually)
ydotool needs the `input` group to be active:
```bash
groups | grep input    # should show 'input'
```
If `input` is not shown → **log out and log back in**.

### Recording doesn't stop on F11 / Super+Shift+K
Check PID file exists:
```bash
cat /tmp/stt-recording.pid
pgrep -a arecord
```
If no PID file → no recording is active. Press F10 / Super+Shift+M to start a new one.

### Shortcut doesn't fire at all
```bash
pgrep -a gsd-media-keys || \
    systemctl --user start org.gnome.SettingsDaemon.MediaKeys.target
```

---

## Environment Notes

**`/etc/environment` should contain:**
```
HF_HOME=/var/cache/huggingface
HF_HUB_DISABLE_TELEMETRY=1
```

> Do **NOT** put `HF_HUB_OFFLINE=1` in `/etc/environment` — it blocks model downloads when you need to update models. The script sets it internally during transcription only.

---

## File Summary

| File | Location | Purpose |
|------|----------|---------|
| `voxfree-dictate` | `/usr/local/bin/` | F10 / Super+Shift+M — start recording |
| `voxfree-dictate-stop` | `/usr/local/bin/` | Stop, transcribe, paste |
| `voxfree-stop-all` | `/usr/local/bin/` | F11 / Super+Shift+K — stop all voice (delegates to dictate-stop if recording) |
| `whisper` | `/usr/local/bin/` | Symlink to whisper-ctranslate2 |
| `openai-whisper/` | `/opt/` | Python venv with whisper-ctranslate2 |
| `base.en model` | `/var/cache/huggingface/hub/` | Shared model cache (all users) |
| `99-uinput.rules` | `/etc/udev/rules.d/` | uinput permissions for ydotool |
| `00-voice-shortcuts` | `/etc/dconf/db/local.d/` | GNOME shortcuts (all users) |
| `last-stt-recording.wav` | `/tmp/` | Debug: last captured audio |
