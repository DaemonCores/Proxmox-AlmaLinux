#!/bin/bash
# Package: pve-network
# Layer: 3
# Type: perl-git

PKG_NAME="pve-network"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

REPO_URL="$(get_pkg_meta "$PKG_NAME" repo)"
BUILD_TYPE="perl-git"
BUILD_SUBDIR="src/PVE"
PKG_DESCRIPTION="PVE network management — SDN, bridges, VLANs, zones"
PKG_DEPENDS=$'perl
perl-IO-Socket-SSL
perl-NetAddr-IP
perl-Net-IP
pve-access-control
pve-cluster
pve-common'

# Override: install PVE network modules
install_override() {
    mkdir -p "$STAGE/root" "$STAGE/meta"

    make install DESTDIR="$STAGE/root" PERL5DIR=/usr/share/perl5/vendor_perl || true

    find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
    find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true
}


full_build
