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

# Auto-fix and sudo-fix tracking
AUTO_FIXED=()
SUDO_FIXES=()
RELOGIN_REASONS=()

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

# ── Auto-fix helpers ──────────────────────────────────────────────────────────

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

sudo_fix() {
    local section="$1" label="$2" command="$3" relogin="${4:-}" reason="${5:-}"
    SUDO_FIXES+=("[$section]@@[$label]@@[$command]@@[$relogin]@@[$reason]")
    if [ "$SHOW_FIX" = true ]; then
        printf "      ${CYAN}Fix:${RESET} %s\n" "$command"
        [ "$relogin" = "yes" ] && RELOGIN_REASONS+=("[$section]: $reason")
    fi
}

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
            local es ecmd rest
            es="${entry%%@@*}"
            rest="${entry#*@@}"
            ecmd="${rest%%@@*}"
            [ "$es" = "[$target_section]" ] && { printf "    %d. %s\n" "$i" "$ecmd"; i=$((i+1)); }
        done
    fi
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
    sudo_fix "System" "Session" "Log in with 'Ubuntu (Wayland)' session at the login screen" "" ""
fi

# PipeWire
if systemctl --user is-active pipewire >/dev/null 2>&1; then
    ok "PipeWire audio server running"
else
    fail "PipeWire not running"
    auto_fix "System" "PipeWire started" systemctl --user start pipewire
    [ -z "$(systemctl --user is-active pipewire 2>/dev/null)" ] && sudo_fix "System" "PipeWire" "systemctl --user start pipewire" "" ""
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
    sudo_fix "ReadLoud — Text-to-Speech" "mimic3 install" "wget https://github.com/MycroftAI/mimic3/releases/download/v0.2.4/mycroft-mimic3-tts_0.2.4_amd64.deb && sudo dpkg -i mycroft-mimic3-tts_0.2.4_amd64.deb" "" ""
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
    auto_fix "ReadLoud — Text-to-Speech" "Voice model downloaded" mimic3-download en_UK/apope_low
    [ ! -d "$USER_VOICE_PATH" ] && [ ! -d "$VOICE_PATH" ] && sudo_fix "ReadLoud — Text-to-Speech" "Voice model" "mimic3-download en_UK/apope_low" "" ""
fi

# speech-dispatcher
if command -v spd-say >/dev/null 2>&1; then
    ok "speech-dispatcher installed"
else
    fail "speech-dispatcher not installed"
    sudo_fix "ReadLoud — Text-to-Speech" "speech-dispatcher" "sudo apt install speech-dispatcher" "" ""
fi

# speech-dispatcher module (local mode check)
MODCONF="/etc/speech-dispatcher/modules/mimic3-generic.conf"
if [ -f "$MODCONF" ]; then
    if grep -q "\-\-remote" "$MODCONF"; then
        fail "mimic3-generic.conf still uses --remote (requires mimic3-server)"
        info "The config must use local mode (without --remote flag)"
        sudo_fix "ReadLoud — Text-to-Speech" "Mimic3 module config" "sudo bash /usr/share/voxfree/deps.sh --tts" "" ""
    else
        ok "speech-dispatcher module: local mode ✔"
    fi
else
    fail "mimic3-generic.conf not found"
    sudo_fix "ReadLoud — Text-to-Speech" "Mimic3 module config" "sudo bash /usr/share/voxfree/deps.sh --tts" "" ""
fi

# speech-dispatcher default module
if grep -q "^DefaultModule mimic3-generic" /etc/speech-dispatcher/speechd.conf 2>/dev/null; then
    ok "speech-dispatcher DefaultModule = mimic3-generic"
else
    fail "speech-dispatcher DefaultModule is not mimic3-generic"
    sudo_fix "ReadLoud — Text-to-Speech" "DefaultModule" "sudo sed -i 's/^DefaultModule.*/DefaultModule mimic3-generic/' /etc/speech-dispatcher/speechd.conf" "" ""
fi

# aplay (audio output)
if command -v aplay >/dev/null 2>&1; then
    ok "aplay available (audio output)"
else
    fail "aplay not found"
    sudo_fix "ReadLoud — Text-to-Speech" "alsa-utils" "sudo apt install alsa-utils" "" ""
fi

# wl-paste (clipboard reading)
if command -v wl-paste >/dev/null 2>&1; then
    ok "wl-paste available (Wayland clipboard)"
else
    fail "wl-paste not found"
    sudo_fix "ReadLoud — Text-to-Speech" "wl-clipboard" "sudo apt install wl-clipboard" "" ""
fi

# read-selection script
if [ -x /usr/local/bin/voxfree-readloud ]; then
    ok "/usr/local/bin/voxfree-readloud installed"
else
    fail "/usr/local/bin/voxfree-readloud not installed"
    sudo_fix "ReadLoud — Text-to-Speech" "ReadLoud scripts" "sudo bash /usr/share/voxfree/ReadLoud/readloud.sh" "" ""
fi

# stop-reading script
if [ -x /usr/local/bin/voxfree-readloud-stop ]; then
    ok "/usr/local/bin/voxfree-readloud-stop installed"
else
    fail "/usr/local/bin/voxfree-readloud-stop not installed"
    sudo_fix "ReadLoud — Text-to-Speech" "ReadLoud scripts" "sudo bash /usr/share/voxfree/ReadLoud/readloud.sh" "" ""
fi

# Quick TTS audio test
if command -v mimic3 >/dev/null 2>&1 && command -v aplay >/dev/null 2>&1; then
    if echo "test" | mimic3 --voice en_UK/apope_low --stdout 2>/dev/null | aplay -q 2>/dev/null; then
        ok "TTS audio pipeline works (mimic3 → aplay)"
    else
        fail "TTS audio pipeline failed"
        sudo_fix "ReadLoud — Text-to-Speech" "Audio check" "Check audio output: wpctl get-volume @DEFAULT_AUDIO_SINK@" "" ""
    fi
fi

# Indicator checks
CURRENT_SECTION="Indicator"
if [ "$CHECK_TTS" = true ]; then

    # python3-gi
    if python3 -c "import gi" 2>/dev/null; then
        ok "python3-gi available (GTK introspection)"
    else
        fail "python3-gi not available"
        sudo_fix "Indicator" "python3-gi" "sudo apt install python3-gi" "" ""
    fi

    # AyatanaAppIndicator3
    if python3 -c "import gi; gi.require_version('AyatanaAppIndicator3', '0.1'); from gi.repository import AyatanaAppIndicator3" 2>/dev/null; then
        ok "AyatanaAppIndicator3 available"
    elif python3 -c "import gi; gi.require_version('AppIndicator3', '0.1'); from gi.repository import AppIndicator3" 2>/dev/null; then
        ok "AppIndicator3 available (fallback)"
    else
        fail "No AppIndicator library found"
        sudo_fix "Indicator" "ayatana-appindicator" "sudo apt install gir1.2-ayatanaappindicator3-0.1" "" ""
    fi

    # voxfree-indicator script
    if [ -x /usr/local/bin/voxfree-indicator ] || [ -x "$HOME/.local/bin/voxfree-indicator" ]; then
        ok "voxfree-indicator installed"
    else
        warn "voxfree-indicator not installed — run readloud.sh to install"
    fi

    # voxfree-readloud-last script
    if [ -x /usr/local/bin/voxfree-readloud-last ] || [ -x "$HOME/.local/bin/voxfree-readloud-last" ]; then
        ok "voxfree-readloud-last installed (replay)"
    else
        warn "voxfree-readloud-last not installed"
    fi

    # Indicator process running
    if pgrep -f "voxfree-indicator" >/dev/null 2>&1; then
        ok "voxfree-indicator is running"
    else
        warn "voxfree-indicator is not running — start with 'voxfree-indicator'"
    fi

    # State file
    if [ -f /tmp/voxfree/state ]; then
        STATE_VAL=$(grep "^STATE=" /tmp/voxfree/state | cut -d= -f2)
        ok "State file: STATE=${STATE_VAL:-unknown}"
    else
        warn "State file not found — will be created on first readloud"
    fi

fi

fi # end TTS checks

# Per-section fix block
print_section_fixes "ReadLoud — Text-to-Speech"

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
    sudo_fix "SpeakToType — Speech-to-Text" "alsa-utils" "sudo apt install alsa-utils" "" ""
fi

# sox (noise reduction)
if command -v sox >/dev/null 2>&1; then
    ok "sox $(sox --version 2>&1 | grep -o 'SoX v[0-9.]*') (noise reduction)"
else
    fail "sox not found"
    sudo_fix "SpeakToType — Speech-to-Text" "sox" "sudo apt install sox libsox-fmt-all" "" ""
fi

# whisper binary
if command -v whisper >/dev/null 2>&1; then
    WHISPER_TARGET=$(readlink -f "$(which whisper)" 2>/dev/null)
    if echo "$WHISPER_TARGET" | grep -q "whisper-ctranslate2"; then
        ok "whisper → whisper-ctranslate2 at $WHISPER_TARGET"
    else
        warn "whisper found but not pointing to whisper-ctranslate2"
        info "Target: $WHISPER_TARGET"
        auto_fix "SpeakToType — Speech-to-Text" "Whisper symlink created" ln -sf /opt/openai-whisper/bin/whisper-ctranslate2 /usr/local/bin/whisper
        [ "$(readlink -f "$(which whisper)" 2>/dev/null)" != "/opt/openai-whisper/bin/whisper-ctranslate2" ] && sudo_fix "SpeakToType — Speech-to-Text" "Whisper symlink" "sudo ln -sf /opt/openai-whisper/bin/whisper-ctranslate2 /usr/local/bin/whisper" "" ""
    fi
else
    fail "whisper not found in PATH"
    sudo_fix "SpeakToType — Speech-to-Text" "whisper install" "sudo bash /usr/share/voxfree/deps.sh --stt" "" ""
fi

# whisper-ctranslate2 venv
if [ -f /opt/openai-whisper/bin/whisper-ctranslate2 ]; then
    VERSION=$(/opt/openai-whisper/bin/pip show whisper-ctranslate2 2>/dev/null | grep "^Version" | awk '{print $2}')
    ok "whisper-ctranslate2 $VERSION in /opt/openai-whisper/"
else
    fail "whisper-ctranslate2 venv not found at /opt/openai-whisper/"
    sudo_fix "SpeakToType — Speech-to-Text" "whisper venv" "sudo python3 -m venv /opt/openai-whisper && sudo /opt/openai-whisper/bin/pip install whisper-ctranslate2" "" ""
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
        sudo_fix "SpeakToType — Speech-to-Text" "Model permissions" "sudo chmod -R a+rX /var/cache/huggingface" "no" "HF_HOME cache permissions"
    fi
else
    fail "Whisper base.en model not in shared cache"
    # Check user cache
    if [ -d "$HOME/.cache/huggingface/hub/models--Systran--faster-whisper-base.en" ]; then
        warn "Model found in user cache ($HOME/.cache) — not shared with other users"
        auto_fix "SpeakToType — Speech-to-Text" "Model copied to shared cache" bash -c "mkdir -p /var/cache/huggingface/hub && cp -r $HOME/.cache/huggingface/hub/models--Systran--faster-whisper-base.en /var/cache/huggingface/hub/ && chmod -R a+rX /var/cache/huggingface"
        [ ! -d "$MODEL_DIR" ] && sudo_fix "SpeakToType — Speech-to-Text" "Model shared" "sudo mkdir -p /var/cache/huggingface/hub && sudo cp -r $HOME/.cache/huggingface/hub/models--Systran--faster-whisper-base.en /var/cache/huggingface/hub/ && sudo chmod -R a+rX /var/cache/huggingface" "no" "HF_HOME cache permissions"
    else
        sudo_fix "SpeakToType — Speech-to-Text" "Whisper model" "sudo bash /usr/share/voxfree/deps.sh --stt" "" ""
    fi
fi

# HF_HOME environment
HF_HOME_VAL="${HF_HOME:-}"
if grep -q "HF_HOME=/var/cache/huggingface" /etc/environment 2>/dev/null; then
    ok "HF_HOME=/var/cache/huggingface in /etc/environment (global)"
elif [ "$HF_HOME_VAL" = "/var/cache/huggingface" ]; then
    warn "HF_HOME set in current session but not in /etc/environment"
    sudo_fix "SpeakToType — Speech-to-Text" "HF_HOME" "echo 'HF_HOME=/var/cache/huggingface' | sudo tee -a /etc/environment" "yes" "HF_HOME env var"
else
    fail "HF_HOME not configured globally"
    sudo_fix "SpeakToType — Speech-to-Text" "HF_HOME" "echo 'HF_HOME=/var/cache/huggingface' | sudo tee -a /etc/environment" "yes" "HF_HOME env var"
fi

# HF_HUB_OFFLINE should NOT be in /etc/environment (blocks model downloads)
if grep -q "HF_HUB_OFFLINE" /etc/environment 2>/dev/null; then
    fail "HF_HUB_OFFLINE is set in /etc/environment — blocks model downloads"
    info "This env var should only be set inside scripts, not globally"
    auto_fix "SpeakToType — Speech-to-Text" "HF_HUB_OFFLINE removed" bash -c "sed -i '/HF_HUB_OFFLINE/d' /etc/environment"
    grep -q "HF_HUB_OFFLINE" /etc/environment 2>/dev/null && sudo_fix "SpeakToType — Speech-to-Text" "HF_HUB_OFFLINE" "sudo sed -i '/HF_HUB_OFFLINE/d' /etc/environment" "" ""
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
        sudo_fix "SpeakToType — Speech-to-Text" "Input group" "sudo usermod -aG input $USER" "yes" "ydotool input group membership"
    fi
    # uinput device
    if [ -e /dev/uinput ]; then
        UINPUT_PERMS=$(stat -c "%a" /dev/uinput 2>/dev/null)
        if [ "$UINPUT_PERMS" = "660" ] || [ "$UINPUT_PERMS" = "666" ]; then
            ok "/dev/uinput accessible (mode $UINPUT_PERMS)"
        else
            warn "/dev/uinput mode is $UINPUT_PERMS — ydotool may not work"
            sudo_fix "SpeakToType — Speech-to-Text" "udev rule" "echo 'KERNEL==\"uinput\", GROUP=\"input\", MODE=\"0660\"' | sudo tee /etc/udev/rules.d/99-uinput.rules && sudo udevadm trigger" "no" "udev rules"
        fi
    else
        fail "/dev/uinput not found"
        sudo_fix "SpeakToType — Speech-to-Text" "uinput kernel module" "sudo modprobe uinput" "no" "uinput module"
    fi
else
    fail "ydotool not installed"
    sudo_fix "SpeakToType — Speech-to-Text" "ydotool" "sudo apt install ydotool" "" ""
fi

# xdotool (Ctrl+V fallback)
if command -v xdotool >/dev/null 2>&1; then
    ok "xdotool installed (Ctrl+V fallback for XWayland apps)"
else
    warn "xdotool not installed (fallback for XWayland apps unavailable)"
    sudo_fix "SpeakToType — Speech-to-Text" "xdotool" "sudo apt install xdotool" "" ""
fi

# wl-copy
if command -v wl-copy >/dev/null 2>&1; then
    ok "wl-copy available (clipboard)"
else
    fail "wl-copy not found"
    sudo_fix "SpeakToType — Speech-to-Text" "wl-clipboard" "sudo apt install wl-clipboard" "" ""
fi

# Microphone
MIC_VOL=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null)
if echo "$MIC_VOL" | grep -q "MUTED"; then
    warn "Microphone is MUTED"
    auto_fix "SpeakToType — Speech-to-Text" "Mic unmuted" wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0
    echo "$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null)" | grep -q "MUTED" && sudo_fix "SpeakToType — Speech-to-Text" "Mic unmuted" "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0" "" ""
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
    sudo_fix "SpeakToType — Speech-to-Text" "Dictation scripts" "sudo bash /usr/share/voxfree/SpeakToType/speak-to-type.sh" "" ""
fi

if [ -x /usr/local/bin/voxfree-dictate-stop ]; then
    ok "/usr/local/bin/voxfree-dictate-stop installed"
else
    fail "/usr/local/bin/voxfree-dictate-stop not installed"
    sudo_fix "SpeakToType — Speech-to-Text" "Dictation scripts" "sudo bash /usr/share/voxfree/SpeakToType/speak-to-type.sh" "" ""
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
        auto_fix "SpeakToType — Speech-to-Text" "PipeWire restarted" systemctl --user restart pipewire pipewire-pulse
        TMPF2=$(mktemp /tmp/voxfree-doctor-XXXXXX.wav)
        timeout 1 arecord -D default -f S16_LE -r 16000 -c 1 -q "$TMPF2" 2>/dev/null
        SZ2=$(stat -c%s "$TMPF2" 2>/dev/null || echo 0)
        rm -f "$TMPF2"
        [ "$SZ2" -le 1000 ] && sudo_fix "SpeakToType — Speech-to-Text" "PipeWire restart" "systemctl --user restart pipewire pipewire-pulse" "no" "PipeWire session"
    fi
fi

fi # end STT checks

# Per-section fix block
print_section_fixes "SpeakToType — Speech-to-Text"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4: GNOME Shortcuts
# ─────────────────────────────────────────────────────────────────────────────
section "GNOME Keyboard Shortcuts"

# gsd-media-keys
if pgrep -x gsd-media-keys >/dev/null 2>&1; then
    ok "gsd-media-keys daemon running (PID $(pgrep -x gsd-media-keys))"
else
    fail "gsd-media-keys not running — shortcuts will not fire"
    sudo_fix "GNOME Keyboard Shortcuts" "gsd-media-keys" "systemctl --user start org.gnome.SettingsDaemon.MediaKeys.target" "" ""
fi

# dconf profile
if grep -q "system-db:local" /etc/dconf/profile/user 2>/dev/null; then
    ok "dconf profile includes system-db:local (all-user defaults)"
else
    warn "dconf profile not configured for system-wide defaults"
    sudo_fix "GNOME Keyboard Shortcuts" "dconf profile" "printf 'user-db:user\nsystem-db:local\n' | sudo tee /etc/dconf/profile/user" "" ""
fi

# dconf shortcuts file
if [ -f /etc/dconf/db/local.d/00-voice-shortcuts ]; then
    ok "/etc/dconf/db/local.d/00-voice-shortcuts exists"
else
    warn "dconf shortcuts file missing (new users won't get shortcuts automatically)"
    sudo_fix "GNOME Keyboard Shortcuts" "dconf shortcuts" "sudo bash /usr/share/voxfree/install.sh" "" ""
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
        auto_fix "GNOME Keyboard Shortcuts" "Shortcut $SLOT fixed" gsettings set "${BASE}${P}/${SLOT}/" command "'$EXPECTED_CMD'"
        CMD=$(gsettings get "${BASE}${P}/${SLOT}/" command 2>/dev/null | tr -d "'")
        [ "$CMD" != "$EXPECTED_CMD" ] && sudo_fix "GNOME Keyboard Shortcuts" "Shortcut $SLOT" "gsettings set \"${BASE}${P}/${SLOT}/\" command '$EXPECTED_CMD'" "" ""
    else
        fail "Shortcut ${SLOT} not configured"
        sudo_fix "GNOME Keyboard Shortcuts" "Shortcut $SLOT" "sudo bash /usr/share/voxfree/install.sh" "" ""
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
    sudo_fix "GNOME Keyboard Shortcuts" "wev" "sudo apt install wev" "" ""
fi

# Per-section fix block
print_section_fixes "GNOME Keyboard Shortcuts"

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
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
    sections_seen=""
    for entry in "${SUDO_FIXES[@]}"; do
        entry_section="${entry%%@@*}"
        if ! echo "$sections_seen" | grep -qF "$entry_section"; then
            sections_seen="$sections_seen $entry_section"
            # Strip brackets for display
            display_name="${entry_section#\[}"
            display_name="${display_name%\]}"
            printf "  %s failures:\n" "$display_name"
            
            # Count and list fixes
            i=1
            for e in "${SUDO_FIXES[@]}"; do
                es="${e%%@@*}"
                rest="${e#*@@}"
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
    first=true
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
