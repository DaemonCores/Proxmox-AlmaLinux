#!/bin/bash
# Package: pve-ha-manager
# Layer: 4
# Type: perl-git

PKG_NAME="pve-ha-manager"
REPO_URL="https://git.proxmox.com/git/pve-ha-manager.git"
BUILD_TYPE="perl-git"
BUILD_SUBDIR="src"
PKG_DESCRIPTION="PVE HA manager — high availability for VMs and containers"
PKG_DEPENDS=$'perl
pve-cluster
pve-common'

# Override: patch Makefile and install PVE HA manager
pre_build_hook() {
    if [[ -f "Makefile" ]]; then
        sed -i "Makefile" \
            -e '/pve-ha-crm.1/d' \
            -e '/pve-ha-lm.1/d' \
            -e '/bash-completion/d' \
            -e '/zsh-completion/d' \
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

source ../../scripts/build-template.sh

full_build
