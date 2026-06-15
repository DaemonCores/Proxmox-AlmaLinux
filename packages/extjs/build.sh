#!/bin/bash
# build.sh — extjs (Layer 1: JavaScript library, no PVE deps)
#
# ExtJS JavaScript framework — used by PVE web UI.
# Sourced from git.proxmox.com (Proxmox's fork/bundle of ExtJS).
# Install is a simple copy of JS/CSS assets to /usr/share/javascript/extjs/.
#
# Adapted from proxmox-nixos:
#   - sourceRoot = extjs/build
#   - Nix installPhase: copy classic/locale, classic/theme-crisp,
#     ext-all-debug.js, ext-all.js, charts JS/CSS to $out/share/javascript/extjs
#   - AlmaLinux: keep /usr/share paths (FHS)
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="extjs"
REPO_URL="git://git.proxmox.com/git/extjs.git"

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

cd "$WORKDIR/extjs/build" 2>/dev/null || cd "$WORKDIR/build" 2>/dev/null || true

# ------------------------------------------------------------------
# 2. Build (no compilation — static JS/CSS assets)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building (static assets) ==="
# ExtJS is a pre-built JavaScript framework; no compilation step.

# ------------------------------------------------------------------
# 3. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root/usr/share/javascript/extjs" "$STAGE/meta"

# Copy ExtJS assets per Nix postInstall
if [[ -d "$WORKDIR/extjs/build" ]]; then
    BUILD_DIR="$WORKDIR/extjs/build"
elif [[ -d "$WORKDIR/build" ]]; then
    BUILD_DIR="$WORKDIR/build"
else
    BUILD_DIR="$WORKDIR"
fi

# Core JS files
for f in ext-all-debug.js ext-all.js; do
    if [[ -f "$BUILD_DIR/$f" ]]; then
        cp "$BUILD_DIR/$f" "$STAGE/root/usr/share/javascript/extjs/"
    fi
done

# Classic locale
if [[ -d "$BUILD_DIR/classic/locale" ]]; then
    cp -r "$BUILD_DIR/classic/locale" "$STAGE/root/usr/share/javascript/extjs/"
fi

# Classic theme-crisp
if [[ -d "$BUILD_DIR/classic/theme-crisp" ]]; then
    cp -r "$BUILD_DIR/classic/theme-crisp" "$STAGE/root/usr/share/javascript/extjs/"
fi

# Charts
if [[ -f "$BUILD_DIR/packages/charts/classic/charts-debug.js" ]]; then
    cp "$BUILD_DIR/packages/charts/classic/charts-debug.js" "$STAGE/root/usr/share/javascript/extjs/"
fi
if [[ -f "$BUILD_DIR/packages/charts/classic/charts.js" ]]; then
    cp "$BUILD_DIR/packages/charts/classic/charts.js" "$STAGE/root/usr/share/javascript/extjs/"
fi
if [[ -d "$BUILD_DIR/packages/charts/classic/crisp" ]]; then
    cp -r "$BUILD_DIR/packages/charts/classic/crisp" "$STAGE/root/usr/share/javascript/extjs/"
fi

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
echo "ExtJS JavaScript framework for PVE web UI" > "$STAGE/meta/description"
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