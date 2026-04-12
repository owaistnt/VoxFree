#!/bin/bash
# =============================================================================
# build-deb.sh — Build voxfree_VERSION_amd64.deb
# Does NOT require sudo. Uses fakeroot.
# =============================================================================
# Usage:
#   bash build-deb.sh          (uses version from VERSION file)
#   bash build-deb.sh 0.2.0    (override version)
#
# Output: dist/voxfree_VERSION_amd64.deb
# =============================================================================

if [ -z "$BASH_VERSION" ]; then exec bash "$0" "$@"; fi
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "0.1.0")}"
STAGING="$SCRIPT_DIR/dist/voxfree_${VERSION}_all"
DEB_OUT="$SCRIPT_DIR/dist/voxfree_${VERSION}_all.deb"

echo "Building VoxFree $VERSION .deb package..."
echo ""

# Check fakeroot is available
if ! command -v fakeroot >/dev/null 2>&1; then
    echo "fakeroot is required: sudo apt install fakeroot"
    exit 1
fi

# Clean staging area
rm -rf "$STAGING"

# ── Create directory structure ────────────────────────────────────────────────
mkdir -p "$STAGING/DEBIAN"
mkdir -p "$STAGING/usr/share/voxfree/ReadLoud"
mkdir -p "$STAGING/usr/share/voxfree/SpeakToType"
mkdir -p "$STAGING/usr/share/voxfree/lib"
mkdir -p "$STAGING/usr/share/doc/voxfree"
mkdir -p "$STAGING/usr/local/bin"

# ── Copy VoxFree scripts ──────────────────────────────────────────────────────
# Root scripts
for F in install.sh deps.sh uninstall.sh voxfree-doctor.sh voxfree-voice.sh VERSION; do
    [ -f "$SCRIPT_DIR/$F" ] && cp "$SCRIPT_DIR/$F" "$STAGING/usr/share/voxfree/"
done

# ReadLoud scripts
for F in readloud.sh readloud.md voxfree-readloud.sh voxfree-readloud-stop.sh voxfree-stop-all.sh; do
    [ -f "$SCRIPT_DIR/ReadLoud/$F" ] && \
        cp "$SCRIPT_DIR/ReadLoud/$F" "$STAGING/usr/share/voxfree/ReadLoud/"
done

# SpeakToType scripts
for F in speak-to-type.sh speak-to-type.md voxfree-dictate.sh voxfree-dictate-stop.sh \
         globalize.sh verify-global.sh; do
    [ -f "$SCRIPT_DIR/SpeakToType/$F" ] && \
        cp "$SCRIPT_DIR/SpeakToType/$F" "$STAGING/usr/share/voxfree/SpeakToType/"
done

# lib/
cp "$SCRIPT_DIR/lib/detect.sh" "$STAGING/usr/share/voxfree/lib/"

# ── Create /usr/local/bin/ wrappers ──────────────────────────────────────────
cat > "$STAGING/usr/local/bin/voxfree" << 'WRAPEOF'
#!/bin/bash
# voxfree — VoxFree unified CLI (installed by .deb)
exec bash /usr/share/voxfree/install.sh --voxfree-cli "$@"
WRAPEOF

cat > "$STAGING/usr/local/bin/voxfree-doctor" << 'WRAPEOF'
#!/bin/bash
# voxfree-doctor — VoxFree health checker (installed by .deb)
exec bash /usr/share/voxfree/voxfree-doctor.sh "$@"
WRAPEOF

chmod 755 "$STAGING/usr/local/bin/voxfree"
chmod 755 "$STAGING/usr/local/bin/voxfree-doctor"

# ── Documentation ─────────────────────────────────────────────────────────────
cp "$SCRIPT_DIR/README.md" "$STAGING/usr/share/doc/voxfree/"
gzip -9 -c "$SCRIPT_DIR/packaging/changelog" > "$STAGING/usr/share/doc/voxfree/changelog.gz"
cp "$SCRIPT_DIR/packaging/copyright" "$STAGING/usr/share/doc/voxfree/"

# ── DEBIAN control files ──────────────────────────────────────────────────────
cp "$SCRIPT_DIR/packaging/DEBIAN/control"  "$STAGING/DEBIAN/control"
cp "$SCRIPT_DIR/packaging/DEBIAN/postinst" "$STAGING/DEBIAN/postinst"
cp "$SCRIPT_DIR/packaging/DEBIAN/prerm"    "$STAGING/DEBIAN/prerm"
cp "$SCRIPT_DIR/packaging/DEBIAN/postrm"   "$STAGING/DEBIAN/postrm"
chmod 755 "$STAGING/DEBIAN/postinst" "$STAGING/DEBIAN/prerm" "$STAGING/DEBIAN/postrm"

# Update version in control file
sed -i "s/^Version:.*/Version: $VERSION/" "$STAGING/DEBIAN/control"

# ── Fix permissions ───────────────────────────────────────────────────────────
find "$STAGING" -type d -exec chmod 755 {} \;
find "$STAGING/usr/share/voxfree" -name "*.sh" -exec chmod 755 {} \;
find "$STAGING/usr/share/voxfree" -name "*.md" -exec chmod 644 {} \;
chmod 644 "$STAGING/usr/share/voxfree/VERSION"

# ── Calculate installed size ──────────────────────────────────────────────────
INSTALLED_KB=$(du -sk "$STAGING/usr" | awk '{print $1}')
sed -i "s/^Installed-Size:.*/Installed-Size: $INSTALLED_KB/" "$STAGING/DEBIAN/control"

# ── Build ─────────────────────────────────────────────────────────────────────
mkdir -p "$SCRIPT_DIR/dist"
fakeroot dpkg-deb --build "$STAGING" "$DEB_OUT"

echo ""
echo "✔ Built: $DEB_OUT"
echo ""
dpkg-deb --info "$DEB_OUT" | grep -E "Package|Version|Size|Depends"
echo ""
echo "Install with:  sudo dpkg -i $DEB_OUT"
echo "After install: sudo voxfree --install"
echo "Health check:  voxfree --doctor"
