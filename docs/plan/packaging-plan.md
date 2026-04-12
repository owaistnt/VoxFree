# VoxFree Distribution & Portability Plan

## Context

VoxFree currently works only if the user runs `sudo bash install.sh` from the cloned project directory. There is no package manager integration, `voxfree-doctor` is not a system command, installation only works with one specific method per dependency (GitHub .deb for mimic3, manual venv for whisper), and there is no way to install without root. This plan addresses all four concerns in a single coherent implementation.

---

## 1. New File Structure

```
VoxFree/
├── VERSION                         ← NEW: single source of truth for version (contains: 0.1.0)
├── build-deb.sh                    ← NEW: reads VERSION, builds dist/voxfree_0.1.0_amd64.deb
├── uninstall.sh                    ← NEW: removes all VoxFree traces
├── docs/
│   ├── building-blocks.md         ← NEW: all technologies, what they do, how they fit
│   ├── distribution-strategy.md   ← NEW: distribution decisions and trade-offs
│   ├── architecture.md            ← NEW: component diagram and data flows
│   ├── packaging.md               ← NEW: how to build and publish the .deb
│   └── plan/
│       └── packaging-plan.md      ← NEW: copy of this plan (implementation roadmap)
├── packaging/
│   ├── DEBIAN/
│   │   ├── control                 ← NEW: package metadata
│   │   ├── postinst                ← NEW: calls install.sh after dpkg installs files
│   │   └── prerm                   ← NEW: removes /usr/local/bin/* scripts on uninstall
│   ├── changelog                   ← NEW: required by dpkg (Debian format)
│   └── copyright                   ← NEW: required by dpkg (Debian format)
├── lib/
│   └── detect.sh                   ← NEW: abstracts detect/install for mimic3 + whisper
├── install.sh                      ← MODIFIED: add INSTALL_MODE, --user, --postinst-mode
├── deps.sh                         ← MODIFIED: source lib/detect.sh, use abstracted funcs
├── voxfree-doctor.sh               ← MODIFIED: fix command paths for installed locations
├── ReadLoud/readloud.sh            ← MODIFIED: use $BIN_DIR, $DCONF_DIR variables
└── SpeakToType/speak-to-type.sh   ← MODIFIED: same as readloud.sh
```

After `sudo apt install voxfree` (or `sudo bash install.sh`), the system gets:
- Scripts in `/usr/share/voxfree/` (source)
- Wrappers in `/usr/local/bin/` — all prefixed with `voxfree-`:

| Old name | New name | Shortcut | Action |
|----------|----------|----------|--------|
| `read-selection` | `voxfree-readloud` | F9 | Read selected text aloud (toggle) |
| `stop-reading` | `voxfree-readloud-stop` | F11 | Force-stop TTS immediately |
| `speech-start` | `voxfree-dictate` | F10 | Start microphone recording |
| `speech-stop` | `voxfree-dictate-stop` | F11 | Stop recording → transcribe → paste |
| *(new)* | `voxfree-doctor` | CLI only | Health check (36 points) |
| *(new)* | `voxfree` | CLI only | Main entry: calls install.sh |

This namespace prevents collisions with other tools and makes it obvious these commands belong to VoxFree (`voxfree-<TAB>` autocompletes everything).

Source files in `ReadLoud/` and `SpeakToType/` also rename to match:
- `read-selection.sh` → `voxfree-readloud.sh`
- `stop-reading.sh` → `voxfree-readloud-stop.sh`
- `speech-start.sh` → `voxfree-dictate.sh`
- `speech-stop.sh` → `voxfree-dictate-stop.sh`

---

## 2. The .deb Package

The .deb contains **only VoxFree scripts** (~120KB). It does NOT bundle mimic3, the whisper venv, or model files — these are downloaded by `postinst`. This is the correct model (same as Chrome, VS Code, etc.).

### packaging/DEBIAN/control
```
Package: voxfree
Version: 0.1.0
Architecture: all
Maintainer: VoxFree Project
Installed-Size: 120
Depends: bash (>= 5.0), wl-clipboard, alsa-utils, libnotify-bin, wev, python3-venv, ffmpeg
Recommends: sox, libsox-fmt-all, xdotool, ydotool, speech-dispatcher
Suggests: mycroft-mimic3-tts
Description: Offline voice tools for Ubuntu 24.04 GNOME/Wayland
 ReadLoud (TTS via Mimic 3) and SpeakToType (STT via Whisper base.en).
```

`mycroft-mimic3-tts` is `Suggests` (not `Depends`) because it is not in Ubuntu repos — dpkg cannot resolve it from `Depends`.

### packaging/DEBIAN/postinst
Calls `bash /usr/share/voxfree/install.sh --postinst-mode` (which skips dep download, goes straight to shortcut/script config). If no TTY, prints: *"VoxFree installed. Run 'sudo voxfree' to configure."*

### build-deb.sh
Assembles staging tree at `dist/voxfree_VERSION_amd64/`, runs `fakeroot dpkg-deb --build`. No sudo needed to build. Output: `dist/voxfree_0.1.0_amd64.deb`.

---

## 3. voxfree-doctor as CLI Command

Install a **wrapper** (not a copy) at install time. The wrapper calls the canonical `.sh` from its installed location, so upgrades automatically take effect:

**System install** → `/usr/local/bin/voxfree-doctor`:
```bash
#!/bin/bash
exec bash /usr/share/voxfree/voxfree-doctor.sh "$@"
```

**User install** → `~/.local/bin/voxfree-doctor`:
```bash
#!/bin/bash
exec bash "$HOME/.local/share/voxfree/voxfree-doctor.sh" "$@"
```

Also install a `voxfree` CLI command at `/usr/local/bin/voxfree` that calls `sudo bash /usr/share/voxfree/install.sh "$@"` so users can run `voxfree --fix` or `voxfree --tts` after installation.

All dconf shortcut commands update to use the new names:
- `binding=XF86Messenger` → command `/usr/local/bin/voxfree-readloud`
- `binding=Cancel` (stop TTS) → command `/usr/local/bin/voxfree-readloud-stop`
- `binding=XF86Go` → command `/usr/local/bin/voxfree-dictate`
- `binding=Cancel` (stop STT) → command `/usr/local/bin/voxfree-dictate-stop`

Changes to `voxfree-doctor.sh`: replace hardcoded `bash VoxFree/deps.sh` fix hints with `bash /usr/share/voxfree/deps.sh` (or `$VOXFREE_HOME/deps.sh` env var).

---

## 4. lib/detect.sh — Flexible Dependency Handling

New file `lib/detect.sh`, sourced by `deps.sh`. Provides four functions:

| Function | What it does |
|----------|-------------|
| `detect_whisper` | Sets `$WHISPER_BIN`, `$WHISPER_VENV`. Checks: `/opt/openai-whisper/`, user venv, existing `whisper` in PATH |
| `install_whisper` | Creates venv at `$TARGET_VENV` (system or user path), installs `whisper-ctranslate2`, falls back to `openai-whisper` |
| `detect_mimic3` | Sets `$MIMIC3_BIN`, `$MIMIC3_METHOD` (deb/pip). Checks `which mimic3` + `dpkg -l` |
| `install_mimic3` | Tries: GitHub .deb via wget/curl → pip install `mycroft-mimic3-tts[all]` → warning with manual instructions |

`deps.sh` becomes: detect → skip if found, install if not. This makes repeated runs idempotent and supports pre-existing installations of either tool.

---

## 5. Per-user Installation (--user flag)

Add `--user` flag to `install.sh`. Also auto-triggers if invoked without root and user hasn't passed `--system`.

### Path mapping

| Component | System (current) | --user (new) |
|-----------|-----------------|--------------|
| Scripts (renamed with voxfree- prefix) | `/usr/local/bin/voxfree-*` | `~/.local/bin/voxfree-*` |
| Script sources | `/usr/share/voxfree/bin/` | `~/.local/share/voxfree/bin/` |
| Whisper venv | `/opt/openai-whisper/` | `~/.local/share/voxfree/whisper-venv/` |
| Whisper symlink | `/usr/local/bin/whisper` | `~/.local/bin/whisper` |
| Model cache | `/var/cache/huggingface/` | `~/.cache/huggingface/` (HF default) |
| HF_HOME | `/etc/environment` | `~/.profile` |
| dconf shortcuts | `/etc/dconf/db/local.d/` | gsettings user-db only |
| voxfree-doctor | `/usr/local/bin/` | `~/.local/bin/` |

### sudo-still-required items in --user mode

Three things always need root. The script handles them gracefully:

1. **apt packages** — check `dpkg -l` first; skip if installed; warn with install command if missing
2. **udev rules** (`/etc/udev/rules.d/99-uinput.rules`) — check if exists; skip if done; warn "ydotool auto-paste needs sudo once: `sudo bash deps.sh --udev`"
3. **speech-dispatcher config** — check if already local mode; skip if correct; warn if not

### Updated install menu

```
Install for:
  1) Current user only  (no sudo needed for most steps)
  2) All users          (requires sudo)
```

If invoked as root or with `sudo`, default to option 2. If invoked as plain user, default to option 1. Flags `--user` and `--system` bypass the menu.

### GNOME shortcuts in --user mode

Skip writing to `/etc/dconf/db/local.d/`. Use only `gsettings` (user database). Shortcuts apply to the current user's session only.

### HF_HOME in --user mode

Append to `~/.profile` instead of `/etc/environment`:
```bash
export HF_HOME="$HOME/.cache/huggingface"
export HF_HUB_DISABLE_TELEMETRY=1
```

---

## 6. Uninstallation

### Two paths: .deb removal and standalone script

**Via .deb:** `sudo apt remove voxfree` triggers `DEBIAN/prerm` then `DEBIAN/postrm`.

**Standalone:** `sudo bash uninstall.sh` (new file) for users who installed via shell.

**User mode:** `bash uninstall.sh --user` — no sudo needed (removes ~/.local only).

### New file: `uninstall.sh`

```bash
# Usage:
#   sudo bash uninstall.sh           (system install, removes /usr/local/bin/voxfree-*)
#   sudo bash uninstall.sh --purge   (also removes whisper venv + model cache)
#   bash uninstall.sh --user         (user install, removes ~/.local/bin/voxfree-*)
```

### What gets removed

| Component | Default remove | --purge only | Never removed |
|-----------|---------------|--------------|---------------|
| `/usr/local/bin/voxfree-*` | ✔ | | |
| `/usr/share/voxfree/` | ✔ | | |
| `/etc/dconf/db/local.d/00-voice-shortcuts` | ✔ + `dconf update` | | |
| `/etc/dconf/profile/user` (system-db:local line) | ✔ (line only, not whole file) | | |
| `/etc/speech-dispatcher/modules/mimic3-generic.conf` | ✔ (restore from .bak if exists) | | |
| `DefaultModule mimic3-generic` in speechd.conf | ✔ (restore original) | | |
| `/etc/udev/rules.d/99-uinput.rules` | ✔ + `udevadm trigger` | | |
| `HF_HOME` lines in `/etc/environment` | ✔ | | |
| `/opt/openai-whisper/` (whisper venv, 520MB) | | ✔ | |
| `/var/cache/huggingface/` (model cache, 145MB) | | ✔ | |
| `input` group membership for user | | | ✔ (other tools may use it) |
| apt packages (sox, ydotool, etc.) | | | ✔ (system-wide, other tools) |
| gsettings custom-keybindings list | ✔ (clears VoxFree entries) | | |

### DEBIAN/postrm (for .deb purge path)

```bash
case "$1" in
  purge)
    rm -f /usr/local/bin/voxfree-*
    rm -rf /usr/share/voxfree/
    sed -i '/HF_HOME\|HF_HUB_DISABLE_TELEMETRY/d' /etc/environment 2>/dev/null
    rm -f /etc/udev/rules.d/99-uinput.rules && udevadm trigger 2>/dev/null
    rm -f /etc/dconf/db/local.d/00-voice-shortcuts && dconf update 2>/dev/null
    echo "VoxFree removed. Whisper venv (/opt/openai-whisper/) and model cache"
    echo "(/var/cache/huggingface/) were retained. Remove manually if desired."
    ;;
esac
```

### User-mode uninstall

`bash uninstall.sh --user` removes:
- `~/.local/bin/voxfree-*`
- `~/.local/share/voxfree/`
- `HF_HOME` lines from `~/.profile`
- gsettings custom-keybindings (VoxFree entries only)

### voxfree-doctor check for uninstall residue

After uninstall, `voxfree-doctor` should show failures for all components, confirming removal. The `--fix` output for a missing component points to `voxfree` (the CLI installer) to re-install.

---

## 7b. docs/building-blocks.md

A single reference document explaining every technology VoxFree depends on, written for someone setting up a new machine. Covers:

| Technology | Covered topics |
|------------|---------------|
| **Mycroft Mimic 3** | What neural TTS is, how the ONNX model works, voice format, why offline |
| **whisper-ctranslate2** | What Whisper is, why ctranslate2 not PyTorch, int8 quantisation, base.en vs other models |
| **speech-dispatcher** | What it is, why it's the system TTS bus, the module config (local vs remote mode) |
| **arecord / ALSA / pipewire-alsa** | Why arecord not sox, the ALSA→PipeWire bridge, why it works from GNOME shortcuts |
| **sox noisered** | How the noise profile trick works (first 0.5s as reference) |
| **ydotool + uinput** | Why wtype is blocked by Mutter, how kernel uinput bypasses compositor restrictions |
| **xdotool** | XWayland fallback, why it works for X11-bridged apps |
| **wl-clipboard** | Wayland primary selection vs clipboard, why wl-paste not xclip |
| **dconf system-db** | How /etc/dconf/db/local.d/ provides defaults for all users |
| **gsd-media-keys** | The GNOME keyboard shortcut daemon, why it must start via .target |
| **PipeWire** | Session-per-user audio, the pulseaudio compat socket, why audio env vars matter |

Each section: what it is → why VoxFree uses it → how it fits in the pipeline → common failure modes.

---

## 7c. Unified `voxfree` CLI + Voice Selector

### Unified CLI: `voxfree <command>`

The existing `voxfree` wrapper at `/usr/local/bin/voxfree` becomes a full dispatcher:

```bash
voxfree --install          # runs install.sh (needs sudo)
voxfree --install --user   # user-mode install
voxfree --uninstall        # runs uninstall.sh
voxfree --doctor           # runs voxfree-doctor.sh (replaces standalone command)
voxfree --doctor --fix     # passes --fix to voxfree-doctor.sh
voxfree --voice            # interactive voice selector (NEW)
voxfree --version          # prints: VoxFree 0.1.0  (reads from /usr/share/voxfree/VERSION or ./VERSION)
voxfree --help             # usage summary
```

`voxfree-doctor` as a standalone command is **kept** for backward compatibility (it just calls `voxfree --doctor`), but the canonical form becomes `voxfree --doctor`.

### New command: `voxfree --voice`

Interactive TTS voice selector. Workflow:

```
$ voxfree --voice

  VoxFree — Voice Selector
  ────────────────────────
  Available English voices (★ = currently selected):

  UK English:
    1) en_UK/apope_low       ★ (installed)
    2) en_UK/...             (download required)

  US English:
    3) en_US/ljspeech_low    (installed)
    4) en_US/vctk_low        (download required)
    5) en_US/cmu-arctic_low  (download required)
    6) en_US/m-ailabs_low    (download required)

  Enter number to select, or q to quit: 3

  Downloading en_US/ljspeech_low...
  ✔ Voice set to: en_US/ljspeech_low
  Test it: voxfree-readloud (highlight any text first)
```

### Voice configuration file

Selected voice stored at:
- System install: `/etc/voxfree/voice` (single line: `en_UK/apope_low`)
- User install: `~/.config/voxfree/voice`

The `voxfree-readloud` script reads from user config first, then system config, then falls back to `en_UK/apope_low`:

```bash
# In voxfree-readloud.sh
VOICE=$(cat ~/.config/voxfree/voice 2>/dev/null || \
        cat /etc/voxfree/voice 2>/dev/null || \
        echo "en_UK/apope_low")
```

### Voice list population

`voxfree --voice` gets the list from `mimic3 --voices` and filters for `en_UK` and `en_US` entries, marking already-downloaded voices with ★.

### New files for voice feature

| File | Purpose |
|------|---------|
| `/usr/local/bin/voxfree` | Unified CLI dispatcher (extended) |
| `/etc/voxfree/voice` | System-wide selected voice config |
| `~/.config/voxfree/voice` | Per-user voice override |

---

## 8. New and Modified Files Summary

### New files
| File | Purpose |
|---|---|
| `lib/detect.sh` | Dependency detection/installation abstraction |
| `uninstall.sh` | Remove all VoxFree traces (system, --user, --purge) |
| `build-deb.sh` | Build `dist/voxfree_VERSION_amd64.deb` via fakeroot dpkg-deb |
| `packaging/DEBIAN/control` | Package metadata, Depends, Suggests |
| `packaging/DEBIAN/postinst` | Post-install: calls install.sh --postinst-mode |
| `packaging/DEBIAN/prerm` | Pre-removal: removes /usr/local/bin/voxfree-* |
| `packaging/DEBIAN/postrm` | Post-purge: removes /etc/dconf, /etc/udev, /etc/environment entries |
| `packaging/changelog` | Debian-format (required by dpkg) |
| `packaging/copyright` | Debian-format (required by dpkg) |
| `docs/building-blocks.md` | All technologies used, what each does, how they fit together |
| `docs/distribution-strategy.md` | Distribution decisions, rationale, trade-offs |
| `docs/architecture.md` | Component diagram, data flows, path layout |
| `docs/packaging.md` | How to build .deb, publish to GitHub Releases, future PPA |

### Renamed files
| Old name | New name |
|----------|----------|
| `ReadLoud/read-selection.sh` | `ReadLoud/voxfree-readloud.sh` |
| `ReadLoud/stop-reading.sh` | `ReadLoud/voxfree-readloud-stop.sh` |
| `SpeakToType/speech-start.sh` | `SpeakToType/voxfree-dictate.sh` |
| `SpeakToType/speech-stop.sh` | `SpeakToType/voxfree-dictate-stop.sh` |

### Modified files
| File | Key changes |
|---|---|
| `install.sh` | INSTALL_MODE, --user/--system/--postinst-mode flags, voxfree-doctor wrapper install, install voxfree CLI |
| `deps.sh` | Source lib/detect.sh, use detect_*/install_* functions, INSTALL_MODE path branching |
| `ReadLoud/readloud.sh` | Use $BIN_DIR, $DCONF_DIR; install voxfree-readloud and voxfree-readloud-stop |
| `SpeakToType/speak-to-type.sh` | Use $BIN_DIR, $DCONF_DIR; install voxfree-dictate and voxfree-dictate-stop |
| `voxfree-doctor.sh` | Fix command paths → /usr/share/voxfree/; check user-mode paths |

---

## 9. Implementation Order

1. **Rename** `read-selection.sh`, `stop-reading.sh`, `speech-start.sh`, `speech-stop.sh` → voxfree-* names; update all internal references
2. **Create `lib/detect.sh`** — purely additive, no existing code changes
3. **Refactor `deps.sh`** to use lib/detect.sh; verify system installs still work
4. **Update `install.sh`** — add INSTALL_MODE, --user flag, voxfree-doctor/voxfree wrapper install
5. **Update `readloud.sh`** and **`speak-to-type.sh`** — use $BIN_DIR, $DCONF_DIR variables
6. **Update `voxfree-doctor.sh`** — fix command paths to /usr/share/voxfree/
7. **Create `uninstall.sh`** — system, --user, and --purge modes
8. **Create `packaging/`** directory — control, postinst, prerm, postrm, changelog, copyright
9. **Create `build-deb.sh`** — assemble staging tree + fakeroot dpkg-deb
10. **Extend `voxfree` CLI** — add dispatch to --doctor, --voice, --uninstall, --version, --help
11. **Create `voxfree --voice`** — voice selector, `/etc/voxfree/voice` config, update voxfree-readloud to read it
12. **Create `docs/`** — building-blocks.md, distribution-strategy.md, architecture.md, packaging.md
13. **Copy plan to `docs/plan/packaging-plan.md`** — living implementation roadmap inside the repo

---

## 7. Verification

```bash
# Test system install still works
sudo bash install.sh --all

# Confirm new voxfree-prefixed commands are in PATH
which voxfree-readloud voxfree-readloud-stop voxfree-dictate voxfree-dictate-stop voxfree-doctor

# Test --user install (no sudo)
bash install.sh --user --all
ls ~/.local/bin/voxfree-*   # should list all commands

# Test voxfree-doctor as command
voxfree-doctor             # should work after system install
voxfree-doctor --fix       # should show paths like /usr/share/voxfree/

# Build and verify .deb
bash build-deb.sh 0.1.0
dpkg-deb --info dist/voxfree_0.1.0_amd64.deb
sudo dpkg -i dist/voxfree_0.1.0_amd64.deb

# Run doctor after .deb install
voxfree-doctor              # should pass all relevant checks
```

---

## Key Design Decisions

- **`/usr/share/voxfree/` not `/opt/voxfree/`** — shell scripts are architecture-independent data; `/opt/` is already used by the whisper venv
- **Wrapper not copy for voxfree-doctor** — updates to the `.sh` are picked up automatically without re-installing the wrapper
- **`Suggests` not `Depends` for mimic3** — mimic3 is not in Ubuntu repos; `Depends` would make dpkg fail with an unresolvable dependency
- **detect-then-install** — idempotent runs, honours existing installations of mimic3/whisper from other sources
- **User mode skips/warns, never aborts** — missing sudo items show a clear one-liner fix but don't prevent the rest of the install from completing
