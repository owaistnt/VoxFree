# 2026-06-22-Layout-Aware-Shortcuts-and-voxfree-switch

## Overview

VoxFree's documentation, scripts, and user-facing messages all defaulted to F9/F10/F11 (ThinkPad hardware keybindings) while the Standard layout (`Super+Shift+R/M/K`) was barely mentioned. This caused confusion for non-ThinkPad users and there was no way to switch layouts after install.

Three problems identified:
1. Documentation only showed ThinkPad shortcuts — Standard users didn't know their bindings
2. No `voxfree --switch` command — switching layouts required re-running the full installer
3. Wrong shortcut in comment — `voxfree-stop-all.sh` listed `Ctrl+Alt+S` which is not bound (should be `Super+Shift+K`)

---

## Implementation

### Design Decisions

| Decision | Rationale |
|----------|-----------|
| Both shortcuts always shown in notifications | No runtime layout detection needed; works for everyone; simple and unambiguous |
| All 3 bindings follow same layout | Mixed layouts (e.g. TTS=ThinkPad, STT=Standard) would be confusing |
| Default layout = `thinkpad` | Backward-compatible — existing installations won't break |
| Config follows the voice file pattern | System: `/etc/voxfree/keyboard-layout`, User: `~/.config/voxfree/keyboard-layout` |
| Layout persistence after install | `readloud.sh` and `speak-to-type.sh` save the chosen layout so `--switch` knows the current state |

### New Files Created (3)

#### `lib/keyboard-layout.sh` — Shared helper

Sourced by all scripts. Three functions:

| Function | Purpose |
|----------|---------|
| `read_keyboard_layout` | Prints current layout from config file. Defaults to `thinkpad`. |
| `write_keyboard_layout <layout>` | Persists `thinkpad` or `standard` to config file. Creates directory if needed. |
| `layout_keys <layout>` | Prints the 3 binding strings for a layout (e.g., `XF86Messenger XF86Go Cancel`). |

Standalone usage: `bash lib/keyboard-layout.sh` prints current layout and keys.

Config location follows the voice file pattern:
- System: `/etc/voxfree/keyboard-layout`
- User: `~/.config/voxfree/keyboard-layout`

#### `voxfree-switch.sh` — `voxfree --switch` implementation

Called by the `voxfree` CLI wrapper.

Workflow:
```
1. Parse $1: "thinkpad" | "standard" | (empty → interactive)
2. Read current layout
3. If empty: show current, interactive prompt
4. Validate: must be "thinkpad" or "standard"
5. write_keyboard_layout $NEW_LAYOUT
6. Detect install mode:
   - System: write dconf shortcuts file, dconf update
   - User: apply via gsettings only
7. For system mode: iterate /run/user/* to apply gsettings to other sessions
8. Restart gsd-media-keys target
9. Print: "Switched to ThinkPad. Current shortcuts: F9 / Super+Shift+R"
```

Multi-user handling:
- **System mode** (`sudo voxfree --switch`): writes `/etc/voxfree/keyboard-layout`, rewrites `/etc/dconf/db/local.d/00-voice-shortcuts`, `dconf update`, iterates `/run/user/*` to apply gsettings to all active sessions
- **User mode** (`voxfree --switch`): writes `~/.config/voxfree/keyboard-layout`, applies via gsettings only to current session, does NOT touch `/etc/dconf/`

This mirrors the existing pattern from `packaging/DEBIAN/postinst` where the script scans `/run/user/*` to sync user-level scripts across sessions.

#### `docs/plan/keyboard-layout-switch-plan.md` — Implementation plan

Dated plan file (2026-06-22) documenting the full scope before implementation.

### Files Modified (17)

#### Scripts (10)

| File | Changes |
|------|---------|
| `install.sh` | Persist layout after sub-scripts run; update summaries to show both shortcuts; update `voxfree` CLI wrapper with `--switch` dispatch |
| `build-deb.sh` | Update embedded `voxfree` wrapper with both shortcuts + `--switch` |
| `ReadLoud/readloud.sh` | Persist layout choice via `write_keyboard_layout` after shortcut application |
| `SpeakToType/speak-to-type.sh` | Persist layout choice via `write_keyboard_layout` after shortcut application |
| `ReadLoud/voxfree-readloud.sh` | Line 38: `press F9` → `press F9 or Super+Shift+R` |
| `SpeakToType/voxfree-dictate.sh` | Lines 11, 40: `press F11` → `press F11 or Super+Shift+K` |
| `SpeakToType/voxfree-dictate-stop.sh` | Lines 13, 26: `Press F10` → `Press F10 or Super+Shift+M` |
| `voxfree-voice.sh` | Line 103: `press F9` → `press F9 or Super+Shift+R` |
| `ReadLoud/voxfree-stop-all.sh` | Line 4: **Fix** `Ctrl+Alt+S` → `Super+Shift+K` (was wrong shortcut) |
| `voxfree-doctor.sh` | Line 213: `F9/F10/F11 bindings` → `keyboard shortcut bindings`; line 434: clarify wev is for ThinkPad key verification |

#### Documentation (7)

| File | Key Changes |
|------|-------------|
| `README.md` | Lines 31, 44, 359, 361, 366, 404: add Standard shortcuts alongside ThinkPad ones; add `--switch` to CLI section; update architecture diagram |
| `ReadLoud/readloud.md` | Lines 3, 13, 23, 24, 147, 158, 160: add both shortcuts everywhere; add `--switch` reference |
| `SpeakToType/speak-to-type.md` | Lines 3, 11, 21, 57, 68-69, 149, 158, 170, 193, 217, 223, 249, 251: add both shortcuts; add `--switch` reference |
| `docs/architecture.md` | Lines 8, 19, 60, 62, 63, 138, 153, 167: add Standard alternatives in parentheses |
| `docs/building-blocks.md` | Lines 101, 117, 192: add Standard alternatives |
| `CLAUDE.md` | Lines 9-10, 38, 101-102: update internal docs with both layouts |
| `CHANGELOG.md` | New 0.3.1 entry |

#### Packaging (2)

| File | Changes |
|------|---------|
| `packaging/DEBIAN/postinst` | Line 25: Fixed `UID` variable name → `RUNID` (UID is readonly in bash) |
| `packaging/changelog` | New 0.3.1 entry |

### Shortcut Layout Reference

| Feature | ThinkPad | Standard |
|---------|----------|----------|
| ReadLoud toggle | `XF86Messenger` (F9) | `<Super><Shift>r` |
| STT start | `XF86Go` (F10) | `<Super><Shift>m` |
| Stop all | `Cancel` (F11) | `<Super><Shift>k` |

---

## Verification

### Syntax check (all 12 scripts pass)
```bash
bash -n lib/keyboard-layout.sh        # ✓
bash -n voxfree-switch.sh              # ✓
bash -n install.sh                     # ✓
bash -n ReadLoud/readloud.sh           # ✓
bash -n SpeakToType/speak-to-type.sh   # ✓
bash -n build-deb.sh                   # ✓
bash -n voxfree-voice.sh               # ✓
bash -n voxfree-doctor.sh              # ✓
bash -n ReadLoud/voxfree-readloud.sh   # ✓
bash -n SpeakToType/voxfree-dictate.sh # ✓
bash -n SpeakToType/voxfree-dictate-stop.sh # ✓
bash -n ReadLoud/voxfree-stop-all.sh   # ✓
```

### Functional test
```bash
# keyboard-layout.sh standalone test
CONF_DIR=/tmp/voxfree-test bash lib/keyboard-layout.sh
# Output: Current layout: thinkpad
#         Keys: XF86Messenger XF86Go Cancel

# Write and read back
CONF_DIR=/tmp/voxfree-test bash -c '
  source lib/keyboard-layout.sh
  echo "Before: $(read_keyboard_layout)"    # thinkpad
  write_keyboard_layout standard
  echo "After:  $(read_keyboard_layout)"    # standard
  echo "Keys:   $(layout_keys standard)"    # <Super><Shift>r <Super><Shift>m <Super><Shift>k
'
```

### Remaining standalone F9/F10/F11 references (expected — in ThinkPad-specific sections)

After all changes, only 17 standalone F9/F10/F11 references remain, all in ThinkPad-specific sections (ThinkPad shortcut tables, ThinkPad-only comments, ThinkPad layout descriptions). This is correct — ThinkPad references should only appear alongside their Standard equivalents.

---

## Key Design Decisions (confirmed)

- **Both shortcuts always shown** — runtime notifications list both options regardless of chosen layout. Avoids complexity of detecting layout at runtime while keeping users informed.
- **No mixed layouts** — all three bindings follow the same layout. Mixed layouts would be confusing.
- **Default is `thinkpad`** — backward-compatible, existing installations won't break.
- **`voxfree --switch` is a CLI command** — shown in `voxfree --help`, dispatched by the `voxfree` wrapper.
- **ThinkPad and Standard are equal** — no preference, both first-class, both documented equally.
- **Config follows the voice file pattern** — system: `/etc/voxfree/keyboard-layout`, user: `~/.config/voxfree/keyboard-layout`.

---

## Plan Reference

The full pre-implementation plan is at: [`docs/plan/keyboard-layout-switch-plan.md`](../../plan/keyboard-layout-switch-plan.md)

## Related Files

| File | Role |
|------|------|
| `lib/keyboard-layout.sh` | Layout persistence helper (new) |
| `voxfree-switch.sh` | `--switch` CLI command (new) |
| `docs/plan/keyboard-layout-switch-plan.md` | Pre-implementation plan (linked above) |
| `releases/voxfree_0.3.1_all.deb` | Package with all changes |
| `CHANGELOG.md` | Version 0.3.1 release notes |
| `packaging/changelog` | Debian-format changelog entry |
