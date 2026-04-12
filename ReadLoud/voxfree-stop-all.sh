#!/bin/bash
# voxfree-stop-all — Stop all active VoxFree voice activity
# Stops both TTS (reading) and STT (dictation) if running.
# Bound to: F11 (ThinkPad) or Ctrl+Alt+S (Standard)

SOUNDS="/usr/share/sounds/freedesktop/stereo"
STOPPED=""

# Stop TTS (mimic3 reading)
if pgrep -f "mimic3.*--stdout" >/dev/null 2>&1; then
    pkill -f "mimic3.*--stdout" 2>/dev/null
    pkill -f "aplay" 2>/dev/null
    STOPPED="reading"
fi

# Stop STT — delegate to voxfree-dictate-stop so it transcribes the audio
PIDFILE="/tmp/stt-recording.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    # Notify about TTS stop first if we stopped reading above
    if [ -n "$STOPPED" ]; then
        notify-send "VoxFree" "Stopped: $STOPPED" -i audio-volume-muted -t 1500 2>/dev/null
    fi
    exec /usr/local/bin/voxfree-dictate-stop
fi

if [ -n "$STOPPED" ]; then
    pw-play "$SOUNDS/dialog-information.oga" 2>/dev/null &
    notify-send "VoxFree" "Stopped: $STOPPED" -i audio-volume-muted -t 1500 2>/dev/null
else
    notify-send "VoxFree" "Nothing active." -i dialog-information -t 1500 2>/dev/null
fi
