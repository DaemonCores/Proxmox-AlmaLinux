#!/bin/bash
# Package: qrcodejs
# Layer: 1
# Type: node

PKG_NAME="qrcodejs"
REPO_URL="git://git.proxmox.com/git/libjs-qrcodejs.git"
BUILD_TYPE="node"
BUILD_SUBDIR="src"
PKG_DESCRIPTION="QRCode.js — Cross-browser QR code generator for JavaScript"

# Override: build with uglify-js
build_override() {
    if command -v uglifyjs &>/dev/null; then
        if [[ -f "qrcode.js" ]]; then
            uglifyjs qrcode.js -o qrcode.min.js || true
        fi
    fi
}

install_override() {
    mkdir -p "$STAGE/root/usr/share/javascript/qrcodejs" "$STAGE/meta"

    if [[ -f "qrcode.min.js" ]]; then
        cp qrcode.min.js "$STAGE/root/usr/share/javascript/qrcodejs/"
    elif [[ -f "qrcode.js" ]]; then
        cp qrcode.js "$STAGE/root/usr/share/javascript/qrcodejs/"
    fi
}

source ../../scripts/build-template.sh

full_build
