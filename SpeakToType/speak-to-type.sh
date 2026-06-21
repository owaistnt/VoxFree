#!/bin/bash
# =============================================================================
# speak-to-type.sh — Speech-to-Text setup for Ubuntu 24.04 GNOME/Wayland
# =============================================================================
# Installs:
#   - whisper-ctranslate2   (offline STT, base.en model, ~145MB)
#   - arecord               (ALSA recording — works reliably from GNOME)
#   - ydotool               (Wayland-native text injection via /dev/uinput)
#   - voxfree-dictate       ($BIN_DIR/voxfree-dictate)       ← F10: start
#   - voxfree-dictate-stop  ($BIN_DIR/voxfree-dictate-stop)  ← stop+transcribe
#   - voxfree-stop-all      ($BIN_DIR/voxfree-stop-all)      ← F11: stop all
#   - GNOME keyboard shortcuts
#
# Keyboard shortcuts (ThinkPad F10/F11 or Super+Shift+M / Super+Shift+K):
#   F10 → start recording     F11 → stop + transcribe + paste
#
# Usage:
#   sudo bash SpeakToType/speak-to-type.sh              (interactive)
#   sudo bash SpeakToType/speak-to-type.sh --thinkpad   (F10/F11)
#   sudo bash SpeakToType/speak-to-type.sh --standard   (Super+Shift+M/K)
# =============================================================================

if [ -z "$BASH_VERSION" ]; then exec bash "$0" "$@"; fi
set -e

STT_DIR="$(cd "$(dirname "$0")" && pwd)"
VOXFREE_DIR="$(cd "$STT_DIR/.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { printf "${GREEN}  ✔ %s${RESET}\n" "$*"; }
info()    { printf "${CYAN}  → %s${RESET}\n" "$*"; }
warn()    { printf "${YELLOW}  ⚠ %s${RESET}\n" "$*"; }
fail()    { printf "${RED}  ✘ %s${RESET}\n" "$*"; exit 1; }
section() { printf "\n${BOLD}${CYAN}=== %s ===${RESET}\n" "$*"; }

# Inherit from install.sh or set defaults
INSTALL_MODE="${INSTALL_MODE:-system}"
ACTUAL_USER="${ACTUAL_USER:-${SUDO_USER:-$(who am i 2>/dev/null | awk '{print $1}')}}"
ACTUAL_USER="${ACTUAL_USER:-$USER}"
BIN_DIR="${BIN_DIR:-/usr/local/bin}"

if [ "$INSTALL_MODE" = "system" ] && [ "$(id -u)" -ne 0 ]; then
    fail "System install requires root: sudo bash $0"
fi

# ── Keyboard layout ───────────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --thinkpad) LAYOUT="thinkpad" ;;
        --standard) LAYOUT="standard" ;;
        --skip)     LAYOUT="skip" ;;
    esac
done

if [ -z "${LAYOUT:-}" ]; then
    printf "\n${BOLD}Choose keyboard shortcut:${RESET}\n"
    printf "  1) ThinkPad  F10 (▶) = Start recording   F11 (✕) = Stop + transcribe\n"
    printf "  2) Standard  Super+Shift+M = Start   Super+Shift+K = Stop\n"
    printf "  3) Skip — configure manually later\n\n"
    while true; do
        read -r -p "  Choice [1/2/3]: " C
        case "$C" in 1) LAYOUT="thinkpad"; break ;; 2) LAYOUT="standard"; break ;; 3) LAYOUT="skip"; break ;; esac
    done
fi

case "$LAYOUT" in
    thinkpad) KEY_DICTATE="XF86Go"; KEY_STOP="Cancel"
              ok "ThinkPad: F10 (XF86Go) = start recording   F11 (Cancel) = stop + transcribe" ;;
    standard) KEY_DICTATE="<Super><Shift>m"; KEY_STOP="<Super><Shift>k"
              ok "Standard: Super+Shift+M = start   Super+Shift+K = stop + transcribe" ;;
    skip)     warn "Skipping shortcut setup." ;;
esac

# ── Step 1: APT packages (skipped if deps.sh already ran) ────────────────────
if [ "${VOXFREE_DEPS_DONE:-}" != "1" ]; then
    DEPS_SCRIPT="$VOXFREE_DIR/deps.sh"
    if [ -f "$DEPS_SCRIPT" ]; then
        section "Step 1: Installing dependencies"
        bash "$DEPS_SCRIPT" "--$INSTALL_MODE" --stt
        export VOXFREE_DEPS_DONE=1
    else
        section "Step 1: Installing apt packages (standalone)"
        apt-get update -qq
        apt-get install -y \
            alsa-utils sox libsox-fmt-all \
            wl-clipboard xdotool ydotool \
            python3-venv ffmpeg libnotify-bin wev
        ok "APT packages installed"

        section "Step 2: ydotool / uinput setup"
        usermod -aG input "$ACTUAL_USER"
        echo 'KERNEL=="uinput", GROUP="input", MODE="0660"' > /etc/udev/rules.d/99-uinput.rules
        udevadm trigger
        ok "Added $ACTUAL_USER to input group (relogin needed)"
        ok "uinput udev rule set"

        section "Step 3: Installing whisper-ctranslate2"
        if [ ! -f /opt/openai-whisper/bin/whisper-ctranslate2 ]; then
            info "Creating Python venv at /opt/openai-whisper..."
            python3 -m venv /opt/openai-whisper
            /opt/openai-whisper/bin/pip install --upgrade pip --quiet
            info "Installing whisper-ctranslate2 (~300MB)..."
            /opt/openai-whisper/bin/pip install whisper-ctranslate2 --quiet
            ok "whisper-ctranslate2 installed"
        else
            ok "whisper-ctranslate2 already installed"
        fi
        ln -sf /opt/openai-whisper/bin/whisper-ctranslate2 /usr/local/bin/whisper
        ok "Symlinked as /usr/local/bin/whisper"

        section "Step 4: Downloading Whisper base.en model (~145MB)"
        mkdir -p /var/cache/huggingface/hub
        chmod 755 /var/cache/huggingface
        MODEL_DIR="/var/cache/huggingface/hub/models--Systran--faster-whisper-base.en"
        if [ ! -d "$MODEL_DIR" ]; then
            info "Downloading base.en model from HuggingFace..."
            HF_HOME=/var/cache/huggingface \
                /usr/local/bin/whisper /dev/null \
                --model base.en --language en --compute_type int8 \
                --output_format txt --output_dir /tmp --verbose False 2>&1 | \
                grep -v "InvalidDataError\|Traceback\|File \"/opt" || true
            [ -d "$MODEL_DIR" ] && ok "Model downloaded" || warn "Download failed — will retry on first use"
        else
            ok "base.en model already present"
        fi
        chmod -R a+rX /var/cache/huggingface
    fi
fi

# ── Step 5: Install scripts from source ──────────────────────────────────────
section "Step 5: Installing STT scripts"
mkdir -p "$BIN_DIR"

install_script() {
    local SRC="$1" DEST="$BIN_DIR/$2"
    if [ -f "$SRC" ]; then
        cp "$SRC" "$DEST"
        chmod 755 "$DEST"
        [ "$INSTALL_MODE" != "system" ] && chown "$ACTUAL_USER:$ACTUAL_USER" "$DEST" 2>/dev/null || true
        ok "$DEST"
    else
        warn "Source not found: $SRC — skipping"
    fi
}

install_script "$STT_DIR/voxfree-dictate.sh"      "voxfree-dictate"
install_script "$STT_DIR/voxfree-dictate-stop.sh"  "voxfree-dictate-stop"

# Install voxfree-stop-all (F11 handler) from ReadLoud/ if not already present
STOP_ALL_SRC="$VOXFREE_DIR/ReadLoud/voxfree-stop-all.sh"
install_script "$STOP_ALL_SRC" "voxfree-stop-all"

# ── Step 6: GNOME keyboard shortcuts ─────────────────────────────────────────
[ "${LAYOUT:-skip}" = "skip" ] && { warn "Skipping shortcuts."; } || {

section "Step 6: Keyboard shortcuts"

USER_ID=$(id -u "$ACTUAL_USER" 2>/dev/null || id -u)
gs() { sudo -u "$ACTUAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_ID}/bus" \
    gsettings "$@" 2>/dev/null || true; }
GBASE="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"
KPATH="['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-readloud/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-dictate/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-stop-all/']"

# Preserve existing TTS binding if readloud.sh has already run
EXISTING_READ=$(grep -A3 "voxfree-readloud\]" /etc/dconf/db/local.d/00-voice-shortcuts 2>/dev/null | \
    grep "^binding" | grep -o "'[^']*'" | tr -d "'" | head -1)
[ -z "$EXISTING_READ" ] && EXISTING_READ="XF86Messenger"

if [ "$INSTALL_MODE" = "system" ]; then
    mkdir -p /etc/dconf/db/local.d /etc/dconf/profile
    grep -q "system-db:local" /etc/dconf/profile/user 2>/dev/null || \
        printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user

    cat > /etc/dconf/db/local.d/00-voice-shortcuts << DCONFEOF
# VoxFree shortcuts — layout: ${LAYOUT} — all users
[org/gnome/settings-daemon/plugins/media-keys]
custom-keybindings=['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-readloud/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-dictate/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-stop-all/']

[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-readloud]
name='Read Aloud (VoxFree TTS)'
command='${BIN_DIR}/voxfree-readloud'
binding='${EXISTING_READ}'

[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-dictate]
name='Start Dictation (VoxFree STT)'
command='${BIN_DIR}/voxfree-dictate'
binding='${KEY_DICTATE}'

[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-stop-all]
name='Stop All Voice (VoxFree)'
command='${BIN_DIR}/voxfree-stop-all'
binding='${KEY_STOP}'
DCONFEOF
    dconf update; ok "dconf system shortcuts updated"
fi

# Apply to current user session
gs set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$KPATH"
gs set "${GBASE}/voxfree-dictate/"  name    'Start Dictation (VoxFree STT)'
gs set "${GBASE}/voxfree-dictate/"  command "$BIN_DIR/voxfree-dictate"
gs set "${GBASE}/voxfree-dictate/"  binding "$KEY_DICTATE"
gs set "${GBASE}/voxfree-stop-all/" name    'Stop All Voice (VoxFree)'
gs set "${GBASE}/voxfree-stop-all/" command "$BIN_DIR/voxfree-stop-all"
gs set "${GBASE}/voxfree-stop-all/" binding "$KEY_STOP"
ok "Shortcuts applied to current session"

sudo -u "$ACTUAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_ID}/bus" \
    systemctl --user start org.gnome.SettingsDaemon.MediaKeys.target 2>/dev/null && \
    ok "gsd-media-keys started" || warn "Shortcuts will activate on next login"

# Persist the chosen layout so voxfree --switch knows the current state
CONF_DIR="$CONF_DIR" bash "$VOXFREE_DIR/lib/keyboard-layout.sh" write_keyboard_layout "$LAYOUT" 2>/dev/null || true
}

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n${BOLD}${GREEN}=== SpeakToType STT Ready ===${RESET}\n\n"
if [ "${LAYOUT:-skip}" = "thinkpad" ]; then
    printf "  ${CYAN}F10 (▶)${RESET}  → Press to START recording  (mic LED turns OFF)\n"
    printf "           → Speak clearly for 2+ seconds\n"
    printf "  ${CYAN}F11 (✕)${RESET}  → Press to STOP → transcribes → pastes at cursor\n"
elif [ "${LAYOUT:-skip}" = "standard" ]; then
    printf "  ${CYAN}Super+Shift+M${RESET}  → Press to START recording\n"
    printf "                 → Speak clearly for 2+ seconds\n"
    printf "  ${CYAN}Super+Shift+K${RESET}  → Press to STOP → transcribes → pastes at cursor\n"
fi
printf "\n  ${YELLOW}IMPORTANT:${RESET} Log out and back in to activate ydotool auto-paste.\n"
printf "  Until then, text is in clipboard — press Ctrl+V (apps) or Ctrl+Shift+V (terminal).\n"
printf "\n  Model: base.en + int8 → ~2s transcription\n"
printf "  Cache: /var/cache/huggingface/ (shared, all users)\n\n"
