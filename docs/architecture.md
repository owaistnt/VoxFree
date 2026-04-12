# VoxFree Architecture

## Component Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Actions                             │
│  Highlight text → F9     F10 (start)     F11 (stop/paste)       │
└──────────────┬────────────────┬────────────────┬────────────────┘
               │                │                │
               ▼                ▼                ▼
     ┌──────────────────────────────────────────────────┐
     │              GNOME Desktop (Wayland/Mutter)       │
     │  gsd-media-keys daemon (must run via .target)     │
     └──────┬─────────────────┬──────────────────┬──────┘
            │                 │                  │
            ▼                 ▼                  ▼
   voxfree-readloud    voxfree-dictate    voxfree-stop-all
   (F9 toggle TTS)     (F10 start STT)   (F11 stop everything)
            │                 │                  │
            │                 │         if STT recording active:
            │                 │                  ▼
            │                 │        voxfree-dictate-stop
            │                 │        (stop + transcribe + paste)
            │                 │                  │
            │                 ▼                  ▼
            │         arecord -D default     [reads PID]
            │         (ALSA→pipewire-alsa)   kill arecord
            │                 │                  │
            ▼                 └──────────────────┤
       wl-paste                                  ▼
   (primary selection)              sox noisered (0.5s profile)
            │                                    │
            ▼                                    ▼
    mimic3 --voice           whisper base.en + int8 + HF_HOME
    (neural TTS, ONNX)       (/var/cache/huggingface/)
            │                                    │
            ▼                                    ▼
       aplay -q                            wl-copy (clipboard)
     (via pipewire-alsa)                         │
            │                                    ▼
            ▼                         ydotool key ctrl+v
        Speakers                      (via /dev/uinput)
                                             OR
                                      xdotool key ctrl+v
                                      (XWayland fallback)
                                             OR
                                      "📋 Press Ctrl+V"
                                      (notification fallback)
```

---

## File Layout (System Install)

```
/usr/local/bin/
  voxfree                  ← unified CLI dispatcher
  voxfree-doctor           ← health checker (wrapper)
  voxfree-readloud         ← TTS toggle (F9)
  voxfree-readloud-stop    ← TTS force-stop
  voxfree-stop-all         ← stop all voice (F11): TTS + delegates STT to dictate-stop
  voxfree-dictate          ← STT start recording (F10)
  voxfree-dictate-stop     ← STT stop + transcribe + paste (called by stop-all)
  whisper                  ← symlink to whisper-ctranslate2

/usr/share/voxfree/        ← source scripts (updated by .deb)
  install.sh, deps.sh, uninstall.sh
  voxfree-doctor.sh, voxfree-voice.sh
  VERSION
  lib/detect.sh
  ReadLoud/
  SpeakToType/

/etc/voxfree/
  voice                    ← system-wide selected voice (e.g. en_UK/apope_low)

~/.config/voxfree/
  voice                    ← per-user voice override (takes precedence)

/opt/openai-whisper/       ← whisper-ctranslate2 Python venv (~520MB)

/var/cache/huggingface/hub/
  models--Systran--faster-whisper-base.en/  ← shared model cache (~145MB)

/etc/dconf/db/local.d/
  00-voice-shortcuts        ← GNOME shortcuts for all users

/etc/dconf/profile/user     ← includes system-db:local

/etc/udev/rules.d/
  99-uinput.rules           ← allows input group to write /dev/uinput

/etc/environment
  HF_HOME=/var/cache/huggingface
  HF_HUB_DISABLE_TELEMETRY=1
```

---

## File Layout (User Install `--user`)

```
~/.local/bin/
  voxfree, voxfree-doctor, voxfree-readloud, voxfree-readloud-stop
  voxfree-dictate, voxfree-dictate-stop, whisper

~/.local/share/voxfree/    ← source scripts copy
  install.sh, deps.sh, uninstall.sh, voxfree-doctor.sh, ...

~/.local/share/voxfree/whisper-venv/   ← user whisper venv

~/.cache/huggingface/hub/  ← user model cache

~/.config/voxfree/
  voice                    ← selected voice

~/.profile
  export HF_HOME="$HOME/.cache/huggingface"
```

---

## Voice Configuration Priority

```
voxfree-readloud reads voice in this order:
  1. ~/.config/voxfree/voice    (user preference — set by voxfree --voice)
  2. /etc/voxfree/voice         (system default — set at install time)
  3. en_UK/apope_low            (hardcoded built-in fallback)
```

---

## Keyboard Shortcut Flow

```
User presses F9 (XF86Messenger)
     │
     ▼
gsd-media-keys → /usr/local/bin/voxfree-readloud
     │
     ▼
voxfree-readloud:
  - reads voice from ~/.config/voxfree/voice → /etc/voxfree/voice → default
  - if mimic3 already running → kill it (toggle off), exit
  - reads highlighted text from wl-paste --primary (no clipboard fallback)
  - if no text selected → notify and exit
  - runs: mimic3 --voice $VOICE --stdout | aplay -q  (backgrounded)
  - saves background PID to /tmp/voxfree-readloud.pid
  - shows "Reading: ..." notification

User presses F10 (XF86Go)
     │
     ▼
gsd-media-keys → /usr/local/bin/voxfree-dictate
     │
     ▼
voxfree-dictate:
  - if already recording → notify "Already recording", exit
  - auto-detects PipeWire session socket (XDG_RUNTIME_DIR)
  - unmutes mic: wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0
  - starts: arecord -D default -f S16_LE -r 16000 -c 1 -q /tmp/stt-recording.wav
  - saves PID to /tmp/stt-recording.pid
  - shows "🔴 REC — Speak now!" notification

User presses F11 (Cancel)
     │
     ▼
gsd-media-keys → /usr/local/bin/voxfree-stop-all
     │
     ├── if mimic3 running → pkill mimic3 + aplay
     │
     └── if /tmp/stt-recording.pid exists and process alive
              │
              ▼
         exec /usr/local/bin/voxfree-dictate-stop
              │
              ▼
         voxfree-dictate-stop:
           - validates recording ≥ 1 second
           - kills arecord, removes PID file
           - applies sox noise reduction (first 0.5s as noise profile)
           - runs whisper base.en --compute_type int8
           - copies transcript to clipboard via wl-copy
           - smart paste: ctrl+shift+v (terminal) or ctrl+v (other apps)
             via ydotool → xdotool fallback → clipboard notification
```

---

## Install Flow

```
sudo bash install.sh
     │
     ├── show menu (scope: system/user, feature: TTS/STT/both)
     │
     ├── deps.sh
     │    ├── apt-get install (system) OR check+warn (user)
     │    ├── detect_mimic3 / install_mimic3 (lib/detect.sh)
     │    ├── detect_whisper / install_whisper (lib/detect.sh)
     │    ├── install_whisper_model (lib/detect.sh)
     │    ├── ydotool uinput setup (system only)
     │    └── /etc/environment or ~/.profile
     │
     ├── ReadLoud/readloud.sh (if TTS)
     │    ├── speech-dispatcher config
     │    ├── /etc/voxfree/voice (default voice)
     │    ├── install voxfree-readloud + voxfree-readloud-stop + voxfree-stop-all to $BIN_DIR
     │    └── dconf shortcuts (system) or gsettings (user)
     │
     ├── SpeakToType/speak-to-type.sh (if STT)
     │    ├── install voxfree-dictate + voxfree-dictate-stop to $BIN_DIR
     │    └── dconf shortcuts (system) or gsettings (user)
     │
     └── install.sh installs:
          - voxfree CLI wrapper
          - voxfree-doctor wrapper
          - voxfree-voice.sh → WRAPPER_DATA_DIR
```
