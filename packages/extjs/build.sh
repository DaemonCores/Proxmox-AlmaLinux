#!/bin/bash
# Package: extjs
# Layer: 1
# Type: node

PKG_NAME="extjs"
REPO_URL="https://git.proxmox.com/git/extjs.git"
BUILD_TYPE="node"
PKG_DESCRIPTION="ExtJS JavaScript framework for PVE web UI"

# Override: install ExtJS static assets
install_override() {
    mkdir -p "$STAGE/root/usr/share/javascript/extjs" "$STAGE/meta"

    # Copy ExtJS assets per Nix postInstall
    if [[ -d "$WORKDIR/extjs/build" ]]; then
        BUILD_DIR="$WORKDIR/extjs/build"
    elif [[ -d "$WORKDIR/build" ]]; then
        BUILD_DIR="$WORKDIR/build"
    else
        BUILD_DIR="$WORKDIR"
    fi

    for f in ext-all-debug.js ext-all.js; do
        if [[ -f "$BUILD_DIR/$f" ]]; then
            cp "$BUILD_DIR/$f" "$STAGE/root/usr/share/javascript/extjs/"
        fi
    done

    if [[ -d "$BUILD_DIR/classic/locale" ]]; then
        cp -r "$BUILD_DIR/classic/locale" "$STAGE/root/usr/share/javascript/extjs/"
    fi

    if [[ -d "$BUILD_DIR/classic/theme-crisp" ]]; then
        cp -r "$BUILD_DIR/classic/theme-crisp" "$STAGE/root/usr/share/javascript/extjs/"
    fi

    if [[ -f "$BUILD_DIR/packages/charts/classic/charts-debug.js" ]]; then
        cp "$BUILD_DIR/packages/charts/classic/charts-debug.js" "$STAGE/root/usr/share/javascript/extjs/"
    fi
    if [[ -f "$BUILD_DIR/packages/charts/classic/charts.js" ]]; then
        cp "$BUILD_DIR/packages/charts/classic/charts.js" "$STAGE/root/usr/share/javascript/extjs/"
    fi
    if [[ -d "$BUILD_DIR/packages/charts/classic/crisp" ]]; then
        cp -r "$BUILD_DIR/packages/charts/classic/crisp" "$STAGE/root/usr/share/javascript/extjs/"
    fi
}

source ../../scripts/build-template.sh

full_build
