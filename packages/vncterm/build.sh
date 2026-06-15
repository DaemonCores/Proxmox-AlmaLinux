#!/bin/bash
# build.sh — vncterm (Layer 1: C binary, no PVE deps)
#
# VNC terminal emulator — provides VNC access to container/VM consoles.
# C binary that links against libvncserver, gnutls, libjpeg, libpng, libnsl.
# Source from git.proxmox.com.
# Depends on unifont-hex for font data at build time.
#
# Adapted from proxmox-nixos:
#   - Nix: stdenv.mkDerivation with libvncserver (patched with tls-auth), gnutls, libjpeg, libnsl, libpng
#   - Nix: postPatch strips architecture.mk, pkg-info, patches Makefile extensively
#   - Nix: makeFlags VNCLIB/VNCDIR, DESTDIR=$(out)
#   - AlmaLinux: use system libvncserver, patch Makefile for FHS paths
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="vncterm"
REPO_URL="git://git.proxmox.com/git/vncterm.git"

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

# ------------------------------------------------------------------
# 2. Patch Makefile for AlmaLinux build
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Patching ==="
if [[ -f "Makefile" ]]; then
    sed -i "Makefile" \
        -e "/architecture.mk/d" \
        -e "/pkg-info/d" \
        -e "s|/usr/share/unifont/unifont.hex|/usr/share/unifont/unifont.hex|g" \
        -e "s|usr/||g" \
        -e "s/Werror/Wno-error/" \
        -e "s|wchardata.c|/usr/share/unifont/wchardata.c|g" \
        -e "/pod2man/d" \
        -e "/man1/d" 2>/dev/null || true
fi

# Apply TLS auth plugin patches from vncpatches/ if they exist
if [[ -d "vncpatches" ]]; then
    for patch in vncpatches/*.patch; do
        [[ -f "$patch" ]] && patch -p1 -i "$patch" || true
    done
fi

# ------------------------------------------------------------------
# 3. Build
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
# Build vncterm binary linking against system libvncserver
# Nix patches libvncserver with tls-auth-plugin; on AlmaLinux we use system libvncserver
make -j"$(nproc)" VNCLIB="-lvncserver" VNCDIR="/usr/include" DESTDIR="/tmp/pkg/${PKG_NAME}/root" || true

# ------------------------------------------------------------------
# 4. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
mkdir -p "$STAGE/root/usr/bin" "$STAGE/meta"

make install DESTDIR="$STAGE/root" PREFIX=/usr SBINDIR=/usr/bin || true

# Ensure binary is installed
if [[ -f "vncterm" ]] && [[ ! -f "$STAGE/root/usr/bin/vncterm" ]]; then
    install -Dm755 vncterm "$STAGE/root/usr/bin/vncterm"
fi

# Patch /usr reference in binary
if [[ -f "$STAGE/root/usr/bin/vncterm" ]]; then
    sed -i "$STAGE/root/usr/bin/vncterm" -e "s|/usr|$STAGE/root/usr|g" 2>/dev/null || true
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
echo "vncterm — VNC terminal emulator for Proxmox VE console access" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
gnutls
libjpeg
libpng
libvncserver
unifont-hex
EOF

# ------------------------------------------------------------------
# 7. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"