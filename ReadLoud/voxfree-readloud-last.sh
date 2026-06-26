#!/bin/bash
# voxfree-readloud-last — Re-read the last spoken text
# Reads LAST_TEXT from /tmp/voxfree/state and pipes it through mimic3 → aplay.
# Voice is configured via: voxfree --voice

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh" 2>/dev/null || \
    source "/usr/share/voxfree/lib/state.sh" 2>/dev/null || \
    source "${HOME}/.local/share/voxfree/lib/state.sh" 2>/dev/null || true

PIDFILE="/tmp/voxfree-readloud.pid"

if [ -f "$PIDFILE" ]; then
    BG_PID=$(cat "$PIDFILE")
    if kill -0 "$BG_PID" 2>/dev/null; then
        notify-send "VoxFree" "Already reading." -i audio-volume-high -t 1500 2>/dev/null
        exit 1
    fi
fi

TEXT=$(state_get "LAST_TEXT")

if [ -z "$TEXT" ]; then
    notify-send "VoxFree" "No previous text to replay." -i dialog-information -t 2000 2>/dev/null
    exit 1
fi

VOICE=$(cat "$HOME/.config/voxfree/voice" 2>/dev/null || \
        cat /etc/voxfree/voice 2>/dev/null || \
        echo "en_UK/apope_low")

PREVIEW="${TEXT:0:60}"
[ "${#TEXT}" -gt 60 ] && PREVIEW="${PREVIEW}..."
notify-send "VoxFree" "Replaying: $PREVIEW" -i audio-volume-high -t 3000 2>/dev/null

{
    echo "$TEXT" | mimic3 --voice "$VOICE" --stdout 2>/dev/null | aplay -q 2>/dev/null
    rm -f "$PIDFILE"
    state_set_idle
    notify-send "VoxFree" "Done." -i audio-volume-high -t 1500 2>/dev/null
} &
PID=$!
echo $PID > "$PIDFILE"
state_set_playing "$PID" "$TEXT"
