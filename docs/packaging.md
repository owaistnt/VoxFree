# VoxFree Packaging Guide

## Building the .deb

The `.deb` package contains only VoxFree scripts (~200KB). Dependencies are downloaded by `postinst`.

### Prerequisites

```bash
sudo apt install fakeroot   # needed to set file ownership in staging tree
```

### Build

```bash
cd VoxFree
bash build-deb.sh              # uses VERSION file (0.1.0)
bash build-deb.sh 0.2.0        # override version
```

Output: `dist/voxfree_0.1.0_all.deb`

### Verify

```bash
dpkg-deb --info dist/voxfree_0.1.0_all.deb
dpkg-deb --contents dist/voxfree_0.1.0_all.deb
```

### Test install

```bash
sudo dpkg -i dist/voxfree_0.1.0_all.deb
voxfree --doctor
```

### Test uninstall

```bash
sudo apt remove voxfree         # removes scripts, keeps venv + models
sudo apt purge voxfree          # also removes /usr/share/voxfree/, dconf, udev
```

---

## Package Contents

After `dpkg -i`, these files are on disk:

```
/usr/share/voxfree/         ← all VoxFree scripts (source)
/usr/share/doc/voxfree/     ← README, changelog, copyright
/usr/local/bin/voxfree      ← CLI dispatcher wrapper
/usr/local/bin/voxfree-doctor  ← health checker wrapper
```

The bin wrappers at `/usr/local/bin/` are thin scripts that call the canonicals in `/usr/share/voxfree/`. This means:
- Upgrading the .deb updates `/usr/share/voxfree/` files
- The wrappers automatically pick up the new versions
- No manual wrapper reinstallation needed

---

## DEBIAN/control Fields

```
Depends:     packages that MUST be installed (apt-resolvable)
Recommends:  packages that SHOULD be installed (apt-resolvable, installed by default)
Suggests:    packages that MAY be useful (not auto-installed)
```

`mycroft-mimic3-tts` is in `Suggests` (not `Depends` or `Recommends`) because it is not in Ubuntu's apt repositories. `dpkg` would fail to resolve it as a dependency.

---

## Releasing to GitHub

1. Build the .deb: `bash build-deb.sh VERSION`
2. Tag the release: `git tag v0.1.0 && git push origin v0.1.0`
3. Create a GitHub Release for `v0.1.0`
4. Attach `dist/voxfree_0.1.0_all.deb` as a release asset

Users can then download and install:
```bash
wget https://github.com/USER/VoxFree/releases/download/v0.1.0/voxfree_0.1.0_all.deb
sudo dpkg -i voxfree_0.1.0_all.deb
```

---

## Future: PPA on Launchpad

To allow `sudo apt install voxfree`:

1. Create a Launchpad account and PPA: `https://launchpad.net/`
2. Build a proper source package (`.dsc` + `.tar.gz`) with debhelper
3. Sign and upload to PPA
4. Users add the PPA: `sudo add-apt-repository ppa:USER/voxfree`

This is a future goal. For now, GitHub Releases with a direct `.deb` download is sufficient.

---

## Updating the Version

1. Update `VERSION` file: `echo "0.2.0" > VERSION`
2. Update `packaging/DEBIAN/control`: `Version: 0.2.0`
3. Update `packaging/changelog`: add new entry
4. Rebuild: `bash build-deb.sh 0.2.0`
5. Tag and release on GitHub
