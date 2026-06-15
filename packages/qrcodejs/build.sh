#!/bin/bash
# build.sh — qrcodejs (Layer 1: JavaScript library, no PVE deps)
#
# QRCode.js — Cross-browser QR code generator for JavaScript.
# Sourced from git.proxmox.com (Proxmox's fork).
# Uses uglify-js for minification.
#
# Adapted from proxmox-nixos:
#   - sourceRoot = src/
#   - Nix: nativeBuildInputs = [ uglify-js ]; installPhase copies qrcode.min.js
#   - AlmaLinux: keep /usr/share paths (FHS), use system uglify-js
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="qrcodejs"
REPO_URL="git://git.proxmox.com/git/libjs-qrcodejs.git"

# ------------------------------------------------------------------
# 1. Clone source
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Cloning source ==="
WORKDIR="/tmp/src/${PKG_NAME}"
rm -rf "$WORKDIR"
git clone "$REPO_URL" "$WORKDIR"
cd "$WORKDIR"

if [[ -n "${VERSION:-}" ]]; then
    git checkout "$VERSION" 2>/dev/null || git checkout "${SHORT:-${VERSION:0:7}}" 2>/dev/null || true
fi

cd "$WORKDIR/src" 2>/dev/null || cd "$WORKDIR" || true

# ------------------------------------------------------------------
# 2. Build (uglify-js minification)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
if command -v uglifyjs &>/dev/null; then
    if [[ -f "qrcode.js" ]]; then
        uglifyjs qrcode.js -o qrcode.min.js || true
    fi
fi

# ------------------------------------------------------------------
# 3. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root/usr/share/javascript/qrcodejs" "$STAGE/meta"

# Copy minified JS (or original if minification failed)
if [[ -f "qrcode.min.js" ]]; then
    cp qrcode.min.js "$STAGE/root/usr/share/javascript/qrcodejs/"
elif [[ -f "qrcode.js" ]]; then
    cp qrcode.js "$STAGE/root/usr/share/javascript/qrcodejs/"
fi

# ------------------------------------------------------------------
# 4. Determine version
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
# 5. Write meta/ files
# ------------------------------------------------------------------
echo "$PKG_NAME"               > "$STAGE/meta/name"
echo "$PKG_VERSION"            > "$STAGE/meta/version"
echo "${TARGET_ARCH:-x86_64}"  > "$STAGE/meta/arch"
echo "QRCode.js — Cross-browser QR code generator for JavaScript" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
EOF

# ------------------------------------------------------------------
# 6. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"