#!/bin/bash
# voxfree-readloud-stop — Force-stop TTS immediately
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh" 2>/dev/null || \
    source "/usr/share/voxfree/lib/state.sh" 2>/dev/null || \
    source "${HOME}/.local/share/voxfree/lib/state.sh" 2>/dev/null || true

state_set_idle
pkill -f "mimic3.*--stdout" 2>/dev/null
pkill -f "aplay" 2>/dev/null
exit 0
