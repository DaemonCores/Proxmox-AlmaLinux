#!/bin/bash
# Package: pve-manager
# Layer: 5
# Type: perl-git

PKG_NAME="pve-manager"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

REPO_URL="$(get_pkg_meta "$PKG_NAME" repo)"
BUILD_TYPE="perl-git"
PKG_DESCRIPTION="PVE manager — web UI, REST API, and management daemons"
PKG_DEPENDS=$'ceph-common
corosync
gnupg2
graphviz
gzip
iproute
openssh
openssl
perl
perl-Crypt-OpenSSL-Bignum
perl-File-ReadBackwards
perl-Net-DNS
perl-Pod-Parser
perl-Template-Toolkit
perl-proxmox-acme
pve-cluster
pve-container
pve-docs
pve-firewall
pve-guest-common
pve-ha-manager
pve-http-server
pve-network
pve-qemu-server
pve-storage
proxmox-i18n
proxmox-widget-toolkit
shadow-utils
sqlite
systemd
util-linux
wget'

# Override: patch build files, build, and install PVE manager
pre_build_hook() {
    # Strip /usr from defines.mk
    if [[ -f "defines.mk" ]]; then
        sed -i "defines.mk" -e "s|/usr||g" 2>/dev/null || true
    fi

    # Patch Makefile — strip Debian-specific targets
    if [[ -f "Makefile" ]]; then
        sed -i "Makefile" \
            -e '/GITVERSION/d' \
            -e '/default.mk/d' \
            -e '/pkg-info/d' \
            -e '/log/d' \
            -e '/architecture/d' \
            -e 's/aplinfo PVE bin www services configs network-hooks test/PVE bin www configs test/'
    fi

    # Strip pod2man/man page targets from bin/Makefile
    if [[ -f "bin/Makefile" ]]; then
        sed -i "bin/Makefile" \
            -e '/pod2man/,+1d' \
            -e '/install -d.*MAN1DIR/,+9d'
    fi

    # Fix asciidoc-pve path
    if [[ -f "www/manager6/Makefile" ]]; then
        sed -i "www/manager6/Makefile" \
            -e '/BIOME/d' \
            -e "s|/usr/bin/asciidoc-pve|/usr/bin/asciidoc-pve|g"
    fi
}

install_override() {
    mkdir -p "$STAGE/root" "$STAGE/meta"

    make install \
        DESTDIR="$STAGE/root" \
        PVERELEASE=9.0 \
        VERSION="${PKG_VERSION:-dev}" \
        REPOID=almalinux \
        PERLLIBDIR=/usr/share/perl5/vendor_perl \
        WIDGETKIT=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js \
        BASH_COMPLETIONS= \
        ZSH_COMPLETIONS= \
        CLI_MANS= \
        SERVICE_MANS= \
        || true

    # Remove Debian-specific tools not needed on AlmaLinux
    rm -rf "$STAGE/root/var" 2>/dev/null || true
    rm -f "$STAGE/root/usr/bin/pveupgrade" 2>/dev/null || true
    rm -f "$STAGE/root/usr/bin/pveupdate" 2>/dev/null || true
    rm -f "$STAGE/root/usr/bin/pveversion" 2>/dev/null || true
    rm -f "$STAGE/root/usr/bin/pve8to9" 2>/dev/null || true

    # Strip -T taint flag from scripts
    for script in "$STAGE/root/usr/bin/"* "$STAGE/root/usr/sbin/"* "$STAGE/root/usr/share/pve-manager/helpers/"*; do
        [[ -f "$script" ]] && sed -i "$script" -e "s/-T//" 2>/dev/null || true
    done

    # Path substitutions for AlmaLinux
    find "$STAGE/root" -type f \( -name "*.pl" -o -name "*.pm" \) | while read -r f; do
        sed -i "$f" \
            -e "/API2::APT/d" \
            -e "/ENV{'PATH'}/d" \
            -e "s|/usr/share/perl5|/usr/share/perl5/vendor_perl|g" || true
    done

    find "$STAGE/root/usr/bin" "$STAGE/root/usr/sbin" \
        "$STAGE/root/usr/share/pve-manager/helpers" \
        -type f 2>/dev/null | while read -r f; do
        sed -i "$f" \
            -e "/ENV{'PATH'}/d" \
            -e "/API2::APT/d" || true
    done

    find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
    find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true
}


full_build
