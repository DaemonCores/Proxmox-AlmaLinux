#!/bin/bash
# Package: pve-edk2-firmware
# Layer: 1
# Type: firmware

PKG_NAME="pve-edk2-firmware"
REPO_URL="$(get_pkg_meta "$PKG_NAME" repo)"
BUILD_TYPE="firmware"
PKG_DESCRIPTION="PVE EDK2 UEFI firmware modules for virtual machines"
PKG_DEPENDS=$'acpica-tools
bc
dosfstools
gcc-aarch64-linux-gnu
libuuid
mtools
nasm
python3-virt-firmware
qemu-img
xorriso'

# Override: patch build files for AlmaLinux
pre_build_hook() {
    if [[ -f "$WORKDIR/Makefile" ]]; then
        sed -i "$WORKDIR/Makefile" \
            -e "s|/usr/share/dpkg|/usr/share/dpkg|g"
    fi
    if [[ -f "$WORKDIR/debian/rules" ]]; then
        sed -i "$WORKDIR/debian/rules" \
            -e "s|/usr/share/dpkg|/usr/share/dpkg|g"
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

full_build
