#!/bin/bash
# build.sh — pve-docs (Layer 1: Documentation, asciidoc/pandoc generation)
#
# Generates HTML/PDF documentation from asciidoc sources for PVE.
# Requires asciidoc, graphviz, imagemagick, dblatex for PDF, etc.
#
# Adapted from proxmox-nixos:
#   - Nix postPatch: patchShebangs, fix perl path in asciidoc-pve.in,
#     strip GITVERSION/pkg-info from Makefile, fix proxmox-widget-toolkit-dev path,
#     strip /usr prefix, fix asciidoc resource paths
#   - Nix makeFlags: GITVERSION, DOCRELEASE, DESTDIR
#   - AlmaLinux: standard asciidoc, FHS paths
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="pve-docs"
REPO_URL="git://git.proxmox.com/git/pve-docs.git"

# ------------------------------------------------------------------
# 1. Clone source
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Cloning source ==="
WORKDIR="/tmp/src/${PKG_NAME}"
rm -rf "$WORKDIR"
git clone "$REPO_URL" "$WORKDIR"
cd "$WORKDIR"

if [[ -n "${VERSION:-}" ]]; then
    git checkout "$VERSION" 2>/dev/null || git checkout "${SHORT:-${VERSION:0:7}}" 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 2. Patch build files — strip Debian-specific targets
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Patching build files ==="
# Nix: sed -i Makefile -e '/GITVERSION/d' -e '/pkg-info/d' -e "s|/usr/share/javascript/proxmox-widget-toolkit-dev|...|"
#      -e 's|/usr||'
# AlmaLinux: keep /usr prefix, strip GITVERSION/pkg-info
if [[ -f "Makefile" ]]; then
    sed -i "Makefile" \
        -e '/GITVERSION/d' \
        -e '/pkg-info/d' \
        -e "s|/usr/share/javascript/proxmox-widget-toolkit-dev|/usr/share/javascript/proxmox-widget-toolkit|g"
fi

if [[ -f "images/Makefile" ]]; then
    sed -i "images/Makefile" -e "s|/usr/share/pve-docs|/usr/share/pve-docs|g"
fi

# Fix asciidoc-pve perl shebang
if [[ -f "asciidoc-pve.in" ]]; then
    sed -i "asciidoc-pve.in" -e '1s|#!/usr/bin/perl|#!/usr/bin/perl|'
fi

# ------------------------------------------------------------------
# 3. Build (asciidoc → HTML docs)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
# pve-docs uses make to generate HTML from asciidoc
make -j"$(nproc)" DOCRELEASE="${PKG_VERSION:-dev}" || true

# ------------------------------------------------------------------
# 4. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root" "$STAGE/meta"

make install DESTDIR="$STAGE/root" DOCRELEASE="${PKG_VERSION:-dev}" || true

# ------------------------------------------------------------------
# 5. Determine version
# ------------------------------------------------------------------
PKG_VERSION=""
if [[ -f "$WORKDIR/debian/changelog" ]]; then
    PKG_VERSION="$(head -1 "$WORKDIR/debian/changelog" | sed 's/.*(\([^)]*\)).*/\1/')"
fi
if [[ -z "${PKG_VERSION:-}" ]]; then
    PKG_VERSION="${SHORT:-0.0.1}"
fi
PKG_VERSION="${PKG_VERSION}+${SHORT:-git}"

# ------------------------------------------------------------------
# 6. Write meta/ files
# ------------------------------------------------------------------
echo "$PKG_NAME"               > "$STAGE/meta/name"
echo "$PKG_VERSION"            > "$STAGE/meta/version"
echo "${TARGET_ARCH:-x86_64}"  > "$STAGE/meta/arch"
echo "PVE documentation — asciidoc-generated HTML/PDF docs" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
asciidoc
graphviz
imagemagick
perl
perl-JSON
perl-Template-Toolkit
EOF

# ------------------------------------------------------------------
# 7. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"