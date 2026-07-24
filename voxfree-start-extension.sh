#!/bin/bash
# voxfree-start-extension — Enable the GNOME Shell extension
# Called by: voxfree --start-extension

UUID="voxfree@voxfree.app"

if ! command -v gnome-extensions >/dev/null 2>&1; then
    echo "Error: gnome-extensions not found. Requires GNOME Shell." >&2
    exit 1
fi

if gnome-extensions list 2>/dev/null | grep -q "$UUID"; then
    STATE=$(gnome-extensions list --details 2>/dev/null | grep -A1 "$UUID" | tail -1 | awk '{print $NF}')
    if [ "$STATE" = "enabled" ]; then
        echo "Extension $UUID is already enabled."
        exit 0
    fi
fi

gnome-extensions enable "$UUID" && echo "Extension $UUID enabled." || echo "Failed to enable extension." >&2
