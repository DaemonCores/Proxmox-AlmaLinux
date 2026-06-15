#!/bin/bash
# Package: pve-novnc
# Layer: 7
# Type: node

PKG_NAME="pve-novnc"
REPO_URL="https://git.proxmox.com/git/novnc-pve.git"
BUILD_TYPE="node"
CLONE_RECURSIVE="1"
PKG_DESCRIPTION="PVE noVNC — Web-based VNC client for Proxmox VE"

# Override: build with esbuild and install noVNC web assets
build_override() {
    cd "$WORKDIR/novnc" 2>/dev/null || cd "$WORKDIR" || true

    # Apply Debian patches
    apply_debian_patches

    # Build with esbuild if available
    if command -v esbuild &>/dev/null; then
        if [[ -f "app/ui.js" ]]; then
            esbuild --bundle --format=esm app/ui.js > app.js 2>/dev/null || true
        fi
    fi
}

install_override() {
    mkdir -p "$STAGE/root/usr/share/novnc-pve" "$STAGE/meta"

    # Copy all web assets
    if [[ -d "$WORKDIR/novnc" ]]; then
        cp -r "$WORKDIR/novnc/"* "$STAGE/root/usr/share/novnc-pve/" 2>/dev/null || true
    elif [[ -d "$WORKDIR" ]]; then
        for dir in app core vendor images include; do
            [[ -d "$WORKDIR/$dir" ]] && cp -r "$WORKDIR/$dir" "$STAGE/root/usr/share/novnc-pve/" || true
        done
        for f in vnc.html *.js *.css; do
            [[ -f "$WORKDIR/$f" ]] && cp "$WORKDIR/$f" "$STAGE/root/usr/share/novnc-pve/" || true
        done
    fi

    # Copy bundled app.js if built
    local build_dir="$WORKDIR"
    [[ -d "$WORKDIR/novnc" ]] && build_dir="$WORKDIR/novnc"
    if [[ -f "$build_dir/app.js" ]]; then
        cp "$build_dir/app.js" "$STAGE/root/usr/share/novnc-pve/"
    fi
}

source ../../scripts/build-template.sh

full_build
