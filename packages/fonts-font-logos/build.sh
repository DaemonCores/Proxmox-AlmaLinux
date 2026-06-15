#!/bin/bash
# build.sh — fonts-font-logos (Layer 1: Font package, no PVE deps)
#
# Font Awesome + custom font icons used by PVE web UI.
# Sourced from git.proxmox.com.
# Install is a simple copy of CSS and font assets.
#
# Adapted from proxmox-nixos:
#   - sourceRoot = src/
#   - Nix installPhase: copy font-logos/assets and font-logos.css
#   - AlmaLinux: install to /usr/share/fonts-font-logos/ (FHS)
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="fonts-font-logos"
REPO_URL="git://git.proxmox.com/git/fonts-font-logos.git"

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
# 2. Build (no compilation — font assets)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building (font assets) ==="

# ------------------------------------------------------------------
# 3. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root/usr/share/fonts-font-logos/css" "$STAGE/root/usr/share/fonts-font-logos/fonts" "$STAGE/meta"

# Copy font assets per Nix installPhase
if [[ -d "$WORKDIR/src/font-logos/assets" ]]; then
    cp -r "$WORKDIR/src/font-logos/assets" "$STAGE/root/usr/share/fonts-font-logos/fonts/"
fi
if [[ -f "$WORKDIR/src/font-logos.css" ]]; then
    cp "$WORKDIR/src/font-logos.css" "$STAGE/root/usr/share/fonts-font-logos/css/"
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
echo "Font logos — Font Awesome + custom font icons for PVE web UI" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
fontconfig
EOF

# ------------------------------------------------------------------
# 6. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"