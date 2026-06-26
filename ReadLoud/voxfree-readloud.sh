#!/bin/bash
# voxfree-readloud — Read selected text aloud (toggle)
# Press once to start reading, press again to stop.
# Voice is configured via: voxfree --voice
#
# Uses a PID file (/tmp/voxfree-readloud.pid) to track state.
# This avoids false matches from speech-dispatcher and mimic3-server
# processes that also use mimic3 --stdout.
# Also writes /tmp/voxfree/state for UI consumers (indicator, etc.).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh" 2>/dev/null || \
    source "/usr/share/voxfree/lib/state.sh" 2>/dev/null || \
    source "${HOME}/.local/share/voxfree/lib/state.sh" 2>/dev/null || true

PIDFILE="/tmp/voxfree-readloud.pid"
VOXFREE_DIR="/tmp/voxfree"

# Read voice: user config → system config → built-in default
VOICE=$(cat "$HOME/.config/voxfree/voice" 2>/dev/null || \
        cat /etc/voxfree/voice 2>/dev/null || \
        echo "en_UK/apope_low")

# Toggle OFF: PID file exists and process is alive → stop
if [ -f "$PIDFILE" ]; then
    BG_PID=$(cat "$PIDFILE")
    if kill -0 "$BG_PID" 2>/dev/null; then
        kill -TERM "$BG_PID" 2>/dev/null
        pkill -P "$BG_PID" 2>/dev/null
        rm -f "$PIDFILE"
        state_set_idle
        notify-send "VoxFree" "Stopped." -i audio-volume-muted -t 1500 2>/dev/null
        exit 0
    else
        rm -f "$PIDFILE"
        state_set_idle
    fi
fi

# Toggle ON: get ONLY highlighted/selected text (primary selection)
TEXT=$(wl-paste --primary --no-newline 2>/dev/null)

if [ -z "$TEXT" ]; then
    notify-send "VoxFree" "No text selected.\nHighlight text with your mouse, then press F9 or Super+Shift+R." \
        -i dialog-information -t 3000 2>/dev/null
    exit 1
fi

PREVIEW="${TEXT:0:60}"
[ "${#TEXT}" -gt 60 ] && PREVIEW="${PREVIEW}..."
notify-send "VoxFree" "Reading: $PREVIEW" -i audio-volume-high -t 3000 2>/dev/null

{
    echo "$TEXT" | mimic3 --voice "$VOICE" --stdout 2>/dev/null | aplay -q 2>/dev/null
    rm -f "$PIDFILE"
    state_set_idle
    notify-send "VoxFree" "Done." -i audio-volume-high -t 1500 2>/dev/null
} &
PID=$!
echo $PID > "$PIDFILE"
state_set_playing "$PID" "$TEXT"
