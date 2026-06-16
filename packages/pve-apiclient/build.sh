#!/bin/bash
# Package: pve-apiclient
# Layer: 1
# Type: perl-git

PKG_NAME="pve-apiclient"
REPO_URL="$(get_pkg_meta "$PKG_NAME" repo)"
BUILD_TYPE="perl-git"
BUILD_SUBDIR="src"
PKG_DESCRIPTION="PVE API client — Perl library for Proxmox VE REST API"
PKG_DEPENDS=$'perl
perl-IO-Socket-SSL'

install_override() {
    mkdir -p "$STAGE/root" "$STAGE/meta"

    make install DESTDIR="$STAGE/root" \
        PERL5DIR=/usr/share/perl5/vendor_perl \
        DOCDIR=/usr/share/doc || true

    find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
    find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

full_build
