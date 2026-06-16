#!/bin/bash
# Package: unifont-hex
# Layer: 1
# Type: font-hash

PKG_NAME="unifont-hex"
BUILD_TYPE="font-hash"
PKG_DESCRIPTION="GNU Unifont — hex format font data for vncterm"
UNIFONT_VERSION="17.0.03"
UNIFONT_URL="https://ftp.gnu.org/gnu/unifont/unifont-17.0.03/unifont-17.0.03.tar.gz"
DOWNLOAD_URL="https://ftp.gnu.org/gnu/unifont/unifont-17.0.03/unifont-17.0.03.tar.gz"
DOWNLOAD_VERSION="17.0.03"
DOWNLOAD_EXTRACT_DIR="unifont-17.0.03"

# Override: download and extract unifont tarball
fetch_source_download() {
    echo "=== [$PKG_NAME] Downloading source from GNU ==="
    WORKDIR="/tmp/src/${PKG_NAME}"
    rm -rf "$WORKDIR"
    mkdir -p "$WORKDIR"
    curl -L -o "/tmp/${PKG_NAME}.tar.gz" "$UNIFONT_URL"
    tar xzf "/tmp/${PKG_NAME}.tar.gz" -C "/tmp/src"
    mv "/tmp/src/unifont-${UNIFONT_VERSION}" "$WORKDIR" 2>/dev/null || true
    cd "$WORKDIR"
}

# Override: build hex font data
build_override() {
    make -j"$(nproc)" hex || true
}

# Override: install hex font data
install_override() {
    mkdir -p "$STAGE/root/usr/share/unifont" "$STAGE/meta"

    if [[ -f "unifont.hex" ]]; then
        cp unifont.hex "$STAGE/root/usr/share/unifont/"
    elif [[ -f "font/plane00/unifont.hex" ]]; then
        cp font/plane00/unifont.hex "$STAGE/root/usr/share/unifont/"
    fi

    if [[ -f "wchardata.c" ]]; then
        cp wchardata.c "$STAGE/root/usr/share/unifont/"
    fi
}

# Override: version from download URL
detect_version() { echo "${UNIFONT_VERSION}+${SHORT:-git}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

full_build
