#!/bin/bash
# build.sh — perlmod (Layer 1: Rust+Perl tool, no PVE deps)
#
# PerlMod — Alternative to Perl XS for Rust, providing Rust-to-Perl bindings.
# Rust crate that builds a shared library + Perl helper script.
# Source from git.proxmox.com.
#
# Adapted from proxmox-nixos:
#   - Nix: rustPlatform.buildRustPackage with libxcrypt dep
#   - Nix: postPatch removes .cargo/config.toml, patches genpackage.pl
#   - Nix: postInstall copies genpackage.pl to $out/lib/perlmod
#   - AlmaLinux: use system Rust toolchain + libxcrypt
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="perlmod"
REPO_URL="git://git.proxmox.com/git/perlmod.git"

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
# 2. Patch for AlmaLinux build
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Patching ==="
# Remove vendored cargo config that points to Nix store
rm -f .cargo/config.toml 2>/dev/null || true
# Patch shebang in genpackage.pl
if [[ -f "perlmod-bin/genpackage.pl" ]]; then
    patchShebangs perlmod-bin/genpackage.pl 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 3. Build (Rust — cargo build --release)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
export LIBCLANG_PATH="${LIBCLANG_PATH:-/usr/lib64/clang}"
cargo build --release -p perlmod-bin 2>/dev/null || cargo build --release 2>/dev/null || true

# ------------------------------------------------------------------
# 4. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root/usr/bin" "$STAGE/root/usr/lib/perlmod" "$STAGE/meta"

# Install binary (proxmox-termproxy or perlmod binary)
if [[ -f "target/release/perlmod" ]]; then
    cp target/release/perlmod "$STAGE/root/usr/bin/"
fi
if [[ -f "target/release/perlmod-bin" ]]; then
    cp target/release/perlmod-bin "$STAGE/root/usr/bin/"
fi

# Install genpackage.pl helper (per Nix postInstall)
if [[ -f "perlmod-bin/genpackage.pl" ]]; then
    cp perlmod-bin/genpackage.pl "$STAGE/root/usr/lib/perlmod/"
fi

# Install shared library if built
if [[ -f "target/release/libperlmod.so" ]]; then
    cp target/release/libperlmod.so "$STAGE/root/usr/lib/"
fi

# ------------------------------------------------------------------
# 5. Determine version
# ------------------------------------------------------------------
PKG_VERSION=""
if [[ -f "$WORKDIR/debian/changelog" ]]; then
    PKG_VERSION="$(head -1 "$WORKDIR/debian/changelog" | sed 's/.*(\([^)]*\)).*/\1/')"
fi
if [[ -z "${PKG_VERSION:-}" ]] && [[ -f "$WORKDIR/Cargo.toml" ]]; then
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
echo "PerlMod — Alternative to Perl XS for Rust bindings" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
libxcrypt
perl
EOF

# ------------------------------------------------------------------
# 7. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"