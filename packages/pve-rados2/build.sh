#!/bin/bash
# build.sh — pve-rados2 (Layer 4: Perl XS module, depends on pve-common + librados)
#
# Perl bindings for Ceph RADOS (librados2).
# XS module linking against librados (Ceph client library).
# Source from git.proxmox.com (librados2-perl.git).
#
# Adapted from proxmox-nixos:
#   - Nix: perl540.pkgs.toPerlModule wrapping stdenv.mkDerivation
#   - Nix: buildInputs = [ perl540 ceph.dev ]
#   - Nix: makeFlags DESTDIR, PREFIX, PERLDIR, PERLSODIR
#   - Nix: postPatch strips GITVERSION, pkg-info, architecture
#   - AlmaLinux: use system perl + ceph-devel (librados2-devel)
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="pve-rados2"
REPO_URL="git://git.proxmox.com/git/librados2-perl.git"

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
        -e "/GITVERSION/d" \
        -e "/pkg-info/d" \
        -e "/architecture/d" 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 3. Build
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
make -j"$(nproc)" DESTDIR=/tmp/pkg/${PKG_NAME}/root \
    PREFIX=/usr \
    SBINDIR=/usr/bin \
    PERLDIR=/usr/share/perl5/vendor_perl \
    PERLSODIR=/usr/lib64/perl5/vendor_perl/auto || true

# ------------------------------------------------------------------
# 4. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
mkdir -p "$STAGE/root" "$STAGE/meta"

make install DESTDIR="$STAGE/root" \
    PREFIX=/usr \
    SBINDIR=/usr/bin \
    PERLDIR=/usr/share/perl5/vendor_perl \
    PERLSODIR=/usr/lib64/perl5/vendor_perl/auto || true

find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true

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
echo "PVE RADOS2 — Perl bindings for Ceph RADOS (librados)" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
ceph-devel
perl
pve-common
EOF

# ------------------------------------------------------------------
# 7. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"