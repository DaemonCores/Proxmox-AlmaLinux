#!/bin/bash
# Package: pve-rados2
# Layer: 4
# Type: perl-git

PKG_NAME="pve-rados2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

REPO_URL="$(get_pkg_meta "$PKG_NAME" repo)"
BUILD_TYPE="perl-git"
PKG_DESCRIPTION="PVE RADOS2 — Perl bindings for Ceph RADOS (librados)"
PKG_DEPENDS=$'ceph-devel
perl
pve-common'

# Override: patch Makefile and install pve-rados2 (Perl XS)
pre_build_hook() {
    if [[ -f "Makefile" ]]; then
        sed -i "Makefile" \
            -e '/GITVERSION/d' \
            -e '/pkg-info/d' \
            -e '/architecture/d' 2>/dev/null || true
    fi
}

install_override() {
    mkdir -p "$STAGE/root" "$STAGE/meta"

    make install DESTDIR="$STAGE/root" PREFIX=/usr SBINDIR=/usr/bin \
        PERLDIR=/usr/share/perl5/vendor_perl \
        PERLSODIR=/usr/lib64/perl5/vendor_perl/auto || true

    find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
    find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true
}


full_build
