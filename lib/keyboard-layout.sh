#!/bin/bash
# =============================================================================
# keyboard-layout.sh — Shared helper for keyboard layout persistence
# =============================================================================
# Reads/writes the chosen keyboard layout (thinkpad or standard)
# Config location follows the same pattern as the voice config:
#   System: /etc/voxfree/keyboard-layout
#   User:   ~/.config/voxfree/keyboard-layout
#
# Functions:
#   read_keyboard_layout   — prints current layout (defaults to "thinkpad")
#   write_keyboard_layout  — persists the layout choice
#   layout_keys            — returns bindings for a layout
# =============================================================================

if [ -n "${BASH_SOURCE:-}" ]; then
    # Sourced — CONF_DIR may or may not be set
    : "${CONF_DIR:=$HOME/.config/voxfree}"
else
    # Executed directly — determine CONF_DIR from caller or default
    CONF_DIR="${CONF_DIR:-$HOME/.config/voxfree}"
fi

KEYBOARD_LAYOUT_FILE="$CONF_DIR/keyboard-layout"

# ── read_keyboard_layout ──────────────────────────────────────────────────────
# Prints the current layout: "thinkpad" or "standard"
# Falls back to "thinkpad" if file doesn't exist or is empty/invalid.
#
# Usage:
#   read_keyboard_layout   # prints "thinkpad" or "standard"
read_keyboard_layout() {
    local LAYOUT
    LAYOUT=$(cat "$KEYBOARD_LAYOUT_FILE" 2>/dev/null | tr -d '[:space:]')
    case "$LAYOUT" in
        thinkpad|standard) printf '%s' "$LAYOUT" ;;
        *) printf '%s' 'thinkpad' ;;
    esac
}

# ── write_keyboard_layout ─────────────────────────────────────────────────────
# Persists the chosen layout to the config file.
#
# Usage:
#   write_keyboard_layout thinkpad
#   write_keyboard_layout standard
write_keyboard_layout() {
    local NEW_LAYOUT="$1"
    case "$NEW_LAYOUT" in
        thinkpad|standard)
            local CONF_DIR_PARENT
            CONF_DIR_PARENT=$(dirname "$KEYBOARD_LAYOUT_FILE")
            mkdir -p "$CONF_DIR_PARENT"
            printf '%s\n' "$NEW_LAYOUT" > "$KEYBOARD_LAYOUT_FILE"
            return 0
            ;;
        *)
            printf '%s\n' "Error: invalid layout '$NEW_LAYOUT' — use 'thinkpad' or 'standard'" >&2
            return 1
            ;;
    esac
}

# ── layout_keys ───────────────────────────────────────────────────────────────
# Returns the three GNOME shortcut bindings for a given layout.
#
# Usage:
#   layout_keys thinkpad   → prints "XF86Messenger XF86Go Cancel"
#   layout_keys standard   → prints "<Super><Shift>r <Super><Shift>m <Super><Shift>k"
layout_keys() {
    local LAYOUT="$1"
    case "$LAYOUT" in
        thinkpad)
            printf '%s\n' 'XF86Messenger XF86Go Cancel'
            ;;
        standard)
            printf '%s\n' '<Super><Shift>r <Super><Shift>m <Super><Shift>k'
            ;;
        *)
            printf '%s\n' ''
            return 1
            ;;
    esac
}

# ── Standalone test ───────────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    printf "Current layout: %s\n" "$(read_keyboard_layout)"
    printf "Keys: %s\n" "$(layout_keys "$(read_keyboard_layout)")"
fi
