#!/bin/bash
# voxfree-readloud-stop — Force-stop TTS immediately
pkill -f "mimic3.*--stdout" 2>/dev/null
pkill -f "aplay" 2>/dev/null
exit 0
