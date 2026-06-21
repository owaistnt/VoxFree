# VoxFree Bash Hash Cache Issue

## Problem

After upgrading VoxFree via `dpkg -i`, running `voxfree` still shows the old version and old commands (e.g. `--switch` missing).

```bash
$ voxfree --version
VoxFree 0.3.0          # ← stale

$ voxfree --switch
Unknown command: --switch   # ← stale
```

## Root Cause

Bash maintains an internal **hash table** mapping command names to the inode number of the binary file on disk. When `dpkg` upgrades a package, it replaces the file on disk with a **new inode** (same path, different inode). Bash's hash cache still points to the **old inode**, which has been unlinked by dpkg but is still referenced by the cached entry. The shell finds the command in PATH, but the hash points to a stale filesystem entry.

## Fix

Clear the bash hash cache and re-lookup:

```bash
hash -r
voxfree --version
```

`hash -r` invalidates all cached command paths. The next `voxfree` call re-resolves via PATH to the correct `/usr/local/bin/voxfree`.

## When This Can Happen

- Any `.deb` upgrade that installs files in `/usr/local/bin/` while the `voxfree` wrapper is also in the deb
- Any package upgrade that replaces a binary at a path already hashed by the current shell session
- Upgrades of `install.sh`-generated wrappers where the shell has already resolved the command

## Prevention

Add to installation/remediation instructions:

```bash
hash -r
voxfree --doctor
```

## Verification

```bash
# Confirm correct binary is being used
type -a voxfree        # should show /usr/local/bin/voxfree
which voxfree          # should show /usr/local/bin/voxfree

# Confirm VERSION file matches
cat /usr/share/voxfree/VERSION    # should match running version

# If still stale, check inode mismatch
ls -li /usr/local/bin/voxfree
```
