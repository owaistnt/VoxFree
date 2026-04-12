# Contributing to VoxFree

Thank you for your interest. VoxFree is a first open-source project maintained by one person, so every contribution — even just testing and reporting what works on your hardware — is genuinely valuable.

## The most useful thing you can do right now

Test it on your machine and report the result. VoxFree has many moving parts (audio routing, Wayland input, GNOME shortcuts, model inference) and has only been verified on a small number of configurations. Even a comment saying "works perfectly on X hardware with Ubuntu 24.04" helps build confidence for other users.

Run the health check and share the output if something is wrong:

```bash
voxfree --doctor
```

## Reporting a bug

Use the [bug report template](https://github.com/owaistnt/VoxFree/issues/new?template=bug_report.md) and include:

- The full output of `voxfree --doctor`
- Your Ubuntu version and hardware
- Whether you installed via `install.sh` or `.deb`
- What you expected vs what happened

The doctor output alone often pinpoints the problem — please always include it.

## Suggesting a feature

Open a [feature request](https://github.com/owaistnt/VoxFree/issues/new?template=feature_request.md) describing the problem you are trying to solve. The goal of VoxFree is to keep things simple and offline — features that add cloud dependencies or complex configuration will generally not be accepted.

## Submitting a change

1. Fork the repository
2. Make your change on a branch
3. Test with `voxfree --doctor` and manually verify the affected feature works
4. Open a pull request with a clear description of what changed and why

There are no automated tests for shell scripts right now. The doctor script (`voxfree-doctor.sh`) is the closest thing — make sure it still passes after your change.

## What to keep in mind

- VoxFree targets Ubuntu 24.04 GNOME/Wayland. Changes that break this target to support other distros or desktops are unlikely to be merged unless they are clearly isolated.
- The install experience should remain reproducible: `sudo bash install.sh --all` should produce a working system on a fresh Ubuntu 24.04 install.
- Shell scripts should be readable and well-commented. Avoid clever one-liners where a clear multi-line version exists.

## Questions

Open an issue or start a discussion on the [GitHub repository](https://github.com/owaistnt/VoxFree). There is no mailing list or chat channel yet.
