# 2026-06-22 — Doctor Auto-Fix Engine and Prerequisites Section

## Problem

When `voxfree-doctor.sh` reported failures, users had to piece together 3-6 separate fix commands scattered under each failed check. The cheatsheet (`docs/wiki/VoxFree_Ubuntu24.04_Cheatsheet.md`) was 320 lines of documentation-heavy steps for setting up Mimic 3 and whisper, and users didn't know which steps were already handled by Doctor.

The README had no prerequisites section — users didn't know what to set up *before* running `install.sh`. There was no legal protection for the author since the installation requires `sudo` commands that modify system packages, kernel modules, and device permissions.

Three specific pain points:

1. Fragmented fix commands — no distinction between "safe to run automatically" and "needs admin access"
2. No prerequisites documentation — users ran `install.sh` expecting it to handle everything, then got stuck on Mimic 3 and whisper setup
3. No legal disclaimer — no written acknowledgment that users are experienced Linux users who accept the risks of system-level commands

## Envisioning

`voxfree-doctor.sh --fix` should become a self-contained repair experience:

- **Auto-execute** safe non-sudo fixes silently (voice model download, mute toggle, symlink creation, environment cleanup) and show `[✔] Auto-fixed: description` inline
- **Group remaining sudo fixes** by subsystem with numbered, copy-paste-ready commands
- **Remind users to relogin** when needed (input group, HF_HOME env var)
- **README prerequisites** — documented setup steps for Mimic 3 and whisper before `install.sh`
- **Legal disclaimer** — written acknowledgment of risk and user responsibility at the bottom of README

Expected output format with `--fix`:

```
System
──────
  [✔] Ubuntu 24.04 (Noble)
  [✔] Wayland session (ubuntu:GNOME)
  [✔] PipeWire audio server running

ReadLoud — Text-to-Speech
─────────────────────────
  [✔] mimic3 0.2.4 — /usr/bin/mimic3
  [✘] Voice en_UK/apope_low not found
  [✔] Auto-fixed: Voice model downloaded

  Fixes needed (copy & paste each):
    1. sudo apt install speech-dispatcher
    2. sudo bash /usr/share/voxfree/deps.sh --tts

Summary  (32 passed · 0 warnings · 1 failed)

  Auto-fixed:
    [✔] [ReadLoud — Text-to-Speech] Voice model downloaded

  ReadLoud — Text-to-Speech failures:
    1. sudo apt install speech-dispatcher
    2. sudo bash /usr/share/voxfree/deps.sh --tts

  After running the above fixes:
  Log out and back in for: HF_HOME env var, ydotool input group membership
```

## Solution

### voxfree-doctor.sh — Auto-Fix Engine

**New data structures:**

```bash
AUTO_FIXED=()           # "section: description" — items auto-fixed during checks
SUDO_FIXES=()           # "section@@label@@command@@relogin@@reason" — sudo fixes grouped by section
RELOGIN_REASONS=()      # "section: reason" — items requiring relogin
```

Delimiter: `@@` instead of `|` because commands may contain `|` characters.

**Three new helper functions:**

- `auto_fix(section, description, ...cmd)` — executes remaining args as a command; on success records in `AUTO_FIXED` and prints `[✔] Auto-fixed: description`; on failure prints `[✘] Auto-fix failed` and falls through to manual fix
- `sudo_fix(section, label, command, relogin, reason)` — collects a fix entry into `SUDO_FIXES` for later grouped display; if `relogin=yes`, adds to `RELOGIN_REASONS`
- `print_section_fixes(section)` — displays numbered fix commands collected for a given section

**~40 `fix()` calls replaced** with `auto_fix()` or `sudo_fix()` across all sections:

**System section:**

| Check | Old fix | New call |
|---|---|---|
| Not Wayland | `fix "Log in with..."` | `sudo_fix "System" "Session" "Log in with..."` |
| PipeWire not running | `fix "systemctl --user start pipewire"` | `auto_fix "System" "PipeWire started" systemctl --user start pipewire` |

**ReadLoud (TTS) section:**

| Check | Old fix | New call |
|---|---|---|
| mimic3 not installed | `fix "wget ... && sudo dpkg ..."` | `sudo_fix "ReadLoud — Text-to-Speech" "mimic3 install" "wget ..."` |
| Voice not found | `fix "mimic3-download en_UK/apope_low"` | `auto_fix "ReadLoud — Text-to-Speech" "Voice model downloaded" mimic3-download en_UK/apope_low` |
| speech-dispatcher not installed | `fix "sudo apt install speech-dispatcher"` | `sudo_fix "ReadLoud — Text-to-Speech" "speech-dispatcher" "sudo apt install speech-dispatcher"` |
| mimic3-generic.conf missing | `fix "sudo bash /usr/share/voxfree/deps.sh --tts"` | `sudo_fix "ReadLoud — Text-to-Speech" "Mimic3 module config" "sudo bash ..."` |
| Config uses --remote | `fix "sudo bash /usr/share/voxfree/deps.sh --tts"` | `sudo_fix "ReadLoud — Text-to-Speech" "Mimic3 module config" "sudo bash ..."` |
| DefaultModule wrong | `fix "sudo sed -i ..."` | `sudo_fix "ReadLoud — Text-to-Speech" "DefaultModule" "sudo sed -i ..."` |
| aplay not found | `fix "sudo apt install alsa-utils"` | `sudo_fix "ReadLoud — Text-to-Speech" "alsa-utils" "sudo apt install alsa-utils"` |
| wl-paste not found | `fix "sudo apt install wl-clipboard"` | `sudo_fix "ReadLoud — Text-to-Speech" "wl-clipboard" "sudo apt install wl-clipboard"` |
| readloud script missing | `fix "sudo bash .../readloud.sh"` | `sudo_fix "ReadLoud — Text-to-Speech" "ReadLoud scripts" "sudo bash .../readloud.sh"` |
| readloud-stop script missing | `fix "sudo bash .../readloud.sh"` | `sudo_fix "ReadLoud — Text-to-Speech" "ReadLoud scripts" "sudo bash .../readloud.sh"` |
| TTS pipeline failed | `fix "Check audio output..."` | `sudo_fix "ReadLoud — Text-to-Speech" "Audio check" "Check audio output..."` |

**SpeakToType (STT) section:**

| Check | Old fix | New call |
|---|---|---|
| arecord not found | `fix "sudo apt install alsa-utils"` | `sudo_fix "SpeakToType — Speech-to-Text" "alsa-utils" "sudo apt install alsa-utils"` |
| sox not found | `fix "sudo apt install sox libsox-fmt-all"` | `sudo_fix "SpeakToType — Speech-to-Text" "sox" "sudo apt install sox libsox-fmt-all"` |
| whisper wrong target | `fix "sudo ln -sf ..."` | `auto_fix "SpeakToType — Speech-to-Text" "Whisper symlink created" ln -sf ...` |
| whisper not in PATH | `fix "sudo bash .../deps.sh --stt"` | `sudo_fix "SpeakToType — Speech-to-Text" "whisper install" "sudo bash .../deps.sh --stt"` |
| venv missing | `fix "sudo python3 -m venv ..."` | `sudo_fix "SpeakToType — Speech-to-Text" "whisper venv" "sudo python3 -m venv ..."` |
| Model in user cache only | `fix "sudo mkdir -p ..."` | `auto_fix "SpeakToType — Speech-to-Text" "Model copied to shared cache" ...` |
| Model missing entirely | `fix "sudo bash .../deps.sh --stt"` | `sudo_fix "SpeakToType — Speech-to-Text" "Whisper model" "sudo bash .../deps.sh --stt"` |
| HF_HOME not configured | `fix "echo ... \| sudo tee ..."` | `sudo_fix "SpeakToType — Speech-to-Text" "HF_HOME" "echo ... \| sudo tee ..." relogin:yes reason:"HF_HOME env var"` |
| HF_HUB_OFFLINE in /etc/env | `fix "sudo sed -i '/HF_HUB_OFFLINE/d' ..."` | `auto_fix "SpeakToType — Speech-to-Text" "HF_HUB_OFFLINE removed" bash -c "sed -i '/HF_HUB_OFFLINE/d' /etc/environment"` |
| Not in input group | `fix "sudo usermod -aG input ..."` | `sudo_fix "SpeakToType — Speech-to-Text" "Input group" "sudo usermod -aG input $USER" relogin:yes reason:"ydotool input group membership"` |
| uinput wrong mode | `fix "echo 'KERNEL...' \| sudo tee ..."` | `sudo_fix "SpeakToType — Speech-to-Text" "udev rule" "echo 'KERNEL==\"uinput\", ...'" relogin:no reason:"udev rules"` |
| /dev/uinput missing | `fix "sudo modprobe uinput"` | `sudo_fix "SpeakToType — Speech-to-Text" "uinput kernel module" "sudo modprobe uinput" relogin:no reason:"uinput module"` |
| ydotool not installed | `fix "sudo apt install ydotool"` | `sudo_fix "SpeakToType — Speech-to-Text" "ydotool" "sudo apt install ydotool"` |
| xdotool not installed | `fix "sudo apt install xdotool"` | `sudo_fix "SpeakToType — Speech-to-Text" "xdotool" "sudo apt install xdotool"` |
| wl-copy not found | `fix "sudo apt install wl-clipboard"` | `sudo_fix "SpeakToType — Speech-to-Text" "wl-clipboard" "sudo apt install wl-clipboard"` |
| Mic muted | `fix "wpctl set-mute ..."` | `auto_fix "SpeakToType — Speech-to-Text" "Mic unmuted" wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0` |
| Mic recording failed | `fix "systemctl --user restart ..."` | `auto_fix "SpeakToType — Speech-to-Text" "PipeWire restarted" systemctl --user restart pipewire pipewire-pulse` |
| dictate scripts missing | `fix "sudo bash .../speak-to-type.sh"` | `sudo_fix "SpeakToType — Speech-to-Text" "Dictation scripts" "sudo bash .../speak-to-type.sh"` |

**GNOME Shortcuts section:**

| Check | Old fix | New call |
|---|---|---|
| gsd-media-keys not running | `fix "systemctl --user start ..."` | `sudo_fix "GNOME Keyboard Shortcuts" "gsd-media-keys" "systemctl --user start ..."` |
| dconf profile missing | `fix "printf ... \| sudo tee ..."` | `sudo_fix "GNOME Keyboard Shortcuts" "dconf profile" "printf ... \| sudo tee ..."` |
| dconf shortcuts file missing | `fix "sudo bash .../install.sh"` | `sudo_fix "GNOME Keyboard Shortcuts" "dconf shortcuts" "sudo bash .../install.sh"` |
| Shortcut binding wrong | `fix "gsettings set ..."` | `auto_fix "GNOME Keyboard Shortcuts" "Shortcut $SLOT fixed" gsettings set "..."` |
| Shortcut not configured | `fix "sudo bash .../install.sh"` | `sudo_fix "GNOME Keyboard Shortcuts" "Shortcut $SLOT" "sudo bash .../install.sh"` |
| wev not installed | `fix "sudo apt install wev"` | `sudo_fix "GNOME Keyboard Shortcuts" "wev" "sudo apt install wev"` |

**Per-section fix blocks:** `print_section_fixes()` called at end of each section (System, ReadLoud, SpeakToType, GNOME Shortcuts). Displays numbered fix commands for any sudo fixes collected in that section.

**Rewritten summary footer:** Replaced the old linear listing of passed/failed items with:
1. Auto-fixed items section (if any)
2. If all passed: clean success message + auto-fixed count
3. If failures remain: grouped by section with numbered commands
4. Re-login reminder (if any items require relogin)

### README.md — Prerequisites Section

New "Prerequisites" section (~140 lines) inserted before "A Note to the Community":

- **System prerequisites** — table of checks (Ubuntu version, Wayland, PipeWire)
- **Install apt packages** — single command for all APT dependencies
- **Input group setup** — `sudo usermod -aG input $USER` with relogin reminder
- **udev rule configuration** — `99-uinput.rules` for ydotool auto-paste
- **Mimic 3 install** — 3 options (pipx, .deb, pip) with "Auto-fixable" badge noting Doctor handles voice download
- **Speech-dispatcher configuration** — module config + DefaultModule setting + restart
- **whisper-ctranslate2 setup** — user and system-wide options with "Auto-fixable" badge noting Doctor handles model download + symlink
- **Whisper model cache** — HF_HOME setup + model download with verify command
- **After prerequisites** — quick-start: `install.sh` → `voxfree-doctor.sh --fix` with explanation of what Doctor does

**Legal Disclaimer** section at end with 6 clauses:
1. Intended Audience — experienced Linux/Ubuntu users only
2. No Warranty — "as is" provision
3. User Responsibility — reviewing commands, backups, recovery
4. Limitation of Liability — no damages
5. Risk Acknowledgement — sudo/system operations carry inherent risks
6. No Support Obligation — bug reports welcome, no guarantee of support

**Doctor section updated** — new `--fix` description with example output showing auto-fix + grouped sudo commands. Flags table updated.

**Troubleshooting updated** — "Nothing works — start fresh" section at top referencing `voxfree-doctor.sh --fix`.

### Auto-fixable items

These are silently auto-executed during checks:

| Item | Command | Section |
|---|---|---|
| PipeWire not running | `systemctl --user start pipewire` | System |
| Voice model not found | `mimic3-download en_UK/apope_low` | ReadLoud |
| Whisper symlink wrong | `ln -sf /opt/openai-whisper/bin/... /usr/local/bin/whisper` | SpeakToType |
| HF_HUB_OFFLINE in /etc/environment | `sudo sed -i '/HF_HUB_OFFLINE/d' /etc/environment` | SpeakToType |
| Mic muted | `wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0` | SpeakToType |
| PipeWire crashed (recording test fail) | `systemctl --user restart pipewire pipewire-pulse` | SpeakToType |
| Shortcut binding wrong | `gsettings set "..." command "..."` | GNOME Shortcuts |

### Non-auto-fixable items (sudo guidance)

These are collected and displayed by subsystem as numbered copy-paste commands:

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

### Risks and mitigations

| Risk | Mitigation |
|---|---|
| Auto-fix fails silently | Prints `[✘] Auto-fix failed` and falls through to manual fix below |
| `@@` delimiter in commands | Commands rarely contain `@@`; if they do, `%%@@*` parsing still works for first two fields |
| `local` outside function | Removed `local` keyword in summary footer (runs at top level of script) |
| Auto-fix changes user's config | Only low-risk auto-fixes: start services, download data, set mute to 0, remove blocking env var, create symlinks, fix gsettings |
| User doesn't run with `--fix` | Without `--fix`, `fix()` lines still print under each failure (unchanged from current behaviour) |

## Related Files

| File | Change |
|------|--------|
| `voxfree-doctor.sh` | Added AUTO_FIXED, SUDO_FIXES, RELOGIN_REASONS arrays; 3 new functions (auto_fix, sudo_fix, print_section_fixes); ~40 fix() calls replaced with auto_fix()/sudo_fix(); per-section fix blocks; rewritten summary footer |
| `README.md` | New Prerequisites section (system checks, apt packages, Mimic 3, speech-dispatcher, whisper-ctranslate2, model cache, after-prerequisites guide); Legal Disclaimer (6 clauses); Doctor section updated with --fix example; Troubleshooting updated |
| `releases/voxfree_0.3.1_all.deb` | Packaged deb (26.6KB) with all changes |
| `docs/plan/doctor-auto-fix-and-prerequisites.md` | Implementation plan documenting the feature |
