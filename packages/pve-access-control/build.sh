#!/bin/bash
# Package: pve-access-control
# Layer: 1
# Type: perl-git

PKG_NAME="pve-access-control"
REPO_URL="https://git.proxmox.com/git/pve-access-control.git"
BUILD_TYPE="perl-git"
BUILD_SUBDIR="src"
PKG_DESCRIPTION="PVE access control framework — user, role, and permission management"
PKG_DEPENDS=$'perl
perl-authen-pam
pve-common'

# Override: patch Makefile for AlmaLinux
pre_build_hook() {
    if [[ -f "Makefile" ]]; then
        sed -i "Makefile" \
            -e "s/pveum.1 oathkeygen pveum.bash-completion pveum.zsh-completion/oathkeygen/" \
            -e "/pveum.1/,+2d"
    fi
}

install_override() {
    mkdir -p "$STAGE/root" "$STAGE/meta"

    make install DESTDIR="$STAGE/root" PREFIX=/usr SBINDIR=/usr/sbin BINDIR=/usr/bin \
        PERLDIR=/usr/share/perl5/vendor_perl || true

    find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
    find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

full_build
