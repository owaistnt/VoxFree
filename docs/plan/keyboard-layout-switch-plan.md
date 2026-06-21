# Keyboard Layout-Aware Shortcuts + `voxfree --switch`

**Date: 2026-06-22**

## Context

VoxFree currently uses F9/F10/F11 (ThinkPad hardware keybindings: `XF86Messenger`, `XF86Go`, `Cancel`) in its documentation, scripts, and user-facing messages. While the code also supports `Super+Shift+R/M/K` as the Standard layout, these are barely mentioned — only in the README shortcuts table. The install scripts, runtime `notify-send` messages, and sub-docs all default to F9/F10/F11 as if it's the only option.

This creates confusion:
- ThinkPad users see F9/F10/F11 and never learn about the Standard alternative
- Standard desktop users see F9/F10/F11 in notifications and wonder which keys to press
- There's no way to switch between layouts after install — users must re-run the full installer
- The `Ctrl+Alt+S` shortcut listed in `voxfree-stop-all.sh` comment is wrong (it's `Super+Shift+K`)

The fix: treat both ThinkPad and Standard layouts as first-class, persist the choice, and provide a `voxfree --switch` command.

---

## Design

### Layout Persistence

Store the chosen layout in a config file that follows the same pattern as the voice config:

| Mode | Config path |
|------|-------------|
| System | `/etc/voxfree/keyboard-layout` |
| User | `~/.config/voxfree/keyboard-layout` |

Contents: `thinkpad` or `standard` (single line, no whitespace).
Default: `thinkpad` (backward-compatible).

### Layout Binding Strings

| Feature | ThinkPad | Standard |
|---------|----------|----------|
| ReadLoud toggle | `XF86Messenger` (F9) | `<Super><Shift>r` |
| STT start | `XF86Go` (F10) | `<Super><Shift>m` |
| Stop all | `Cancel` (F11) | `<Super><Shift>k` |

All three bindings follow the same layout. No mixed layouts.

### `voxfree --switch` Command

```
voxfree --switch           → interactive: shows current, prompts for choice
voxfree --switch thinkpad  → switch to ThinkPad (F9/F10/F11)
voxfree --switch standard  → switch to Standard (Super+Shift+R/M/K)
```

Behavior:
1. Validates input (`thinkpad` or `standard`)
2. Persists layout to config file
3. Rewrites `/etc/dconf/db/local.d/00-voice-shortcuts` (all 3 bindings) — or applies via gsettings for user mode
4. `dconf update` (system mode)
5. Restarts `gsd-media-keys` target
6. System mode: iterates `/run/user/*` to apply gsettings to all active user sessions (same pattern as `postinst`)
7. Prints summary: "Switched to ThinkPad. Current shortcuts: F9 / Super+Shift+R"

### Runtime Notifications — Show Both

Every `notify-send` that mentions a shortcut shows **both** options:
```
"press F9 or Super+Shift+R"
"press F11 or Super+Shift+K to stop"
"press F10 or Super+Shift+M to start"
```

Rationale: no layout detection needed at runtime; works for everyone regardless of chosen layout; simple and unambiguous.

---

## New Files (2)

### `lib/keyboard-layout.sh` — Shared helper

Functions (sourced by scripts):

| Function | Purpose |
|----------|---------|
| `read_keyboard_layout` | Prints current layout from config file. Defaults to `thinkpad`. |
| `write_keyboard_layout <layout>` | Persists `thinkpad` or `standard` to config file. Creates directory if needed. |
| `layout_keys <layout>` | Prints the 3 binding strings for a layout (e.g., `XF86Messenger XF86Go Cancel`). |

Standalone usage: `bash lib/keyboard-layout.sh` prints current layout and keys.

### `voxfree-switch.sh` — `--switch` implementation

Called by `voxfree --switch` from the `voxfree` CLI wrapper.

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

---

## Modified Files (17)

### Scripts

#### 1. `install.sh`

| Location | Change |
|----------|--------|
| Header (lines 7-8) | `press F9` → `press F9 / Super+Shift+R` in script header comments |
| Interactive menu (line 106-107) | `F9` → `F9 / Super+Shift+R`, `F10` → `F10 / Super+Shift+M`, `F11` → `F11 / Super+Shift+K` |
| Line 137 (after readloud.sh) | Source `lib/keyboard-layout.sh`, persist layout via `write_keyboard_layout` |
| Line 145 (after speak-to-type.sh) | Source `lib/keyboard-layout.sh`, persist layout |
| `voxfree` CLI wrapper (lines 209-212) | Replace hardcoded "Keyboard shortcuts (ThinkPad)" with both options |
| Post-install summary (lines 237-250) | Show both shortcut options in summary |

#### 2. `build-deb.sh`

| Location | Change |
|----------|--------|
| Lines 85-88 (embedded voxfree wrapper) | Replace hardcoded ThinkPad shortcuts with both options |

#### 3. `ReadLoud/readloud.sh`

| Location | Change |
|----------|--------|
| After shortcut application (around line 213) | Source `lib/keyboard-layout.sh`, call `write_keyboard_layout "$LAYOUT"` to persist the user's choice |
| Summary block (lines 220-228) | Already has `if/elif thinkpad/standard` — keep as-is, no changes needed |

#### 4. `SpeakToType/speak-to-type.sh`

| Location | Change |
|----------|--------|
| After shortcut application (around line 206) | Source `lib/keyboard-layout.sh`, call `write_keyboard_layout "$LAYOUT"` to persist the user's choice |
| Summary block (lines 213-227) | Already has `if/elif thinkpad/standard` — keep as-is, no changes needed |

#### 5. `ReadLoud/voxfree-readloud.sh`

| Location | Old | New |
|----------|-----|-----|
| Line 38 | `press F9` | `press F9 or Super+Shift+R` |

#### 6. `SpeakToType/voxfree-dictate.sh`

| Location | Old | New |
|----------|-----|-----|
| Line 2 (comment) | `Start microphone recording (F10)` | `Start microphone recording` |
| Line 3 (comment) | `(F11)` | remove |
| Line 11 | `press F11 to stop` | `press F11 or Super+Shift+K to stop` |
| Line 40 | `Press F11 to stop` | `Press F11 or Super+Shift+K to stop` |

#### 7. `SpeakToType/voxfree-dictate-stop.sh`

| Location | Old | New |
|----------|-----|-----|
| Line 2 (comment) | `(F11)` | remove |
| Line 13 | `Press F10 to start` | `Press F10 or Super+Shift+M to start` |
| Line 26 | `Keep F10 held down longer` | `Press F10 or Super+Shift+M to start, then speak` |

#### 8. `voxfree-voice.sh`

| Location | Old | New |
|----------|-----|-----|
| Line 103 | `press F9` | `press F9 or Super+Shift+R` |

#### 9. `ReadLoud/voxfree-stop-all.sh`

| Location | Old | New |
|----------|-----|-----|
| Line 4 (comment) | `Ctrl+Alt+S (Standard)` | `Super+Shift+K (Standard)` — **fix wrong shortcut** |

#### 10. `voxfree-doctor.sh`

| Location | Old | New |
|----------|-----|-----|
| Line 213 (README section) | `F9/F10/F11 bindings` | `keyboard shortcut bindings` |
| Line 434 (wev check) | `wev installed (ThinkPad keysym detection)` | `wev installed (keysym detection for ThinkPad keyboards)` |

---

### Documentation

#### 11. `README.md`

| Location | Change |
|----------|--------|
| Line 31 | `press **F9**` → `press **F9** (ThinkPad) / **Super+Shift+R** (Standard)` |
| Line 44 | `**F10**` → `**F10** (ThinkPad) / **Super+Shift+M** (Standard)`; `**F11**` → `**F11** / **Super+Shift+K**` |
| Lines 359, 361, 366 (file structure) | `← F9:` → `← F9 / Super+Shift+R:`; `← F11:` → `← F11 / Super+Shift+K:`; `← F10:` → `← F10 / Super+Shift+M:` |
| Line 404 (troubleshooting) | `wait for the F10 start sound` → `wait for the start sound` |
| After line 271 (All commands section) | Add `voxfree --switch [thinkpad|standard]  Switch keyboard shortcut layout` to the command table |

#### 12. `ReadLoud/readloud.md`

| Location | Change |
|----------|--------|
| Line 3 (heading) | `press **F9**` → `press **F9** (ThinkPad) / **Super+Shift+R** (Standard)` |
| Line 13 | `Press F9` → `Press F9 / Super+Shift+R` |
| Line 23 | `Press F9 again` → `Press F9 / Super+Shift+R again` |
| Line 24 | `Press F11` → `Press F11 / Super+Shift+K` |
| Line 147 | `press F9` → `press F9 or Super+Shift+R` |
| Lines 158, 160 (file table) | `F9` → `F9 / Super+Shift+R`; `F11` → `F11 / Super+Shift+K` |
| After the shortcuts section | Add paragraph: `Switch layouts: \`voxfree --switch thinkpad\` or \`voxfree --switch standard\`` |

#### 13. `SpeakToType/speak-to-type.md`

| Location | Change |
|----------|--------|
| Line 3 (heading) | `**F10**` / `**F11**` → `**F10** (ThinkPad) / **Super+Shift+M** (Standard)` / `**F11** / **Super+Shift+K**` |
| Line 11 | `Press F10` → `Press F10 / Super+Shift+M` |
| Line 21 | `Press F11` → `Press F11 / Super+Shift+K` |
| Line 57 | `press F10, speak, press F11` → `press F10 / Super+Shift+M, speak, press F11 / Super+Shift+K` |
| Lines 68-69 (shortcut table) | Already shows ThinkPad in table — add Standard row below it (already exists — verify) |
| Line 149 | `bound to F10` → `bound to F10 / Super+Shift+M` |
| Line 158 | `called by F11` → `called by F11 / Super+Shift+K` |
| Line 170 | `bound to F11` → `bound to F11 / Super+Shift+K` |
| Line 193 | `Press F10` → `Press F10 / Super+Shift+M` |
| Line 217 | `on F11` → `on F11 / Super+Shift+K` |
| Line 223 | `Press F10` → `Press F10 / Super+Shift+M` |
| Lines 249, 251 (file table) | `F10` → `F10 / Super+Shift+M`; `F11` → `F11 / Super+Shift+K` |
| After shortcuts section | Add: `Switch layouts: \`voxfree --switch thinkpad\` or \`voxfree --switch standard\`` |

#### 14. `docs/architecture.md`

| Location | Change |
|----------|--------|
| Line 8 (diagram) | `F9` → `F9 / Super+Shift+R`; `F10` → `F10 / Super+Shift+M`; `F11` → `F11 / Super+Shift+K` |
| Line 19 | Add `(Standard: Super+Shift+R/M/K)` alongside ThinkPad references |
| Lines 60, 62, 63 (file layout) | Add Standard shortcuts in parentheses |
| Lines 138, 153, 167 (shortcut flow) | Add Standard alternatives in parentheses |

#### 15. `docs/building-blocks.md`

| Location | Change |
|----------|--------|
| Line 101 | `F10 recording fails` → `F10 / Super+Shift+M recording fails` |
| Line 117 | `after pressing F10` → `after pressing F10 / Super+Shift+M` |
| Line 192 | `F9/F10/F11` → `F9 / Super+Shift+R or F10 / Super+Shift+M or F11 / Super+Shift+K` |

---

## Multi-User Handling

### System mode (`sudo voxfree --switch`)
1. Writes `/etc/voxfree/keyboard-layout`
2. Rewrites `/etc/dconf/db/local.d/00-voice-shortcuts` with new bindings (all 3)
3. `dconf update`
4. Iterates `/run/user/*` to find active user sessions and applies gsettings to each
5. Restarts `gsd-media-keys` target for current session

### User mode (`voxfree --switch`)
1. Writes `~/.config/voxfree/keyboard-layout`
2. Applies via gsettings to current user session only
3. Restarts `gsd-media-keys` target
4. Does NOT touch `/etc/dconf/` (no sudo access)

This mirrors the existing pattern from `packaging/DEBIAN/postinst` where the script scans `/run/user/*` to sync user-level scripts across sessions.

---

## Implementation Order

1. **Create `lib/keyboard-layout.sh`** — pure helper, no dependencies on existing code
2. **Create `voxfree-switch.sh`** — depends on keyboard-layout.sh
3. **Update `install.sh`** — add `--switch` dispatch, update summaries, persist layout after sub-scripts
4. **Update `ReadLoud/readloud.sh`** — persist layout choice after shortcut application
5. **Update `SpeakToType/speak-to-type.sh`** — persist layout choice after shortcut application
6. **Update `build-deb.sh`** — update embedded voxfree wrapper with both shortcuts + `--switch`
7. **Update runtime scripts** — `voxfree-readloud.sh`, `voxfree-dictate.sh`, `voxfree-dictate-stop.sh`, `voxfree-stop-all.sh`
8. **Update `voxfree-voice.sh`** — remove hardcoded F9
9. **Update `voxfree-doctor.sh`** — update shortcut references
10. **Update documentation** — README.md, readloud.md, speak-to-type.md, architecture.md, building-blocks.md
11. **Run `voxfree-doctor.sh`** — verify everything still works

---

## Verification

```bash
# Test switch command
voxfree --switch thinkpad
# Verify: dconf read the bindings, config file has "thinkpad"

voxfree --switch standard
# Verify: dconf read the bindings, config file has "standard"

# Test that notifications show both shortcuts
# Trigger TTS: highlight text, press shortcut — notification should say "F9 or Super+Shift+R"
# Trigger STT: press shortcut — notification should say "F11 or Super+Shift+K"

# Test system vs user mode
sudo voxfree --switch standard    # should update /etc/voxfree/keyboard-layout
voxfree --switch thinkpad         # should update ~/.config/voxfree/keyboard-layout

# Run doctor
voxfree-doctor                    # should pass all checks

# Verify dconf shortcuts file
cat /etc/dconf/db/local.d/00-voice-shortcuts   # system mode
```

---

## Key Design Decisions (confirmed)

- **Both shortcuts always shown** — runtime notifications list both options regardless of chosen layout. This avoids complexity of detecting layout at runtime while keeping users informed.
- **No mixed layouts** — all three bindings follow the same layout. Mixed (e.g., TTS=ThinkPad, STT=Standard) would be confusing.
- **Default is `thinkpad`** — backward-compatible, existing installations won't break.
- **`voxfree --switch` is a CLI command** — shown in `voxfree --help`, dispatched by the `voxfree` wrapper.
- **ThinkPad and Standard are equal** — no preference, both first-class, both documented equally.
- **Config follows the voice file pattern** — system: `/etc/voxfree/keyboard-layout`, user: `~/.config/voxfree/keyboard-layout`.

---

## Files Summary

| Type | Count | Files |
|------|-------|-------|
| New | 2 | `lib/keyboard-layout.sh`, `voxfree-switch.sh` |
| Modified — Scripts | 10 | `install.sh`, `build-deb.sh`, `readloud.sh`, `speak-to-type.sh`, `voxfree-readloud.sh`, `voxfree-dictate.sh`, `voxfree-dictate-stop.sh`, `voxfree-stop-all.sh`, `voxfree-voice.sh`, `voxfree-doctor.sh` |
| Modified — Docs | 5 | `README.md`, `readloud.md`, `speak-to-type.md`, `architecture.md`, `building-blocks.md` |
| **Total** | **17** | |
