#!/bin/bash
# Package: pve-xtermjs
# Layer: 7
# Type: node

PKG_NAME="pve-xtermjs"
REPO_URL="git://git.proxmox.com/git/pve-xtermjs.git"
BUILD_TYPE="node"
PKG_DESCRIPTION="PVE xterm.js — Web-based terminal emulator for Proxmox VE"
PKG_DEPENDS=$'termproxy'

# Override: install static web assets for xterm.js terminal
install_override() {
    mkdir -p "$STAGE/root/usr/share/pve-xtermjs" "$STAGE/meta"

    # Copy all web assets per Nix installPhase
    if [[ -d "$WORKDIR/xterm.js/src" ]]; then
        cp -r "$WORKDIR/xterm.js/src/"* "$STAGE/root/usr/share/pve-xtermjs/"
    elif [[ -d "$WORKDIR/src" ]]; then
        cp -r "$WORKDIR/src/"* "$STAGE/root/usr/share/pve-xtermjs/"
    fi

    # Rename template files per Nix postInstall
    cd "$STAGE/root/usr/share/pve-xtermjs"
    [[ -f "index.html.hbs.in" ]] && mv index.html.hbs.in index.html.hbs 2>/dev/null || true
    [[ -f "index.html.tpl.in" ]] && mv index.html.tpl.in index.html.tpl 2>/dev/null || true
}

source ../../scripts/build-template.sh

full_build
