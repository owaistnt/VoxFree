#!/bin/bash
# voxfree-set-voice — Set the active TTS voice
# Called by: voxfree-indicator when user selects a voice
# Writes voice to ~/.config/voxfree/voice
#
# Usage: voxfree-set-voice <voice_name>

VOICE="${1:-}"
if [ -z "$VOICE" ]; then
    echo "Usage: voxfree-set-voice <voice_name>" >&2
    exit 1
fi

USER_CONF="$HOME/.config/voxfree/voice"
mkdir -p "$(dirname "$USER_CONF")"
echo "$VOICE" > "$USER_CONF"
