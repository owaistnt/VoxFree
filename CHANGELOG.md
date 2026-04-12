# Changelog

## [0.1.1] — 2026-04-12

### Fixed
- **F11 now transcribes STT instead of discarding audio** — `voxfree-stop-all` delegates to `voxfree-dictate-stop` when a recording is active, so audio is always transcribed and pasted
- **Fresh install via `install.sh --all` now produces a working system** — `speak-to-type.sh` was overwriting the correct `voxfree-dictate` with a stale toggle-based version; rewired to copy from source files
- **`.deb` upgrade path** — `postinst` now always re-copies runtime scripts on upgrade so F9/F10/F11 handlers are updated without re-running interactive setup
- **No `cp: same file` warnings during `.deb` install** — `install.sh` skips file copies when already running from the target directory (`/usr/share/voxfree/`)
- **`voxfree-stop-all` included in `.deb`** — was missing from `build-deb.sh` file list

### Improved
- Documentation: corrected all stale script names, wrong shortcuts (`Ctrl+Alt` → `Super+Shift`), and incorrect behaviour descriptions across `readloud.md`, `speak-to-type.md`, `docs/architecture.md`, `docs/building-blocks.md`, and `README.md`

## [0.1.0] — 2026-04-12

Initial release.

- **ReadLoud** — Text-to-Speech via Mycroft Mimic 3 (F9 toggle, voice selector)
- **SpeakToType** — Speech-to-Text via Whisper base.en with int8 quantisation (F10 start, F11 stop + paste)
- **voxfree CLI** — unified entry point (`--install`, `--doctor`, `--voice`, `--uninstall`)
- **voxfree-doctor** — 36-point health checker with `--fix` flag
- System-wide and per-user install modes
- `.deb` packaging with `postinst` interactive configuration
