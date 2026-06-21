# Plan: Doctor Auto-Fix & README Prerequisites

**Created:** 2026-06-22  
**Status:** Draft  
**Files affected:** `voxfree-doctor.sh`, `README.md`

---

## Problem

Users get stuck after `voxfree-doctor.sh` fails because:

1. Fix commands are scattered as individual `fix()` lines under each failed check — users must piece together 3-6 separate commands.
2. The cheatsheet (`docs/wiki/VoxFree_Ubuntu24.04_Cheatsheet.md`) is 320 lines of documentation-heavy steps for setting up Mimic 3 and whisper.
3. No distinction between "safe to run automatically" and "needs admin access" — users see a wall of sudo commands and don't know what they can skip.
4. README has no prerequisites section — users don't know what to set up *before* running `install.sh`.

---

## Goal

Make `voxfree-doctor.sh --fix` a self-contained repair experience:

- **Auto-execute** non-sudo fixes silently (voice model download, mute toggle, symlink creation, env var cleanup).
- **Group remaining sudo fixes** by subsystem with numbered, copy-paste-ready commands.
- **Remind** users to relogin when needed.
- **Document** prerequisites in README so users can set up Mimic 3 and whisper manually before install.

---

## Changes

### 1. `voxfree-doctor.sh` — Auto-Fix Engine

#### 1.1 New data structures (replace lines 24-26)

```bash
AUTO_FIXED=()           # "section: description"
SUDO_FIXES=()           # "section@@label@@command@@relogin@@reason"
RELOGIN_REASONS=()      # "section: reason"
```

Delimiter: `@@` instead of `|` (commands may contain `|` characters).

#### 1.2 New helper functions (insert after line 59)

**`auto_fix()`** — executes a command silently; on success, records in `AUTO_FIXED` and prints `[✔] Auto-fixed: description`; on failure, prints `[✘] Auto-fix failed` and falls through to manual fix.

```bash
auto_fix() {
    local section="$1" description="$2"
    shift 2
    if "$@" >/dev/null 2>&1; then
        printf "  ${GREEN}[✔]${RESET} Auto-fixed: %s\n" "$description"
        AUTO_FIXED+=("[$section] $description")
    else
        printf "  ${RED}[✘]${RESET} Auto-fix failed: %s\n" "$description"
    fi
}
```

**`sudo_fix()`** — collects a fix entry into `SUDO_FIXES` array for later display.

```bash
sudo_fix() {
    local section="$1" label="$2" command="$3" relogin="${4:-}" reason="${5:-}"
    SUDO_FIXES+=("[$section]@@[$label]@@[$command]@@[$relogin]@@[$reason]")
    if [ "$SHOW_FIX" = true ]; then
        printf "      ${CYAN}Fix:${RESET} %s\n" "$command"
        [ "$relogin" = "yes" ] && RELOGIN_REASONS+=("[$section]: $reason")
    fi
}
```

#### 1.3 Per-check fix classification

Every `fail()` / `warn()` with a `fix()` call gets replaced. Here is the complete mapping:

**System section:**

| Check (line) | Old fix | New call |
|---|---|---|
| Not Wayland (89) | `fix "Log in with..."` | `sudo_fix "System" "Session" "Log in with 'Ubuntu (Wayland)' session at the login screen" "" ""` |
| PipeWire not running (99) | `fix "systemctl --user start pipewire"` | `auto_fix "System" "PipeWire started" systemctl --user start pipewire` |

**ReadLoud (TTS) section:**

| Check (line) | Old fix | New call |
|---|---|---|
| mimic3 not installed (113) | `fix "wget ... && sudo dpkg ..."` | `sudo_fix "ReadLoud — Text-to-Speech" "mimic3 install" "wget https://github.com/MycroftAI/mimic3/releases/download/v0.2.4/mycroft-mimic3-tts_0.2.4_amd64.deb && sudo dpkg -i mycroft-mimic3-tts_0.2.4_amd64.deb" "" ""` |
| Voice not found (126) | `fix "mimic3-download en_UK/apope_low"` | `auto_fix "ReadLoud — Text-to-Speech" "Voice model downloaded" mimic3-download en_UK/apope_low` |
| speech-dispatcher not installed (134) | `fix "sudo apt install speech-dispatcher"` | `sudo_fix "ReadLoud — Text-to-Speech" "speech-dispatcher" "sudo apt install speech-dispatcher" "" ""` |
| mimic3-generic.conf missing (149) | `fix "sudo bash /usr/share/voxfree/deps.sh --tts"` | `sudo_fix "ReadLoud — Text-to-Speech" "Mimic3 module config" "sudo bash /usr/share/voxfree/deps.sh --tts" "" ""` |
| Config uses --remote (143) | `fix "sudo bash /usr/share/voxfree/deps.sh --tts"` | `sudo_fix "ReadLoud — Text-to-Speech" "Mimic3 module config" "sudo bash /usr/share/voxfree/deps.sh --tts" "" ""` |
| DefaultModule wrong (157) | `fix "sudo sed -i ..."` | `sudo_fix "ReadLoud — Text-to-Speech" "DefaultModule" "sudo sed -i 's/^DefaultModule.*/DefaultModule mimic3-generic/' /etc/speech-dispatcher/speechd.conf" "" ""` |
| aplay not found (165) | `fix "sudo apt install alsa-utils"` | `sudo_fix "ReadLoud — Text-to-Speech" "alsa-utils" "sudo apt install alsa-utils" "" ""` |
| wl-paste not found (173) | `fix "sudo apt install wl-clipboard"` | `sudo_fix "ReadLoud — Text-to-Speech" "wl-clipboard" "sudo apt install wl-clipboard" "" ""` |
| readloud script missing (181) | `fix "sudo bash .../readloud.sh"` | `sudo_fix "ReadLoud — Text-to-Speech" "ReadLoud scripts" "sudo bash /usr/share/voxfree/ReadLoud/readloud.sh" "" ""` |
| readloud-stop script missing (189) | `fix "sudo bash .../readloud.sh"` | `sudo_fix "ReadLoud — Text-to-Speech" "ReadLoud scripts" "sudo bash /usr/share/voxfree/ReadLoud/readloud.sh" "" ""` |
| TTS pipeline failed (198) | `fix "Check audio output..."` | `sudo_fix "ReadLoud — Text-to-Speech" "Audio check" "Check audio output: wpctl get-volume @DEFAULT_AUDIO_SINK@" "" ""` |

**SpeakToType (STT) section:**

| Check (line) | Old fix | New call |
|---|---|---|
| arecord not found (215) | `fix "sudo apt install alsa-utils"` | `sudo_fix "SpeakToType — Speech-to-Text" "alsa-utils" "sudo apt install alsa-utils" "" ""` |
| sox not found (223) | `fix "sudo apt install sox libsox-fmt-all"` | `sudo_fix "SpeakToType — Speech-to-Text" "sox" "sudo apt install sox libsox-fmt-all" "" ""` |
| whisper wrong target (234) | `fix "sudo ln -sf ..."` | `auto_fix "SpeakToType — Speech-to-Text" "Whisper symlink created" ln -sf /opt/openai-whisper/bin/whisper-ctranslate2 /usr/local/bin/whisper` |
| whisper not in PATH (238) | `fix "sudo bash .../deps.sh --stt"` | `sudo_fix "SpeakToType — Speech-to-Text" "whisper install" "sudo bash /usr/share/voxfree/deps.sh --stt" "" ""` |
| venv missing (247) | `fix "sudo python3 -m venv ..."` | `sudo_fix "SpeakToType — Speech-to-Text" "whisper venv" "sudo python3 -m venv /opt/openai-whisper && sudo /opt/openai-whisper/bin/pip install whisper-ctranslate2" "" ""` |
| Model in user cache only (267) | `fix "sudo mkdir -p ..."` | `sudo_fix "SpeakToType — Speech-to-Text" "Model shared" "sudo mkdir -p /var/cache/huggingface/hub && sudo cp -r $HOME/.cache/huggingface/hub/models--Systran--faster-whisper-base.en /var/cache/huggingface/hub/ && sudo chmod -R a+rX /var/cache/huggingface" "no" "HF_HOME cache permissions"` |
| Model missing (269) | `fix "sudo bash .../deps.sh --stt"` | `sudo_fix "SpeakToType — Speech-to-Text" "Whisper model" "sudo bash /usr/share/voxfree/deps.sh --stt" "" ""` |
| HF_HOME not set (279/282) | `fix "echo ... \| sudo tee ..."` | `sudo_fix "SpeakToType — Speech-to-Text" "HF_HOME" "echo 'HF_HOME=/var/cache/huggingface' \| sudo tee -a /etc/environment" "yes" "HF_HOME env var"` |
| HF_HUB_OFFLINE in /etc/environment (289) | `fix "sudo sed -i ..."` | `auto_fix "SpeakToType — Speech-to-Text" "HF_HUB_OFFLINE removed" sudo sed -i '/HF_HUB_OFFLINE/d' /etc/environment` |
| Not in input group (301) | `fix "sudo usermod ..."` | `sudo_fix "SpeakToType — Speech-to-Text" "Input group" "sudo usermod -aG input $USER" "yes" "ydotool input group membership"` |
| uinput wrong mode (310) | `fix "echo 'KERNEL...' \| sudo tee ..."` | `sudo_fix "SpeakToType — Speech-to-Text" "udev rule" "echo 'KERNEL==\"uinput\", GROUP=\"input\", MODE=\"0660\"' \| sudo tee /etc/udev/rules.d/99-uinput.rules && sudo udevadm trigger" "no" "udev rules"` |
| /dev/uinput missing (314) | `fix "sudo modprobe uinput"` | `sudo_fix "SpeakToType — Speech-to-Text" "uinput kernel module" "sudo modprobe uinput" "no" "uinput module"` |
| ydotool not installed (318) | `fix "sudo apt install ydotool"` | `sudo_fix "SpeakToType — Speech-to-Text" "ydotool" "sudo apt install ydotool" "" ""` |
| xdotool not installed (326) | `fix "sudo apt install xdotool"` | `sudo_fix "SpeakToType — Speech-to-Text" "xdotool" "sudo apt install xdotool" "" ""` |
| wl-copy not found (334) | `fix "sudo apt install wl-clipboard"` | `sudo_fix "SpeakToType — Speech-to-Text" "wl-clipboard" "sudo apt install wl-clipboard" "" ""` |
| Mic muted (341) | `fix "wpctl set-mute ... 0"` | `auto_fix "SpeakToType — Speech-to-Text" "Mic unmuted" wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0` |
| Mic recording test failed (374) | `fix "systemctl --user restart ..."` | `auto_fix "SpeakToType — Speech-to-Text" "PipeWire restarted" systemctl --user restart pipewire pipewire-pulse` |
| dictate scripts missing (353/360) | `fix "sudo bash .../speak-to-type.sh"` | `sudo_fix "SpeakToType — Speech-to-Text" "Dictation scripts" "sudo bash /usr/share/voxfree/SpeakToType/speak-to-type.sh" "" ""` |

**GNOME Shortcuts section:**

| Check (line) | Old fix | New call |
|---|---|---|
| gsd-media-keys not running (390) | `fix "systemctl --user start ..."` | `sudo_fix "GNOME Keyboard Shortcuts" "gsd-media-keys" "systemctl --user start org.gnome.SettingsDaemon.MediaKeys.target" "" ""` |
| dconf profile missing (398) | `fix "printf ... \| sudo tee ..."` | `sudo_fix "GNOME Keyboard Shortcuts" "dconf profile" "printf 'user-db:user\nsystem-db:local\n' \| sudo tee /etc/dconf/profile/user" "" ""` |
| dconf shortcuts file missing (406) | `fix "sudo bash .../install.sh"` | `sudo_fix "GNOME Keyboard Shortcuts" "dconf shortcuts" "sudo bash /usr/share/voxfree/install.sh" "" ""` |
| Shortcut binding wrong (421) | `fix "gsettings set ..."` | `auto_fix "GNOME Keyboard Shortcuts" "Shortcut $SLOT fixed" gsettings set "$BASE$P/$SLOT/" command "$EXPECTED_CMD"` |
| Shortcut not configured (424) | `fix "sudo bash .../install.sh"` | `sudo_fix "GNOME Keyboard Shortcuts" "Shortcut $SLOT" "sudo bash /usr/share/voxfree/install.sh" "" ""` |
| wev not installed (437) | `fix "sudo apt install wev"` | `sudo_fix "GNOME Keyboard Shortcuts" "wev" "sudo apt install wev" "" ""` |

#### 1.4 Per-section fix block display

Add function `print_section_fixes()` (insert after `sudo_fix()`):

```bash
print_section_fixes() {
    local target_section="$1"
    local count=0 i=1
    for entry in "${SUDO_FIXES[@]}"; do
        local es="${entry%%@@*}"
        [ "$es" = "[$target_section]" ] && count=$((count+1))
    done
    if [ "$count" -gt 0 ]; then
        printf "\n  Fixes needed (copy & paste each):\n"
        for entry in "${SUDO_FIXES[@]}"; do
            local es ecmd
            es="${entry%%@@*}"
            local rest="${entry#*@@}"
            ecmd="${rest%%@@*}"
            [ "$es" = "[$target_section]" ] && { printf "    %d. %s\n" "$i" "$ecmd"; i=$((i+1)); }
        done
    fi
}
```

Insert `print_section_fixes "Section Name"` at the end of each section block, just before the closing `fi` that ends the section.

- After ReadLoud section (after line 202, before `fi`)
- After SpeakToType section (after line 378, before `fi`)
- After GNOME Shortcuts section (after line 438, before next section)
- System section has only 1 sudo fix (PipeWire) — include it too after line 100

#### 1.5 Rewritten summary footer (replace lines 441-482)

The summary footer groups failures by section and shows auto-fixed items and relogin reminders:

```bash
# ── SUMMARY ──────────────────────────────────────────────────────────────────
printf "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
printf "${BOLD} Summary  (${PASS} passed · ${WARN} warnings · ${FAIL} failed)${RESET}\n"
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

# Auto-fixed items
if [ "${#AUTO_FIXED[@]}" -gt 0 ]; then
    printf "\n  ${GREEN}Auto-fixed:${RESET}\n"
    for item in "${AUTO_FIXED[@]}"; do
        printf "    ${GREEN}[✔]${RESET} %s\n" "$item"
    done
fi

if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
    printf "\n  ${GREEN}${BOLD}✔ VoxFree is fully operational!${RESET}\n\n"
    [ "${#AUTO_FIXED[@]}" -gt 0 ] && printf "  ${DIM}Auto-fixed: %d issue(s). No further action needed.${RESET}\n" "${#AUTO_FIXED[@]}"
    printf "\n"
elif [ "$FAIL" -eq 0 ]; then
    printf "\n  ${YELLOW}${BOLD}VoxFree is operational with minor warnings.${RESET}\n"
    printf "  Run ${CYAN}bash voxfree-doctor.sh --fix${RESET} for remediation commands.\n\n"
else
    printf "\n  ${RED}${BOLD}VoxFree has issues that need attention.${RESET}\n\n"
    
    # Group remaining sudo fixes by section
    local sections_seen=""
    for entry in "${SUDO_FIXES[@]}"; do
        local entry_section="${entry%%@@*}"
        if ! echo "$sections_seen" | grep -qF "$entry_section"; then
            sections_seen="$sections_seen $entry_section"
            # Strip brackets for display
            local display_name
            display_name="${entry_section#\[}"
            display_name="${display_name%\]}"
            printf "  ${RED}%s failures:${RESET}\n" "$display_name"
            
            # Count and list fixes
            local i=1
            for e in "${SUDO_FIXES[@]}"; do
                local es ec
                es="${e%%@@*}"
                local rest="${e#*@@}"
                ec="${rest%%@@*}"
                if [ "$es" = "$entry_section" ]; then
                    printf "    %d. %s\n" "$i" "$ec"
                    i=$((i+1))
                fi
            done
            printf "\n"
        fi
    done
fi

# Re-login reminder
if [ "${#RELOGIN_REASONS[@]}" -gt 0 ]; then
    printf "  ${YELLOW}${BOLD}After running the above fixes:${RESET}\n"
    printf "  ${CYAN}Log out and back in for: ${RESET}"
    local first=true
    for reason in "${RELOGIN_REASONS[@]}"; do
        if [ "$first" = true ]; then
            printf "%s" "$reason"
            first=false
        else
            printf ", %s" "$reason"
        fi
    done
    printf "\n\n"
fi
```

Note: `local` declarations in the summary footer work because the footer runs at the top level of the script. In bash, `local` outside a function is permitted but has no special meaning — it's just a regular variable assignment. Remove `local` keyword from these to be safe:

```bash
# Instead of: local display_name
display_name="${entry_section#\[}"
```

---

### 2. README.md — Prerequisites Section

#### 2.1 Insert "Prerequisites" section (after line 10, before line 13 "A Note to the Community")

Place the Prerequisites section first, with a callout linking to the Legal Disclaimer (section 2.3).

#### 2.2 Update "VoxFree Doctor" section (lines 153-204)

```markdown
## Prerequisites

VoxFree requires **Ubuntu 24.04 + GNOME + Wayland + PipeWire**. These must be set up *before* installing VoxFree.

### System prerequisites

| Requirement | How to check |
|---|---|
| Ubuntu 24.04 | `lsb_release -a` |
| GNOME on Wayland | `echo $XDG_SESSION_TYPE` (must say `wayland`) |
| PipeWire running | `systemctl --user is-active pipewire` (must say `active`) |

### Install apt packages

Run once before VoxFree:

```bash
sudo apt update
sudo apt install -y \
  pipewire pipewire-pulse \
  alsa-utils \
  sox libsox-fmt-all \
  wl-clipboard xdotool ydotool \
  python3-venv ffmpeg \
  wev
```

### Add user to input group (for ydotool auto-paste)

```bash
sudo usermod -aG input $USER
```

> ⚠ **Log out and back in** after this step — ydotool will not work until relogin.

### Configure udev rule (for ydotool auto-paste)

```bash
echo 'KERNEL=="uinput", GROUP="input", MODE="0660"' | sudo tee /etc/udev/rules.d/99-uinput.rules
sudo udevadm trigger
```

### Install Mimic 3 (TTS engine)

> **Auto-fixable:** VoxFree Doctor can download the voice model automatically. You only need to install the binary and configure speech-dispatcher.

```bash
# Option 1: pipx (recommended)
sudo apt install pipx
pipx ensurepath
source ~/.bashrc
pipx install mimic3
mimic3-download --voice en_UK/apope_low

# Option 2: .deb package
wget https://github.com/MycroftAI/mimic3/releases/download/v0.2.4/mycroft-mimic3-tts_0.2.4_amd64.deb
sudo dpkg -i mycroft-mimic3-tts_0.2.4_amd64.deb

# Option 3: pip
python3 -m pip install --user "mycroft-mimic3-tts[all]"
```

### Configure speech-dispatcher for Mimic 3

```bash
sudo apt install speech-dispatcher speech-dispatcher-audio-plugins

# Create module config (local mode — no --remote flag)
echo 'GenericExecuteSynth "mimic3 --voice en_UK/apope_low"
AddVoice "en" "male1" "en_UK/apope_low"' | sudo tee /etc/speech-dispatcher/modules/mimic3-generic.conf

# Set as default module
sudo sed -i 's/^DefaultModule.*/DefaultModule mimic3-generic/' /etc/speech-dispatcher/speechd.conf
sudo systemctl --user restart speech-dispatcher
```

Verify: `spd-say "Hello from Mimic 3"`

### Install whisper-ctranslate2 (STT engine)

> **Auto-fixable:** VoxFree Doctor can download the whisper model and set up the symlink automatically. You only need to create the Python virtual environment.

```bash
python3 -m venv ~/.local/share/voxfree/whisper-venv
source ~/.local/share/voxfree/whisper-venv/bin/activate
pip install whisper-ctranslate2

# Create the path VoxFree expects
sudo ln -sf ~/.local/share/voxfree/whisper-venv /opt/openai-whisper
```

Or for system-wide install:

```bash
sudo python3 -m venv /opt/openai-whisper
sudo /opt/openai-whisper/bin/pip install whisper-ctranslate2
sudo ln -sf /opt/openai-whisper/bin/whisper-ctranslate2 /usr/local/bin/whisper
```

### Set up Whisper model cache

```bash
sudo mkdir -p /var/cache/huggingface
sudo chown -R $USER:$USER /var/cache/huggingface
echo 'HF_HOME=/var/cache/huggingface' | sudo tee -a /etc/environment
source /etc/environment
```

Download the model:

```bash
source /opt/openai-whisper/bin/activate   # or: source ~/.local/share/voxfree/whisper-venv/bin/activate
python -c 'from faster_whisper import WhisperModel; WhisperModel("base.en"); print("Done")'
```

Verify: `find /var/cache/huggingface -type d | grep base`

---

## After prerequisites

Now install VoxFree:

```bash
sudo bash install.sh --all
```

Then verify everything:

```bash
bash voxfree-doctor.sh --fix
```

If any steps are missed, Doctor will **auto-execute** what it can (voice model download, mute toggle, symlink creation, environment cleanup) and show you **exact copy-paste commands** for everything that needs admin access.

> **Quick fix all:** If you want to skip manual setup entirely, just run:
> ```bash
> sudo bash voxfree-doctor.sh --fix
> ```
> It will auto-execute non-sudo fixes and list all remaining sudo commands grouped by subsystem.
```

#### 2.2 Update "VoxFree Doctor" section (lines 153-204)

Update the intro text after `## Verify Your Installation — VoxFree Doctor`:

**Before:**
```markdown
Run the doctor after installing to check every component is correctly set up:
```

**After:**
```markdown
Run the doctor after installing to check every component is correctly set up:

With `--fix`, Doctor **auto-executes** safe non-sudo fixes (voice model download, mute toggle, symlink creation) and groups remaining sudo-required fixes by subsystem — each with a copy-paste-ready command.
```

Update the Doctor flags table (around line 191):

**Before:**
| `--fix` | Show the exact fix command for every failure/warning |

**After:**
| `--fix` | Auto-execute non-sudo fixes + show copy-paste commands for sudo fixes |

#### 2.3 Update Troubleshooting section (line 384+)

Add new subsection at the top of "Common issues":

```markdown
**Nothing works — start fresh:**
```bash
sudo bash voxfree-doctor.sh --fix
```
Doctor auto-fixes what it can and lists every sudo command you need to run, grouped by subsystem.
```

#### 2.4 Add "Legal Disclaimer" section (append at end of README)

A formal disclaimer stating:

- Target audience is experienced Linux/Ubuntu users
- No warranty, no liability
- User is responsible for reviewing commands before executing
- User accepts risks of sudo/system-level operations
- Links back to this section from the Prerequisites callout at the top

---

### Auto-fixable items summary

These are silently auto-executed during `--fix`:

| Item | Command | Section |
|---|---|---|
| PipeWire not running | `systemctl --user start pipewire` | System |
| Voice model not found | `mimic3-download en_UK/apope_low` | ReadLoud |
| Whisper symlink wrong | `ln -sf /opt/openai-whisper/bin/... /usr/local/bin/whisper` | SpeakToType |
| HF_HUB_OFFLINE in /etc/environment | `sudo sed -i '/HF_HUB_OFFLINE/d' /etc/environment` | SpeakToType |
| Mic muted | `wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0` | SpeakToType |
| PipeWire crashed (recording test fail) | `systemctl --user restart pipewire pipewire-pulse` | SpeakToType |
| Shortcut binding wrong | `gsettings set "..." command "..."` | GNOME Shortcuts |

## Non-auto-fixable items (sudo guidance)

These are collected and displayed by subsystem:

| Item | Command | Needs relogin |
|---|---|---|
| Mimic 3 install | wget + dpkg | No |
| speech-dispatcher install | `sudo apt install speech-dispatcher` | No |
| speech-dispatcher module config | `sudo bash deps.sh --tts` | No |
| DefaultModule config | `sudo sed -i ...` | No |
| aplay / alsa-utils | `sudo apt install alsa-utils` | No |
| wl-clipboard | `sudo apt install wl-clipboard` | No |
| ReadLoud scripts | `sudo bash .../readloud.sh` | No |
| whisper venv / install | `sudo bash deps.sh --stt` | No |
| whisper model | `sudo bash deps.sh --stt` | No |
| HF_HOME in /etc/environment | `echo ... \| sudo tee -a /etc/environment` | **Yes** |
| Input group membership | `sudo usermod -aG input $USER` | **Yes** |
| udev rule | `sudo tee /etc/udev/rules.d/99-uinput.rules` | No |
| uinput kernel module | `sudo modprobe uinput` | No |
| ydotool / xdotool / wev / sox | `sudo apt install ...` | No |
| Dictation scripts | `sudo bash .../speak-to-type.sh` | No |
| gsd-media-keys | `systemctl --user start ...` | No |
| dconf profile / shortcuts | `sudo tee /etc/dconf/...` | No |
| Install VoxFree (shortcuts) | `sudo bash install.sh` | No |

---

## Implementation order

1. **`voxfree-doctor.sh`** — add data structures, helper functions, rewrite all 40+ fix calls, add per-section display, rewrite summary footer
2. **`README.md`** — add Prerequisites section, Legal Disclaimer, update Doctor section, update Troubleshooting
3. **Test** — `bash voxfree-doctor.sh --fix` on a system with simulated failures

## Testing approach

1. Create a test scenario by temporarily renaming mimic3 binary, muting mic, removing shortcut bindings.
2. Run `bash voxfree-doctor.sh --fix` and verify:
   - Auto-fixed items show `[✔] Auto-fixed: description` inline
   - Sudo fixes appear grouped under each subsystem with numbered commands
   - Summary footer shows auto-fixed count, grouped failures, and relogin reminder
   - `--fix` with no failures shows clean success + auto-fixed count

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Auto-fix fails silently | Prints `[✘] Auto-fix failed` and falls through to manual fix below |
| `@@` delimiter in commands | Commands rarely contain `@@`; if they do, `%%@@*` parsing still works for first two fields |
| `local` outside function | Remove `local` keyword in summary footer (runs at top level) |
| Auto-fix changes user's config | Only auto-fixes are low-risk: start services, download data, set mute to 0, remove blocking env var, create symlinks, fix gsettings |
| User doesn't run with `--fix` | Without `--fix`, `--fix` lines still print under each failure (unchanged from current behaviour) |

## Files to edit

1. `/home/developer/Projects/VoxFree/voxfree-doctor.sh` — ~100 lines added, ~50 lines modified
2. `/home/developer/Projects/VoxFree/README.md` — ~130 lines added, ~10 lines modified
