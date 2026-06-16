#!/bin/bash
# Package: pve-yew-mobile-gui
# Layer: 7
# Type: rust-wasm

PKG_NAME="pve-yew-mobile-gui"
REPO_URL="$(get_pkg_meta "$PKG_NAME" repo)"
BUILD_TYPE="rust-wasm"
CLONE_RECURSIVE="1"
PKG_DESCRIPTION="PVE Yew Mobile GUI — Mobile web interface (Rust/WASM)"

# Override: patch Makefile and build Rust→WASM
pre_build_hook() {
    # Remove dpkg includes and fix grass path
    if [[ -f "Makefile" ]]; then
        sed -i "Makefile" \
            -e '/include.*dpkg/d' \
            -e "s|rust-grass|grass|g" 2>/dev/null || true
    fi

    # Remove vendored cargo config
    rm -f .cargo/config.toml 2>/dev/null || true
}

build_override() {
    export LIBCLANG_PATH="${LIBCLANG_PATH:-/usr/lib64/clang}"

    # Try wasm-pack first, then cargo with wasm32 target
    if command -v wasm-pack &>/dev/null; then
        wasm-pack build --release --target web 2>/dev/null || true
    elif command -v cargo &>/dev/null; then
        rustup target add wasm32-unknown-unknown 2>/dev/null || true
        cargo build --release --target wasm32-unknown-unknown 2>/dev/null || true
    fi

    # Also try make if available
    make -j"$(nproc)" 2>/dev/null || true
}

install_override() {
    mkdir -p "$STAGE/root/usr/share/pve-yew-mobile-gui" "$STAGE/meta"

    # Copy WASM output and web assets
    if [[ -f "pkg/pve_yew_mobile_gui_bg.wasm" ]]; then
        cp -r pkg/* "$STAGE/root/usr/share/pve-yew-mobile-gui/" 2>/dev/null || true
    fi

    # Fallback: install from make install
    make install DESTDIR="$STAGE/root" PREFIX=/usr 2>/dev/null || true
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

full_build
