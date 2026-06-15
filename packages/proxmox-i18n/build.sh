#!/bin/bash
# Package: proxmox-i18n
# Layer: 1
# Type: i18n

PKG_NAME="proxmox-i18n"
REPO_URL="git://git.proxmox.com/git/proxmox-i18n.git"
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

source ../../scripts/build-template.sh

full_build
