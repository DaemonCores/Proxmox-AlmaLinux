#!/bin/bash
# Package: vncterm
# Layer: 1
# Type: c-patched

PKG_NAME="vncterm"
REPO_URL="$(get_pkg_meta "$PKG_NAME" repo)"
BUILD_TYPE="c-patched"
PKG_DESCRIPTION="vncterm — VNC terminal emulator for Proxmox VE console access"
PKG_DEPENDS=$'gnutls
libjpeg
libpng
libvncserver
unifont-hex'

# Override: patch Makefile for AlmaLinux build
pre_build_hook() {
    if [[ -f "Makefile" ]]; then
        sed -i "Makefile" \
            -e "/architecture.mk/d" \
            -e "/pkg-info/d" \
            -e "s|/usr/share/unifont/unifont.hex|/usr/share/unifont/unifont.hex|g" \
            -e "s|usr/||g" \
            -e "s/Werror/Wno-error/" \
            -e "s|wchardata.c|/usr/share/unifont/wchardata.c|g" \
            -e "/pod2man/d" \
            -e "/man1/d" 2>/dev/null || true
    fi

    # Apply TLS auth plugin patches from vncpatches/ if they exist
    if [[ -d "vncpatches" ]]; then
        for patch in vncpatches/*.patch; do
            [[ -f "$patch" ]] && patch -p1 -i "$patch" || true
        done
    fi
}

# Override: build vncterm binary
build_override() {
    make -j"$(nproc)" VNCLIB="-lvncserver" VNCDIR="/usr/include" DESTDIR="/tmp/pkg/${PKG_NAME}/root" || true
}

# Override: install vncterm binary
install_override() {
    mkdir -p "$STAGE/root/usr/bin" "$STAGE/meta"

    make install DESTDIR="$STAGE/root" PREFIX=/usr SBINDIR=/usr/bin || true

    # Ensure binary is installed
    if [[ -f "vncterm" ]] && [[ ! -f "$STAGE/root/usr/bin/vncterm" ]]; then
        install -Dm755 vncterm "$STAGE/root/usr/bin/vncterm"
    fi

    # Patch /usr reference in binary
    if [[ -f "$STAGE/root/usr/bin/vncterm" ]]; then
        sed -i "$STAGE/root/usr/bin/vncterm" -e "s|/usr|$STAGE/root/usr|g" 2>/dev/null || true
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

full_build
