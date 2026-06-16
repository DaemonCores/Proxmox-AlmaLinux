#!/bin/bash
# Package: pve-common
# Layer: 2
# Type: perl-git

PKG_NAME="pve-common"
REPO_URL="$(get_pkg_meta "$PKG_NAME" repo)"
BUILD_TYPE="perl-git"
PKG_DESCRIPTION="PVE common Perl library — core utilities, INotify, ProcFSTools, and more"
PKG_DEPENDS=$'perl
perl-authen-pam
perl-crypt-openssl-random
perl-crypt-openssl-rsa
perl-data-dumper
perl-digest-sha
perl-file-readbackwards
perl-filesys-df
perl-findbin
perl-http-daemon
perl-iosocketip
perl-json
perl-linux-inotify2
perl-mail-spamassassin
perl-mimebase32
perl-mimebase64
perl-netsubnet
perl-net-dns
perl-net-ip
perl-net-ssleay
perl-posixstrptime
perl-socket
perl-termreadline
perl-testharness
perl-uri
perl-uuid
perl-www-perl
perl-xml-parser
proxmox-backup-qemu'

# Override: install PVE common library
pre_build_hook() {
    # Patch Makefile for AlmaLinux — strip Debian-specific targets
    if [[ -f "Makefile" ]]; then
        sed -i "Makefile" \
            -e '/GITVERSION/d' \
            -e '/default.mk/d' \
            -e '/pkg-info/d'
    fi
}

install_override() {
    mkdir -p "$STAGE/root" "$STAGE/meta"

    make install DESTDIR="$STAGE/root" INSTALLDIRS=vendor || true

    find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
    find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

full_build
