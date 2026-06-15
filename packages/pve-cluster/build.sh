#!/bin/bash
# Package: pve-cluster
# Layer: 3
# Type: perl-git

PKG_NAME="pve-cluster"
REPO_URL="git://git.proxmox.com/git/pve-cluster.git"
BUILD_TYPE="perl-git"
BUILD_SUBDIR="src"
PKG_DESCRIPTION="PVE cluster filesystem (pmxcfs) and cluster management tools"
PKG_DEPENDS=$'corosync
fuse
glib2
libqb
libxcrypt
perl
perl-Net-DNS
perl-IO-Socket-SSL
pve-access-control
pve-apiclient
pve-common
proxmox-perl-rs
rrdtool
sqlite'

# Override: build and install pve-cluster (C + Perl hybrid)
pre_build_hook() {
    # Strip Debian-specific targets from Makefiles
    for mkfile in Makefile src/Makefile; do
        if [[ -f "$WORKDIR/$mkfile" ]]; then
            sed -i "$WORKDIR/$mkfile" \
                -e '/GITVERSION/d' \
                -e '/pkg-info/d' \
                -e '/architecture/d' \
                -e '/dpkg-buildflags/d'
        fi
    done
}

install_override() {
    mkdir -p "$STAGE/root" "$STAGE/meta"

    make install DESTDIR="$STAGE/root" PREFIX=/usr SBINDIR=/usr/sbin \
        PERLDIR=/usr/share/perl5/vendor_perl || true

    # Strip hard-coded /usr/bin/ and /usr/sbin/ from Perl modules
    find "$STAGE/root" -type f \( -name "*.pm" -o -name "*.pl" \) | while read -r f; do
        sed -i "$f" -e "s|(/usr)?/s?bin/||g" 2>/dev/null || true
    done

    find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
    find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true
}

source ../../scripts/build-template.sh

full_build
