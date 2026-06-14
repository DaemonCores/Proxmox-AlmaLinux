#!/bin/bash
# build.sh — proxmox-rs (Layer 1: Rust library, Proxmox framework)
#
# Core Rust library for Proxmox — provides shared types, utilities, and APIs
# consumed by proxmox-perl-rs and other Rust-based PVE components.
#
# Adapted from proxmox-nixos: rustPlatform.buildRustPackage
# AlmaLinux: cargo build --release, system deps
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="proxmox-rs"
REPO_URL="git://git.proxmox.com/git/proxmox-rs.git"

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
# proxmox-rs is a workspace of Rust crates
cargo build --release

# ------------------------------------------------------------------
# 4. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root/usr/lib" "$STAGE/meta"

# Install the built Rust libraries (.rlib/.so) to staging
# The primary output is static/shared Rust libraries consumed at build time
# by downstream crates (proxmox-perl-rs, pve-qemu, etc.)
cargo install --path . --root "$STAGE/root/usr" --locked || true

# For library crates, copy the compiled artifacts
if [[ -d "$WORKDIR/target/release" ]]; then
    mkdir -p "$STAGE/root/usr/lib/proxmox-rs"
    find "$WORKDIR/target/release" -maxdepth 1 -name 'libproxmox*.rlib' -exec cp {} "$STAGE/root/usr/lib/proxmox-rs/" \; 2>/dev/null || true
    find "$WORKDIR/target/release" -maxdepth 1 -name 'libproxmox*.so' -exec cp {} "$STAGE/root/usr/lib/" \; 2>/dev/null || true
fi

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
echo "Proxmox Rust framework — core types, utilities, and API libraries" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
cargo
openssl-libs
pkgconf-pkg-config
EOF

# ------------------------------------------------------------------
# 7. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"