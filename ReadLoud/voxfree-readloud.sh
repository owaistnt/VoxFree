#!/bin/bash
# voxfree-readloud — Read selected text aloud (toggle)
# Press once to start reading, press again to stop.
# Voice is configured via: voxfree --voice
#
# Uses a PID file (/tmp/voxfree-readloud.pid) to track state.
# This avoids false matches from speech-dispatcher and mimic3-server
# processes that also use mimic3 --stdout.

PIDFILE="/tmp/voxfree-readloud.pid"

# Read voice: user config → system config → built-in default
VOICE=$(cat "$HOME/.config/voxfree/voice" 2>/dev/null || \
        cat /etc/voxfree/voice 2>/dev/null || \
        echo "en_UK/apope_low")

# Toggle OFF: PID file exists and process is alive → stop
if [ -f "$PIDFILE" ]; then
    BG_PID=$(cat "$PIDFILE")
    if kill -0 "$BG_PID" 2>/dev/null; then
        kill -TERM "$BG_PID" 2>/dev/null
        # Also kill any mimic3/aplay children of that process
        pkill -P "$BG_PID" 2>/dev/null
        rm -f "$PIDFILE"
        notify-send "VoxFree" "Stopped." -i audio-volume-muted -t 1500 2>/dev/null
        exit 0
    else
        # Stale PID file — process already finished
        rm -f "$PIDFILE"
    fi
fi

# Toggle ON: get ONLY highlighted/selected text (primary selection)
# No clipboard fallback — avoids accidentally reading screen/terminal content
TEXT=$(wl-paste --primary --no-newline 2>/dev/null)

if [ -z "$TEXT" ]; then
    notify-send "VoxFree" "No text selected.\nHighlight text with your mouse, then press F9 or Super+Shift+R." \
        -i dialog-information -t 3000 2>/dev/null
    exit 1
fi

PREVIEW="${TEXT:0:60}"
[ "${#TEXT}" -gt 60 ] && PREVIEW="${PREVIEW}..."
notify-send "VoxFree" "Reading: $PREVIEW" -i audio-volume-high -t 3000 2>/dev/null

# Run in background, save PID, clean up when done
{
    echo "$TEXT" | mimic3 --voice "$VOICE" --stdout 2>/dev/null | aplay -q 2>/dev/null
    rm -f "$PIDFILE"
    notify-send "VoxFree" "Done." -i audio-volume-high -t 1500 2>/dev/null
} &
echo $! > "$PIDFILE"
