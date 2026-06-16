#!/bin/bash
# Package: pve-http-server
# Layer: 3
# Type: perl-git

PKG_NAME="pve-http-server"
REPO_URL="https://git.proxmox.com/git/pve-http-server.git"
BUILD_TYPE="perl-git"
BUILD_SUBDIR="src"
PKG_DESCRIPTION="PVE HTTP server — serves the Proxmox VE web UI and REST API"
PKG_DEPENDS=$'perl
perl-AnyEvent-HTTP
proxmox-i18n
proxmox-widget-toolkit
pve-common'

# Override: install PVE HTTP server
install_override() {
    mkdir -p "$STAGE/root" "$STAGE/meta"

    make install DESTDIR="$STAGE/root" PERL5DIR=/usr/share/perl5/vendor_perl || true

    # Create expected web asset directories (populated at install time)
    mkdir -p "$STAGE/root/usr/share/javascript" "$STAGE/root/usr/share/bootstrap-html" 2>/dev/null || true

    find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
    find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

full_build
