#!/bin/bash
# Package: fonts-font-logos
# Layer: 1
# Type: font

PKG_NAME="fonts-font-logos"
REPO_URL="$(get_pkg_meta "$PKG_NAME" repo)"
BUILD_TYPE="font"
BUILD_SUBDIR="src"
PKG_DESCRIPTION="Font logos — Font Awesome + custom font icons for PVE web UI"
PKG_DEPENDS=$'fontconfig'

# Override: install font assets
install_override() {
    mkdir -p "$STAGE/root/usr/share/fonts-font-logos/css" "$STAGE/root/usr/share/fonts-font-logos/fonts"

    if [[ -d "$WORKDIR/src/font-logos/assets" ]]; then
        cp -r "$WORKDIR/src/font-logos/assets" "$STAGE/root/usr/share/fonts-font-logos/fonts/"
    fi
    if [[ -f "$WORKDIR/src/font-logos.css" ]]; then
        cp "$WORKDIR/src/font-logos.css" "$STAGE/root/usr/share/fonts-font-logos/css/"
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

full_build
