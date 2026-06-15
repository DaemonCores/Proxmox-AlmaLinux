#!/bin/bash
# Package: markedjs
# Layer: 1
# Type: node-hash

PKG_NAME="markedjs"
BUILD_TYPE="node-hash"
PKG_DESCRIPTION="Marked — Markdown parser and compiler for JavaScript"
MARKED_VERSION="17.0.4"
MARKED_URL="https://cdn.jsdelivr.net/npm/marked@17.0.4/lib/marked.umd.min.js"
MARKED_FALLBACK_URL="https://cdn.jsdelivr.net/npm/marked/lib/marked.umd.min.js"
DOWNLOAD_URL="https://cdn.jsdelivr.net/npm/marked@17.0.4/lib/marked.umd.min.js"
DOWNLOAD_VERSION="17.0.4"
DOWNLOAD_FALLBACK_URL="https://cdn.jsdelivr.net/npm/marked/lib/marked.umd.min.js"

# Override: download pre-built marked.min.js
fetch_source_download() {
    echo "=== [$PKG_NAME] Downloading marked.js ==="
    WORKDIR="/tmp/src/${PKG_NAME}"
    rm -rf "$WORKDIR"
    mkdir -p "$WORKDIR"
    if ! curl -L -o "$WORKDIR/marked.min.js" "$MARKED_URL"; then
        echo "=== [$PKG_NAME] GitHub release failed, trying npm ==="
        if ! curl -L -o "$WORKDIR/marked.min.js" "$MARKED_FALLBACK_URL"; then
            echo "ERROR: Failed to download marked.js"
            exit 1
        fi
    fi
}

# Override: install marked.js to staging
install_override() {
    mkdir -p "$STAGE/root/usr/share/javascript/markedjs" "$STAGE/meta"

    cp "$WORKDIR/marked.min.js" "$STAGE/root/usr/share/javascript/markedjs/marked.js"
}

# Override: version from download URL
detect_version() { echo "${MARKED_VERSION}+${SHORT:-git}"; }

source ../../scripts/build-template.sh

full_build
