#!/bin/bash
# voxfree-stop-all — Stop all active VoxFree voice activity
# Stops both TTS (reading) and STT (dictation) if running.
# Bound to: F11 (ThinkPad) or Super+Shift+K (Standard)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh" 2>/dev/null || \
    source "/usr/share/voxfree/lib/state.sh" 2>/dev/null || \
    source "${HOME}/.local/share/voxfree/lib/state.sh" 2>/dev/null || true

SOUNDS="/usr/share/sounds/freedesktop/stereo"
STOPPED=""

# Stop TTS (mimic3 reading)
if pgrep -f "mimic3.*--stdout" >/dev/null 2>&1; then
    pkill -f "mimic3.*--stdout" 2>/dev/null
    pkill -f "aplay" 2>/dev/null
    state_set_idle
    STOPPED="reading"
fi

# Stop STT — check if any stt-recording WAV file is being written to
# Uses fuser to detect active file handles, more reliable than PID checks
STT_ACTIVE=false
for WAV in /tmp/stt-recording-*.wav; do
    [ -f "$WAV" ] && fuser "$WAV" >/dev/null 2>&1 && STT_ACTIVE=true && break
done

if [ "$STT_ACTIVE" = true ]; then
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
