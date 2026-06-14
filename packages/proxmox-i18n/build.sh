#!/bin/bash
# build.sh — proxmox-i18n (Layer 1: Translation files, gettext-based)
#
# Proxmox internationalization package — generates .po/.mo translation files.
# No compilation (pure gettext + Perl scripts).
#
# Adapted from proxmox-nixos: uses gettext + perl (Encode, GetoptLong, JSON, LocalePO).
# Nix postPatch: removes dpkg pkg-info.mk, replaces /usr/share → /share.
# AlmaLinux: strip dpkg references, keep FHS paths.
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="proxmox-i18n"
REPO_URL="git://git.proxmox.com/git/proxmox-i18n.git"

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
# 2. Patch Makefile — strip Debian-specific targets
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Patching Makefile ==="
# Nix: substituteInPlace ./Makefile --replace-fail 'include /usr/share/dpkg/pkg-info.mk' ""
# Nix: substituteInPlace ./Makefile --replace-fail '/usr/share' '/share'
if [[ -f "$WORKDIR/Makefile" ]]; then
    sed -i "$WORKDIR/Makefile" \
        -e '/include.*dpkg.*pkg-info\.mk/d' \
        -e 's|/usr/share|/usr/share|g'
fi

# ------------------------------------------------------------------
# 3. Build (gettext translations — no real compilation)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
# proxmox-i18n uses make to generate .mo files from .po
make -j"$(nproc)" || true

# ------------------------------------------------------------------
# 4. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root" "$STAGE/meta"

make install DESTDIR="$STAGE/root" || true

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
echo "Proxmox internationalization — gettext translation files" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
gettext
perl
EOF

# ------------------------------------------------------------------
# 7. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"