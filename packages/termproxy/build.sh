#!/bin/bash
# Package: termproxy
# Layer: 1
# Type: rust-submodules

PKG_NAME="termproxy"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

REPO_URL="$(get_pkg_meta "$PKG_NAME" repo)"
BUILD_TYPE="rust-submodules"
BUILD_SUBDIR="termproxy"
CLONE_RECURSIVE="1"
PKG_DESCRIPTION="Termproxy — Terminal proxy utility for xterm.js web console"

# Override: build termproxy binary from pve-xtermjs subdirectory
build_override() {
    rm -f .cargo/config.toml 2>/dev/null || true
    rm -f ../.cargo/config.toml 2>/dev/null || true
    export LIBCLANG_PATH="${LIBCLANG_PATH:-/usr/lib64/clang}"
    cargo build --release 2>/dev/null || cargo build --release --manifest-path "$WORKDIR/termproxy/Cargo.toml" 2>/dev/null || true
}

install_override() {
    mkdir -p "$STAGE/root/usr/bin" "$STAGE/meta"

    # Nix postInstall renames proxmox-termproxy -> termproxy
    if [[ -f "target/release/proxmox-termproxy" ]]; then
        cp target/release/proxmox-termproxy "$STAGE/root/usr/bin/termproxy"
    elif [[ -f "target/release/termproxy" ]]; then
        cp target/release/termproxy "$STAGE/root/usr/bin/termproxy"
    elif [[ -f "$WORKDIR/target/release/proxmox-termproxy" ]]; then
        cp "$WORKDIR/target/release/proxmox-termproxy" "$STAGE/root/usr/bin/termproxy"
    elif [[ -f "$WORKDIR/target/release/termproxy" ]]; then
        cp "$WORKDIR/target/release/termproxy" "$STAGE/root/usr/bin/termproxy"
    fi
}


full_build
