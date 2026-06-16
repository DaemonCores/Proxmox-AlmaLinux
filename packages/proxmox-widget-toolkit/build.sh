#!/bin/bash
# Package: proxmox-widget-toolkit
# Layer: 1
# Type: node

PKG_NAME="proxmox-widget-toolkit"
REPO_URL="$(get_pkg_meta "$PKG_NAME" repo)"
BUILD_TYPE="node"
BUILD_SUBDIR="src"
PKG_DESCRIPTION="Proxmox ExtJS widget toolkit — JS/CSS for PVE web UI"
PKG_DEPENDS=$'sassc
uglify-js'

# Override: patch defines.mk and Makefile, then make
pre_build_hook() {
    if [[ -f "defines.mk" ]]; then
        sed -i "defines.mk" -e "/BUILD_VERSION=/d"
    fi
    if [[ -f "Makefile" ]]; then
        sed -i "Makefile" \
            -e '/BUILD_VERSION=/d' \
            -e '/BIOME/d'
    fi
}

install_override() {
    mkdir -p "$STAGE/root" "$STAGE/meta"

    make install DESTDIR="$STAGE/root" || true

    # Copy APIViewer.js (per Nix postInstall)
    if [[ -f "$WORKDIR/src/api-viewer/APIViewer.js" ]]; then
        mkdir -p "$STAGE/root/usr/share/javascript/proxmox-widget-toolkit"
        cp "$WORKDIR/src/api-viewer/APIViewer.js" "$STAGE/root/usr/share/javascript/proxmox-widget-toolkit/"
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

full_build
