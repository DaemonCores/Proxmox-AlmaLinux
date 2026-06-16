#!/bin/bash
# Package: proxmox-rs
# Layer: 1
# Type: rust-workspace

PKG_NAME="proxmox-rs"
REPO_URL="$(get_pkg_meta "$PKG_NAME" repo)"
BUILD_TYPE="rust-workspace"
PKG_DESCRIPTION="Proxmox Rust framework — core types, utilities, and API libraries"
PKG_DEPENDS=$'cargo
openssl-libs
pkgconf-pkg-config'

# Override: install workspace crates
install_override() {
    mkdir -p "$STAGE/root/usr/lib" "$STAGE/meta"

    # Install the built Rust libraries (.rlib/.so) to staging
    cargo install --path . --root "$STAGE/root/usr" --locked || true

    if [[ -d "$WORKDIR/target/release" ]]; then
        mkdir -p "$STAGE/root/usr/lib/proxmox-rs"
        find "$WORKDIR/target/release" -maxdepth 1 -name 'libproxmox*.rlib' -exec cp {} "$STAGE/root/usr/lib/proxmox-rs/" \; 2>/dev/null || true
        find "$WORKDIR/target/release" -maxdepth 1 -name 'libproxmox*.so' -exec cp {} "$STAGE/root/usr/lib/" \; 2>/dev/null || true
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

full_build
