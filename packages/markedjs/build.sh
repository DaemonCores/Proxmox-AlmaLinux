#!/bin/bash
# build.sh — markedjs (Layer 1: JavaScript library, no PVE deps)
#
# Marked — Markdown parser and compiler for JavaScript.
# Used by proxmox-widget-toolkit and PVE for rendering Markdown docs.
# NPM package, installed as static JS assets.
#
# Adapted from proxmox-nixos:
#   - Nix: buildNpmPackage with npmDepsHash
#   - AlmaLinux: download pre-built from npm or GitHub release
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="markedjs"
MARKED_VERSION="17.0.4"
MARKED_URL="https://github.com/markedjs/marked/releases/download/v${MARKED_VERSION}/marked.min.js"

# ------------------------------------------------------------------
# 1. Download pre-built marked.min.js
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Downloading marked.js ==="
WORKDIR="/tmp/src/${PKG_NAME}"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
curl -L -o "$WORKDIR/marked.min.js" "$MARKED_URL" || {
    # Fallback: download from npm registry
    echo "=== [$PKG_NAME] GitHub release failed, trying npm ==="
    curl -L -o "$WORKDIR/marked.min.js" "https://cdn.jsdelivr.net/npm/marked@${MARKED_VERSION}/marked.min.js" || {
        echo "ERROR: Failed to download marked.js"
        exit 1
    }
}

# ------------------------------------------------------------------
# 2. Build (no compilation — pre-built JS)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building (static JS) ==="

# ------------------------------------------------------------------
# 3. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root/usr/share/javascript/markedjs" "$STAGE/meta"

cp "$WORKDIR/marked.min.js" "$STAGE/root/usr/share/javascript/markedjs/marked.js"

# ------------------------------------------------------------------
# 4. Determine version
# ------------------------------------------------------------------
PKG_VERSION="${MARKED_VERSION}+${SHORT:-git}"

# ------------------------------------------------------------------
# 5. Write meta/ files
# ------------------------------------------------------------------
echo "$PKG_NAME"               > "$STAGE/meta/name"
echo "$PKG_VERSION"            > "$STAGE/meta/version"
echo "${TARGET_ARCH:-x86_64}"  > "$STAGE/meta/arch"
echo "Marked — Markdown parser and compiler for JavaScript" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
EOF

# ------------------------------------------------------------------
# 6. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"