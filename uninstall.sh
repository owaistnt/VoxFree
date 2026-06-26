#!/bin/bash
# =============================================================================
# VoxFree — uninstall.sh
# Remove all VoxFree components from the system
# =============================================================================
# Usage:
#   sudo bash uninstall.sh             (remove system install)
#   sudo bash uninstall.sh --purge     (also remove whisper venv + model cache)
#   bash uninstall.sh --user           (remove user install, no sudo needed)
# =============================================================================

if [ -z "$BASH_VERSION" ]; then exec bash "$0" "$@"; fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { printf "${GREEN}  ✔ %s${RESET}\n" "$*"; }
info()    { printf "${CYAN}  → %s${RESET}\n" "$*"; }
warn()    { printf "${YELLOW}  ⚠ %s${RESET}\n" "$*"; }
section() { printf "\n${BOLD}${CYAN}=== %s ===${RESET}\n" "$*"; }

INSTALL_MODE="system"
PURGE=false

for arg in "$@"; do
    case "$arg" in
        --user)  INSTALL_MODE="user" ;;
        --purge) PURGE=true ;;
    esac
done

if [ "$INSTALL_MODE" = "system" ] && [ "$(id -u)" -ne 0 ]; then
    printf "${RED}System uninstall requires root: sudo bash $0${RESET}\n"
    printf "Or uninstall for current user: bash $0 --user\n"
    exit 1
fi

ACTUAL_USER="${SUDO_USER:-${USER:-$(whoami)}}"
ACTUAL_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)

printf "\n${BOLD}${RED}VoxFree Uninstaller${RESET}\n"
printf "Mode: $INSTALL_MODE%s\n\n" "$([ "$PURGE" = true ] && echo " (--purge)")"

if [ "$INSTALL_MODE" = "system" ]; then
    read -r -p "Remove VoxFree system install? [y/N]: " CONFIRM
    [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ] && { printf "Cancelled.\n"; exit 0; }
else
    read -r -p "Remove VoxFree for user $ACTUAL_USER? [y/N]: " CONFIRM
    [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ] && { printf "Cancelled.\n"; exit 0; }
fi

# ── System uninstall ──────────────────────────────────────────────────────────
if [ "$INSTALL_MODE" = "system" ]; then

    section "Removing /usr/local/bin/voxfree-* commands"
    for CMD in voxfree voxfree-doctor voxfree-readloud voxfree-readloud-stop \
               voxfree-readloud-last voxfree-indicator voxfree-set-voice \
               voxfree-dictate voxfree-dictate-stop; do
        if [ -f "/usr/local/bin/$CMD" ]; then
            rm -f "/usr/local/bin/$CMD"
            ok "Removed /usr/local/bin/$CMD"
        fi
    done
    rm -rf "/usr/local/bin/lib" 2>/dev/null || true
    # Legacy names (backward compat)
    for CMD in read-selection stop-reading speech-start speech-stop speech-to-type; do
        rm -f "/usr/local/bin/$CMD" 2>/dev/null && ok "Removed legacy /usr/local/bin/$CMD" || true
    done

    section "Removing /usr/share/voxfree/"
    if [ -d /usr/share/voxfree ]; then
        rm -rf /usr/share/voxfree
        ok "Removed /usr/share/voxfree/"
    fi

    section "Removing /etc/voxfree/ (voice config)"
    if [ -d /etc/voxfree ]; then
        rm -rf /etc/voxfree
        ok "Removed /etc/voxfree/"
    fi

    section "Reverting speech-dispatcher"
    MODCONF="/etc/speech-dispatcher/modules/mimic3-generic.conf"
    if [ -f "${MODCONF}.bak" ]; then
        mv "${MODCONF}.bak" "$MODCONF"
        ok "Restored $MODCONF from backup"
    elif [ -f "$MODCONF" ]; then
        rm -f "$MODCONF"
        ok "Removed $MODCONF"
    fi
    SCFG="/etc/speech-dispatcher/speechd.conf"
    if grep -q "^DefaultModule mimic3-generic" "$SCFG" 2>/dev/null; then
        sed -i 's/^DefaultModule mimic3-generic/# DefaultModule mimic3-generic/' "$SCFG"
        ok "Commented out DefaultModule mimic3-generic in speechd.conf"
    fi

    section "Removing GNOME shortcuts (dconf)"
    if [ -f /etc/dconf/db/local.d/00-voice-shortcuts ]; then
        rm -f /etc/dconf/db/local.d/00-voice-shortcuts
        dconf update 2>/dev/null && ok "dconf shortcuts removed and database updated"
    fi
    # Remove system-db:local line from dconf profile if we added it
    if grep -q "system-db:local" /etc/dconf/profile/user 2>/dev/null; then
        sed -i '/system-db:local/d' /etc/dconf/profile/user
        ok "Removed system-db:local from dconf profile"
    fi

    section "Removing indicator, extension, and state"
    pkill -f voxfree-indicator 2>/dev/null || true
    rm -f /etc/xdg/autostart/voxfree-indicator.desktop 2>/dev/null || true
    rm -rf /tmp/voxfree 2>/dev/null || true
    if command -v gnome-extensions >/dev/null 2>&1; then
        sudo -u "$ACTUAL_USER" gnome-extensions disable voxfree@voxfree.app 2>/dev/null || true
    fi
    rm -rf /usr/share/gnome-shell/extensions/voxfree@voxfree.app/ 2>/dev/null || true
    ok "Removed indicator + extension + state files"

    section "Removing udev rule"
    if [ -f /etc/udev/rules.d/99-uinput.rules ]; then
        rm -f /etc/udev/rules.d/99-uinput.rules
        udevadm trigger 2>/dev/null
        ok "Removed 99-uinput.rules"
    fi

    section "Removing HF_HOME from /etc/environment"
    if grep -q "HF_HOME\|HF_HUB_DISABLE_TELEMETRY" /etc/environment 2>/dev/null; then
        sed -i '/^HF_HOME\|^HF_HUB_DISABLE_TELEMETRY\|^HF_HUB_OFFLINE/d' /etc/environment
        ok "Removed HF vars from /etc/environment"
    fi

    # Clear user gsettings shortcuts for each active session
    USER_ID=$(id -u "$ACTUAL_USER" 2>/dev/null)
    if [ -S "/run/user/${USER_ID}/bus" ]; then
        DBUS_ADDR="unix:path=/run/user/${USER_ID}/bus"
        sudo -u "$ACTUAL_USER" DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
            gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings '@as []' 2>/dev/null && \
            ok "Cleared GNOME custom keybindings for $ACTUAL_USER" || true
    fi

    if [ "$PURGE" = true ]; then
        section "--purge: Removing large shared data"

        if [ -d /opt/openai-whisper ]; then
            rm -rf /opt/openai-whisper
            ok "Removed /opt/openai-whisper/ (whisper venv, ~520MB)"
        fi
        rm -f /usr/local/bin/whisper 2>/dev/null || true

        if [ -d /var/cache/huggingface ]; then
            rm -rf /var/cache/huggingface
            ok "Removed /var/cache/huggingface/ (model cache, ~145MB)"
        fi
    else
        warn "Whisper venv (/opt/openai-whisper/, ~520MB) retained."
        warn "Model cache (/var/cache/huggingface/, ~145MB) retained."
        warn "Remove them with: sudo bash uninstall.sh --purge"
    fi

# ── User uninstall ────────────────────────────────────────────────────────────
else

    section "Removing ~/.local/bin/voxfree-* commands"
    for CMD in voxfree voxfree-doctor voxfree-readloud voxfree-readloud-stop \
               voxfree-readloud-last voxfree-indicator voxfree-set-voice \
               voxfree-dictate voxfree-dictate-stop whisper; do
        if [ -f "$ACTUAL_HOME/.local/bin/$CMD" ]; then
            rm -f "$ACTUAL_HOME/.local/bin/$CMD"
            ok "Removed ~/.local/bin/$CMD"
        fi
    done
    rm -rf "$ACTUAL_HOME/.local/bin/lib" 2>/dev/null || true

    section "Removing ~/.local/share/voxfree/"
    if [ -d "$ACTUAL_HOME/.local/share/voxfree" ]; then
        rm -rf "$ACTUAL_HOME/.local/share/voxfree"
        ok "Removed ~/.local/share/voxfree/"
    fi

    section "Removing ~/.config/voxfree/ (voice config)"
    if [ -d "$ACTUAL_HOME/.config/voxfree" ]; then
        rm -rf "$ACTUAL_HOME/.config/voxfree"
        ok "Removed ~/.config/voxfree/"
    fi

    section "Removing HF_HOME from ~/.profile"
    if grep -q "VoxFree\|HF_HOME" "$ACTUAL_HOME/.profile" 2>/dev/null; then
        sed -i '/# VoxFree/,+2d' "$ACTUAL_HOME/.profile"
        ok "Removed HF_HOME from ~/.profile"
    fi

    section "Removing indicator, extension, and state"
    pkill -f voxfree-indicator 2>/dev/null || true
    rm -f "$ACTUAL_HOME/.config/autostart/voxfree-indicator.desktop" 2>/dev/null || true
    rm -rf /tmp/voxfree 2>/dev/null || true
    if command -v gnome-extensions >/dev/null 2>&1; then
        gnome-extensions disable voxfree@voxfree.app 2>/dev/null || true
    fi
    rm -rf "$ACTUAL_HOME/.local/share/gnome-shell/extensions/voxfree@voxfree.app/" 2>/dev/null || true
    ok "Removed indicator + extension + state files"

    section "Clearing GNOME shortcuts"
    USER_ID=$(id -u "$ACTUAL_USER" 2>/dev/null)
    if [ -S "/run/user/${USER_ID}/bus" ]; then
        DBUS_ADDR="unix:path=/run/user/${USER_ID}/bus"
        DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
            gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings '@as []' 2>/dev/null && \
            ok "Cleared GNOME custom keybindings" || true
    fi

    if [ "$PURGE" = true ]; then
        section "--purge: Removing user model cache"
        if [ -d "$ACTUAL_HOME/.cache/huggingface" ]; then
            rm -rf "$ACTUAL_HOME/.cache/huggingface"
            ok "Removed ~/.cache/huggingface/"
        fi
        if [ -d "$ACTUAL_HOME/.local/share/voxfree/whisper-venv" ]; then
            rm -rf "$ACTUAL_HOME/.local/share/voxfree/whisper-venv"
            ok "Removed user whisper venv"
        fi
    fi

fi

# ── Done ──────────────────────────────────────────────────────────────────────
printf "\n${BOLD}${GREEN}VoxFree uninstalled.${RESET}\n"
if [ "$PURGE" = false ] && [ "$INSTALL_MODE" = "system" ]; then
    printf "\nTo also remove large shared data:\n"
    printf "  ${YELLOW}sudo bash uninstall.sh --purge${RESET}\n\n"
fi
