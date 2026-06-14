#!/bin/bash
# build.sh — perl-authen-pam (Layer 0: Perl leaf module, no PVE deps)
#
# Produces a .pkg.tar intermediate with meta/ + root/ for downstream
# conversion to RPM (and deb/pacman) via pkg-build-rpm.sh et al.
#
# Environment (injected by build-chain.yml):
#   VERSION        — full git commit hash
#   COMMIT         — same as VERSION
#   SHORT          — short hash (7 chars)
#   TARGET_ID      — "almabuilder"
#   TARGET_ARCH    — "x86_64"
#   TARGET_CFLAGS  — (empty for AlmaLinux)
#   TARGET_CXXFLAGS— (empty for AlmaLinux)
#   SOURCE_DISTRO  — "almalinux-10"
set -euo pipefail

PKG_NAME="perl-authen-pam"
REPO_URL="git://git.proxmox.com/git/perl-authen-pam.git"

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
# 2. Build the Perl module
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
perl Makefile.PL INSTALLDIRS=vendor NO_PACKLIST=1 NO_PERLLOCAL=1
make -j"$(nproc)"

# ------------------------------------------------------------------
# 3. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root" "$STAGE/meta"

make install DESTDIR="$STAGE/root" INSTALLDIRS=vendor

# Prune .packlist and perllocal.pod (packaged separately or not needed)
find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true

# ------------------------------------------------------------------
# 4. Determine version from Makefile or git
# ------------------------------------------------------------------
if [[ -f "$WORKDIR/Makefile" ]]; then
    PKG_VERSION="$(grep '^VERSION' "$WORKDIR/Makefile" | head -1 | sed 's/.*= *//; s/ //g')"
fi
if [[ -z "${PKG_VERSION:-}" ]]; then
    PKG_VERSION="${SHORT:-0.0.1}"
fi
PKG_VERSION="${PKG_VERSION}-${SHORT:-1}"

# ------------------------------------------------------------------
# 5. Write meta/ files (intermediate format consumed by pkg-build-rpm.sh)
# ------------------------------------------------------------------
echo "$PKG_NAME"               > "$STAGE/meta/name"
echo "$PKG_VERSION"            > "$STAGE/meta/version"
echo "${TARGET_ARCH:-x86_64}"  > "$STAGE/meta/arch"
echo "PAM authentication interface for Perl" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

# Dependencies — AlmaLinux RPM names for this Perl module
cat > "$STAGE/meta/depends" << 'EOF'
perl
pam
EOF

# ------------------------------------------------------------------
# 6. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"