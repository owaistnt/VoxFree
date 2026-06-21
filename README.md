# VoxFree

![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)
![Version](https://img.shields.io/badge/version-0.3.0-blue.svg)
![Platform](https://img.shields.io/badge/platform-Ubuntu%2024.04%20GNOME%2FWayland-orange.svg)

**Offline voice tools for Ubuntu 24.04 GNOME/Wayland.**

Press a key to hear any text read aloud. Press a key to speak and have your words typed anywhere. No internet, no cloud APIs, no subscriptions. Everything runs locally on your machine.

---

## A Note to the Community

VoxFree is my first open-source project for Ubuntu. I built it because I wanted reliable, offline voice tools for my own machine and could not find anything that worked out of the box on GNOME/Wayland without cloud dependencies.

I am not a seasoned Linux systems developer. This project was built with a lot of research, experimentation, and the help of AI agents to reason through the moving parts — audio routing, Wayland input simulation, GNOME shortcut registration, Whisper inference, and packaging. The tools work well on my machine and I have tried to make the install experience reproducible, but there are many components that need to cooperate and not every hardware or software configuration has been tested.

**If something breaks, I sincerely ask for your patience and kindness.** Every bug report is genuinely useful — it helps narrow down the configurations that need fixing and makes the project better for everyone. Please open an issue and describe what failed; I will do my best to address it.

> **Report bugs:** [github.com/owaistnt/VoxFree/issues](https://github.com/owaistnt/VoxFree/issues)

The long-term goal is to make the Linux desktop feel more immersive and accessible through voice — where reading and dictating feel as natural as typing. VoxFree is a small step toward that.

---

## Sub-projects

### 🔊 ReadLoud — Text-to-Speech

Highlight any text on screen and press **F9** to hear it read aloud. Press **F9** again to stop.

- **Engine:** Mycroft Mimic 3 (neural TTS, offline)
- **Voice:** en_UK/apope_low (British English) — more voices downloadable
- **Works in:** any app — browser, PDF, terminal, document, email
- **System-wide:** all users, all sessions

→ [ReadLoud documentation](ReadLoud/readloud.md)

---

### 🎙 SpeakToType — Speech-to-Text

Press **F10** to start recording, speak, press **F11** to stop — your words appear at the cursor.

- **Engine:** OpenAI Whisper base.en + int8 quantisation (~2s transcription)
- **Recording:** arecord (ALSA/pipewire-alsa, reliable from GNOME shortcuts)
- **Noise reduction:** sox noise profile applied before transcription
- **Paste:** ydotool Ctrl+V (all Wayland apps) or xdotool fallback
- **System-wide:** all users, shared model cache in /var/cache/huggingface/

→ [SpeakToType documentation](SpeakToType/speak-to-type.md)

---

## Dependencies

VoxFree orchestrates several existing open-source tools. `deps.sh` (called automatically by `install.sh`) handles installation, but here is what gets installed and where to learn more about each component.

### Text-to-Speech — ReadLoud

| Tool | Purpose | Source |
|------|---------|--------|
| **Mycroft Mimic 3** | Neural TTS engine, runs fully offline | [github.com/MycroftAI/mimic3](https://github.com/MycroftAI/mimic3) |
| **aplay** | ALSA audio playback (part of `alsa-utils`) | `sudo apt install alsa-utils` |
| **wl-paste** | Reads highlighted text from Wayland primary selection | `sudo apt install wl-clipboard` |
| **speech-dispatcher** | Audio routing layer (configured for local/direct mode) | `sudo apt install speech-dispatcher` |

**Installing Mimic 3 separately:**
```bash
pip install mycroft-mimic3-tts[all]
mimic3 --voice en_UK/apope_low "Hello"   # test it
```
Voices are downloaded on first use and cached locally. Browse available voices with `mimic3 --list-voices`.

### Speech-to-Text — SpeakToType

| Tool | Purpose | Source |
|------|---------|--------|
| **whisper-ctranslate2** | Fast Whisper inference using CTranslate2 (4× faster than original) | [github.com/Softcatala/whisper-ctranslate2](https://github.com/Softcatala/whisper-ctranslate2) |
| **arecord** | ALSA audio capture via PipeWire bridge | `sudo apt install alsa-utils` |
| **sox** | Noise reduction applied before transcription | `sudo apt install sox` |
| **ydotool** | Wayland-native keyboard input simulation via `/dev/uinput` | `sudo apt install ydotool` |
| **wl-copy** | Writes transcribed text to clipboard | `sudo apt install wl-clipboard` |

**Installing whisper-ctranslate2 separately:**
```bash
pip install whisper-ctranslate2
whisper-ctranslate2 audio.wav --model base.en   # test it
```
The `base.en` model (~150MB) is downloaded on first use to `/var/cache/huggingface/` (system install) or `~/.cache/huggingface/` (user install).

> **Why whisper-ctranslate2 instead of openai-whisper?** CTranslate2 int8 quantisation gives ~4× faster inference and uses ~300MB of disk vs ~2GB, with negligible accuracy difference for short dictation.

### Why No GPU Required?

Both engines run on CPU. Mimic 3 uses a lightweight neural vocoder; Whisper `base.en` with int8 quantisation transcribes a 5-second clip in ~2 seconds on a modern CPU.

---

## Quick Install

```bash
# Clone or copy VoxFree to your machine, then:
sudo bash install.sh
```

Prompts you to choose TTS, STT, or both. Or use flags:

```bash
sudo bash install.sh --tts    # ReadLoud only
sudo bash install.sh --stt    # SpeakToType only
sudo bash install.sh --all    # both silently
```

**After install:** log out and back in once (activates ydotool auto-paste for STT).

---

## Install via .deb Package

Pre-built `.deb` packages are available in the [`releases/`](releases/) folder for Ubuntu 24.04 (amd64).

```bash
# 1. Download the .deb
wget https://github.com/owaistnt/VoxFree/raw/main/releases/voxfree_0.3.0_all.deb

# 2. Install
sudo dpkg -i voxfree_0.3.0_all.deb

# 3. Fix any missing dependencies
sudo apt install -f

# 4. Configure (choose TTS, STT, or both)
sudo voxfree --install
```

**After install:** log out and back in once (activates ydotool auto-paste for STT).

> The `.deb` installs VoxFree scripts to `/usr/share/voxfree/` and the `voxfree` and `voxfree-doctor` commands to `/usr/local/bin/`. It does **not** download Whisper or Mimic 3 automatically — `sudo voxfree --install` handles that interactively.

### Upgrade from a previous version

```bash
sudo dpkg -i voxfree_0.3.0_all.deb   # dpkg handles the upgrade automatically
voxfree --doctor                       # verify everything is working
```

No reconfiguration needed on upgrade — keyboard shortcuts and settings are preserved.

---

## Verify Your Installation — VoxFree Doctor

Run the doctor after installing to check every component is correctly set up:

```bash
bash voxfree-doctor.sh
```

It checks 36 points across four sections and prints a full summary grouped by result:

```
  VoxFree Doctor
  Checking your VoxFree installation...

System
──────
  [✔] Ubuntu 24.04 (Noble)
  [✔] Wayland session (ubuntu:GNOME)
  [✔] PipeWire audio server running

ReadLoud — Text-to-Speech
─────────────────────────
  [✔] mimic3 0.2.4 — /usr/bin/mimic3
  [✔] Voice en_UK/apope_low available
  ...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Summary  (36 passed · 0 warnings · 0 failed)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Passed:
    [✔] [System] Ubuntu 24.04 (Noble)
    [✔] [ReadLoud] mimic3 0.2.4
    ...

  ✔ VoxFree is fully operational!
```

### Doctor flags

| Flag | Description |
|------|-------------|
| *(none)* | Full check — all 36 points |
| `--tts` | ReadLoud checks only |
| `--stt` | SpeakToType checks only |
| `--fix` | Show the exact fix command for every failure/warning |

```bash
bash voxfree-doctor.sh --fix    # show remediation for every issue
bash voxfree-doctor.sh --tts    # check ReadLoud only
bash voxfree-doctor.sh --stt    # check SpeakToType only
```

### What it checks

| Section | Checks |
|---------|--------|
| **System** | Ubuntu version, Wayland session, PipeWire running |
| **ReadLoud** | mimic3 binary, voice model, speech-dispatcher config (local mode), aplay, wl-paste, scripts, live TTS audio test |
| **SpeakToType** | arecord, sox, whisper symlink, whisper-ctranslate2 venv, base.en model, model permissions, HF_HOME env var, HF_HUB_OFFLINE not blocking downloads, ydotool, input group, /dev/uinput, xdotool, wl-copy, mic unmuted, live recording test, scripts |
| **GNOME Shortcuts** | gsd-media-keys daemon, dconf profile, shortcuts file, F9/F10/F11 bindings, wev |

---

## CLI Commands

After installation, the `voxfree` command is available system-wide.

### `voxfree --version`

Shows the installed version:

```
$ voxfree --version
VoxFree 0.3.0
```

### `voxfree --voice`

Interactive voice selector for ReadLoud. Lists all available English voices from Mimic 3, shows which are installed locally and which require a download, and marks the current active voice:

```
  VoxFree — Voice Selector
  ────────────────────────

  Available English voices (★ = current, ✔ = installed):

  en_UK:
  ★ ✔   1) en_UK/apope_low
    ↓   2) en_UK/semaine
    ↓   3) en_UK/southern_english_female_low

  en_US:
    ✔   4) en_US/cmu-arctic_low
    ↓   5) en_US/hifi-tts_low
    ↓   6) en_US/ljspeech_low

  ✔ = installed locally   ↓ = download required   ★ = current

  Enter number to select (or q to quit):
```

Selecting a voice that is not yet installed downloads it automatically. The choice is saved to `~/.config/voxfree/voice` and takes effect immediately — no restart needed.

```bash
voxfree --voice    # run the selector
```

**Voice config priority:** user config (`~/.config/voxfree/voice`) → system config (`/etc/voxfree/voice`) → built-in default (`en_UK/apope_low`).

### All commands

```
voxfree --install [--tts|--stt|--all] [--user]   Install or reconfigure
voxfree --uninstall [--purge] [--user]            Remove VoxFree
voxfree --doctor [--tts|--stt] [--fix]            Health check
voxfree --voice                                   Change TTS voice
voxfree --version                                 Show version
```

---

## Keyboard Shortcuts

### Lenovo ThinkPad (verified on Ubuntu 24.04 via `wev`)

| Key | Keysym | Action |
|-----|--------|--------|
| **F9** (✉ message icon) | `XF86Messenger` | Read selected text aloud / stop (toggle) |
| **F10** (▶ go icon) | `XF86Go` | Start speech recording |
| **F11** (✕ cancel icon) | `Cancel` | Stop all voice — if recording: transcribes and pastes; if reading: stops TTS |

> Keysyms vary by ThinkPad model. Run `wev` and press each key to verify yours.

### Standard (any Linux/GNOME machine)

Uses `Super+Shift` combinations — confirmed free on all standard GNOME/Ubuntu installs.

| Shortcut | Action |
|----------|--------|
| **Super+Shift+R** | Read selected text aloud / stop (toggle) |
| **Super+Shift+M** | Start dictation (microphone) |
| **Super+Shift+K** | Stop all voice activity (TTS + STT) |

> **Why not Ctrl+Alt?** `Ctrl+Alt` and `Super+Alt` can conflict with Ubuntu defaults (screen recording, accessibility, input methods). `Super+Shift+[letter]` is confirmed free — only arrow/navigation keys use Super+Shift.

---

## System Requirements

- Ubuntu 24.04 (Noble)
- GNOME desktop on Wayland
- ~500MB disk space (Whisper base.en model + Mimic 3)
- No GPU required — runs on CPU

---

## How It Works (Architecture)

```
┌─────────────────────────────────────────────────────────┐
│                     GNOME Desktop                        │
│                                                          │
│  F9 pressed              F10 pressed        F11 pressed   │
│       ↓                       ↓                  ↓        │
│  gsd-media-keys          gsd-media-keys    gsd-media-keys │
│       ↓                       ↓                  ↓        │
│  voxfree-readloud     voxfree-dictate    voxfree-stop-all │
│       ↓                       ↓            (stops TTS or  │
│  wl-paste --primary   arecord -D default   delegates to   │
│  (highlighted text)   (ALSA/pipewire-alsa) dictate-stop)  │
│       ↓                       ↓                  ↓        │
│  mimic3 (TTS)          sox noise reduction  voxfree-      │
│       ↓                       ↓             dictate-stop  │
│  aplay (speakers)      whisper base.en            ↓       │
│                        (/var/cache/huggingface)   ↓       │
│                               ↓             wl-copy +     │
│                        smart paste:         ydotool key   │
│                        ctrl+shift+v (term)  (pastes at    │
│                        ctrl+v (other apps)   cursor)      │
└─────────────────────────────────────────────────────────┘
```

---

## Known Limitations

- **GNOME Wayland only** — `wtype` (virtual keyboard) is blocked by Mutter compositor. Auto-paste uses ydotool via `/dev/uinput` instead.
- **Relogin required once** — after install, log out and back in to activate ydotool (input group membership).
- **English only** — `base.en` model. Change to `base`, `small`, or `medium` in `/usr/local/bin/voxfree-dictate-stop` for multilingual support.
- **ThinkPad keysyms vary** — always verify with `wev` on your specific model.

---

## File Structure

```
VoxFree/
├── README.md               ← this file
├── install.sh              ← installs TTS, STT, or both
├── deps.sh                 ← installs ALL dependencies (apt, mimic3, whisper, model)
├── voxfree-doctor.sh       ← verifies the full installation (36 checks)
│
├── ReadLoud/
│   ├── readloud.sh              ← TTS installer (called by install.sh)
│   ├── readloud.md              ← TTS full documentation
│   ├── voxfree-readloud.sh      ← F9: read selected text aloud (toggle)
│   ├── voxfree-readloud-stop.sh ← force-stop TTS at any time
│   └── voxfree-stop-all.sh      ← F11: stop all voice (TTS + STT)
│
└── SpeakToType/
    ├── speak-to-type.sh         ← STT installer (called by install.sh)
    ├── speak-to-type.md         ← STT full documentation
    ├── voxfree-dictate.sh       ← F10: start microphone recording
    └── voxfree-dictate-stop.sh  ← stop recording → transcribe → paste
```

### Script dependency flow

```
install.sh
    ├── deps.sh              (installs all apt packages, mimic3, whisper, model)
    ├── ReadLoud/readloud.sh       (configures speech-dispatcher, scripts, shortcuts)
    └── SpeakToType/speak-to-type.sh  (configures scripts, shortcuts, udev rules)

voxfree-doctor.sh        (run anytime to verify — independent of install)
```

---

## Troubleshooting

**Run the doctor first** — it identifies the exact problem and shows the fix:

```bash
bash voxfree-doctor.sh --fix
```

Common issues:

**Shortcuts don't fire:**
```bash
systemctl --user start org.gnome.SettingsDaemon.MediaKeys.target
```

**Have to press Ctrl+V manually (ydotool not auto-pasting):**
```bash
groups | grep input   # if 'input' not shown → log out and back in
```

**Wrong words / hallucinations:**
Recording too short — wait for the F10 start sound before speaking.
```bash
sox /tmp/last-stt-recording.wav -n stat 2>&1 | grep Length
# Should be 2+ seconds
```

**Wrong ThinkPad keysyms:**
```bash
wev   # press each key, read the 'sym' field
# Edit /etc/dconf/db/local.d/00-voice-shortcuts then: sudo dconf update
```
