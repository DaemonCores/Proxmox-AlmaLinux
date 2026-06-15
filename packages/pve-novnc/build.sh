#!/bin/bash
# build.sh — pve-novnc (Layer 7: Static JS assets, no PVE deps)
#
# noVNC web client — Proxmox's fork of noVNC with PVE-specific patches.
# Static JS/CSS assets, built with esbuild.
# Source from git.proxmox.com (novnc-pve.git).
#
# Adapted from proxmox-nixos:
#   - Nix: novnc.overrideAttrs with PVE source + patches from debian/patches/series
#   - Nix: sourceRoot = novnc/, buildInputs = [ esbuild ]
#   - Nix: installPhase copies web assets to $out/share/webapps/novnc/
#   - AlmaLinux: keep /usr/share paths (FHS)
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="pve-novnc"
REPO_URL="git://git.proxmox.com/git/novnc-pve.git"

# ------------------------------------------------------------------
# 1. Clone source
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Cloning source ==="
WORKDIR="/tmp/src/${PKG_NAME}"
rm -rf "$WORKDIR"
git clone "$REPO_URL" "$WORKDIR" --recursive
cd "$WORKDIR"

if [[ -n "${VERSION:-}" ]]; then
    git checkout "$VERSION" 2>/dev/null || git checkout "${SHORT:-${VERSION:0:7}}" 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 2. Apply patches from debian/patches/series
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Applying patches ==="
if [[ -f "$WORKDIR/debian/patches/series" ]]; then
    while IFS= read -r patch; do
        [[ -z "$patch" || "$patch" =~ ^# ]] && continue
        echo "  Applying: $patch"
        patch -p1 -d "$WORKDIR" -i "$WORKDIR/debian/patches/$patch" || true
    done < "$WORKDIR/debian/patches/series"
fi

cd "$WORKDIR/novnc" 2>/dev/null || cd "$WORKDIR" || true

# ------------------------------------------------------------------
# 3. Build (esbuild bundle)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
if command -v esbuild &>/dev/null; then
    if [[ -f "app/ui.js" ]]; then
        esbuild --bundle --format=esm app/ui.js > app.js 2>/dev/null || true
    fi
fi

# ------------------------------------------------------------------
# 4. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root/usr/share/novnc-pve" "$STAGE/meta"

# Copy all web assets (noVNC is a static web application)
if [[ -d "$WORKDIR/novnc" ]]; then
    cp -r "$WORKDIR/novnc/"* "$STAGE/root/usr/share/novnc-pve/" 2>/dev/null || true
elif [[ -d "$WORKDIR" ]]; then
    # Copy relevant files
    for dir in app core vendor images include; do
        [[ -d "$WORKDIR/$dir" ]] && cp -r "$WORKDIR/$dir" "$STAGE/root/usr/share/novnc-pve/" || true
    done
    for f in vnc.html *.js *.css; do
        [[ -f "$WORKDIR/$f" ]] && cp "$WORKDIR/$f" "$STAGE/root/usr/share/novnc-pve/" || true
    done
fi

# Copy bundled app.js if built
if [[ -f "app.js" ]]; then
    cp app.js "$STAGE/root/usr/share/novnc-pve/"
fi

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
echo "PVE noVNC — Web-based VNC client for Proxmox VE" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
EOF

# ------------------------------------------------------------------
# 7. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"