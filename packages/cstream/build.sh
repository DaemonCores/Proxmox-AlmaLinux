#!/bin/bash
# build.sh — cstream (Layer 1: C utility, no PVE deps)
#
# cstream — General-purpose stream handling tool like dd.
# Used by PVE for streaming data operations.
# Downloaded from https://www.cons.org/cracauer/cstream/
#
# Adapted from proxmox-nixos:
#   - Nix: stdenv.mkDerivation, simple fetchurl + build
#   - AlmaLinux: standard autotools build
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="cstream"
CSTREAM_VERSION="4.0.0"
CSTREAM_URL="https://www.cons.org/cracauer/download/cstream-${CSTREAM_VERSION}.tar.gz"

# ------------------------------------------------------------------
# 1. Download source
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Downloading source ==="
WORKDIR="/tmp/src/${PKG_NAME}"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
curl -L -o "/tmp/${PKG_NAME}.tar.gz" "$CSTREAM_URL"
tar xzf "/tmp/${PKG_NAME}.tar.gz" -C "/tmp/src"
mv "/tmp/src/cstream-${CSTREAM_VERSION}" "$WORKDIR"
cd "$WORKDIR"

# ------------------------------------------------------------------
# 2. Build (standard autotools)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
./configure --prefix=/usr --disable-static
make -j"$(nproc)"

# ------------------------------------------------------------------
# 3. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root" "$STAGE/meta"

make install DESTDIR="$STAGE/root" PREFIX=/usr || true

# ------------------------------------------------------------------
# 4. Determine version
# ------------------------------------------------------------------
PKG_VERSION="${CSTREAM_VERSION}+${SHORT:-git}"

# ------------------------------------------------------------------
# 5. Write meta/ files
# ------------------------------------------------------------------
echo "$PKG_NAME"               > "$STAGE/meta/name"
echo "$PKG_VERSION"            > "$STAGE/meta/version"
echo "${TARGET_ARCH:-x86_64}"  > "$STAGE/meta/arch"
echo "cstream — General-purpose stream handling tool like dd" > "$STAGE/meta/description"
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