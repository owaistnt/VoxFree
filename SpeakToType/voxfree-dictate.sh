#!/bin/bash
# voxfree-dictate — Start microphone recording (F10)
# Paired with voxfree-dictate-stop (F11) which stops and transcribes

PIDFILE="/tmp/stt-recording.pid"
WAVFILE="/tmp/stt-recording-$$-$(date +%s).wav"
SOUNDS="/usr/share/sounds/freedesktop/stereo"

# Already recording — ignore (prevents key repeat issues)
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    notify-send "VoxFree" "⏺ Already recording — press F11 to stop." \
        -i audio-input-microphone -t 2000 2>/dev/null
    exit 0
fi

# Find active PipeWire/PulseAudio session — works from GNOME shortcuts
# where XDG_RUNTIME_DIR may not be set correctly
if [ -z "$XDG_RUNTIME_DIR" ] || [ ! -S "$XDG_RUNTIME_DIR/pulse/native" ]; then
    for _d in /run/user/*/; do
        [ -S "${_d}pulse/native" ] && export XDG_RUNTIME_DIR="${_d%/}" && break
    done
fi
export PULSE_RUNTIME_PATH="$XDG_RUNTIME_DIR/pulse"

# Unmute mic — ThinkPad LED turns OFF = recording active
wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0 2>/dev/null

# Clean up any previous recording (remove stale PID file, leave WAV files alone)
rm -f "$PIDFILE" 2>/dev/null || :

# Start recording
arecord -D default -f S16_LE -r 16000 -c 1 -q "$WAVFILE" &
REC_PID=$!
echo "$REC_PID" > "$PIDFILE"

# Play start sound
pw-play "$SOUNDS/message-new-instant.oga" 2>/dev/null &

notify-send "VoxFree" "🔴 REC — Speak now!  Press F11 to stop." \
    -i audio-input-microphone -u low -t 60000 2>/dev/null
