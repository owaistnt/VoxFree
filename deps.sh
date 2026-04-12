#!/bin/bash
# =============================================================================
# VoxFree — deps.sh
# Install ALL dependencies for ReadLoud (TTS) and SpeakToType (STT)
# =============================================================================
# Called automatically by install.sh, readloud.sh, and speak-to-type.sh.
# Safe to run multiple times — skips already-installed components.
#
# Usage:
#   sudo bash deps.sh              (system install, everything)
#   sudo bash deps.sh --tts        (TTS dependencies only)
#   sudo bash deps.sh --stt        (STT dependencies only)
#   bash deps.sh --user            (user install, no sudo needed for most steps)
#   bash deps.sh --user --tts
#   bash deps.sh --user --stt
# =============================================================================

if [ -z "$BASH_VERSION" ]; then exec bash "$0" "$@"; fi
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { printf "${GREEN}  ✔ %s${RESET}\n" "$*"; }
info()    { printf "${CYAN}  → %s${RESET}\n" "$*"; }
warn()    { printf "${YELLOW}  ⚠ %s${RESET}\n" "$*"; }
fail()    { printf "${RED}  ✘ %s${RESET}\n" "$*"; exit 1; }
section() { printf "\n${BOLD}${CYAN}=== %s ===${RESET}\n" "$*"; }

# ── Install mode detection ────────────────────────────────────────────────────
INSTALL_MODE="${INSTALL_MODE:-system}"
INSTALL_TTS=true
INSTALL_STT=true

for arg in "$@"; do
    case "$arg" in
        --user)   INSTALL_MODE="user" ;;
        --system) INSTALL_MODE="system" ;;
        --tts)    INSTALL_STT=false ;;
        --stt)    INSTALL_TTS=false ;;
        --sst)    INSTALL_TTS=false ;;   # typo-safe
    esac
done

if [ "$INSTALL_MODE" = "system" ] && [ "$(id -u)" -ne 0 ]; then
    fail "System install requires root. Use: sudo bash $0\nOr install for current user: bash $0 --user"
fi

ACTUAL_USER="${ACTUAL_USER:-${SUDO_USER:-$(who am i 2>/dev/null | awk '{print $1}')}}"
ACTUAL_USER="${ACTUAL_USER:-$USER}"
ACTUAL_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)

info "Install mode: $INSTALL_MODE | User: $ACTUAL_USER"

# Source detection library
# shellcheck source=lib/detect.sh
source "$SCRIPT_DIR/lib/detect.sh"

# ── Step 1: APT packages ──────────────────────────────────────────────────────
section "Step 1: APT packages"

COMMON_PKGS="wl-clipboard alsa-utils libnotify-bin wev"
TTS_PKGS="speech-dispatcher"
STT_PKGS="sox libsox-fmt-all xdotool ydotool python3-venv ffmpeg"

if [ "$INSTALL_MODE" = "system" ]; then
    PKGS="$COMMON_PKGS"
    [ "$INSTALL_TTS" = true ] && PKGS="$PKGS $TTS_PKGS"
    [ "$INSTALL_STT" = true ] && PKGS="$PKGS $STT_PKGS"
    apt-get update -qq
    # shellcheck disable=SC2086
    apt-get install -y $PKGS
    ok "APT packages installed"
else
    # User mode: check for missing packages, warn but don't abort
    MISSING=""
    ALL_PKGS="$COMMON_PKGS"
    [ "$INSTALL_TTS" = true ] && ALL_PKGS="$ALL_PKGS $TTS_PKGS"
    [ "$INSTALL_STT" = true ] && ALL_PKGS="$ALL_PKGS $STT_PKGS"
    for pkg in $ALL_PKGS; do
        dpkg -l "$pkg" >/dev/null 2>&1 || MISSING="$MISSING $pkg"
    done
    if [ -z "$MISSING" ]; then
        ok "All required APT packages already installed"
    else
        warn "Missing packages (need sudo to install):$MISSING"
        warn "Run:  sudo apt install$MISSING"
    fi
fi

# ── Step 2: Mycroft Mimic 3 (TTS engine) ─────────────────────────────────────
if [ "$INSTALL_TTS" = true ]; then
    section "Step 2: Mycroft Mimic 3 (TTS engine)"
    if detect_mimic3; then
        ok "mimic3 already installed ($(mimic3 --version 2>/dev/null)) via $MIMIC3_METHOD"
    elif [ "$INSTALL_MODE" = "system" ]; then
        install_mimic3 || warn "mimic3 install failed — TTS will not work until installed"
    else
        warn "mimic3 not installed. Install with: sudo bash $SCRIPT_DIR/deps.sh --tts"
    fi

    # Voice model
    VOICE_DIR="/usr/share/mycroft/mimic3/voices/en_UK/apope_low"
    USER_VOICE_DIR="$ACTUAL_HOME/.local/share/mycroft/mimic3/voices/en_UK/apope_low"
    if [ -d "$VOICE_DIR" ] || [ -d "$USER_VOICE_DIR" ]; then
        ok "Voice en_UK/apope_low available"
    elif command -v mimic3-download >/dev/null 2>&1; then
        info "Downloading voice en_UK/apope_low ..."
        sudo -u "$ACTUAL_USER" mimic3-download en_UK/apope_low 2>/dev/null && \
            ok "Voice downloaded" || warn "Voice will download on first use"
    fi
fi

# ── Step 3: whisper-ctranslate2 (STT engine) ─────────────────────────────────
if [ "$INSTALL_STT" = true ]; then
    section "Step 3: whisper-ctranslate2 (STT engine)"

    # IMPORTANT: Do NOT use 'python3-whisper' from apt —
    # that is the Graphite time-series database tool, NOT OpenAI Whisper.

    if detect_whisper; then
        ok "whisper already installed at $WHISPER_BIN"
        # Ensure symlink is in the right bin directory
        if [ "$INSTALL_MODE" = "system" ]; then
            ln -sf "$WHISPER_BIN" /usr/local/bin/whisper
        else
            mkdir -p "$ACTUAL_HOME/.local/bin"
            ln -sf "$WHISPER_BIN" "$ACTUAL_HOME/.local/bin/whisper"
        fi
    else
        install_whisper
    fi

    # ── Step 4: Whisper base.en model ─────────────────────────────────────────
    section "Step 4: Whisper base.en model (~145MB, English-only)"

    if detect_whisper_model; then
        ok "Whisper base.en model found at $HF_CACHE_DIR/"
    else
        install_whisper_model || true   # warn already printed inside function
    fi
    chmod -R a+rX "${HF_CACHE_DIR:-/var/cache/huggingface}" 2>/dev/null || true

    # ── Step 5: ydotool / uinput (Wayland auto-paste) ─────────────────────────
    section "Step 5: ydotool auto-paste (Wayland)"

    if [ "$INSTALL_MODE" = "system" ]; then
        if groups "$ACTUAL_USER" | grep -q '\binput\b'; then
            ok "$ACTUAL_USER already in input group"
        else
            usermod -aG input "$ACTUAL_USER"
            ok "Added $ACTUAL_USER to input group (relogin required)"
        fi

        UDEV_RULE='/etc/udev/rules.d/99-uinput.rules'
        if [ -f "$UDEV_RULE" ]; then
            ok "udev rule already exists"
        else
            echo 'KERNEL=="uinput", GROUP="input", MODE="0660"' > "$UDEV_RULE"
            udevadm trigger
            ok "udev rule created: /dev/uinput accessible to input group"
        fi
    else
        # User mode: check if already set up by a previous system install
        if [ -f '/etc/udev/rules.d/99-uinput.rules' ] && groups "$ACTUAL_USER" | grep -q '\binput\b'; then
            ok "ydotool uinput access already configured"
        else
            warn "ydotool auto-paste needs one-time admin setup:"
            warn "  sudo usermod -aG input $ACTUAL_USER"
            warn "  echo 'KERNEL==\"uinput\", GROUP=\"input\", MODE=\"0660\"' | sudo tee /etc/udev/rules.d/99-uinput.rules"
            warn "  sudo udevadm trigger && log out and back in"
            warn "Until then, paste will use Ctrl+V (text is always in clipboard)."
        fi
    fi
fi

# ── Step 6: Environment variables ─────────────────────────────────────────────
section "Step 6: Environment variables"

if [ "$INSTALL_MODE" = "system" ]; then
    if grep -q "HF_HOME" /etc/environment 2>/dev/null; then
        ok "HF_HOME already in /etc/environment"
    else
        printf '\nHF_HOME=/var/cache/huggingface\nHF_HUB_DISABLE_TELEMETRY=1\n' >> /etc/environment
        ok "Added HF_HOME to /etc/environment (global)"
    fi
else
    PROFILE="$ACTUAL_HOME/.profile"
    if grep -q "HF_HOME" "$PROFILE" 2>/dev/null; then
        ok "HF_HOME already in ~/.profile"
    else
        HF_VAL="${HF_CACHE_DIR:-$ACTUAL_HOME/.cache/huggingface}"
        printf '\n# VoxFree — Whisper model cache\nexport HF_HOME="%s"\nexport HF_HUB_DISABLE_TELEMETRY=1\n' \
            "$HF_VAL" >> "$PROFILE"
        ok "Added HF_HOME to ~/.profile"
    fi
fi

# NOTE: HF_HUB_OFFLINE=1 is intentionally NOT added here.
# It would block future model downloads. Scripts set it internally instead.

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n${BOLD}${GREEN}=== Dependencies ready ===${RESET}\n\n"

[ "$INSTALL_TTS" = true ] && {
    printf "${BOLD}TTS:${RESET}\n"
    command -v mimic3 >/dev/null && printf "  mimic3 %s\n" "$(mimic3 --version 2>/dev/null)" || printf "  mimic3: NOT INSTALLED\n"
    printf "  speech-dispatcher: %s\n\n" "$(dpkg -s speech-dispatcher 2>/dev/null | grep Version | awk '{print $2}')"
}

[ "$INSTALL_STT" = true ] && {
    printf "${BOLD}STT:${RESET}\n"
    [ -n "${WHISPER_BIN:-}" ] && printf "  whisper: %s\n" "$WHISPER_BIN" || printf "  whisper: NOT INSTALLED\n"
    [ -n "${HF_CACHE_DIR:-}" ] && printf "  model: %s/hub/\n" "$HF_CACHE_DIR" || printf "  model: NOT DOWNLOADED\n"
    printf "  sox: %s\n" "$(sox --version 2>&1 | head -1)"
    printf "\n  ${YELLOW}⚠ Log out and back in to activate ydotool auto-paste${RESET}\n\n"
}
