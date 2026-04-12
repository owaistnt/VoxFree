#!/bin/bash
# verify-global.sh — Quick check that everything is properly global
# Run without sudo: bash ~/verify-global.sh

PASS=0; FAIL=0
ok()   { echo "  ✔ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✘ $*"; FAIL=$((FAIL+1)); }
section() { echo ""; echo "── $* ──────────────────────────────"; }

section "Whisper model (global)"
[ -d "/var/cache/huggingface/hub/models--Systran--faster-whisper-tiny.en" ] && \
    ok "Model in /var/cache/huggingface/hub/ ✔" || \
    fail "Model NOT in /var/cache/huggingface/ — run sudo bash ~/globalize.sh"

[ -r "/var/cache/huggingface/hub/models--Systran--faster-whisper-tiny.en" ] && \
    ok "Model is readable by all users ✔" || \
    fail "Model not readable — check permissions"

section "Scripts (global, no home-dir references)"
for SCRIPT in read-selection speech-to-type stop-reading; do
    [ -x "/usr/local/bin/$SCRIPT" ] && ok "$SCRIPT installed ✔" || fail "$SCRIPT missing"
    grep -q '\$HOME' /usr/local/bin/speech-to-type 2>/dev/null && \
        fail "speech-to-type still has \$HOME reference" || \
        ok "speech-to-type has no \$HOME references ✔"
    break
done

section "Global environment (/etc/environment)"
grep -q "HF_HOME=/var/cache/huggingface" /etc/environment 2>/dev/null && \
    ok "HF_HOME=/var/cache/huggingface ✔" || fail "HF_HOME not in /etc/environment"
grep -q "HF_HUB_OFFLINE=1" /etc/environment 2>/dev/null && \
    ok "HF_HUB_OFFLINE=1 ✔" || fail "HF_HUB_OFFLINE not set"

section "dconf system defaults (all future users)"
[ -f "/etc/dconf/db/local.d/00-voice-shortcuts" ] && \
    ok "dconf shortcuts file exists ✔" || fail "dconf shortcuts file missing"
grep -q "system-db:local" /etc/dconf/profile/user 2>/dev/null && \
    ok "dconf profile includes system-db ✔" || fail "dconf profile not configured"

section "Current session shortcuts"
BINDINGS=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings 2>/dev/null)
echo "  Registered: $BINDINGS"
echo "$BINDINGS" | grep -q "read-selection" && ok "read-selection registered ✔" || fail "read-selection NOT registered"
echo "$BINDINGS" | grep -q "speech-to-type" && ok "speech-to-type registered ✔" || fail "speech-to-type NOT registered"

section "gsd-media-keys daemon"
pgrep -x gsd-media-keys > /dev/null && \
    ok "gsd-media-keys running ✔" || fail "gsd-media-keys NOT running"

section "End-to-end TTS test"
echo "Global test" | mimic3 --voice en_UK/apope_low --stdout 2>/dev/null | aplay -q 2>/dev/null && \
    ok "TTS audio output works ✔" || fail "TTS failed"

section "End-to-end STT test (transcription only)"
TMPD=$(mktemp -d)
echo "global system test" | mimic3 --voice en_UK/apope_low --stdout 2>/dev/null > "$TMPD/t.wav"
RESULT=$(HF_HOME=/var/cache/huggingface HF_HUB_OFFLINE=1 \
    whisper "$TMPD/t.wav" --model tiny.en --language en \
    --compute_type int8 --output_format txt --output_dir "$TMPD" \
    --verbose False 2>/dev/null && cat "$TMPD/t.txt" 2>/dev/null | tr -d '\n')
rm -rf "$TMPD"
[ -n "$RESULT" ] && ok "STT transcription: \"$RESULT\" ✔" || fail "STT transcription failed"

echo ""
echo "════════════════════════════════"
echo "  PASSED: $PASS   FAILED: $FAIL"
echo "════════════════════════════════"
[ "$FAIL" -eq 0 ] && echo "  All checks passed — fully global ✔" || \
    echo "  Some checks failed — run: sudo bash ~/globalize.sh"
