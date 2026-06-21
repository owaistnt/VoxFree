# ReadLoud — Text-to-Speech (TTS) for Ubuntu 24.04

Highlight any text → press **F9** (ThinkPad) / **Super+Shift+R** (Standard) → hear it read aloud. Press the same key again to stop.
Fully offline. No cloud APIs. Works on GNOME Wayland.

---

## How It Works

```
Highlight text anywhere (browser, PDF, terminal, document)
    ↓
 Press F9 / Super+Shift+R
    ↓
wl-paste reads Wayland primary selection (what you highlighted)
    ↓
mimic3 synthesises speech locally (neural TTS, en_UK/apope_low)
    ↓
aplay plays audio through speakers
    ↓
Notification: "Reading: first 60 chars of text..."

Press F9 / Super+Shift+R again while speaking → stops immediately → "Stopped."
Press F11 (Cancel) / Super+Shift+K → stops TTS immediately; if STT was recording, transcribes first
```

---

## Setup on a New Ubuntu System

```bash
# From the VoxFree project directory:
sudo bash install.sh --tts
```

Or install both TTS and STT together:
```bash
sudo bash install.sh --all
```

---

## Keyboard Shortcuts

### Lenovo ThinkPad (verified via `wev`)

| Key | Keysym | Action |
|-----|--------|--------|
| **F9** (✉ message icon) | `XF86Messenger` | Read selected text / Stop reading (toggle) |
| **F11** (✕ cancel icon) | `Cancel` | Stop all voice activity |

> F9 / Super+Shift+R works as a toggle — same key starts and stops. F11 / Super+Shift+K is the universal stop: kills TTS immediately, and if STT dictation was recording it stops and transcribes before exiting.

### Standard (any Linux/GNOME machine)

| Shortcut | Action |
|----------|--------|
| **Super+Shift+R** | Read selected text / Stop (toggle) |
| **Super+Shift+K** | Stop all voice activity |

> Switch layouts after install: `voxfree --switch thinkpad` or `voxfree --switch standard`

---

## Dependencies

```bash
sudo apt install -y speech-dispatcher wl-clipboard alsa-utils libnotify-bin wev
```

### Mimic 3 — TTS Engine

Install from official `.deb`:
```bash
wget https://github.com/MycroftAI/mimic3/releases/download/v0.2.4/mycroft-mimic3-tts_0.2.4_amd64.deb
sudo dpkg -i mycroft-mimic3-tts_0.2.4_amd64.deb
sudo apt --fix-broken install
```

Pre-installed voice: `en_UK/apope_low` (British English, in `/usr/share/mycroft/mimic3/voices/`)

List and download additional voices:
```bash
mimic3 --voices                          # list all available
mimic3-download en_US/ljspeech_low       # American English female
mimic3-download en_US/vctk_low           # American English multi-speaker
```

Change the active voice:
```bash
voxfree --voice    # interactive selector — saves to ~/.config/voxfree/voice
```

### speech-dispatcher — System TTS Daemon

Fix module to use **local mode** (default config uses `--remote` which requires a server):
```bash
sudo tee /etc/speech-dispatcher/modules/mimic3-generic.conf > /dev/null << 'EOF'
GenericExecuteSynth "printf %s \'$DATA\' | /usr/bin/mimic3 --voice \'$VOICE\' --stdout 2>/dev/null | aplay -q 2>/dev/null"
AddVoice "en" "MALE1" "en_UK/apope_low"
AddVoice "en" "FEMALE1" "en_UK/apope_low"
EOF
```

Set as default in `/etc/speech-dispatcher/speechd.conf`:
```
DefaultModule mimic3-generic
```

Test: `spd-say "speech dispatcher working"`

---

## Scripts

### `/usr/local/bin/voxfree-readloud`
- Gets highlighted text via `wl-paste --primary` (Wayland primary selection)
- Toggle: if mimic3 is already running, kills it and exits
- Reads active voice from `~/.config/voxfree/voice` → `/etc/voxfree/voice` → `en_UK/apope_low`

### `/usr/local/bin/voxfree-readloud-stop`
- Force-kills mimic3 and aplay immediately (no state tracking)

### `/usr/local/bin/voxfree-stop-all`
- Stops TTS (mimic3 + aplay) if running
- If STT dictation was recording: delegates to `voxfree-dictate-stop` so it transcribes
- Bound to F11 / Super+Shift+K

---

## Troubleshooting

### No sound
```bash
wpctl get-volume @DEFAULT_AUDIO_SINK@
wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
pw-play /usr/share/sounds/freedesktop/stereo/bell.oga
```

### Shortcut doesn't fire
```bash
# Start the GNOME keyboard daemon (always via .target, not directly)
systemctl --user start org.gnome.SettingsDaemon.MediaKeys.target
pgrep -a gsd-media-keys
```

### Wrong ThinkPad keysym
```bash
wev    # press F9 or Super+Shift+R, read the 'sym' field
# Update /etc/dconf/db/local.d/00-voice-shortcuts then:
sudo dconf update
```

---

## File Summary

| File | Location | Purpose |
|------|----------|---------|
| `voxfree-readloud` | `/usr/local/bin/` | TTS toggle script (F9 / Super+Shift+R) |
| `voxfree-readloud-stop` | `/usr/local/bin/` | Force-stop TTS |
| `voxfree-stop-all` | `/usr/local/bin/` | Stop all voice (F11 / Super+Shift+K): TTS + STT |
| `mimic3` | `/usr/bin/` | TTS engine binary |
| `en_UK/apope_low` | `/usr/share/mycroft/mimic3/voices/` | Default voice model |
| `mimic3-generic.conf` | `/etc/speech-dispatcher/modules/` | Local mode config |
| `00-voice-shortcuts` | `/etc/dconf/db/local.d/` | GNOME shortcuts (all users) |
