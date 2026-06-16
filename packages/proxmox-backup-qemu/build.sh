#!/bin/bash
# Package: proxmox-backup-qemu
# Layer: 1
# Type: rust-submodules

PKG_NAME="proxmox-backup-qemu"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

REPO_URL="$(get_pkg_meta "$PKG_NAME" repo)"
BUILD_TYPE="rust-submodules"
CLONE_RECURSIVE="1"
PKG_DESCRIPTION="Proxmox Backup client library for QEMU — Rust shared library"
PKG_DEPENDS=$'acl
clang-libs
libuuid
libxcrypt
openssl-libs
pam
sg3_utils-libs
zstd'
CARGO_PKG="proxmox-backup-qemu"

# Override: install shared library + header
install_override() {
    mkdir -p "$STAGE/root/usr/lib" "$STAGE/root/usr/include" "$STAGE/meta"

    cp target/release/libproxmox_backup_qemu.so "$STAGE/root/usr/lib/libproxmox_backup_qemu.so.0"
    ln -sf libproxmox_backup_qemu.so.0 "$STAGE/root/usr/lib/libproxmox_backup_qemu.so"
    cp proxmox-backup-qemu.h "$STAGE/root/usr/lib/"
}


full_build
