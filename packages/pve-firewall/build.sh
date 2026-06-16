#!/bin/bash
# Package: pve-firewall
# Layer: 4
# Type: perl-git

PKG_NAME="pve-firewall"
REPO_URL="https://git.proxmox.com/git/pve-firewall.git"
BUILD_TYPE="perl-git"
BUILD_SUBDIR="src"
PKG_DESCRIPTION="PVE firewall — iptables/nftables rules, ipsets, and security groups"
PKG_DEPENDS=$'glib2
libnetfilter_conntrack
libnetfilter_log
libnfnetlink
perl
pve-access-control
pve-cluster
pve-common
pve-network'

# Override: patch Makefile and install PVE firewall
pre_build_hook() {
    if [[ -f "Makefile" ]]; then
        sed -i "Makefile" \
            -e '/pve-firewall.1/d' \
            -e '/bash-completion/d' \
            -e '/zsh-completion/d' \
            -e '/dpkg-buildflags/d' \
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
