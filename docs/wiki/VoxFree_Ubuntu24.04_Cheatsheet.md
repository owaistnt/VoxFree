# VoxFree Ubuntu 24.04 Dependency Cheat Sheet

## Mimic3 Installation (Recommended: pipx)

### Install pipx

```bash
sudo apt update
sudo apt install pipx
pipx ensurepath
```

Log out and back in, or:

```bash
source ~/.bashrc
```

### Install Mimic3

```bash
pipx install mimic3
```

Verify:

```bash
mimic3 --version
```

Expected:

```text
mimic3 0.2.x
```

### Download Voice

```bash
mimic3-download --voice en_UK/apope_low
```

Verify:

```bash
find ~/.local/share/mycroft/mimic3/voices
```

Expected voice path:

```text
~/.local/share/mycroft/mimic3/voices/en_UK/apope_low
```

---

## Alternative Mimic3 Installation (venv)

```bash
python3 -m venv ~/.local/share/voxfree/mimic3-venv
source ~/.local/share/voxfree/mimic3-venv/bin/activate
pip install mimic3
```

---

## Speech Dispatcher

```bash
sudo apt install speech-dispatcher speech-dispatcher-audio-plugins
```

### Mimic3 Module

Create:

```bash
sudo nano /etc/speech-dispatcher/modules/mimic3-generic.conf
```

Configure for LOCAL mode (important):

```ini
GenericExecuteSynth "mimic3 --voice en_UK/apope_low"

AddVoice "en" "male1" "en_UK/apope_low"
```

Do NOT use:

```text
--remote
```

because that requires mimic3-server.

---

## Set Mimic3 as Default Speech Dispatcher Module

Edit:

```bash
sudo nano /etc/speech-dispatcher/speechd.conf
```

Replace:

```ini
# DefaultModule espeak-ng
```

with:

```ini
DefaultModule mimic3-generic
```

Restart:

```bash
systemctl --user restart speech-dispatcher
```

Verify:

```bash
grep "^DefaultModule" /etc/speech-dispatcher/speechd.conf
```

Expected:

```text
DefaultModule mimic3-generic
```

---

## Test Mimic3

```bash
spd-say "Hello from Mimic3"
```

---

# Whisper Setup

## Create Whisper Environment

```bash
python3 -m venv ~/.local/share/voxfree/whisper-venv

source ~/.local/share/voxfree/whisper-venv/bin/activate
```

Install:

```bash
pip install faster-whisper whisper-ctranslate2
```

Verify:

```bash
which whisper-ctranslate2
```

---

## VoxFree Compatibility Path

VoxFree expects:

```text
/opt/openai-whisper
```

Create:

```bash
sudo ln -s \
  /home/$USER/.local/share/voxfree/whisper-venv \
  /opt/openai-whisper
```

Verify:

```bash
ls -l /opt/openai-whisper/bin/whisper-ctranslate2
```

---

## Shared HuggingFace Cache

```bash
sudo mkdir -p /var/cache/huggingface
sudo chown -R $USER:$USER /var/cache/huggingface
```

Add to:

```bash
sudo nano /etc/environment
```

```ini
HF_HOME=/var/cache/huggingface
```

Reload:

```bash
source /etc/environment
```

Verify:

```bash
echo $HF_HOME
```

Expected:

```text
/var/cache/huggingface
```

---

## Download Whisper base.en

Activate environment:

```bash
source /opt/openai-whisper/bin/activate
```

Download:

```bash
python - <<'EOF'
from faster_whisper import WhisperModel
WhisperModel("base.en")
print("Downloaded base.en")
EOF
```

Verify:

```bash
find /var/cache/huggingface -type d | grep base
```

Expected:

```text
models--Systran--faster-whisper-base.en
```

---

## Audio Dependencies

```bash
sudo apt install \
  pipewire \
  pipewire-pulse \
  sox \
  alsa-utils
```

---

## Wayland Clipboard Dependencies

```bash
sudo apt install \
  wl-clipboard \
  xdotool \
  ydotool
```

Add user to input group:

```bash
sudo usermod -aG input $USER
```

Log out and back in.

---

## Final Validation

```bash
voxfree --doctor
```

Expected:

```text
30 passed
0 failed
```

---

## Known-Good Configuration

- Ubuntu 24.04
- GNOME Wayland
- PipeWire
- Mimic3 0.2.4
- Speech Dispatcher → mimic3-generic
- whisper-ctranslate2 0.5.7
- Whisper model: base.en
- HF_HOME=/var/cache/huggingface
- VoxFree Doctor: 30 passed, 0 failed
