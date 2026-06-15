#!/bin/bash
# build.sh — pve-xtermjs (Layer 7: Static JS assets, no PVE deps)
#
# xterm.js webclient for Proxmox VE — terminal emulator in the browser.
# Static JS/HTML assets, no compilation needed.
# Source from git.proxmox.com.
#
# Adapted from proxmox-nixos:
#   - Nix: stdenv.mkDerivation, dontBuild = true
#   - Nix: installPhase copies src/xterm.js/src/* to $out/share/pve-xtermjs/
#   - Nix: renames index.html.hbs.in and index.html.tpl.in
#   - AlmaLinux: keep /usr/share paths (FHS)
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="pve-xtermjs"
REPO_URL="git://git.proxmox.com/git/pve-xtermjs.git"

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
# 2. Build (no compilation — static JS/HTML assets)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building (static assets) ==="

# ------------------------------------------------------------------
# 3. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
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

# ------------------------------------------------------------------
# 4. Determine version
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
# 5. Write meta/ files
# ------------------------------------------------------------------
echo "$PKG_NAME"               > "$STAGE/meta/name"
echo "$PKG_VERSION"            > "$STAGE/meta/version"
echo "${TARGET_ARCH:-x86_64}"  > "$STAGE/meta/arch"
echo "PVE xterm.js — Web-based terminal emulator for Proxmox VE" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
termproxy
EOF

# ------------------------------------------------------------------
# 6. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"