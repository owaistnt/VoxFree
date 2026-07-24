#!/bin/bash
# voxfree-set-speed — Set the TTS playback speed
# Called by: voxfree --speed
#
# Usage:
#   voxfree-set-speed [slow|default|fast]
#   voxfree-set-speed current          # show current speed

CONF_DIR="$HOME/.config/voxfree"
CONF_FILE="$CONF_DIR/speed"

show_current() {
    source "$(dirname "$0")/lib/set-speed.sh" 2>/dev/null || \
        source "/usr/share/voxfree/lib/set-speed.sh" 2>/dev/null || \
        source "${HOME}/.local/share/voxfree/lib/set-speed.sh" 2>/dev/null || \
        (SPEED_PRESET="default"; SPEED_SCALE="1.0")

    local label
    case "$SPEED_PRESET" in
        slow)     label="Slow (${SPEED_SCALE}x)" ;;
        fast)     label="Fast (${SPEED_SCALE}x)" ;;
        *)        label="Default (${SPEED_SCALE}x)" ;;
    esac
    printf "Playback speed: %s\n" "$label"
    printf "Stored in: %s\n" "$CONF_FILE"
}

if [ "${1:-}" = "current" ]; then
    show_current
    exit 0
fi

SPEED="${1:-}"
if [ -z "$SPEED" ]; then
    printf "Usage: voxfree-set-speed [slow|default|fast]\n" >&2
    printf "       voxfree-set-speed current\n" >&2
    exit 1
fi

SPEED=$(echo "$SPEED" | tr '[:upper:]' '[:lower:]')
case "$SPEED" in
    slow|fast|default) ;;
    *)
        printf "Invalid speed: %s\n" "$SPEED" >&2
        printf "Valid options: slow, default, fast\n" >&2
        exit 1
        ;;
esac

mkdir -p "$CONF_DIR"
echo "$SPEED" > "$CONF_FILE"

show_current
