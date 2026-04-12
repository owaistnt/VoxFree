#!/bin/bash
# =============================================================================
# VoxFree — install.sh
# Offline voice tools for Ubuntu 24.04 GNOME/Wayland
# =============================================================================
# Sub-projects:
#   ReadLoud    — Text-to-Speech: highlight text → press F9 → hear it read
#   SpeakToType — Speech-to-Text: press F10 → speak → press F11 → types at cursor
#
# Usage:
#   sudo bash install.sh               (interactive)
#   sudo bash install.sh --tts         (ReadLoud only, system-wide)
#   sudo bash install.sh --stt         (SpeakToType only, system-wide)
#   sudo bash install.sh --all         (both, no prompts)
#   bash install.sh --user             (interactive, current user only)
#   bash install.sh --user --tts
#   bash install.sh --user --all
# =============================================================================

if [ -z "$BASH_VERSION" ]; then exec bash "$0" "$@"; fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "0.1.0")

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { printf "${GREEN}  ✔ %s${RESET}\n" "$*"; }
info()    { printf "${CYAN}  → %s${RESET}\n" "$*"; }
warn()    { printf "${YELLOW}  ⚠ %s${RESET}\n" "$*"; }
fail()    { printf "${RED}  ✘ %s${RESET}\n" "$*"; exit 1; }
section() { printf "\n${BOLD}${CYAN}=== %s ===${RESET}\n" "$*"; }

# ── Parse flags ───────────────────────────────────────────────────────────────
INSTALL_MODE="system"
INSTALL_TTS=false
INSTALL_STT=false
POSTINST_MODE=false

for arg in "$@"; do
    case "$arg" in
        --user)          INSTALL_MODE="user" ;;
        --system)        INSTALL_MODE="system" ;;
        --tts)           INSTALL_TTS=true ;;
        --stt)           INSTALL_STT=true ;;
        --all)           INSTALL_TTS=true; INSTALL_STT=true ;;
        --postinst-mode) POSTINST_MODE=true ;;
    esac
done

# Auto user-mode if not root and --system not explicitly requested
if [ "$(id -u)" -ne 0 ] && [ "$INSTALL_MODE" = "system" ]; then
    INSTALL_MODE="user"
fi

# System mode still needs root
if [ "$INSTALL_MODE" = "system" ] && [ "$(id -u)" -ne 0 ]; then
    fail "System install requires root: sudo bash $0\nOr install for current user: bash $0 --user"
fi

export INSTALL_MODE
export ACTUAL_USER="${SUDO_USER:-$(who am i 2>/dev/null | awk '{print $1}')}"
export ACTUAL_USER="${ACTUAL_USER:-$USER}"
export ACTUAL_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)

# Set path variables based on install mode
if [ "$INSTALL_MODE" = "system" ]; then
    BIN_DIR="/usr/local/bin"
    DATA_DIR="/usr/share/voxfree"
    CONF_DIR="/etc/voxfree"
else
    BIN_DIR="$ACTUAL_HOME/.local/bin"
    DATA_DIR="$ACTUAL_HOME/.local/share/voxfree"
    CONF_DIR="$ACTUAL_HOME/.config/voxfree"
fi
export BIN_DIR DATA_DIR CONF_DIR

# ── Interactive menu (when no feature flag given) ─────────────────────────────
if [ "$INSTALL_TTS" = false ] && [ "$INSTALL_STT" = false ] && [ "$POSTINST_MODE" = false ]; then
    printf "\n${BOLD}"
    printf "  ██╗   ██╗ ██████╗ ██╗  ██╗    ███████╗██████╗ ███████╗███████╗\n"
    printf "  ██║   ██║██╔═══██╗╚██╗██╔╝    ██╔════╝██╔══██╗██╔════╝██╔════╝\n"
    printf "  ██║   ██║██║   ██║ ╚███╔╝     █████╗  ██████╔╝█████╗  █████╗  \n"
    printf "  ╚██╗ ██╔╝██║   ██║ ██╔██╗     ██╔══╝  ██╔══██╗██╔══╝  ██╔══╝  \n"
    printf "   ╚████╔╝ ╚██████╔╝██╔╝ ██╗    ██║     ██║  ██║███████╗███████╗\n"
    printf "    ╚═══╝   ╚═════╝ ╚═╝  ╚═╝    ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝\n"
    printf "${RESET}"
    printf "\n  VoxFree %s — Offline voice tools for Ubuntu 24.04\n\n" "$VERSION"

    printf "  ${BOLD}Install for:${RESET}\n"
    printf "  1) Current user only  ${DIM}(no sudo needed for most steps)${RESET}\n"
    printf "  2) All users          ${DIM}(requires sudo — currently: %s)${RESET}\n\n" \
        "$([ "$INSTALL_MODE" = "system" ] && echo "system mode" || echo "user mode")"

    while true; do
        read -r -p "  User scope [1/2]: " SCOPE
        case "$SCOPE" in
            1) INSTALL_MODE="user";   export INSTALL_MODE; break ;;
            2) INSTALL_MODE="system"; export INSTALL_MODE
               [ "$(id -u)" -ne 0 ] && fail "System install needs sudo. Re-run: sudo bash $0"
               break ;;
            *) printf "  Please enter 1 or 2\n" ;;
        esac
    done

    printf "\n  ${BOLD}What to install:${RESET}\n\n"
    printf "  1) ${BOLD}ReadLoud${RESET}    — Highlight text → F9 → hear it read aloud\n\n"
    printf "  2) ${BOLD}SpeakToType${RESET} — F10 → speak → F11 → text at cursor\n\n"
    printf "  3) ${BOLD}Both${RESET}\n\n"

    while true; do
        read -r -p "  Choice [1/2/3]: " C
        case "$C" in
            1) INSTALL_TTS=true; break ;;
            2) INSTALL_STT=true; break ;;
            3) INSTALL_TTS=true; INSTALL_STT=true; break ;;
            *) printf "  Please enter 1, 2, or 3\n" ;;
        esac
    done
fi

# ── Step 1: Install dependencies ─────────────────────────────────────────────
if [ "${VOXFREE_DEPS_DONE:-}" != "1" ] && [ "$POSTINST_MODE" = false ]; then
    section "Installing dependencies"
    DEPS_FLAGS="--$INSTALL_MODE"
    [ "$INSTALL_TTS" = true ] && [ "$INSTALL_STT" = false ] && DEPS_FLAGS="$DEPS_FLAGS --tts"
    [ "$INSTALL_STT" = true ] && [ "$INSTALL_TTS" = false ] && DEPS_FLAGS="$DEPS_FLAGS --stt"
    # shellcheck disable=SC2086
    bash "$SCRIPT_DIR/deps.sh" $DEPS_FLAGS
    export VOXFREE_DEPS_DONE=1
fi

# ── Step 2: Configure ReadLoud ────────────────────────────────────────────────
if [ "$INSTALL_TTS" = true ]; then
    section "Configuring ReadLoud (TTS)"
    [ -f "$SCRIPT_DIR/ReadLoud/readloud.sh" ] || \
        fail "ReadLoud/readloud.sh not found — run from the VoxFree directory."
    bash "$SCRIPT_DIR/ReadLoud/readloud.sh"
fi

# ── Step 3: Configure SpeakToType ─────────────────────────────────────────────
if [ "$INSTALL_STT" = true ]; then
    section "Configuring SpeakToType (STT)"
    [ -f "$SCRIPT_DIR/SpeakToType/speak-to-type.sh" ] || \
        fail "SpeakToType/speak-to-type.sh not found — run from the VoxFree directory."
    bash "$SCRIPT_DIR/SpeakToType/speak-to-type.sh"
fi

# ── Step 4: Install voxfree CLI + voxfree-doctor command ─────────────────────
section "Installing voxfree CLI commands"

# Determine canonical data dir and copy scripts there
if [ "$INSTALL_MODE" = "system" ]; then
    WRAPPER_DATA_DIR="/usr/share/voxfree"
    mkdir -p "$WRAPPER_DATA_DIR"
    # Skip copy if already running from the target directory (e.g. postinst via .deb)
    if [ "$(realpath "$SCRIPT_DIR")" != "$(realpath "$WRAPPER_DATA_DIR")" ]; then
        cp "$SCRIPT_DIR/voxfree-doctor.sh"  "$WRAPPER_DATA_DIR/"
        cp "$SCRIPT_DIR/voxfree-voice.sh"   "$WRAPPER_DATA_DIR/"
        cp "$SCRIPT_DIR/install.sh"         "$WRAPPER_DATA_DIR/"
        cp "$SCRIPT_DIR/deps.sh"            "$WRAPPER_DATA_DIR/"
        cp "$SCRIPT_DIR/uninstall.sh"       "$WRAPPER_DATA_DIR/" 2>/dev/null || true
        cp "$SCRIPT_DIR/VERSION"            "$WRAPPER_DATA_DIR/"
        cp -r "$SCRIPT_DIR/lib"             "$WRAPPER_DATA_DIR/"
        cp -r "$SCRIPT_DIR/ReadLoud"        "$WRAPPER_DATA_DIR/"
        cp -r "$SCRIPT_DIR/SpeakToType"     "$WRAPPER_DATA_DIR/"
        chmod -R 755 "$WRAPPER_DATA_DIR"
    fi
    ok "Scripts installed to $WRAPPER_DATA_DIR"
else
    WRAPPER_DATA_DIR="$ACTUAL_HOME/.local/share/voxfree"
    mkdir -p "$WRAPPER_DATA_DIR"
    cp "$SCRIPT_DIR/voxfree-doctor.sh"  "$WRAPPER_DATA_DIR/"
    cp "$SCRIPT_DIR/voxfree-voice.sh"   "$WRAPPER_DATA_DIR/"
    cp "$SCRIPT_DIR/install.sh"         "$WRAPPER_DATA_DIR/"
    cp "$SCRIPT_DIR/deps.sh"            "$WRAPPER_DATA_DIR/"
    cp "$SCRIPT_DIR/uninstall.sh"       "$WRAPPER_DATA_DIR/" 2>/dev/null || true
    cp "$SCRIPT_DIR/VERSION"            "$WRAPPER_DATA_DIR/"
    cp -r "$SCRIPT_DIR/lib"             "$WRAPPER_DATA_DIR/"
    cp -r "$SCRIPT_DIR/ReadLoud"        "$WRAPPER_DATA_DIR/"
    cp -r "$SCRIPT_DIR/SpeakToType"     "$WRAPPER_DATA_DIR/"
    chown -R "$ACTUAL_USER:$ACTUAL_USER" "$WRAPPER_DATA_DIR" 2>/dev/null || true
    ok "Scripts installed to $WRAPPER_DATA_DIR"
fi

mkdir -p "$BIN_DIR"

# voxfree — unified CLI dispatcher
cat > "$BIN_DIR/voxfree" << WRAPEOF
#!/bin/bash
# voxfree — VoxFree unified CLI
# Auto-generated by install.sh. Do not edit manually.
VOXFREE_HOME="${WRAPPER_DATA_DIR}"
VERSION=\$(cat "\$VOXFREE_HOME/VERSION" 2>/dev/null || echo "0.1.0")

case "\${1:-}" in
    --version|-v)  printf "VoxFree %s\n" "\$VERSION" ;;
    --doctor)      shift; exec bash "\$VOXFREE_HOME/voxfree-doctor.sh" "\$@" ;;
    --voice)       shift; exec bash "\$VOXFREE_HOME/voxfree-voice.sh" "\$@" ;;
    --install)     shift; exec bash "\$VOXFREE_HOME/install.sh" "\$@" ;;
    --uninstall)   shift; exec bash "\$VOXFREE_HOME/uninstall.sh" "\$@" ;;
    --help|-h|"")
        printf "\nVoxFree %s — Offline voice tools for Ubuntu 24.04\n\n" "\$VERSION"
        printf "Usage: voxfree <command>\n\n"
        printf "  --install [--tts|--stt|--all] [--user]  Install or reconfigure\n"
        printf "  --uninstall [--purge] [--user]           Remove VoxFree\n"
        printf "  --doctor [--tts|--stt] [--fix]           Health check\n"
        printf "  --voice                                  Change TTS voice\n"
        printf "  --version                                Show version\n\n"
        printf "Keyboard shortcuts (ThinkPad):\n"
        printf "  F9   — Read selected text aloud (voxfree-readloud)\n"
        printf "  F10  — Start dictation (voxfree-dictate)\n"
        printf "  F11  — Stop reading / Stop dictation\n\n"
        ;;
    *)  printf "Unknown command: %s\nRun: voxfree --help\n" "\$1" >&2; exit 1 ;;
esac
WRAPEOF
chmod 755 "$BIN_DIR/voxfree"
[ "$INSTALL_MODE" != "system" ] && chown "$ACTUAL_USER:$ACTUAL_USER" "$BIN_DIR/voxfree" 2>/dev/null || true
ok "$BIN_DIR/voxfree installed"

# voxfree-doctor — backward-compatible standalone command
cat > "$BIN_DIR/voxfree-doctor" << WRAPEOF
#!/bin/bash
exec bash "${WRAPPER_DATA_DIR}/voxfree-doctor.sh" "\$@"
WRAPEOF
chmod 755 "$BIN_DIR/voxfree-doctor"
[ "$INSTALL_MODE" != "system" ] && chown "$ACTUAL_USER:$ACTUAL_USER" "$BIN_DIR/voxfree-doctor" 2>/dev/null || true
ok "$BIN_DIR/voxfree-doctor installed"

# ── Post-install summary ──────────────────────────────────────────────────────
printf "\n${BOLD}${GREEN}"
printf "╔══════════════════════════════════════╗\n"
printf "║     VoxFree %s Installation Complete ║\n" "$VERSION"
printf "╚══════════════════════════════════════╝\n"
printf "${RESET}\n"

if [ "$INSTALL_TTS" = true ]; then
    printf "${BOLD}ReadLoud (TTS):${RESET}\n"
    printf "  ${CYAN}F9${RESET}  → Highlight text → press to read aloud  [press again to stop]\n"
    printf "  ${CYAN}F11${RESET} → Force-stop at any time\n\n"
fi

if [ "$INSTALL_STT" = true ]; then
    printf "${BOLD}SpeakToType (STT):${RESET}\n"
    printf "  ${CYAN}F10${RESET} → Press to START recording (mic LED turns OFF)\n"
    printf "  Speak clearly for 2+ seconds\n"
    printf "  ${CYAN}F11${RESET} → Press to STOP → transcribes → pastes at cursor\n\n"
    printf "  ${YELLOW}IMPORTANT:${RESET} Log out and back in to activate ydotool auto-paste.\n"
    printf "  Until then, text is in clipboard — press Ctrl+V manually.\n\n"
fi

printf "${BOLD}CLI commands available:${RESET}\n"
printf "  ${YELLOW}voxfree --doctor${RESET}   — run health check (36 points)\n"
printf "  ${YELLOW}voxfree --voice${RESET}    — change TTS voice\n"
printf "  ${YELLOW}voxfree --version${RESET}  — show version\n\n"

printf "${BOLD}Verify installation:${RESET}\n"
printf "  ${YELLOW}voxfree --doctor${RESET}\n\n"

if [ "$INSTALL_MODE" = "user" ]; then
    printf "${YELLOW}Note:${RESET} User install — ensure ~/.local/bin is in your PATH:\n"
    printf "  ${YELLOW}echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc${RESET}\n\n"
fi
