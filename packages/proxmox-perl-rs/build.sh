#!/bin/bash
# Package: proxmox-perl-rs
# Layer: 1
# Type: rust-perl

PKG_NAME="proxmox-perl-rs"
REPO_URL="https://git.proxmox.com/git/proxmox-perl-rs.git"
BUILD_TYPE="rust-perl"
BUILD_SUBDIR="pve-rs"
PKG_DESCRIPTION="Proxmox Rust bindings for Perl — perlmod-generated XS modules"
PKG_DEPENDS=$'cargo
perl
libuuid
openssl-libs
pkgconf-pkg-config'

# Override: patch Makefiles for AlmaLinux
pre_build_hook() {
    for mkfile in common/pkg/Makefile pve-rs/Makefile; do
        if [[ -f "$WORKDIR/$mkfile" ]]; then
            sed -i "$WORKDIR/$mkfile" \
                -e '/GITVERSION/d' \
                -e '/dpkg-architecture/d' \
                -e '/pkg-info/d' \
                -e '/MConfig/d'
        fi
    done
}

# Override: build Rust + Perl wrapper
build_override() {
    cd "$WORKDIR/pve-rs"

    # Build the Rust library
    cargo build --release

    # Build the Perl module wrapper
    make BUILDIR="/tmp/src/${PKG_NAME}" BUILD_MODE=release GITVERSION="${SHORT:-git}" || true
}

install_override() {
    mkdir -p "$STAGE/root" "$STAGE/meta"

    # Install Perl modules and .so from pve-rs
    make install DESTDIR="$STAGE/root" \
        BUILDIR="/tmp/src/${PKG_NAME}" \
        BUILD_MODE=release \
        PERL_INSTALLVENDORARCH="/usr/lib64/perl5/vendor_perl" \
        PERL_INSTALLVENDORLIB="/usr/share/perl5/vendor_perl" || true

    # Install common/pkg Perl modules
    cd "$WORKDIR/common/pkg"
    make install PERL_INSTALLVENDORLIB="$STAGE/root/usr/share/perl5/vendor_perl" || true
    cd "$WORKDIR"

    find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
    find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true
}

source ../../scripts/build-template.sh

full_build
