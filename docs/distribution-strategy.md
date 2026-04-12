# VoxFree Distribution Strategy

## Approach

VoxFree uses a **shell installer + .deb package** dual distribution strategy:

| Method | Use case |
|--------|---------|
| `sudo bash install.sh` | Developers, quick setup, CI/CD |
| `sudo dpkg -i voxfree.deb` | End users, package manager integration |
| `bash install.sh --user` | No-root installs, multi-user machines |

Both methods produce identical results. The .deb is a thin wrapper — it installs scripts to `/usr/share/voxfree/` then calls `install.sh`.

---

## Why Not Snap / Flatpak?

| Format | Issue |
|--------|-------|
| Snap | Sandboxed — `/dev/uinput` access for ydotool is blocked or complex |
| Flatpak | Same sandboxing issues; GNOME dconf system-db not accessible |
| AppImage | Single binary model doesn't suit system-level config (dconf, udev) |

VoxFree needs to: write to `/etc/dconf/`, create udev rules, install systemd user services. These require system-level access that containerised formats restrict.

---

## Why the .deb Does Not Bundle Dependencies

VoxFree has two large runtime dependencies:
- **whisper-ctranslate2 venv**: ~520MB (varies by platform)
- **Whisper base.en model**: ~145MB

Bundling these would make the .deb ~700MB+, which is impractical for distribution. Instead:
- `postinst` downloads and installs them after `dpkg -i`
- `deps.sh` handles this with detect-then-install logic (idempotent, uses existing installations)

This is the same approach used by Google Chrome, VS Code, and other large applications that distribute .deb packages.

---

## Why `mycroft-mimic3-tts` is `Suggests` not `Depends`

`dpkg` resolves `Depends:` packages from apt repositories only. `mycroft-mimic3-tts` is not in Ubuntu's apt repositories — it's only available as a `.deb` from GitHub releases. Putting it in `Depends:` would cause `dpkg -i voxfree.deb` to fail with an unresolvable dependency error.

`Suggests:` communicates that it's needed for TTS without blocking installation.

---

## Per-User Installation

The `--user` flag installs VoxFree without root access (except for optional udev/apt steps). This is useful for:
- Multi-user machines where users can't sudo
- Testing without modifying system files
- Corporate environments with restricted sudo

User-mode paths are isolated under `~/.local/` so they don't interfere with system installs.

The only things that still need sudo in user mode:
1. `apt install` for missing packages
2. `/etc/udev/rules.d/99-uinput.rules` for ydotool
3. `/etc/speech-dispatcher/` for speech-dispatcher config

The scripts check if these are already done and skip gracefully if so.

---

## Future Distribution Paths

1. **GitHub Releases**: Attach `voxfree_VERSION_all.deb` to each release tag
2. **PPA**: Add to a Launchpad PPA for `apt install voxfree`
3. **Homebrew tap** (if macOS support added)
4. **AUR** (if Arch Linux support added)
