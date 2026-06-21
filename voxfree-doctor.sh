#!/bin/bash
# =============================================================================
# VoxFree Doctor — voxfree-doctor.sh
# Checks all dependencies and configuration, like flutter doctor
# =============================================================================
# Usage:
#   bash voxfree-doctor.sh           (full check)
#   bash voxfree-doctor.sh --tts     (ReadLoud checks only)
#   bash voxfree-doctor.sh --stt     (SpeakToType checks only)
#   bash voxfree-doctor.sh --fix     (show fix commands for failures)
# =============================================================================

if [ -z "$BASH_VERSION" ]; then exec bash "$0" "$@"; fi

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

PASS=0; FAIL=0; WARN=0
CHECK_TTS=true; CHECK_STT=true; SHOW_FIX=false
CURRENT_SECTION=""

# Arrays to collect results for summary
PASSED_ITEMS=()
FAILED_ITEMS=()
WARNED_ITEMS=()

for arg in "$@"; do
    case "$arg" in
        --tts) CHECK_STT=false ;;
        --stt) CHECK_TTS=false ;;
        --fix) SHOW_FIX=true ;;
    esac
done

# ── Output helpers ────────────────────────────────────────────────────────────
ok()   {
    printf "  ${GREEN}[✔]${RESET} %s\n" "$*"
    PASS=$((PASS+1))
    PASSED_ITEMS+=("[$CURRENT_SECTION] $*")
}
fail() {
    printf "  ${RED}[✘]${RESET} %s\n" "$*"
    FAIL=$((FAIL+1))
    FAILED_ITEMS+=("[$CURRENT_SECTION] $*")
}
warn() {
    printf "  ${YELLOW}[!]${RESET} %s\n" "$*"
    WARN=$((WARN+1))
    WARNED_ITEMS+=("[$CURRENT_SECTION] $*")
}
info() { printf "      ${DIM}%s${RESET}\n" "$*"; }
fix()  { [ "$SHOW_FIX" = true ] && printf "      ${CYAN}Fix:${RESET} %s\n" "$*"; }
section() {
    CURRENT_SECTION="$1"
    printf "\n${BOLD}%s${RESET}\n" "$1"
    printf '%0.s─' $(seq 1 ${#1})
    printf "\n"
}

# ── Header ────────────────────────────────────────────────────────────────────
printf "\n${BOLD}${CYAN}"
printf "  VoxFree Doctor\n"
printf "${RESET}"
printf "  Checking your VoxFree installation...\n"
[ "$SHOW_FIX" = false ] && printf "  ${DIM}Tip: run with --fix to see remediation commands${RESET}\n"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1: System
# ─────────────────────────────────────────────────────────────────────────────
section "System"

# OS version
OS_ID=$(grep "^ID=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
OS_VER=$(grep "^VERSION_ID=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
if [ "$OS_ID" = "ubuntu" ] && [ "$OS_VER" = "24.04" ]; then
    ok "Ubuntu 24.04 (Noble)"
elif [ "$OS_ID" = "ubuntu" ]; then
    warn "Ubuntu $OS_VER — tested on 24.04, may work on other versions"
else
    warn "OS: $OS_ID $OS_VER — VoxFree is designed for Ubuntu 24.04"
fi

# Display server
SESSION="${XDG_SESSION_TYPE:-unknown}"
if [ "$SESSION" = "wayland" ]; then
    ok "Wayland session ($XDG_CURRENT_DESKTOP)"
else
    fail "Not running on Wayland (detected: $SESSION)"
    info "VoxFree requires GNOME on Wayland"
    fix "Log in with 'Ubuntu (Wayland)' session at the login screen"
fi

# PipeWire
if systemctl --user is-active pipewire >/dev/null 2>&1; then
    ok "PipeWire audio server running"
else
    fail "PipeWire not running"
    fix "systemctl --user start pipewire"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2: ReadLoud (TTS)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$CHECK_TTS" = true ]; then
section "ReadLoud — Text-to-Speech"

# mimic3
if command -v mimic3 >/dev/null 2>&1; then
    ok "mimic3 $(mimic3 --version 2>/dev/null) — $(which mimic3)"
else
    fail "mimic3 not installed"
    fix "wget https://github.com/MycroftAI/mimic3/releases/download/v0.2.4/mycroft-mimic3-tts_0.2.4_amd64.deb && sudo dpkg -i mycroft-mimic3-tts_0.2.4_amd64.deb"
fi

# Voice model
VOICE_PATH="/usr/share/mycroft/mimic3/voices/en_UK/apope_low"
USER_VOICE_PATH="$HOME/.local/share/mycroft/mimic3/voices/en_UK/apope_low"
if [ -d "$VOICE_PATH" ]; then
    ok "Voice en_UK/apope_low at $VOICE_PATH"
elif [ -d "$USER_VOICE_PATH" ]; then
    ok "Voice en_UK/apope_low at $USER_VOICE_PATH"
    warn "Voice is user-specific — for all users install to /usr/share"
else
    fail "Voice en_UK/apope_low not found"
    fix "mimic3-download en_UK/apope_low"
fi

# speech-dispatcher
if command -v spd-say >/dev/null 2>&1; then
    ok "speech-dispatcher installed"
else
    fail "speech-dispatcher not installed"
    fix "sudo apt install speech-dispatcher"
fi

# speech-dispatcher module (local mode check)
MODCONF="/etc/speech-dispatcher/modules/mimic3-generic.conf"
if [ -f "$MODCONF" ]; then
    if grep -q "\-\-remote" "$MODCONF"; then
        fail "mimic3-generic.conf still uses --remote (requires mimic3-server)"
        info "The config must use local mode (without --remote flag)"
        fix "sudo bash /usr/share/voxfree/deps.sh --tts"
    else
        ok "speech-dispatcher module: local mode ✔"
    fi
else
    fail "mimic3-generic.conf not found"
    fix "sudo bash /usr/share/voxfree/deps.sh --tts"
fi

# speech-dispatcher default module
if grep -q "^DefaultModule mimic3-generic" /etc/speech-dispatcher/speechd.conf 2>/dev/null; then
    ok "speech-dispatcher DefaultModule = mimic3-generic"
else
    fail "speech-dispatcher DefaultModule is not mimic3-generic"
    fix "sudo sed -i 's/^DefaultModule.*/DefaultModule mimic3-generic/' /etc/speech-dispatcher/speechd.conf"
fi

# aplay (audio output)
if command -v aplay >/dev/null 2>&1; then
    ok "aplay available (audio output)"
else
    fail "aplay not found"
    fix "sudo apt install alsa-utils"
fi

# wl-paste (clipboard reading)
if command -v wl-paste >/dev/null 2>&1; then
    ok "wl-paste available (Wayland clipboard)"
else
    fail "wl-paste not found"
    fix "sudo apt install wl-clipboard"
fi

# read-selection script
if [ -x /usr/local/bin/voxfree-readloud ]; then
    ok "/usr/local/bin/voxfree-readloud installed"
else
    fail "/usr/local/bin/voxfree-readloud not installed"
    fix "sudo bash /usr/share/voxfree/ReadLoud/readloud.sh"
fi

# stop-reading script
if [ -x /usr/local/bin/voxfree-readloud-stop ]; then
    ok "/usr/local/bin/voxfree-readloud-stop installed"
else
    fail "/usr/local/bin/voxfree-readloud-stop not installed"
    fix "sudo bash /usr/share/voxfree/ReadLoud/readloud.sh"
fi

# Quick TTS audio test
if command -v mimic3 >/dev/null 2>&1 && command -v aplay >/dev/null 2>&1; then
    if echo "test" | mimic3 --voice en_UK/apope_low --stdout 2>/dev/null | aplay -q 2>/dev/null; then
        ok "TTS audio pipeline works (mimic3 → aplay)"
    else
        fail "TTS audio pipeline failed"
        fix "Check audio output: wpctl get-volume @DEFAULT_AUDIO_SINK@"
    fi
fi

fi # end TTS checks

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3: SpeakToType (STT)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$CHECK_STT" = true ]; then
section "SpeakToType — Speech-to-Text"

# arecord (microphone recording)
if command -v arecord >/dev/null 2>&1; then
    ok "arecord available (microphone recording)"
else
    fail "arecord not found"
    fix "sudo apt install alsa-utils"
fi

# sox (noise reduction)
if command -v sox >/dev/null 2>&1; then
    ok "sox $(sox --version 2>&1 | grep -o 'SoX v[0-9.]*') (noise reduction)"
else
    fail "sox not found"
    fix "sudo apt install sox libsox-fmt-all"
fi

# whisper binary
if command -v whisper >/dev/null 2>&1; then
    WHISPER_TARGET=$(readlink -f "$(which whisper)" 2>/dev/null)
    if echo "$WHISPER_TARGET" | grep -q "whisper-ctranslate2"; then
        ok "whisper → whisper-ctranslate2 at $WHISPER_TARGET"
    else
        warn "whisper found but not pointing to whisper-ctranslate2"
        info "Target: $WHISPER_TARGET"
        fix "sudo ln -sf /opt/openai-whisper/bin/whisper-ctranslate2 /usr/local/bin/whisper"
    fi
else
    fail "whisper not found in PATH"
    fix "sudo bash /usr/share/voxfree/deps.sh --stt"
fi

# whisper-ctranslate2 venv
if [ -f /opt/openai-whisper/bin/whisper-ctranslate2 ]; then
    VERSION=$(/opt/openai-whisper/bin/pip show whisper-ctranslate2 2>/dev/null | grep "^Version" | awk '{print $2}')
    ok "whisper-ctranslate2 $VERSION in /opt/openai-whisper/"
else
    fail "whisper-ctranslate2 venv not found at /opt/openai-whisper/"
    fix "sudo python3 -m venv /opt/openai-whisper && sudo /opt/openai-whisper/bin/pip install whisper-ctranslate2"
fi

# Whisper base.en model
MODEL_DIR="/var/cache/huggingface/hub/models--Systran--faster-whisper-base.en"
if [ -d "$MODEL_DIR" ]; then
    MODEL_SIZE=$(du -sh "$MODEL_DIR" 2>/dev/null | awk '{print $1}')
    ok "Whisper base.en model in /var/cache/huggingface/ ($MODEL_SIZE)"
    # Check permissions (all users should be able to read)
    if [ -r "$MODEL_DIR" ]; then
        ok "Model readable by all users"
    else
        warn "Model may not be readable by all users"
        fix "sudo chmod -R a+rX /var/cache/huggingface"
    fi
else
    fail "Whisper base.en model not in shared cache"
    # Check user cache
    if [ -d "$HOME/.cache/huggingface/hub/models--Systran--faster-whisper-base.en" ]; then
        warn "Model found in user cache ($HOME/.cache) — not shared with other users"
        fix "sudo mkdir -p /var/cache/huggingface/hub && sudo cp -r $HOME/.cache/huggingface/hub/models--Systran--faster-whisper-base.en /var/cache/huggingface/hub/ && sudo chmod -R a+rX /var/cache/huggingface"
    else
        fix "sudo bash /usr/share/voxfree/deps.sh --stt"
    fi
fi

# HF_HOME environment
HF_HOME_VAL="${HF_HOME:-}"
if grep -q "HF_HOME=/var/cache/huggingface" /etc/environment 2>/dev/null; then
    ok "HF_HOME=/var/cache/huggingface in /etc/environment (global)"
elif [ "$HF_HOME_VAL" = "/var/cache/huggingface" ]; then
    warn "HF_HOME set in current session but not in /etc/environment"
    fix "echo 'HF_HOME=/var/cache/huggingface' | sudo tee -a /etc/environment"
else
    fail "HF_HOME not configured globally"
    fix "echo 'HF_HOME=/var/cache/huggingface' | sudo tee -a /etc/environment"
fi

# HF_HUB_OFFLINE should NOT be in /etc/environment (blocks model downloads)
if grep -q "HF_HUB_OFFLINE" /etc/environment 2>/dev/null; then
    fail "HF_HUB_OFFLINE is set in /etc/environment — blocks model downloads"
    info "This env var should only be set inside scripts, not globally"
    fix "sudo sed -i '/HF_HUB_OFFLINE/d' /etc/environment"
fi

# ydotool
if command -v ydotool >/dev/null 2>&1; then
    ok "ydotool installed"
    # input group membership
    if groups 2>/dev/null | grep -q '\binput\b'; then
        ok "Current user is in 'input' group (ydotool auto-paste active)"
    else
        warn "Current user not in 'input' group — ydotool paste requires Ctrl+V manually"
        info "Run: sudo usermod -aG input $USER  then log out and back in"
        fix "sudo usermod -aG input $USER && echo 'Then log out and back in'"
    fi
    # uinput device
    if [ -e /dev/uinput ]; then
        UINPUT_PERMS=$(stat -c "%a" /dev/uinput 2>/dev/null)
        if [ "$UINPUT_PERMS" = "660" ] || [ "$UINPUT_PERMS" = "666" ]; then
            ok "/dev/uinput accessible (mode $UINPUT_PERMS)"
        else
            warn "/dev/uinput mode is $UINPUT_PERMS — ydotool may not work"
            fix "echo 'KERNEL==\"uinput\", GROUP=\"input\", MODE=\"0660\"' | sudo tee /etc/udev/rules.d/99-uinput.rules && sudo udevadm trigger"
        fi
    else
        fail "/dev/uinput not found"
        fix "sudo modprobe uinput"
    fi
else
    fail "ydotool not installed"
    fix "sudo apt install ydotool"
fi

# xdotool (Ctrl+V fallback)
if command -v xdotool >/dev/null 2>&1; then
    ok "xdotool installed (Ctrl+V fallback for XWayland apps)"
else
    warn "xdotool not installed (fallback for XWayland apps unavailable)"
    fix "sudo apt install xdotool"
fi

# wl-copy
if command -v wl-copy >/dev/null 2>&1; then
    ok "wl-copy available (clipboard)"
else
    fail "wl-copy not found"
    fix "sudo apt install wl-clipboard"
fi

# Microphone
MIC_VOL=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null)
if echo "$MIC_VOL" | grep -q "MUTED"; then
    warn "Microphone is MUTED"
    fix "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0"
elif [ -n "$MIC_VOL" ]; then
    ok "Microphone active: $MIC_VOL"
else
    warn "Could not query microphone status (wpctl unavailable)"
fi

# speech-start / speech-stop scripts
if [ -x /usr/local/bin/voxfree-dictate ]; then
    ok "/usr/local/bin/voxfree-dictate installed"
else
    fail "/usr/local/bin/voxfree-dictate not installed"
    fix "sudo bash /usr/share/voxfree/SpeakToType/speak-to-type.sh"
fi

if [ -x /usr/local/bin/voxfree-dictate-stop ]; then
    ok "/usr/local/bin/voxfree-dictate-stop installed"
else
    fail "/usr/local/bin/voxfree-dictate-stop not installed"
    fix "sudo bash /usr/share/voxfree/SpeakToType/speak-to-type.sh"
fi

# Quick STT recording test
if command -v arecord >/dev/null 2>&1; then
    TMPF=$(mktemp /tmp/voxfree-doctor-XXXXXX.wav)
    timeout 1 arecord -D default -f S16_LE -r 16000 -c 1 -q "$TMPF" 2>/dev/null
    SZ=$(stat -c%s "$TMPF" 2>/dev/null || echo 0)
    rm -f "$TMPF"
    if [ "$SZ" -gt 1000 ]; then
        ok "Microphone recording test passed (captured ${SZ}B in 1s)"
    else
        fail "Microphone recording test failed (captured ${SZ}B)"
        info "arecord could not capture audio — check audio session"
        fix "systemctl --user restart pipewire pipewire-pulse"
    fi
fi

fi # end STT checks

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4: GNOME Shortcuts
# ─────────────────────────────────────────────────────────────────────────────
section "GNOME Keyboard Shortcuts"

# gsd-media-keys
if pgrep -x gsd-media-keys >/dev/null 2>&1; then
    ok "gsd-media-keys daemon running (PID $(pgrep -x gsd-media-keys))"
else
    fail "gsd-media-keys not running — shortcuts will not fire"
    fix "systemctl --user start org.gnome.SettingsDaemon.MediaKeys.target"
fi

# dconf profile
if grep -q "system-db:local" /etc/dconf/profile/user 2>/dev/null; then
    ok "dconf profile includes system-db:local (all-user defaults)"
else
    warn "dconf profile not configured for system-wide defaults"
    fix "printf 'user-db:user\nsystem-db:local\n' | sudo tee /etc/dconf/profile/user"
fi

# dconf shortcuts file
if [ -f /etc/dconf/db/local.d/00-voice-shortcuts ]; then
    ok "/etc/dconf/db/local.d/00-voice-shortcuts exists"
else
    warn "dconf shortcuts file missing (new users won't get shortcuts automatically)"
    fix "sudo bash /usr/share/voxfree/install.sh"
fi

# Active gsettings shortcuts
BASE="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"
P="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

check_shortcut() {
    local SLOT="$1" EXPECTED_CMD="$2" LABEL="$3"
    CMD=$(gsettings get "${BASE}${P}/${SLOT}/" command 2>/dev/null | tr -d "'")
    KEY=$(gsettings get "${BASE}${P}/${SLOT}/" binding 2>/dev/null | tr -d "'")
    if [ "$CMD" = "$EXPECTED_CMD" ]; then
        ok "Shortcut: $KEY → $LABEL"
    elif [ -n "$CMD" ]; then
        warn "Shortcut ${SLOT}: bound to '$CMD' (expected '$EXPECTED_CMD')"
        fix "gsettings set \"${BASE}${P}/${SLOT}/\" command '$EXPECTED_CMD'"
    else
        fail "Shortcut ${SLOT} not configured"
        fix "sudo bash /usr/share/voxfree/install.sh"
    fi
}

[ "$CHECK_TTS" = true ] && check_shortcut "voxfree-readloud" "/usr/local/bin/voxfree-readloud" "Read Aloud (TTS)"
[ "$CHECK_STT" = true ] && check_shortcut "voxfree-dictate"  "/usr/local/bin/voxfree-dictate"   "Start Recording (STT)"
check_shortcut "voxfree-stop-all"   "/usr/local/bin/voxfree-stop-all"    "Stop All Voice"

# wev (for keysym detection)
if command -v wev >/dev/null 2>&1; then
    ok "wev installed (keysym detection for ThinkPad keyboards)"
else
    warn "wev not installed — can't verify ThinkPad key names"
    fix "sudo apt install wev"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
printf "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
printf "${BOLD} Summary  (${PASS} passed · ${WARN} warnings · ${FAIL} failed)${RESET}\n"
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

# Failed checks
if [ "${#FAILED_ITEMS[@]}" -gt 0 ]; then
    printf "\n  ${RED}${BOLD}Failed:${RESET}\n"
    for item in "${FAILED_ITEMS[@]}"; do
        printf "    ${RED}[✘]${RESET} %s\n" "$item"
    done
fi

# Warnings
if [ "${#WARNED_ITEMS[@]}" -gt 0 ]; then
    printf "\n  ${YELLOW}${BOLD}Warnings:${RESET}\n"
    for item in "${WARNED_ITEMS[@]}"; do
        printf "    ${YELLOW}[!]${RESET} %s\n" "$item"
    done
fi

# Passed checks
if [ "${#PASSED_ITEMS[@]}" -gt 0 ]; then
    printf "\n  ${GREEN}${BOLD}Passed:${RESET}\n"
    for item in "${PASSED_ITEMS[@]}"; do
        printf "    ${GREEN}[✔]${RESET} %s\n" "$item"
    done
fi

# Overall status
printf "\n"
if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
    printf "  ${GREEN}${BOLD}✔ VoxFree is fully operational!${RESET}\n\n"
elif [ "$FAIL" -eq 0 ]; then
    printf "  ${YELLOW}${BOLD}VoxFree is operational with minor warnings.${RESET}\n"
    printf "  Run ${CYAN}bash voxfree-doctor.sh --fix${RESET} for remediation commands.\n\n"
else
    printf "  ${RED}${BOLD}VoxFree has issues that need attention.${RESET}\n"
    printf "  Run ${CYAN}bash voxfree-doctor.sh --fix${RESET} to see fix commands.\n"
    printf "  Or run ${CYAN}sudo bash install.sh${RESET} to reinstall.\n\n"
fi
