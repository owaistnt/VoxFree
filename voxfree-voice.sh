#!/bin/bash
# voxfree-voice — Interactive TTS voice selector
# Called by: voxfree --voice
# Sets the voice used by voxfree-readloud

if [ -z "$BASH_VERSION" ]; then exec bash "$0" "$@"; fi

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'
YELLOW='\033[1;33m'; DIM='\033[2m'; RESET='\033[0m'

# Voice config paths
USER_CONF="$HOME/.config/voxfree/voice"
SYS_CONF="/etc/voxfree/voice"

# Read current voice
CURRENT=$(cat "$USER_CONF" 2>/dev/null || cat "$SYS_CONF" 2>/dev/null || echo "en_UK/apope_low")

# Check mimic3 is installed
if ! command -v mimic3 >/dev/null 2>&1; then
    printf "Error: mimic3 is not installed. Run: voxfree --install --tts\n" >&2
    exit 1
fi

# Get all English voices from mimic3 + filter UK/US
printf "\n${BOLD}  VoxFree — Voice Selector${RESET}\n"
printf "  ────────────────────────\n\n"

# Collect en_UK and en_US voices
mapfile -t ALL_VOICES < <(mimic3 --voices 2>/dev/null | grep -E "^en_UK|^en_US" | awk '{print $1}' | sort)

if [ "${#ALL_VOICES[@]}" -eq 0 ]; then
    printf "No English voices found. The base voice en_UK/apope_low is always available.\n"
    ALL_VOICES=("en_UK/apope_low")
fi

# Check which voices are locally installed
is_installed() {
    local VOICE="$1"
    local LANG="${VOICE%%/*}"
    local NAME="${VOICE##*/}"
    [ -d "/usr/share/mycroft/mimic3/voices/$LANG/$NAME" ] || \
    [ -d "$HOME/.local/share/mycroft/mimic3/voices/$LANG/$NAME" ]
}

# Display grouped list
printf "  Available English voices (${YELLOW}★${RESET} = current, ${GREEN}✔${RESET} = installed):\n\n"

declare -A VOICE_IDX
IDX=1
PREV_LANG=""

for VOICE in "${ALL_VOICES[@]}"; do
    LANG="${VOICE%%/*}"
    if [ "$LANG" != "$PREV_LANG" ]; then
        [ -n "$PREV_LANG" ] && printf "\n"
        printf "  ${BOLD}%s:${RESET}\n" "$LANG"
        PREV_LANG="$LANG"
    fi

    STATUS="  "
    [ "$VOICE" = "$CURRENT" ] && STATUS="${YELLOW}★${RESET} "
    is_installed "$VOICE" && STATUS="${STATUS}${GREEN}✔${RESET}" || STATUS="${STATUS}${DIM}↓${RESET}"

    printf "  %s %3d) %s\n" "$STATUS" "$IDX" "$VOICE"
    VOICE_IDX[$IDX]="$VOICE"
    IDX=$((IDX + 1))
done

printf "\n  ${DIM}✔ = installed locally   ↓ = download required   ★ = current${RESET}\n\n"

# Prompt
while true; do
    read -r -p "  Enter number to select (or q to quit): " CHOICE
    case "$CHOICE" in
        q|Q) printf "  No change.\n\n"; exit 0 ;;
        ''|*[!0-9]*) printf "  Please enter a number or q\n"; continue ;;
    esac

    SELECTED="${VOICE_IDX[$CHOICE]:-}"
    if [ -z "$SELECTED" ]; then
        printf "  Invalid choice — enter 1-%d or q\n" "$((IDX - 1))"
        continue
    fi

    break
done

# Download if not installed
if ! is_installed "$SELECTED"; then
    printf "\n  Downloading %s ...\n" "$SELECTED"
    mimic3-download "$SELECTED" 2>/dev/null && \
        printf "  ${GREEN}✔ Downloaded${RESET}\n" || {
        printf "  ${YELLOW}⚠ Download failed. Check internet connection.${RESET}\n"
        exit 1
    }
fi

# Save voice config
mkdir -p "$(dirname "$USER_CONF")"
echo "$SELECTED" > "$USER_CONF"
printf "\n  ${GREEN}✔ Voice set to: %s${RESET}\n" "$SELECTED"
printf "  Stored in: %s\n\n" "$USER_CONF"
printf "  Test it: select some text and press F9\n\n"
