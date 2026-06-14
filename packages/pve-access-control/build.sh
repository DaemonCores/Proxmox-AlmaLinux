#!/bin/bash
# build.sh — pve-access-control (Layer 1: Perl, ACL/RBAC management)
#
# Proxmox VE access control framework — user/role/permission management.
# Source is in src/ subdirectory. Pure Perl + C helper (oathkeygen).
#
# Adapted from proxmox-nixos:
#   - sourceRoot = src/
#   - Nix postPatch: strips pveum.1, bash/zsh completions from Makefile
#   - Nix makeFlags: DESTDIR=$(out) PREFIX= SBINDIR=/.bin BINDIR=/.bin
#     PERLDIR=/${perl540.libPrefix}/${perl540.version}
#   - AlmaLinux: use /usr prefix, standard Perl vendor paths
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="pve-access-control"
REPO_URL="git://git.proxmox.com/git/pve-access-control.git"

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
# 2. Patch Makefile — strip man pages and completions
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Patching Makefile ==="
# Nix: sed -i Makefile -e "s/pveum.1 oathkeygen pveum.bash-completion pveum.zsh-completion/oathkeygen/"
#      -e "/pveum.1/,+2d"
if [[ -f "Makefile" ]]; then
    sed -i "Makefile" \
        -e "s/pveum.1 oathkeygen pveum.bash-completion pveum.zsh-completion/oathkeygen/" \
        -e "/pveum.1/,+2d"
fi

# ------------------------------------------------------------------
# 3. Build
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
make -j"$(nproc)" || true

# ------------------------------------------------------------------
# 4. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root" "$STAGE/meta"

make install DESTDIR="$STAGE/root" PREFIX=/usr SBINDIR=/usr/sbin BINDIR=/usr/bin \
    PERLDIR=/usr/share/perl5/vendor_perl || true

find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true

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
echo "PVE access control framework — user, role, and permission management" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
perl
perl-authen-pam
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