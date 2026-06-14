#!/bin/bash
# build.sh — pve-http-server (Layer 3: Perl, HTTP server)
#
# Proxmox VE HTTP server — serves the PVE web UI and API.
# Pure Perl, source in src/ subdirectory.
#
# Adapted from proxmox-nixos:
#   - sourceRoot = src/
#   - Nix makeFlags: PERL5DIR=$(out)/${perl540.libPrefix}/${perl540.version}
#   - Nix postFixup: find $out -type f | xargs sed -i
#       -e "s|/usr/share/javascript|$out/share/javascript|"
#       -e "s|/usr/share/bootstrap-html|$out/share/bootstrap-html|"
#     + symlinks for extjs, proxmox-widget-toolkit, qrcodejs, font-awesome, etc.
#   - AlmaLinux: keep /usr/share paths (FHS), create symlinks for web assets
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="pve-http-server"
REPO_URL="git://git.proxmox.com/git/pve-http-server.git"

# ------------------------------------------------------------------
# 1. Clone source
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Cloning source ==="
WORKDIR="/tmp/src/${PKG_NAME}"
rm -rf "$WORKDIR"
git clone "$REPO_URL" "$WORKDIR"
cd "$WORKDIR/src"

if [[ -n "${VERSION:-}" ]]; then
    git checkout "$VERSION" 2>/dev/null || git checkout "${SHORT:-${VERSION:0:7}}" 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 2. Build
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
make -j"$(nproc)" || true

# ------------------------------------------------------------------
# 3. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root" "$STAGE/meta"

make install DESTDIR="$STAGE/root" PERL5DIR=/usr/share/perl5/vendor_perl || true

find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true

# ------------------------------------------------------------------
# 4. Nix→AlmaLinux path substitutions
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Applying path substitutions ==="
# Nix: substitutes /usr/share/javascript and /usr/share/bootstrap-html with Nix store paths
# AlmaLinux: these are valid FHS paths, no substitution needed.
# Create expected web asset directories (populated by dependent packages at install time)
mkdir -p "$STAGE/root/usr/share/javascript" "$STAGE/root/usr/share/bootstrap-html" 2>/dev/null || true

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
echo "PVE HTTP server — serves the Proxmox VE web UI and REST API" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
perl
perl-AnyEvent-HTTP
proxmox-i18n
proxmox-widget-toolkit
pve-common
EOF

# ------------------------------------------------------------------
# 7. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"