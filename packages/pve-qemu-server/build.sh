#!/bin/bash
# Package: pve-qemu-server
# Layer: 5
# Type: perl-git

PKG_NAME="pve-qemu-server"
REPO_URL="https://git.proxmox.com/git/qemu-server.git"
BUILD_TYPE="perl-git"
BUILD_SUBDIR="src"
PKG_DESCRIPTION="PVE QEMU server — QEMU/KVM VM management (qm command)"
PKG_DEPENDS=$'ceph-common
glusterfs-libs
perl
pve-common
pve-guest-common
pve-qemu
pve-storage'

# Override: patch Makefile and install PVE QEMU server
pre_build_hook() {
    if [[ -f "Makefile" ]]; then
        sed -i "Makefile" \
            -e '/GITVERSION/d' \
            -e '/default.mk/d' \
            -e '/pve-doc-generator/d' \
            -e '/MAN1DIR/d' \
            -e '/bash-completion/d' \
            -e '/zsh-completion/d' \
            -e 's/-Werror/-Wno-error/g'
    fi
    if [[ -f "bin/Makefile" ]]; then
        sed -i "bin/Makefile" \
            -e '/pod2man/d' \
            -e '/MAN1DIR/d'
    fi
}

install_override() {
    mkdir -p "$STAGE/root" "$STAGE/meta"

    make install DESTDIR="$STAGE/root" \
        PKGSOURCES="qm qmrestore qmextract" \
        PREFIX=/usr SBINDIR=/usr/sbin \
        PERLDIR=/usr/share/perl5/vendor_perl \
        USRSHAREDIR=/usr/share/qemu-server || true

    find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
    find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true

    # Strip ENV{PATH} lines from Perl modules (AlmaLinux uses PATH-resolved tools)
    find "$STAGE/root" -type f \( -name "*.pm" -o -name "*.pl" \) | while read -r f; do
        sed -i "$f" -e "/ENV{'PATH'}/d" 2>/dev/null || true
    done
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

full_build
