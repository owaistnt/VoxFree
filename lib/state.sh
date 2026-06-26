#!/bin/bash
# VoxFree state file library
# Provides atomic state file ops for core↔UI decoupling.
# Source this file from any core script:  source /path/to/lib/state.sh
#
# State file format (/tmp/voxfree/state):
#   STATE=idle|playing
#   PID=<process_id>
#   LAST_TEXT=<last_read_text>
#   STARTED_AT=<unix_timestamp>

STATE_DIR="/tmp/voxfree"
STATE_FILE="$STATE_DIR/state"
STATE_TMP="${STATE_FILE}.tmp"

state_init() {
    mkdir -p "$STATE_DIR"
    if [ ! -f "$STATE_FILE" ]; then
        printf 'STATE=idle\nPID=\nLAST_TEXT=\nSTARTED_AT=\n' > "$STATE_FILE"
    fi
}

state_set() {
    local key="$1" val="$2"
    state_init
    if grep -q "^${key}=" "$STATE_FILE" 2>/dev/null; then
        sed "s|^${key}=.*|${key}=${val}|" "$STATE_FILE" > "$STATE_TMP"
    else
        cp "$STATE_FILE" "$STATE_TMP"
        printf '%s=%s\n' "$key" "$val" >> "$STATE_TMP"
    fi
    mv "$STATE_TMP" "$STATE_FILE"
}

state_get() {
    local key="$1"
    grep "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d= -f2- || true
}

state_set_playing() {
    local pid="${1:-$$}" text="${2:-}"
    state_init
    cat > "$STATE_TMP" << STATEEOF
STATE=playing
PID=${pid}
LAST_TEXT=${text}
STARTED_AT=$(date +%s)
STATEEOF
    mv "$STATE_TMP" "$STATE_FILE"
}

state_set_idle() {
    state_init
    {
        grep -v '^STATE=\|^PID=\|^STARTED_AT=' "$STATE_FILE" 2>/dev/null || true
        printf 'STATE=idle\nPID=\nSTARTED_AT=\n'
    } > "$STATE_TMP"
    mv "$STATE_TMP" "$STATE_FILE"
}

state_cleanup() {
    rm -f "$STATE_FILE" "$STATE_TMP"
    rmdir "$STATE_DIR" 2>/dev/null || true
}
