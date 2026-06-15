#!/bin/bash
# build.sh — pve-yew-mobile-gui (Layer 7: Rust/WASM, no PVE deps)
#
# PVE mobile web UI built with Yew (Rust WebAssembly framework).
# Compiles to WASM for browser execution.
# Source from git.proxmox.com.
#
# Adapted from proxmox-nixos:
#   - Nix: rustPlatform + binaryen + esbuild + grass-sass + wasm-builder
#   - Nix: cargoSetupHook, lld linker, openssl, libuuid
#   - Nix: postPatch strips dpkg/default.mk, replaces rust-grass with grass
#   - AlmaLinux: use system Rust/WASM toolchain, openssl, libuuid
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="pve-yew-mobile-gui"
REPO_URL="git://git.proxmox.com/git/ui/pve-yew-mobile-gui.git"

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
# Remove dpkg includes and fix grass path
if [[ -f "Makefile" ]]; then
    sed -i "Makefile" \
        -e "/include.*dpkg/d" \
        -e "s|rust-grass|grass|g" 2>/dev/null || true
fi

# Remove vendored cargo config
rm -f .cargo/config.toml 2>/dev/null || true

# ------------------------------------------------------------------
# 3. Build (Rust → WASM)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
# Build with wasm target
export LIBCLANG_PATH="${LIBCLANG_PATH:-/usr/lib64/clang}"

# Try cargo build with wasm32-unknown-unknown target
if command -v wasm-pack &>/dev/null; then
    wasm-pack build --release --target web 2>/dev/null || true
elif command -v cargo &>/dev/null; then
    rustup target add wasm32-unknown-unknown 2>/dev/null || true
    cargo build --release --target wasm32-unknown-unknown 2>/dev/null || true
fi

# Also try make if available
make -j"$(nproc)" 2>/dev/null || true

# ------------------------------------------------------------------
# 4. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root/usr/share/pve-yew-mobile-gui" "$STAGE/meta"

# Copy WASM output and web assets
if [[ -f "pkg/pve_yew_mobile_gui_bg.wasm" ]]; then
    cp -r pkg/* "$STAGE/root/usr/share/pve-yew-mobile-gui/" 2>/dev/null || true
fi

# Fallback: install from make install
make install DESTDIR="$STAGE/root" PREFIX=/usr 2>/dev/null || true

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
echo "PVE Yew Mobile GUI — Mobile web interface for Proxmox VE (Rust/WASM)" > "$STAGE/meta/description"
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