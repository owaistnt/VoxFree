#!/bin/bash
# =============================================================================
# globalize.sh — Make all voice tools truly system-wide on Ubuntu 24.04
# =============================================================================
# Fixes:
#   1. Downloads Whisper model to /var/cache/huggingface/ (shared, all users)
#   2. Updates scripts to use ONLY /var/cache paths (no user-home fallback)
#   3. Sets correct permissions on all shared resources
#   4. Applies dconf shortcuts for ALL currently logged-in GNOME users
#   5. Ensures gsd-media-keys is running for all active sessions
#
# Usage: sudo bash globalize.sh   ← must use bash, not sh
# =============================================================================

# Enforce bash — re-exec with bash if running under sh/dash
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
ok()      { printf "${GREEN}  ✔ %s${RESET}\n" "$*"; }
info()    { printf "${CYAN}  → %s${RESET}\n" "$*"; }
warn()    { printf "${YELLOW}  ⚠ %s${RESET}\n" "$*"; }
fail()    { printf "${RED}  ✘ %s${RESET}\n" "$*"; exit 1; }
section() { printf "\n${BOLD}${CYAN}=== %s ===${RESET}\n" "$*"; }

if [ "$(id -u)" -ne 0 ]; then
    fail "Run as root: sudo bash globalize.sh"
fi

# ── Step 1: Whisper model → /var/cache/huggingface/ (shared) ─────────────────
section "Step 1: Whisper model to shared system cache"

mkdir -p /var/cache/huggingface/hub
chmod 755 /var/cache/huggingface /var/cache/huggingface/hub

MODEL_DIR="/var/cache/huggingface/hub/models--Systran--faster-whisper-tiny.en"

if [ -d "$MODEL_DIR" ]; then
    ok "Model already in /var/cache/huggingface/hub/ ✔"
else
    # Look for model in any user's home cache
    FOUND=""
    for USER_HOME in /home/*/; do
        CANDIDATE="${USER_HOME}.cache/huggingface/hub/models--Systran--faster-whisper-tiny.en"
        if [ -d "$CANDIDATE" ]; then
            FOUND="$CANDIDATE"
            info "Found model in $CANDIDATE — copying to shared location..."
            cp -r "$CANDIDATE" /var/cache/huggingface/hub/
            ok "Model copied from $CANDIDATE"
            break
        fi
    done

    if [ -z "$FOUND" ]; then
        info "Model not found locally — downloading to /var/cache/huggingface/ (~75MB)..."
        HF_HOME=/var/cache/huggingface \
        HF_HUB_DISABLE_TELEMETRY=1 \
            /usr/local/bin/whisper /dev/null \
            --model tiny.en \
            --language en \
            --compute_type int8 \
            --output_format txt \
            --output_dir /tmp \
            --verbose False 2>&1 | grep -v "^$" | tail -5
        ok "Model downloaded to /var/cache/huggingface/"
    fi
fi

# Make readable by all users
chmod -R a+rX /var/cache/huggingface
ok "Permissions set: all users can read model ✔"

# ── Step 2: Update scripts to use ONLY /var/cache paths ──────────────────────
section "Step 2: Updating scripts — removing user-home fallbacks"

# read-selection
cat > /usr/local/bin/read-selection << 'SCRIPTEOF'
#!/bin/bash
# read-selection: Toggle TTS with the same key.
#   Press once  → reads highlighted text aloud
#   Press again → stops reading immediately
VOICE="${MIMIC3_VOICE:-en_UK/apope_low}"

if pgrep -f "mimic3.*--stdout" > /dev/null; then
    pkill -f "mimic3.*--stdout" 2>/dev/null
    pkill -f "aplay" 2>/dev/null
    notify-send "Read Selection" "Stopped." -i audio-volume-muted -t 1500 2>/dev/null
    exit 0
fi

TEXT=$(wl-paste --primary --no-newline 2>/dev/null)
[ -z "$TEXT" ] && TEXT=$(wl-paste --no-newline 2>/dev/null)

if [ -z "$TEXT" ]; then
    notify-send "Read Selection" "No text selected — highlight text first." \
        -i dialog-information -t 2000 2>/dev/null
    exit 1
fi

PREVIEW="${TEXT:0:60}"
[ "${#TEXT}" -gt 60 ] && PREVIEW="${PREVIEW}..."
notify-send "Read Selection" "Reading: $PREVIEW" \
    -i audio-volume-high -t 3000 2>/dev/null

echo "$TEXT" | mimic3 --voice "$VOICE" --stdout 2>/dev/null | aplay -q 2>/dev/null

notify-send "Read Selection" "Done." -i audio-volume-high -t 1500 2>/dev/null
SCRIPTEOF
chmod 755 /usr/local/bin/read-selection
ok "/usr/local/bin/read-selection updated ✔"

# speech-to-type (global paths only)
cat > /usr/local/bin/speech-to-type << 'SCRIPTEOF'
#!/bin/bash
# speech-to-type: Toggle recording with the same key.
#   Press once  → starts recording (auto-stops after 2s silence, max 30s)
#   Press again → force-stops recording immediately
#   Both paths  → transcribes with Whisper tiny.en (int8) → types at cursor
#
# All paths are system-global — works identically for every user.

LOCK="/tmp/speech-to-type.lock"

# ── SECOND PRESS: force-stop ──────────────────────────────────────────────────
if [ -f "$LOCK" ]; then
    SOX_PID=$(cat "$LOCK")
    if kill -0 "$SOX_PID" 2>/dev/null; then
        kill -TERM "$SOX_PID" 2>/dev/null
        notify-send "Speech to Type" "Stopped — transcribing now..." \
            -i system-run -t 5000 2>/dev/null
    else
        rm -f "$LOCK"
        notify-send "Speech to Type" "Already done recording." \
            -i dialog-information -t 2000 2>/dev/null
    fi
    exit 0
fi

# ── FIRST PRESS: start recording ─────────────────────────────────────────────
TMPDIR_BASE=$(mktemp -d /tmp/stt-XXXXXX)
TMPWAV="$TMPDIR_BASE/recording.wav"

# Auto-unmute mic if muted
if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -q MUTED; then
    wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0
    notify-send "Speech to Type" "Microphone was muted — unmuted automatically." \
        -i audio-input-microphone -t 2000 2>/dev/null
fi

notify-send "Speech to Type" "🎙 Recording... (auto-stops after 2s silence, or press again to stop)" \
    -i audio-input-microphone -u low -t 30000 2>/dev/null

sox -d -r 16000 -c 1 -e signed -b 16 "$TMPWAV" \
    silence 1 0.1 3% 1 2.0 3% trim 0 30 &
SOX_PID=$!
echo "$SOX_PID" > "$LOCK"

# Background watcher: transcribes when sox finishes (naturally or force-killed)
(
    wait "$SOX_PID" 2>/dev/null
    sleep 0.3
    rm -f "$LOCK"

    if [ ! -f "$TMPWAV" ] || [ ! -s "$TMPWAV" ]; then
        notify-send "Speech to Type" "No audio captured — was mic muted?" \
            -i dialog-error -t 3000 2>/dev/null
        rm -rf "$TMPDIR_BASE"
        exit 1
    fi

    notify-send "Speech to Type" "Transcribing..." -i system-run -t 15000 2>/dev/null

    # Global model cache — same path for ALL users, no home-directory fallback
    export HF_HOME="/var/cache/huggingface"
    export HF_HUB_OFFLINE=1
    export HF_HUB_DISABLE_TELEMETRY=1

    TRANSCRIPT=$(whisper "$TMPWAV" \
        --model tiny.en \
        --language en \
        --compute_type int8 \
        --output_format txt \
        --output_dir "$TMPDIR_BASE" \
        --verbose False \
        2>/dev/null && cat "$TMPDIR_BASE/recording.txt" 2>/dev/null | tr -d '\n')

    rm -rf "$TMPDIR_BASE"

    if [ -z "$TRANSCRIPT" ]; then
        notify-send "Speech to Type" "Could not transcribe — try speaking louder." \
            -i dialog-error -t 3000 2>/dev/null
        exit 1
    fi

    notify-send "Speech to Type" "Typing: $TRANSCRIPT" \
        -i input-keyboard -t 4000 2>/dev/null

    wtype "$TRANSCRIPT" 2>/dev/null || \
        xdotool type --clearmodifiers "$TRANSCRIPT" 2>/dev/null || \
        notify-send "Speech to Type" "Could not inject text — was a text field focused?" \
            -i dialog-error -t 3000 2>/dev/null
) &
disown
SCRIPTEOF
chmod 755 /usr/local/bin/speech-to-type
ok "/usr/local/bin/speech-to-type updated (global paths only) ✔"

# stop-reading
cat > /usr/local/bin/stop-reading << 'SCRIPTEOF'
#!/bin/bash
pkill -f "mimic3.*--stdout" 2>/dev/null
pkill -f "aplay" 2>/dev/null
exit 0
SCRIPTEOF
chmod 755 /usr/local/bin/stop-reading
ok "/usr/local/bin/stop-reading updated ✔"

# ── Step 3: dconf system-wide shortcuts (all future user sessions) ────────────
section "Step 3: dconf system-wide shortcuts for all users"

mkdir -p /etc/dconf/db/local.d /etc/dconf/profile

if ! grep -q "system-db:local" /etc/dconf/profile/user 2>/dev/null; then
    printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
fi

# Read current layout from existing config (preserve whatever was chosen)
CURRENT_BINDING=$(grep "binding='.*Messenger\|binding='.*Mail\|binding='<Ctrl>" \
    /etc/dconf/db/local.d/00-voice-shortcuts 2>/dev/null | head -1 | \
    grep -o "'.*'" | tr -d "'")

[ -z "$CURRENT_BINDING" ] && CURRENT_BINDING="XF86Messenger"

# Verify dconf file is current
if [ -f /etc/dconf/db/local.d/00-voice-shortcuts ]; then
    ok "dconf shortcuts file exists (layout preserved) ✔"
else
    warn "dconf shortcuts file missing — re-creating with ThinkPad defaults"
    cat > /etc/dconf/db/local.d/00-voice-shortcuts << 'DCONFEOF'
[org/gnome/settings-daemon/plugins/media-keys]
custom-keybindings=['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/read-selection/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/speech-to-type/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/stop-reading/']

[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/read-selection]
name='Read Selected Text (TTS)'
command='/usr/local/bin/read-selection'
binding='XF86Messenger'

[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/speech-to-type]
name='Speech to Type (STT)'
command='/usr/local/bin/speech-to-type'
binding='XF86Go'

[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/stop-reading]
name='Stop Reading (TTS off)'
command='/usr/local/bin/stop-reading'
binding='Cancel'
DCONFEOF
fi

dconf update
ok "dconf database compiled ✔"

# ── Step 4: Apply shortcuts to ALL currently active GNOME sessions ────────────
section "Step 4: Applying shortcuts to all active user sessions"

KEYBINDING_PATH="['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/read-selection/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/speech-to-type/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/stop-reading/']"

# Get bindings from dconf file
KEY_READ=$(grep    "binding=.*read-selection" -A1 /etc/dconf/db/local.d/00-voice-shortcuts | grep "^binding" | grep -o "'.*'" | tr -d "'" | head -1)
KEY_DICTATE=$(grep "binding=.*speech-to-type" -A1 /etc/dconf/db/local.d/00-voice-shortcuts | grep "^binding" | grep -o "'.*'" | tr -d "'" | head -1)
KEY_STOP=$(grep    "binding=.*stop-reading"   -A1 /etc/dconf/db/local.d/00-voice-shortcuts | grep "^binding" | grep -o "'.*'" | tr -d "'" | head -1)

# Parse bindings directly from the file sections
KEY_READ=$(awk '/\[.*read-selection\]/,/\[.*speech-to-type\]/' /etc/dconf/db/local.d/00-voice-shortcuts | grep "^binding" | grep -o "'[^']*'" | tr -d "'")
KEY_DICTATE=$(awk '/\[.*speech-to-type\]/,/\[.*stop-reading\]/' /etc/dconf/db/local.d/00-voice-shortcuts | grep "^binding" | grep -o "'[^']*'" | tr -d "'")
KEY_STOP=$(awk '/\[.*stop-reading\]/,0' /etc/dconf/db/local.d/00-voice-shortcuts | grep "^binding" | grep -o "'[^']*'" | tr -d "'")

[ -z "$KEY_READ" ]    && KEY_READ="XF86Messenger"
[ -z "$KEY_DICTATE" ] && KEY_DICTATE="XF86Go"
[ -z "$KEY_STOP" ]    && KEY_STOP="Cancel"

GBASE="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

# Apply to every user with an active GNOME session
APPLIED=0
SESSION_TMP=$(mktemp)
loginctl list-sessions --no-legend 2>/dev/null | grep -v "^$" > "$SESSION_TMP"

while IFS= read -r SESSION_LINE; do
    SESSION_USER=$(echo "$SESSION_LINE" | awk '{print $3}')
    SESSION_UID=$(id -u "$SESSION_USER" 2>/dev/null) || continue
    DBUS_ADDR="unix:path=/run/user/${SESSION_UID}/bus"

    # Skip if no active DBUS socket (no live GNOME session)
    [ ! -S "/run/user/${SESSION_UID}/bus" ] && continue

    info "Applying shortcuts to user: $SESSION_USER (UID $SESSION_UID)"

    gs() {
        sudo -u "$SESSION_USER" \
            DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
            gsettings "$@" 2>/dev/null || true
    }

    gs set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$KEYBINDING_PATH"
    gs set "${GBASE}/read-selection/" name    "Read Selected Text (TTS)"
    gs set "${GBASE}/read-selection/" command "/usr/local/bin/read-selection"
    gs set "${GBASE}/read-selection/" binding "$KEY_READ"
    gs set "${GBASE}/speech-to-type/" name    "Speech to Type (STT)"
    gs set "${GBASE}/speech-to-type/" command "/usr/local/bin/speech-to-type"
    gs set "${GBASE}/speech-to-type/" binding "$KEY_DICTATE"
    gs set "${GBASE}/stop-reading/"   name    "Stop Reading (TTS off)"
    gs set "${GBASE}/stop-reading/"   command "/usr/local/bin/stop-reading"
    gs set "${GBASE}/stop-reading/"   binding "$KEY_STOP"

    # Start gsd-media-keys via systemd target
    sudo -u "$SESSION_USER" \
        DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
        systemctl --user start org.gnome.SettingsDaemon.MediaKeys.target 2>/dev/null && \
        ok "  gsd-media-keys started for $SESSION_USER ✔" || \
        warn "  gsd-media-keys may need login/logout for $SESSION_USER"

    APPLIED=$((APPLIED + 1))
done < "$SESSION_TMP"
rm -f "$SESSION_TMP"

[ "$APPLIED" -eq 0 ] && \
    warn "No active sessions found — shortcuts will apply on next login" || \
    ok "Shortcuts applied to $APPLIED active session(s) ✔"

# ── Step 5: Set global environment variables ──────────────────────────────────
section "Step 5: Global environment variables"

# Add HF vars to /etc/environment so all processes know where the model is
if ! grep -q "HF_HOME" /etc/environment 2>/dev/null; then
    echo 'HF_HOME=/var/cache/huggingface' >> /etc/environment
    echo 'HF_HUB_OFFLINE=1'              >> /etc/environment
    echo 'HF_HUB_DISABLE_TELEMETRY=1'   >> /etc/environment
    ok "Added HF_HOME, HF_HUB_OFFLINE to /etc/environment ✔"
else
    ok "/etc/environment already has HF settings ✔"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}============================================${RESET}"
echo -e "${BOLD}${GREEN}  GLOBALIZATION COMPLETE${RESET}"
echo -e "${BOLD}${GREEN}============================================${RESET}"
echo ""
echo -e "${BOLD}All users on this machine now have:${RESET}"
echo -e "  ${GREEN}✔${RESET} Whisper model in /var/cache/huggingface/ (read by all users)"
echo -e "  ${GREEN}✔${RESET} Scripts in /usr/local/bin/ (zero user-home dependencies)"
echo -e "  ${GREEN}✔${RESET} dconf system defaults (auto-applied on every user's first login)"
echo -e "  ${GREEN}✔${RESET} HF_HOME=/var/cache/huggingface in /etc/environment"
echo ""
echo -e "${BOLD}Note on GNOME keyboard shortcuts:${RESET}"
echo -e "  GNOME shortcuts are activated per-session (inherent Linux desktop design)."
echo -e "  ${CYAN}New users${RESET}: shortcuts auto-apply on first login via dconf system DB."
echo -e "  ${CYAN}Existing users${RESET}: already applied above to all active sessions."
echo -e "  ${CYAN}After reboot${RESET}: all users get shortcuts automatically."
echo ""
echo -e "  ${YELLOW}Run this script after adding new users to this machine.${RESET}"
