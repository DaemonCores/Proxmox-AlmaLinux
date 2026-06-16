#!/bin/bash
# Package: pve-guest-common
# Layer: 2
# Type: perl-git

PKG_NAME="pve-guest-common"
REPO_URL="https://git.proxmox.com/git/pve-guest-common.git"
BUILD_TYPE="perl-git"
BUILD_SUBDIR="src"
PKG_DESCRIPTION="PVE guest-related Perl modules — common code for guest agents"
PKG_DEPENDS=$'perl
pve-common'

# Override: install PVE guest-common modules
install_override() {
    mkdir -p "$STAGE/root" "$STAGE/meta"

    make install DESTDIR="$STAGE/root" \
        PERL5DIR=/usr/share/perl5/vendor_perl \
        DOCDIR=/usr/share/doc/pve-guest-common || true

    find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
    find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

full_build
