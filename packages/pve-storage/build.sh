#!/bin/bash
# Package: pve-storage
# Layer: 4
# Type: perl-git

PKG_NAME="pve-storage"
REPO_URL="$(get_pkg_meta "$PKG_NAME" repo)"
BUILD_TYPE="perl-git"
BUILD_SUBDIR="src"
PKG_DESCRIPTION="PVE storage library — ZFS, LVM, Ceph RBD, iSCSI, NFS, and more"
PKG_DEPENDS=$'ceph-common
ceph-libs
glusterfs-libs
iperf3
libaio
libiscsi
lvm2
perl
pve-cluster
pve-common
pve-rados2
smartmontools
targetcli'

# Override: patch Makefile and install PVE storage library
pre_build_hook() {
    if [[ -f "Makefile" ]]; then
        sed -i "Makefile" \
            -e '/pvesm.1/d' \
            -e '/bash-completion/d' \
            -e '/zsh-completion/d'
    fi
    if [[ -f "bin/Makefile" ]]; then
        sed -i "bin/Makefile" \
            -e '/pvesm.1/d' \
            -e '/bash-completion/d' \
            -e '/zsh-completion/d'
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
