#!/bin/bash
# set-speed.sh — Resolve playback speed preset to mimic3 --length-scale value
# Source this file from any script:  source /path/to/lib/set-speed.sh
#
# Provides:
#   SPEED_SCALE   — the numeric --length-scale value (e.g. 1.0, 1.15, 0.85)
#   SPEED_PRESET  — the resolved preset name (slow, default, fast)
#
# Config file: ~/.config/voxfree/speed (user) or /etc/voxfree/speed (system)
# Stored value: "slow", "default", or "fast"
# Default fallback: "default" (1.0)

SPEED_CONF_USER="$HOME/.config/voxfree/speed"
SPEED_CONF_SYSTEM="/etc/voxfree/speed"

_get_speed_config() {
    cat "$SPEED_CONF_USER" 2>/dev/null || cat "$SPEED_CONF_SYSTEM" 2>/dev/null || echo "default"
}

resolve_speed() {
    local preset
    preset=$(_get_speed_config)
    preset=$(echo "$preset" | tr '[:upper:]' '[:lower:]' | xargs)

    case "$preset" in
        slow)     SPEED_PRESET="slow";     SPEED_SCALE="1.15" ;;
        fast)     SPEED_PRESET="fast";     SPEED_SCALE="0.85" ;;
        *)        SPEED_PRESET="default";  SPEED_SCALE="1.0" ;;
    esac
}

resolve_speed
