#!/bin/bash
# Package: proxmox-i18n
# Layer: 1
# Type: i18n

PKG_NAME="proxmox-i18n"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

REPO_URL="$(get_pkg_meta "$PKG_NAME" repo)"
BUILD_TYPE="i18n"
PKG_DESCRIPTION="Proxmox internationalization — gettext translation files"
PKG_DEPENDS=$'gettext
perl'

# Override: patch Makefile — strip Debian-specific targets
pre_build_hook() {
    if [[ -f "$WORKDIR/Makefile" ]]; then
        sed -i "$WORKDIR/Makefile" \
            -e '/include.*dpkg.*pkg-info\.mk/d' \
            -e 's|/usr/share|/usr/share|g'
    fi
}


full_build
