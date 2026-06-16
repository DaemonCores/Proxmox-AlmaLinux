#!/bin/bash
# Package: pve-container
# Layer: 5
# Type: perl-git

PKG_NAME="pve-container"
REPO_URL="https://git.proxmox.com/git/pve-container.git"
BUILD_TYPE="perl-git"
BUILD_SUBDIR="src"
PKG_DESCRIPTION="PVE container manager — LXC container management (pct command)"
PKG_DEPENDS=$'lxc
lxc-libs
perl
pve-common
pve-guest-common
pve-storage'

# Override: patch Makefile and install PVE container manager
pre_build_hook() {
    if [[ -f "Makefile" ]]; then
        sed -i "Makefile" \
            -e '/GITVERSION/d' \
            -e '/SERVICEDIR/d' \
            -e '/BASHCOMPLDIR/d' \
            -e '/ZSHCOMPLDIR/d' \
            -e '/MAN1DIR/d' \
            -e '/MAN5DIR/d' \
            -e '/PVE_GENERATING_DOCS/d' \
            -e 's/-Werror/-Wno-error/g'
    fi
}

install_override() {
    mkdir -p "$STAGE/root" "$STAGE/meta"

    make install DESTDIR="$STAGE/root" PREFIX=/usr SBINDIR=/usr/sbin \
        PERLDIR=/usr/share/perl5/vendor_perl || true

    find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
    find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

full_build
