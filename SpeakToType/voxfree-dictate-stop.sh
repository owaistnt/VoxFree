#!/bin/bash
# voxfree-dictate-stop — Stop recording, transcribe, paste (F11)

PIDFILE="/tmp/stt-recording.pid"
WAVFILE="/tmp/stt-recording.wav"
DEBUG_WAV="/tmp/last-stt-recording.wav"
SOUNDS="/usr/share/sounds/freedesktop/stereo"

# Not recording — nothing to stop
if [ ! -f "$PIDFILE" ]; then
    notify-send "VoxFree" "ℹ Not recording. Press F10 to start." \
        -i dialog-information -t 2000 2>/dev/null
    exit 0
fi

REC_PID=$(cat "$PIDFILE")

# Check recording is long enough (need at least 1 second)
if [ -f "$WAVFILE" ]; then
    RECORDED_BYTES=$(stat -c%s "$WAVFILE" 2>/dev/null || echo 0)
    # 16000 samples/s × 2 bytes = 32000 bytes/s → 1s = 32000 bytes
    if [ "$RECORDED_BYTES" -lt 32000 ]; then
        notify-send "VoxFree" \
            "⚠ Too short! Keep F10 held down longer while speaking." \
            -i dialog-warning -t 3000 2>/dev/null
        kill -TERM "$REC_PID" 2>/dev/null
        rm -f "$PIDFILE"
        exit 0
    fi
fi

# Stop recording
kill -TERM "$REC_PID" 2>/dev/null
rm -f "$PIDFILE"
sleep 0.3   # let arecord finalize the WAV header

pw-play "$SOUNDS/complete.oga" 2>/dev/null &

# Save debug copy
[ -f "$WAVFILE" ] && cp "$WAVFILE" "$DEBUG_WAV" 2>/dev/null

if [ ! -f "$WAVFILE" ] || [ ! -s "$WAVFILE" ]; then
    pw-play "$SOUNDS/dialog-error.oga" 2>/dev/null &
    notify-send "VoxFree" "❌ No audio captured." \
        -i dialog-error -t 4000 2>/dev/null
    exit 1
fi

notify-send "VoxFree" "⏳ Transcribing..." \
    -i system-run -t 15000 2>/dev/null

# Noise reduction: use first 0.5s as noise profile
TMPDIR_BASE=$(mktemp -d /tmp/stt-XXXXXX)
CLEAN_WAV="$TMPDIR_BASE/clean.wav"

if sox "$WAVFILE" -n trim 0 0.5 noiseprof "$TMPDIR_BASE/noise.prof" 2>/dev/null; then
    sox "$WAVFILE" "$CLEAN_WAV" noisered "$TMPDIR_BASE/noise.prof" 0.15 2>/dev/null || \
        cp "$WAVFILE" "$CLEAN_WAV"
else
    cp "$WAVFILE" "$CLEAN_WAV"
fi

export HF_HOME="/var/cache/huggingface"
export HF_HUB_OFFLINE=1
export HF_HUB_DISABLE_TELEMETRY=1

whisper "$CLEAN_WAV" \
    --model base.en --language en --compute_type int8 \
    --output_format txt --output_dir "$TMPDIR_BASE" \
    --verbose False >/dev/null 2>&1

TRANSCRIPT=$(cat "$TMPDIR_BASE/clean.txt" 2>/dev/null | tr -d '\n' | xargs)
rm -rf "$TMPDIR_BASE"

if [ -z "$TRANSCRIPT" ]; then
    pw-play "$SOUNDS/dialog-error.oga" 2>/dev/null &
    notify-send "VoxFree" \
        "❌ Nothing recognised.\nSpeak louder and closer to mic." \
        -i dialog-error -t 5000 2>/dev/null
    exit 1
fi

PREVIEW="${TRANSCRIPT:0:60}"
[ "${#TRANSCRIPT}" -gt 60 ] && PREVIEW="${PREVIEW}..."

# Copy to clipboard (always — works for all apps)
echo -n "$TRANSCRIPT" | wl-copy 2>/dev/null

# Smart paste: detect if a terminal is focused and use correct paste key
# Terminals use Ctrl+Shift+V; all other apps use Ctrl+V
sleep 0.3
PASTED=false

WIN_CLASS=$(DISPLAY=:0 xdotool getactivewindow getwindowclassname 2>/dev/null | tr '[:upper:]' '[:lower:]')
TERMINAL_CLASSES="gnome-terminal|tilix|kitty|alacritty|xterm|urxvt|konsole|guake|terminator|st-|foot|wezterm"
if echo "${WIN_CLASS:-}" | grep -qE "$TERMINAL_CLASSES"; then
    # Terminal focused (Claude CLI, bash, etc.) — use Ctrl+Shift+V
    PASTE_KEY="ctrl+shift+v"
    PASTE_LABEL="terminal"
else
    # Regular app — use Ctrl+V
    PASTE_KEY="ctrl+v"
    PASTE_LABEL="app"
fi

if command -v ydotool >/dev/null 2>&1; then
    ydotool key "$PASTE_KEY" 2>/dev/null && PASTED=true
fi
if [ "$PASTED" = false ] && command -v xdotool >/dev/null 2>&1; then
    DISPLAY=:0 xdotool key --clearmodifiers "$PASTE_KEY" 2>/dev/null && PASTED=true
fi

if [ "$PASTED" = true ]; then
    notify-send "VoxFree" "✅ Typed in $PASTE_LABEL: $PREVIEW" \
        -i input-keyboard -t 4000 2>/dev/null
else
    # Clipboard fallback — user presses the right paste key manually
    HINT="Ctrl+V (apps) or Ctrl+Shift+V (terminal)"
    notify-send "VoxFree" "📋 Copied — paste with $HINT:\n$PREVIEW" \
        -i edit-paste -t 10000 2>/dev/null
fi
