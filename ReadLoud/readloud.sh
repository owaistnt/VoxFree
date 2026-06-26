#!/bin/bash
# =============================================================================
# readloud.sh — Text-to-Speech setup for Ubuntu 24.04 GNOME/Wayland
# =============================================================================
# Installs:
#   - Mycroft Mimic 3  (offline neural TTS)
#   - speech-dispatcher (system TTS daemon)
#   - voxfree-readloud       → read selected text (toggle)
#   - voxfree-readloud-stop  → force-stop TTS
#   - GNOME keyboard shortcut (ThinkPad F9 or Super+Shift+R)
#
# Usage:
#   sudo bash ReadLoud/readloud.sh              (interactive)
#   sudo bash ReadLoud/readloud.sh --thinkpad   (ThinkPad F9 = XF86Messenger)
#   sudo bash ReadLoud/readloud.sh --standard   (Super+Shift+R)
# =============================================================================

if [ -z "$BASH_VERSION" ]; then exec bash "$0" "$@"; fi
set -e

RL_DIR="$(cd "$(dirname "$0")" && pwd)"
VOXFREE_DIR="$(cd "$RL_DIR/.." && pwd)"

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
ACTUAL_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
BIN_DIR="${BIN_DIR:-/usr/local/bin}"
CONF_DIR="${CONF_DIR:-/etc/voxfree}"

if [ "$INSTALL_MODE" = "system" ] && [ "$(id -u)" -ne 0 ]; then
    fail "System install requires root: sudo bash $0"
fi

# ── Keyboard layout ───────────────────────────────────────────────────────────
THINKPAD_READ="XF86Messenger"   # F9  (✉ message icon, verified via wev)
THINKPAD_STOP="Cancel"   # F11 → voxfree-stop-all (stops TTS + STT)          # F11 (✕ cancel icon, verified via wev)
STANDARD_READ="<Super><Shift>r"
STANDARD_STOP="<Super><Shift>k"  
KEY_READ=""; KEY_STOP=""; LAYOUT=""

for arg in "$@"; do
    case "$arg" in
        --thinkpad) LAYOUT="thinkpad" ;;
        --standard) LAYOUT="standard" ;;
        --skip)     LAYOUT="skip" ;;
    esac
done

if [ -z "$LAYOUT" ]; then
    printf "\n${BOLD}Choose keyboard shortcut:${RESET}\n"
    printf "  1) ThinkPad  F9 (✉) = Read toggle   F11 (✕) = Force stop\n"
    printf "  2) Standard  Super+Shift+R = Read toggle   Super+Shift+K = Stop all\n"
    printf "  3) Skip — configure manually later\n\n"
    while true; do
        read -r -p "  Choice [1/2/3]: " C
        case "$C" in 1) LAYOUT="thinkpad"; break ;; 2) LAYOUT="standard"; break ;; 3) LAYOUT="skip"; break ;; esac
    done
fi

case "$LAYOUT" in
    thinkpad) KEY_READ="$THINKPAD_READ"; KEY_STOP="$THINKPAD_STOP"; ok "ThinkPad: F9=Read  F11=Stop" ;;
    standard) KEY_READ="$STANDARD_READ"; KEY_STOP="$STANDARD_STOP"; ok "Standard: Super+Shift+R=Read  Super+Shift+K=Stop" ;;
    skip)     warn "Skipping shortcuts." ;;
esac

# ── Step 1: Dependencies ──────────────────────────────────────────────────────
if [ "${VOXFREE_DEPS_DONE:-}" != "1" ]; then
    DEPS_SCRIPT="$VOXFREE_DIR/deps.sh"
    if [ -f "$DEPS_SCRIPT" ]; then
        bash "$DEPS_SCRIPT" "--$INSTALL_MODE" --tts
    else
        # Standalone fallback
        section "Step 1: APT packages (standalone)"
        [ "$INSTALL_MODE" = "system" ] && apt-get update -qq && apt-get install -y speech-dispatcher wl-clipboard alsa-utils libnotify-bin wev || \
            warn "Cannot install apt packages in user mode"
    fi
fi

# ── Step 2: speech-dispatcher (system-wide only) ──────────────────────────────
if [ "$INSTALL_MODE" = "system" ]; then
    section "Step 2: Configuring speech-dispatcher"
    MODCONF="/etc/speech-dispatcher/modules/mimic3-generic.conf"
    cp "$MODCONF" "${MODCONF}.bak" 2>/dev/null || true
    cat > "$MODCONF" << 'EOF'
GenericExecuteSynth "printf %s \'$DATA\' | /usr/bin/mimic3 --voice \'$VOICE\' --stdout 2>/dev/null | aplay -q 2>/dev/null"
AddVoice "en" "MALE1" "en_UK/apope_low"
AddVoice "en" "FEMALE1" "en_UK/apope_low"
EOF
    SCFG="/etc/speech-dispatcher/speechd.conf"
    grep -q "^DefaultModule" "$SCFG" && \
        sed -i 's/^DefaultModule.*/DefaultModule mimic3-generic/' "$SCFG" || \
        echo "DefaultModule mimic3-generic" >> "$SCFG"
    pkill speech-dispatcher 2>/dev/null || true
    ok "speech-dispatcher configured (mimic3 local mode)"
else
    # Check if system already configured
    if grep -q "mimic3" /etc/speech-dispatcher/modules/mimic3-generic.conf 2>/dev/null && \
       ! grep -q "\-\-remote" /etc/speech-dispatcher/modules/mimic3-generic.conf 2>/dev/null; then
        ok "speech-dispatcher already configured (system)"
    else
        warn "speech-dispatcher needs system config — run: sudo bash $VOXFREE_DIR/ReadLoud/readloud.sh --system"
    fi
fi

# ── Step 3: Voice config directory ───────────────────────────────────────────
section "Step 3: Voice configuration"
mkdir -p "$CONF_DIR"
[ "$INSTALL_MODE" != "system" ] && chown "$ACTUAL_USER:$ACTUAL_USER" "$CONF_DIR" 2>/dev/null || true

VOICE_CFG="$CONF_DIR/voice"
if [ ! -f "$VOICE_CFG" ]; then
    echo "en_UK/apope_low" > "$VOICE_CFG"
    [ "$INSTALL_MODE" != "system" ] && chown "$ACTUAL_USER:$ACTUAL_USER" "$VOICE_CFG" 2>/dev/null || true
    ok "Default voice set: en_UK/apope_low → $VOICE_CFG"
else
    ok "Voice config exists: $(cat "$VOICE_CFG") → $VOICE_CFG"
fi

# ── Step 4: Install scripts ───────────────────────────────────────────────────
section "Step 4: Installing scripts"
mkdir -p "$BIN_DIR"

# Install by copying from ReadLoud/ directory — keeps sources and bin in sync
install_script() {
    local SRC="$RL_DIR/$1" DEST="$BIN_DIR/$2"
    if [ -f "$SRC" ]; then
        cp "$SRC" "$DEST"
        chmod 755 "$DEST"
        [ "$INSTALL_MODE" != "system" ] && chown "$ACTUAL_USER:$ACTUAL_USER" "$DEST" 2>/dev/null || true
        ok "$DEST"
    else
        warn "Source not found: $SRC"
    fi
}

install_script "voxfree-readloud.sh"      "voxfree-readloud"
install_script "voxfree-readloud-stop.sh" "voxfree-readloud-stop"
install_script "voxfree-stop-all.sh"      "voxfree-stop-all"
install_script "voxfree-readloud-last.sh" "voxfree-readloud-last"
install_script "voxfree-indicator"        "voxfree-indicator"

# Install state.sh library alongside the scripts
STATE_LIB_DEST="$BIN_DIR/lib"
mkdir -p "$STATE_LIB_DEST"
if [ -f "$VOXFREE_DIR/lib/state.sh" ]; then
    cp "$VOXFREE_DIR/lib/state.sh" "$STATE_LIB_DEST/state.sh"
    chmod 644 "$STATE_LIB_DEST/state.sh"
    [ "$INSTALL_MODE" != "system" ] && chown "$ACTUAL_USER:$ACTUAL_USER" "$STATE_LIB_DEST" "$STATE_LIB_DEST/state.sh" 2>/dev/null || true
    ok "$STATE_LIB_DEST/state.sh"
fi

# ── Step 5: GNOME keyboard shortcuts ─────────────────────────────────────────
[ "$LAYOUT" = "skip" ] && { warn "Skipping shortcuts."; } || {

section "Step 5: Keyboard shortcuts"

USER_ID=$(id -u "$ACTUAL_USER")
gs() { sudo -u "$ACTUAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_ID}/bus" gsettings "$@" 2>/dev/null || true; }
GBASE="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

# Preserve existing STT shortcut binding if already configured
EXISTING_DICTATE=$(grep "binding=.*dictate\b" /etc/dconf/db/local.d/00-voice-shortcuts 2>/dev/null | \
    grep -o "'[^']*'" | tr -d "'" | head -1)
[ -z "$EXISTING_DICTATE" ] && EXISTING_DICTATE=$(grep "binding=.*speech-to-type\|binding=.*XF86Go" \
    /etc/dconf/db/local.d/00-voice-shortcuts 2>/dev/null | grep -o "'[^']*'" | tr -d "'" | head -1)
[ -z "$EXISTING_DICTATE" ] && EXISTING_DICTATE="XF86Go"

EXISTING_DICTATE_STOP=$(grep -A3 "dictate-stop\]" /etc/dconf/db/local.d/00-voice-shortcuts 2>/dev/null | \
    grep "^binding" | grep -o "'[^']*'" | tr -d "'" | head -1)
[ -z "$EXISTING_DICTATE_STOP" ] && EXISTING_DICTATE_STOP="Cancel"

KPATH="['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-readloud/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-dictate/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-stop-all/']"

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
binding='${KEY_READ}'

[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-readloud-stop]
name='Stop Reading (VoxFree)'
command='${BIN_DIR}/voxfree-stop-all'
binding='${KEY_STOP}'

[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-dictate]
name='Start Dictation (VoxFree STT)'
command='${BIN_DIR}/voxfree-dictate'
binding='${EXISTING_DICTATE}'

[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-dictate-stop]
name='Stop Dictation (VoxFree)'
command='${BIN_DIR}/voxfree-stop-all'
binding='${EXISTING_DICTATE_STOP}'
DCONFEOF
    dconf update; ok "dconf system shortcuts updated"
fi

# Apply to current user session (both system and user mode)
gs set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$KPATH"
gs set "${GBASE}/voxfree-readloud/"      name    'Read Aloud (VoxFree TTS)'
gs set "${GBASE}/voxfree-readloud/"      command "$BIN_DIR/voxfree-readloud"
gs set "${GBASE}/voxfree-readloud/"      binding "$KEY_READ"
gs set "${GBASE}/voxfree-readloud-stop/" name    'Stop Reading (VoxFree)'
gs set "${GBASE}/voxfree-readloud-stop/" command "$BIN_DIR/voxfree-readloud-stop"
gs set "${GBASE}/voxfree-readloud-stop/" binding "$KEY_STOP"
  ok "Shortcuts applied to current session"

sudo -u "$ACTUAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_ID}/bus" \
    systemctl --user start org.gnome.SettingsDaemon.MediaKeys.target 2>/dev/null && \
    ok "gsd-media-keys started" || warn "Shortcuts will activate on next login"

# Persist the chosen layout so voxfree --switch knows the current state
CONF_DIR="$CONF_DIR" bash "$VOXFREE_DIR/lib/keyboard-layout.sh" write_keyboard_layout "$LAYOUT" 2>/dev/null || true
}

# ── Step 6: System tray indicator ─────────────────────────────────────────────
section "Step 6: System tray indicator"

if [ -f "$RL_DIR/voxfree-indicator" ]; then
    ok "voxfree-indicator installed to $BIN_DIR"

    INSTALL_INDICATOR=""
    if [ -t 0 ]; then
        printf "\n  ${BOLD}VoxFree can show a system tray icon${RESET} to start/stop reading.\n"
        printf "  (requires: gir1.2-ayatanaappindicator3-0.1)\n"
        while true; do
            read -r -p "  Launch indicator at login? [Y/n]: " ANS
            case "$ANS" in
                ""|y|Y) INSTALL_INDICATOR="yes"; break ;;
                n|N) INSTALL_INDICATOR="no"; break ;;
            esac
        done
    fi

    if [ "$INSTALL_INDICATOR" != "no" ]; then
        if [ "$INSTALL_MODE" = "system" ]; then
            AUTOSTART_DIR="/etc/xdg/autostart"
        else
            AUTOSTART_DIR="$ACTUAL_HOME/.config/autostart"
            mkdir -p "$AUTOSTART_DIR"
        fi

        cat > "$AUTOSTART_DIR/voxfree-indicator.desktop" << DESKTOPF
[Desktop Entry]
Type=Application
Name=VoxFree ReadLoud Indicator
Comment=Start and stop text-to-speech reading from the system tray
Exec=${BIN_DIR}/voxfree-indicator
Terminal=false
Categories=Utility;Audio;
X-GNOME-Autostart-enabled=true
DESKTOPF
        chmod 644 "$AUTOSTART_DIR/voxfree-indicator.desktop"
        [ "$INSTALL_MODE" != "system" ] && chown "$ACTUAL_USER:$ACTUAL_USER" "$AUTOSTART_DIR/voxfree-indicator.desktop" 2>/dev/null || true
        ok "Autostart configured: $AUTOSTART_DIR/voxfree-indicator.desktop"

        # Install GNOME Shell extension (replaces Python indicator on GNOME)
        if [ "$INSTALL_MODE" = "system" ]; then
            EXT_DIR="/usr/share/gnome-shell/extensions/voxfree@voxfree.app"
        else
            EXT_DIR="$ACTUAL_HOME/.local/share/gnome-shell/extensions/voxfree@voxfree.app"
        fi
        if [ -d "$RL_DIR/gnome-shell-extension" ]; then
            mkdir -p "$EXT_DIR"
            cp "$RL_DIR/gnome-shell-extension/"*.js "$RL_DIR/gnome-shell-extension/"*.json "$EXT_DIR/" 2>/dev/null || true
            chmod 644 "$EXT_DIR"/*.json "$EXT_DIR"/*.js 2>/dev/null || true
            if [ "$INSTALL_MODE" != "system" ]; then
                chown -R "$ACTUAL_USER:$ACTUAL_USER" "$EXT_DIR" 2>/dev/null || true
            fi
            if command -v gnome-extensions >/dev/null 2>&1; then
                if [ "$INSTALL_MODE" = "system" ]; then
                    sudo -u "$ACTUAL_USER" gnome-extensions enable voxfree@voxfree.app 2>/dev/null || true
                else
                    gnome-extensions enable voxfree@voxfree.app 2>/dev/null || true
                fi
            fi
            ok "GNOME Shell extension installed to $EXT_DIR"
        fi
    else
        info "Skipping autostart. Run 'voxfree-indicator' manually to start the indicator."
    fi
else
    warn "voxfree-indicator script not found — skipping indicator setup"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n${BOLD}${GREEN}=== ReadLoud TTS Ready ===${RESET}\n\n"
if [ "$LAYOUT" = "thinkpad" ]; then
    printf "  ${CYAN}F9  (✉)${RESET}  → Highlight text → press to read aloud / press again to stop\n"
    printf "  ${CYAN}F11 (✕)${RESET}  → Force-stop at any time\n"
elif [ "$LAYOUT" = "standard" ]; then
    printf "  ${CYAN}Super+Shift+R${RESET}  → Highlight text → press to read / press again to stop\n"
    printf "  ${CYAN}Super+Shift+K${RESET}  → Stop all voice activity\n"
fi
printf "\n  Change voice:   ${YELLOW}voxfree --voice${RESET}\n"
printf "  Replay last:    ${YELLOW}voxfree-readloud-last${RESET} (or via indicator menu)\n"
printf "  Indicator:      ${YELLOW}voxfree-indicator${RESET}\n"
printf "  Quick test:     ${YELLOW}spd-say 'TTS is working'${RESET}\n\n"
