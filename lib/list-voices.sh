#!/bin/bash
# list-voices.sh — List all Mimic 3 voices with status
# Called by: voxfree-indicator, voxfree-voice.sh
# Output: INDEX|voice_name|is_installed|is_current
#
# Usage: source /path/to/list-voices.sh

# Read current voice
CURRENT=""
if [ -f "$HOME/.config/voxfree/voice" ]; then
    CURRENT=$(cat "$HOME/.config/voxfree/voice" 2>/dev/null)
elif [ -f "/etc/voxfree/voice" ]; then
    CURRENT=$(cat "/etc/voxfree/voice" 2>/dev/null)
fi
CURRENT="${CURRENT:-en_UK/apope_low}"

# Check if mimic3 is installed
if ! command -v mimic3 >/dev/null 2>&1; then
    echo "1|en_UK/apope_low|0|1"
    return 0 2>/dev/null || exit 0
fi

# Check if a voice is installed locally
_is_installed() {
    local VOICE="$1"
    local LANG="${VOICE%%/*}"
    local NAME="${VOICE##*/}"
    [ -d "/usr/share/mycroft/mimic3/voices/$LANG/$NAME" ] || \
    [ -d "$HOME/.local/share/mycroft/mimic3/voices/$LANG/$NAME" ]
}

# Get all English voices
mapfile -t VOICES < <(mimic3 --voices 2>/dev/null | grep -E "^en_UK|^en_US" | awk '{print $1}' | sort)

if [ "${#VOICES[@]}" -eq 0 ]; then
    VOICES=("en_UK/apope_low")
fi

IDX=1
for VOICE in "${VOICES[@]}"; do
    INSTALLED=0
    if _is_installed "$VOICE"; then
        INSTALLED=1
    fi

    IS_CURRENT=0
    if [ "$VOICE" = "$CURRENT" ]; then
        IS_CURRENT=1
    fi

    echo "${IDX}|${VOICE}|${INSTALLED}|${IS_CURRENT}"
    IDX=$((IDX + 1))
done
