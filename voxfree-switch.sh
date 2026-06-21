#!/bin/bash
# =============================================================================
# voxfree-switch — Switch keyboard shortcut layout
# =============================================================================
# Usage:
#   voxfree --switch                Interactive: shows current, prompts
#   voxfree --switch thinkpad       Switch to ThinkPad (F9/F10/F11)
#   voxfree --switch standard       Switch to Standard (Super+Shift+R/M/K)
#
# System mode (sudo): rewrites /etc/dconf/db/local.d/00-voice-shortcuts,
#   iterates /run/user/* to propagate to all active sessions.
# User mode: applies via gsettings only to current session.
# =============================================================================

if [ -z "$BASH_VERSION" ]; then exec bash "$0" "$@"; fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VOXFREE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Determine if we're running as root/system or user
if [ "$(id -u)" -eq 0 ]; then
    INSTALL_MODE="system"
    ACTUAL_USER="${SUDO_USER:-root}"
    ACTUAL_HOME=$(getent passwd "$ACTUAL_USER" 2>/dev/null | cut -d: -f6)
    ACTUAL_HOME="${ACTUAL_HOME:-/root}"
else
    INSTALL_MODE="user"
    ACTUAL_USER="$USER"
    ACTUAL_HOME="$HOME"
fi

# Source helper
source "$VOXFREE_DIR/lib/keyboard-layout.sh"

# Use appropriate config dir
if [ "$INSTALL_MODE" = "system" ]; then
    CONF_DIR="/etc/voxfree"
else
    CONF_DIR="$ACTUAL_HOME/.config/voxfree"
fi

# Re-source to pick up correct CONF_DIR
source "$VOXFREE_DIR/lib/keyboard-layout.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; RESET='\033[0m'
ok()  { printf "${GREEN}  ✔ %s${RESET}\n" "$*"; }
info(){ printf "${CYAN}  → %s${RESET}\n" "$*"; }
warn(){ printf "${YELLOW}  ⚠ %s${RESET}\n" "$*"; }
fail(){ printf "${RED}  ✘ %s${RESET}\n" "$*"; exit 1; }

# ── Determine layout ─────────────────────────────────────────────────────────
NEW_LAYOUT="${1:-}"

if [ -z "$NEW_LAYOUT" ]; then
    CURRENT="$(read_keyboard_layout)"
    printf "\n${BOLD}Current layout: ${CYAN}%s${RESET}\n\n" "$CURRENT"
    printf "  1) ${BOLD}ThinkPad${RESET}    — F9 / F10 / F11\n"
    printf "  2) ${BOLD}Standard${RESET}   — Super+Shift+R / Super+Shift+M / Super+Shift+K\n\n"
    read -r -p "  Switch to [1/2]: " CHOICE
    case "$CHOICE" in
        1) NEW_LAYOUT="thinkpad" ;;
        2) NEW_LAYOUT="standard" ;;
        *) fail "Invalid choice." ;;
    esac
fi

case "$NEW_LAYOUT" in
    thinkpad|standard) ;;
    *) fail "Invalid layout '$NEW_LAYOUT'. Use 'thinkpad' or 'standard'." ;;
esac

CURRENT="$(read_keyboard_layout)"
if [ "$CURRENT" = "$NEW_LAYOUT" ]; then
    ok "Already on $NEW_LAYOUT layout."
    printf "\n  Current shortcuts: ${BOLD}"
    if [ "$NEW_LAYOUT" = "thinkpad" ]; then
        printf "F9  (Read) / F10  (Dictate) / F11 (Stop)"
    else
        printf "Super+Shift+R  (Read) / Super+Shift+M  (Dictate) / Super+Shift+K  (Stop)"
    fi
    printf "${RESET}\n\n"
    exit 0
fi

# ── Persist layout ────────────────────────────────────────────────────────────
write_keyboard_layout "$NEW_LAYOUT" && ok "Layout saved to $KEYBOARD_LAYOUT_FILE"

# ── Get bindings ──────────────────────────────────────────────────────────────
read -r KEY_READ KEY_DICTATE KEY_STOP <<< "$(layout_keys "$NEW_LAYOUT")"

# ── Update dconf shortcuts ────────────────────────────────────────────────────
USER_ID=$(id -u "$ACTUAL_USER" 2>/dev/null || id -u)
gs() { sudo -u "$ACTUAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_ID}/bus" \
    gsettings "$@" 2>/dev/null || true; }
GBASE="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

# Update current user session via gsettings
KPATH="['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-readloud/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-dictate/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-stop-all/']"

gs set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$KPATH"
gs set "${GBASE}/voxfree-readloud/"      command '/usr/local/bin/voxfree-readloud'
gs set "${GBASE}/voxfree-readloud/"      binding "$KEY_READ"
gs set "${GBASE}/voxfree-dictate/"       command '/usr/local/bin/voxfree-dictate'
gs set "${GBASE}/voxfree-dictate/"       binding "$KEY_DICTATE"
gs set "${GBASE}/voxfree-stop-all/"      command '/usr/local/bin/voxfree-stop-all'
gs set "${GBASE}/voxfree-stop-all/"      binding "$KEY_STOP"
ok "Shortcuts applied to current user session"

# System mode: also update dconf file and propagate to other sessions
if [ "$INSTALL_MODE" = "system" ]; then
    mkdir -p /etc/dconf/db/local.d /etc/dconf/profile
    grep -q "system-db:local" /etc/dconf/profile/user 2>/dev/null || \
        printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user

    cat > /etc/dconf/db/local.d/00-voice-shortcuts << DCONFEOF
# VoxFree shortcuts — layout: ${NEW_LAYOUT} — all users
[org/gnome/settings-daemon/plugins/media-keys]
custom-keybindings=['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-readloud/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-dictate/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-stop-all/']

[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-readloud]
name='Read Aloud (VoxFree TTS)'
command='/usr/local/bin/voxfree-readloud'
binding='${KEY_READ}'

[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-dictate]
name='Start Dictation (VoxFree STT)'
command='/usr/local/bin/voxfree-dictate'
binding='${KEY_DICTATE}'

[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voxfree-stop-all]
name='Stop All Voice (VoxFree)'
command='/usr/local/bin/voxfree-stop-all'
binding='${KEY_STOP}'
DCONFEOF
    dconf update && ok "dconf system shortcuts updated"

    # Propagate to other active user sessions
    for RUNTIME_DIR in /run/user/*/; do
        SESSION_UID=$(basename "$RUNTIME_DIR")
        SESSION_USER=$(getent passwd "$SESSION_UID" 2>/dev/null | cut -d: -f1)
        [ -z "$SESSION_USER" ] && continue

        USER_GS_DBUS="unix:path=${RUNTIME_DIR}bus"
        sudo -u "$SESSION_USER" DBUS_SESSION_BUS_ADDRESS="$USER_GS_DBUS" \
            gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$KPATH" 2>/dev/null && \
            ok "Propagated to user '$SESSION_USER' (UID $SESSION_UID)" || \
            info "Session for '$SESSION_USER' may not be active"
    done
fi

# ── Restart media-keys target ─────────────────────────────────────────────────
sudo -u "$ACTUAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_ID}/bus" \
    systemctl --user start org.gnome.SettingsDaemon.MediaKeys.target 2>/dev/null && \
    ok "gsd-media-keys restarted" || \
    info "Shortcuts will activate on next login"

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n${BOLD}${GREEN}✔ Layout switched to: %s${RESET}\n\n" "$NEW_LAYOUT"
printf "  ${CYAN}Read (TTS):${RESET}     ${BOLD}F9${RESET} / Super+Shift+R\n"
printf "  ${CYAN}Dictate (STT):${RESET}  ${BOLD}F10${RESET} / Super+Shift+M\n"
printf "  ${CYAN}Stop all:${RESET}        ${BOLD}F11${RESET} / Super+Shift+K\n\n"
printf "  Run ${YELLOW}voxfree${RESET} to see this again.\n\n"
