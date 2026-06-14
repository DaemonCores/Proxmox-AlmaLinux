#!/bin/bash
# build.sh — proxmox-backup-qemu (Layer 1: C library, QEMU backup client)
#
# Rust library providing the proxmox backup client for QEMU.
# Produces a shared library (.so) consumed by pve-qemu at link time.
#
# Adapted from proxmox-nixos: rustPlatform.buildRustPackage with
# acl, libuuid, openssl, zstd, libxcrypt, linux-pam, sg3_utils deps.
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="proxmox-backup-qemu"
REPO_URL="git://git.proxmox.com/git/proxmox-backup-qemu.git"

# ------------------------------------------------------------------
# 1. Clone source
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Cloning source ==="
WORKDIR="/tmp/src/${PKG_NAME}"
rm -rf "$WORKDIR"
git clone "$REPO_URL" "$WORKDIR" --recursive
cd "$WORKDIR"

if [[ -n "${VERSION:-}" ]]; then
    git checkout "$VERSION" 2>/dev/null || git checkout "${SHORT:-${VERSION:0:7}}" 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 2. Apply patches from debian/patches/series
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Applying patches ==="
if [[ -f "$WORKDIR/debian/patches/series" ]]; then
    while IFS= read -r patch; do
        [[ -z "$patch" || "$patch" =~ ^# ]] && continue
        echo "  Applying: $patch"
        patch -p1 -d "$WORKDIR" -i "$WORKDIR/debian/patches/$patch" || true
    done < "$WORKDIR/debian/patches/series"
fi

# ------------------------------------------------------------------
# 3. Build (Rust — cargo build --release)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
# proxmox-backup-qemu is a Rust crate that produces libproxmox_backup_qemu.so
# Nix: cargo build with acl, libuuid, openssl, zstd, libxcrypt, linux-pam, sg3_utils
# AlmaLinux: these are all available via dnf as system packages
export LIBCLANG_PATH="${LIBCLANG_PATH:-/usr/lib64/clang}"
cargo build --release -p proxmox-backup-qemu

# ------------------------------------------------------------------
# 4. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root/usr/lib" "$STAGE/root/usr/include" "$STAGE/meta"

# Install the shared library and header (per Nix postInstall)
cp target/release/libproxmox_backup_qemu.so "$STAGE/root/usr/lib/libproxmox_backup_qemu.so.0"
ln -sf libproxmox_backup_qemu.so.0 "$STAGE/root/usr/lib/libproxmox_backup_qemu.so"
cp proxmox-backup-qemu.h "$STAGE/root/usr/lib/"

# ------------------------------------------------------------------
# 5. Determine version
# ------------------------------------------------------------------
PKG_VERSION=""
if [[ -f "$WORKDIR/debian/changelog" ]]; then
    PKG_VERSION="$(head -1 "$WORKDIR/debian/changelog" | sed 's/.*(\([^)]*\)).*/\1/')"
fi
if [[ -z "${PKG_VERSION:-}" ]]; then
    PKG_VERSION="$(grep '^version' "$WORKDIR/Cargo.toml" | head -1 | sed 's/.*= *"*\([^"]*\)"*.*/\1/')"
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
echo "Proxmox Backup client library for QEMU — Rust shared library" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
acl
clang-libs
libuuid
libxcrypt
openssl-libs
pam
sg3_utils-libs
zstd
EOF

# ------------------------------------------------------------------
# 7. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"