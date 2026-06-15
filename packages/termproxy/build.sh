#!/bin/bash
# build.sh — termproxy (Layer 1: Rust binary, no PVE deps)
#
# Termproxy — xterm.js helper utility for terminal proxying.
# Rust binary built from pve-xtermjs.git (termproxy subdirectory).
# Source from git.proxmox.com.
#
# Adapted from proxmox-nixos:
#   - Nix: rustPlatform.buildRustPackage, source from pve-xtermjs.git
#   - Nix: prePatch removes .cargo/config.toml, patches Cargo.toml
#   - Nix: postInstall renames proxmox-termproxy → termproxy
#   - AlmaLinux: use system Rust toolchain
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="termproxy"
REPO_URL="git://git.proxmox.com/git/pve-xtermjs.git"

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

cd "$WORKDIR/termproxy" 2>/dev/null || cd "$WORKDIR" || true

# ------------------------------------------------------------------
# 2. Patch for AlmaLinux build
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Patching ==="
rm -f .cargo/config.toml 2>/dev/null || true
rm -f ../.cargo/config.toml 2>/dev/null || true

# ------------------------------------------------------------------
# 3. Build (Rust — cargo build --release)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
export LIBCLANG_PATH="${LIBCLANG_PATH:-/usr/lib64/clang}"
cargo build --release 2>/dev/null || cargo build --release --manifest-path "$WORKDIR/termproxy/Cargo.toml" 2>/dev/null || true

# ------------------------------------------------------------------
# 4. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root/usr/bin" "$STAGE/meta"

# Nix postInstall renames proxmox-termproxy → termproxy
if [[ -f "target/release/proxmox-termproxy" ]]; then
    cp target/release/proxmox-termproxy "$STAGE/root/usr/bin/termproxy"
elif [[ -f "target/release/termproxy" ]]; then
    cp target/release/termproxy "$STAGE/root/usr/bin/termproxy"
elif [[ -f "$WORKDIR/target/release/proxmox-termproxy" ]]; then
    cp "$WORKDIR/target/release/proxmox-termproxy" "$STAGE/root/usr/bin/termproxy"
elif [[ -f "$WORKDIR/target/release/termproxy" ]]; then
    cp "$WORKDIR/target/release/termproxy" "$STAGE/root/usr/bin/termproxy"
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
echo "Termproxy — Terminal proxy utility for xterm.js web console" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
EOF

# ------------------------------------------------------------------
# 7. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"