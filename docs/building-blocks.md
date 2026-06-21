# VoxFree Building Blocks

Every technology VoxFree depends on, what it does, why it was chosen, how it fits in the pipeline, and what breaks when it's misconfigured.

---

## Text-to-Speech Pipeline

```
Highlighted text → wl-paste → mimic3 → WAV audio → aplay → speakers
```

### wl-clipboard (`wl-paste`)

**What it is:** Wayland clipboard utility. `wl-paste` reads text from the Wayland clipboard.

**Why VoxFree uses it:** On Wayland, the traditional X11 clipboard tools (`xclip`, `xsel`) don't work. `wl-paste --primary` reads the *primary selection* — the text currently highlighted/selected with the mouse — which is exactly what ReadLoud needs.

**How it fits:** `voxfree-readloud` uses `wl-paste --primary` (highlighted text) exclusively. There is no clipboard fallback — this is intentional to prevent accidentally reading stale clipboard content or terminal history when no text is selected. If nothing is highlighted, it shows "No text selected — highlight text first."

**Common failure:** If no text is selected and no clipboard content exists, the script shows "No text selected — highlight text first."

---

### Mycroft Mimic 3

**What it is:** An offline neural Text-to-Speech engine by Mycroft AI. Uses ONNX-format neural network models to convert text to speech.

**How it works:**
1. Text → phonemes (via espeak-ng or gruut)
2. Phonemes → mel spectrogram (via the ONNX neural model)
3. Mel spectrogram → raw audio waveform (via HiFiGAN vocoder)

**Why VoxFree uses it:** Fully offline, high-quality voices, MIT-licensed, fast on CPU, good English quality. The `en_UK/apope_low` voice provides natural-sounding British English.

**How it fits:** `voxfree-readloud` pipes text to `mimic3 --voice en_UK/apope_low --stdout` which outputs raw WAV audio to stdout, then pipes that to `aplay`.

**Voice config:** VoxFree stores the selected voice in `/etc/voxfree/voice` (system) or `~/.config/voxfree/voice` (user). Change it with `voxfree --voice`.

**Common failure:** First run loads the ONNX model (~2–3s). "Voice not found" means the voice wasn't downloaded — run `mimic3-download en_UK/apope_low`.

---

### ALSA / aplay

**What it is:** Advanced Linux Sound Architecture. `aplay` plays WAV files.

**Why VoxFree uses it:** Simple, reliable, no extra dependencies. `aplay -q` plays silently (no output) and exits when done.

**How it fits:** `mimic3 --stdout | aplay -q` — mimic3 streams WAV to stdout, aplay reads from stdin and plays through speakers.

**PipeWire integration:** On Ubuntu 24.04, ALSA is routed through `pipewire-alsa`. This means `aplay` goes through PipeWire which handles mixing, volume, and output routing automatically.

**Common failure:** "No such file or directory" for audio device → PipeWire not running. Fix: `systemctl --user start pipewire`.

---

### speech-dispatcher

**What it is:** A system-level TTS routing daemon. Applications can request TTS through speech-dispatcher without knowing which engine is installed.

**Why VoxFree configures it:** Accessibility tools (Orca screen reader), browsers with read-aloud features, and `spd-say` all use speech-dispatcher. By configuring mimic3 as the backend, VoxFree makes high-quality TTS available to all these tools automatically.

**Critical config:** The default `mimic3-generic.conf` uses `--remote` (requires a running mimic3 HTTP server). VoxFree replaces it with local mode:
```
GenericExecuteSynth "printf %s '$DATA' | mimic3 --voice '$VOICE' --stdout | aplay -q"
```

**Common failure:** If `--remote` is still in the config, speech-dispatcher silently fails because the mimic3 server isn't running. Fix: `sudo bash VoxFree/deps.sh --tts`.

---

## Speech-to-Text Pipeline

```
Mic → arecord → WAV → sox noisered → whisper base.en → text → wl-copy → ydotool Ctrl+V → cursor
```

### ALSA / arecord

**What it is:** ALSA's microphone recorder. `arecord -D default` records from the system default input device.

**Why VoxFree uses `arecord` not `sox -d`:** `sox -d` uses the PulseAudio library (libsox-fmt-pulse) to access the microphone. When triggered from a GNOME keyboard shortcut via gsd-media-keys, the PulseAudio socket environment variables are not set, causing sox to fail with "Sorry, there is no default audio device configured." `arecord` uses ALSA directly via `pipewire-alsa`, which works reliably in all execution contexts.

**How it fits:** `voxfree-dictate` runs `arecord -D default -f S16_LE -r 16000 -c 1 -q recording.wav &` in the background. 16kHz mono S16LE is the format Whisper expects.

**Common failure:** "Host is down" → PipeWire session is wrong user. The script auto-detects the active PipeWire session. "No audio captured" (empty file) → mic is muted; `voxfree-dictate` auto-unmutes with `wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0`.

---

### PipeWire

**What it is:** The modern Linux audio/video server. Replaces PulseAudio and JACK in Ubuntu 22.04+.

**Session model:** Each user's GNOME login session runs its own PipeWire instance. Audio routing (sources, sinks, volumes) is per-session. This is why `wpctl` and audio tools work correctly when run from a keyboard shortcut in the user's session, but fail when run from a different user's terminal.

**PipeWire-ALSA bridge:** `pipewire-alsa` is a plugin that makes ALSA applications (like `arecord`, `aplay`) route through PipeWire transparently. This is why `arecord` and `aplay` work correctly in the GNOME session context.

**Key socket:** `/run/user/UID/pulse/native` — the PulseAudio-compatible socket for PipeWire. This is what `sox -d` fails to find when run from gsd-media-keys. `arecord` doesn't need this socket.

**Common failure:** F10 / Super+Shift+M recording fails → check `PULSE_SERVER` env var isn't set to wrong path. `voxfree-doctor` checks the active session automatically.

---

### sox noisered

**What it is:** SoX (Sound eXchange) is a command-line audio processing tool. The `noisered` effect removes background noise.

**How the noise profile trick works:**
1. Record audio (includes speech + background noise)
2. Take the first 0.5 seconds (before speaking starts, just background noise)
3. Generate a "noise profile" from that sample: `sox audio.wav -n trim 0 0.5 noiseprof noise.prof`
4. Apply the profile to denoise the full recording: `sox audio.wav clean.wav noisered noise.prof 0.15`

The `0.15` is the sensitivity threshold — higher = more aggressive noise removal (but can distort speech).

**Why 0.5 seconds:** The GNOME notification sound plays first, then VoxFree starts recording. The user naturally doesn't speak for ~0.5s after pressing F10 / Super+Shift+M, giving clean noise reference.

**Common failure:** If `libsox-fmt-all` is missing, `sox` can't read/write certain formats. Fix: `sudo apt install libsox-fmt-all`.

---

### OpenAI Whisper (whisper-ctranslate2)

**What it is:** A deep learning speech recognition model. `whisper-ctranslate2` is a drop-in CLI replacement that uses CTranslate2 instead of PyTorch.

**How Whisper works:**
1. Audio → mel spectrogram (frequency vs time)
2. Encoder transformer: processes the spectrogram
3. Decoder transformer: generates text tokens one by one
4. Output: transcribed text

**Why `whisper-ctranslate2` not `openai-whisper`:**

| | openai-whisper | whisper-ctranslate2 |
|--|--|--|
| Backend | PyTorch (~2GB) | CTranslate2 (~300MB) |
| Speed | baseline | 4× faster |
| Accuracy | same | same |

**Why `base.en` not `tiny.en`:** `tiny.en` is faster (~75MB, ~1.3s) but produces more hallucinations on imperfect audio. `base.en` (~145MB, ~2s) is significantly more accurate for natural speech with background noise.

**Why `int8` compute type:** Quantises the model weights from float32 to int8. This halves memory usage and makes inference ~3× faster on CPU, with negligible accuracy loss.

**`HF_HUB_OFFLINE=1`:** Set in scripts during transcription to prevent Whisper from checking the internet for model updates. The model is pre-downloaded to `/var/cache/huggingface/`. This env var is NOT set globally (would block future model downloads for `voxfree --voice`).

**Common failure:** "Nothing recognised" → audio too short (< 1s), mic too quiet, or too much background noise. Check `/tmp/last-stt-recording.wav` — play it back to hear what was captured.

---

### ydotool + /dev/uinput

**What it is:** `ydotool` injects keyboard events using the Linux kernel's `uinput` (user input) subsystem. This creates a virtual keyboard at the kernel level.

**Why not `wtype`:** GNOME's Mutter compositor blocks the `zwp_virtual_keyboard_v1` Wayland protocol for security. `wtype` uses this protocol and fails with "Compositor does not support the virtual keyboard protocol."

**How uinput bypasses Wayland:** uinput operates at the kernel level, below the display server. It doesn't ask the compositor for permission — it injects events into the input event chain that the compositor sees as real keyboard input.

**Why `input` group relogin is needed:** `/dev/uinput` requires write access. Adding a user to the `input` group (and creating the udev rule `KERNEL=="uinput", GROUP="input", MODE="0660"`) grants this access. Group membership in Linux only takes effect in new login sessions.

**How paste works (smart paste):**
1. `wl-copy "$TRANSCRIPT"` puts text in Wayland clipboard
2. `voxfree-dictate-stop` detects the focused window class via xdotool
3. If a terminal is focused (gnome-terminal, kitty, alacritty, etc.): sends `ctrl+shift+v` — terminals use this for paste to avoid conflicting with Ctrl+V (interrupt signal)
4. All other apps: sends `ctrl+v`
5. The focused application receives the paste key and pastes from clipboard

**Common failure:** "ydotool not auto-pasting" → user not in `input` group yet. Fix: log out and back in. Until then, text is always in clipboard — press `Ctrl+V` (apps) or `Ctrl+Shift+V` (terminals) manually.

---

### xdotool (fallback)

**What it is:** X11 automation tool. Can send keyboard events to X11 (XWayland) windows.

**When it's used:** If ydotool fails, `voxfree-dictate-stop` falls back to `DISPLAY=:0 xdotool key --clearmodifiers ctrl+v`. This works for apps running under XWayland (many GTK3 apps, some Qt apps).

**Limitation:** Doesn't work for GTK4 or other native Wayland apps (like the GNOME Text Editor). For these, the clipboard fallback is used.

---

### dconf + gsd-media-keys

**What is dconf:** GNOME's configuration database. Settings are stored in a binary database. `gsettings` is the high-level API; `dconf` is the low-level database.

**System-wide defaults:** `/etc/dconf/db/local.d/00-voice-shortcuts` provides defaults for all users. The `/etc/dconf/profile/user` file tells GNOME to check the `local` system database after the user database. On first login, users get VoxFree shortcuts automatically.

**gsd-media-keys:** The `gnome-settings-daemon` plugin that handles keyboard shortcuts. It reads `gsettings` and grabs keys from the Wayland compositor. When a bound key is pressed, it executes the configured command.

**Why start via `.target` not directly:** gsd-media-keys must be started by the systemd user session to have permission to grab keys from the compositor. Direct start (`/usr/libexec/gsd-media-keys`) fails with "GrabAccelerators is not allowed". Correct start: `systemctl --user start org.gnome.SettingsDaemon.MediaKeys.target`.

**Common failure:** F9 / Super+Shift+R, F10 / Super+Shift+M, or F11 / Super+Shift+K don't fire → gsd-media-keys not running. Fix: `systemctl --user start org.gnome.SettingsDaemon.MediaKeys.target`. Check with `pgrep -a gsd-media-keys`.
