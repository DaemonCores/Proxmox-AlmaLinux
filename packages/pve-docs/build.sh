#!/bin/bash
# Package: pve-docs
# Layer: 1
# Type: docs

PKG_NAME="pve-docs"
REPO_URL="git://git.proxmox.com/git/pve-docs.git"
BUILD_TYPE="docs"
PKG_DESCRIPTION="PVE documentation — asciidoc-generated HTML/PDF docs"
PKG_DEPENDS=$'asciidoc
graphviz
imagemagick
perl
perl-JSON
perl-Template-Toolkit'

# Override: patch build files for AlmaLinux
pre_build_hook() {
    if [[ -f "Makefile" ]]; then
        sed -i "Makefile" \
            -e '/GITVERSION/d' \
            -e '/pkg-info/d' \
            -e "s|/usr/share/javascript/proxmox-widget-toolkit-dev|/usr/share/javascript/proxmox-widget-toolkit|g"
    fi

    if [[ -f "images/Makefile" ]]; then
        sed -i "images/Makefile" -e "s|/usr/share/pve-docs|/usr/share/pve-docs|g"
    fi

    if [[ -f "asciidoc-pve.in" ]]; then
        sed -i 'asciidoc-pve.in' -e '1s|#!/usr/bin/perl|#!/usr/bin/perl|'
    fi
}

source ../../scripts/build-template.sh

full_build
