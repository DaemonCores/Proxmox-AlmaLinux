#!/bin/bash
# build.sh — proxmox-widget-toolkit (Layer 1: JS/CSS widget toolkit)
#
# ExtJS-based widget toolkit for Proxmox web UI — JS/CSS, no real compilation.
# Uses sassc for CSS compilation and uglify-js for JS minification.
#
# Adapted from proxmox-nixos:
#   - sourceRoot = src/
#   - Nix postPatch: sed -i defines.mk -e "s,/usr,,", sed -i Makefile for BUILD_VERSION/BIOME
#   - Nix makeFlags: DESTDIR=$(out), MARKEDJS=...path...
#   - Nix postInstall: cp api-viewer/APIViewer.js
#   - AlmaLinux: keep /usr prefix (FHS), use system uglify-js / sassc
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="proxmox-widget-toolkit"
REPO_URL="git://git.proxmox.com/git/proxmox-widget-toolkit.git"

# ------------------------------------------------------------------
# 1. Clone source
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Cloning source ==="
WORKDIR="/tmp/src/${PKG_NAME}"
rm -rf "$WORKDIR"
git clone "$REPO_URL" "$WORKDIR"
cd "$WORKDIR/src"

if [[ -n "${VERSION:-}" ]]; then
    git checkout "$VERSION" 2>/dev/null || git checkout "${SHORT:-${VERSION:0:7}}" 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 2. Patch defines.mk and Makefile
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Patching build files ==="
# Nix: sed -i defines.mk -e "s,/usr,,"
# AlmaLinux: keep /usr prefix (FHS), just strip BUILD_VERSION and BIOME
if [[ -f "defines.mk" ]]; then
    sed -i "defines.mk" -e "/BUILD_VERSION=/d"
fi
if [[ -f "Makefile" ]]; then
    sed -i "Makefile" \
        -e "/BUILD_VERSION=/d" \
        -e "/BIOME/d"
fi

# ------------------------------------------------------------------
# 3. Build (JS/CSS — sassc + uglify-js)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
# The Makefile compiles SCSS → CSS via sassc and minifies JS via uglifyjs
make -j"$(nproc)" || true

# ------------------------------------------------------------------
# 4. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root" "$STAGE/meta"

make install DESTDIR="$STAGE/root" || true

# Copy APIViewer.js (per Nix postInstall)
if [[ -f "$WORKDIR/src/api-viewer/APIViewer.js" ]]; then
    mkdir -p "$STAGE/root/usr/share/javascript/proxmox-widget-toolkit"
    cp "$WORKDIR/src/api-viewer/APIViewer.js" "$STAGE/root/usr/share/javascript/proxmox-widget-toolkit/"
fi

# ------------------------------------------------------------------
# 5. Determine version
# ------------------------------------------------------------------
PKG_VERSION=""
if [[ -f "$WORKDIR/debian/changelog" ]]; then
    PKG_VERSION="$(head -1 "$WORKDIR/debian/changelog" | sed 's/.*(\([^)]*\)).*/\1/')"
fi
if [[ -z "${PKG_VERSION:-}" ]]; then
    PKG_VERSION="${SHORT:-0.0.1}"
fi
PKG_VERSION="${PKG_VERSION}+${SHORT:-git}"

# ------------------------------------------------------------------
# 6. Write meta/ files
# ------------------------------------------------------------------
echo "$PKG_NAME"               > "$STAGE/meta/name"
echo "$PKG_VERSION"            > "$STAGE/meta/version"
echo "${TARGET_ARCH:-x86_64}"  > "$STAGE/meta/arch"
echo "Proxmox ExtJS widget toolkit — JS/CSS for PVE web UI" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
sassc
uglify-js
EOF

# ------------------------------------------------------------------
# 7. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"