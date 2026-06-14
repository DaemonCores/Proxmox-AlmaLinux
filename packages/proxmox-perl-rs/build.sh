#!/bin/bash
# build.sh — proxmox-perl-rs (Layer 1: Rust + Perl bindings via perlmod)
#
# Provides Rust-to-Perl bindings for PVE. Built via cargo + Makefile that
# generates Perl XS modules from Rust code using perlmod/genpackage.pl.
#
# Adapted from proxmox-nixos (pve-rs package):
#   - Source is proxmox-perl-rs.git
#   - cargo build with registry patches
#   - make install for Perl modules + .so
#   - Nix postPatch: strips GITVERSION, dpkg-architecture, pkg-info, MConfig,
#     replaces /usr/lib/perlmod/genpackage.pl with Nix store path
#   - AlmaLinux: use system perlmod if available, or build from source
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="proxmox-perl-rs"
REPO_URL="git://git.proxmox.com/git/proxmox-perl-rs.git"

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

# ------------------------------------------------------------------
# 3. Patch Makefiles — strip Debian-specific targets
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Patching Makefiles ==="
# Nix: strips GITVERSION, dpkg-architecture, pkg-info, MConfig from Makefiles
# AlmaLinux: same stripping, keep /usr/lib/perl5 for vendor paths
for mkfile in common/pkg/Makefile pve-rs/Makefile; do
    if [[ -f "$WORKDIR/$mkfile" ]]; then
        sed -i "$WORKDIR/$mkfile" \
            -e '/GITVERSION/d' \
            -e '/dpkg-architecture/d' \
            -e '/pkg-info/d' \
            -e '/MConfig/d'
    fi
done

# ------------------------------------------------------------------
# 4. Build (Rust — cargo + Perl module generation)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
cd "$WORKDIR/pve-rs"

# Build the Rust library
cargo build --release

# Build the Perl module wrapper
make BUILDIR="/tmp/src/${PKG_NAME}" BUILD_MODE=release GITVERSION="${SHORT:-git}" || true

# ------------------------------------------------------------------
# 5. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root" "$STAGE/meta"

# Install Perl modules and .so from pve-rs
make install DESTDIR="$STAGE/root" \
    BUILDIR="/tmp/src/${PKG_NAME}" \
    BUILD_MODE=release \
    PERL_INSTALLVENDORARCH="/usr/lib64/perl5/vendor_perl" \
    PERL_INSTALLVENDORLIB="/usr/share/perl5/vendor_perl" || true

# Install common/pkg Perl modules
cd "$WORKDIR/common/pkg"
make install PERL_INSTALLVENDORLIB="$STAGE/root/usr/share/perl5/vendor_perl" || true
cd "$WORKDIR"

find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true

# ------------------------------------------------------------------
# 6. Determine version
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
# 7. Write meta/ files
# ------------------------------------------------------------------
echo "$PKG_NAME"               > "$STAGE/meta/name"
echo "$PKG_VERSION"            > "$STAGE/meta/version"
echo "${TARGET_ARCH:-x86_64}"  > "$STAGE/meta/arch"
echo "Proxmox Rust bindings for Perl — perlmod-generated XS modules" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
cargo
perl
libuuid
openssl-libs
pkgconf-pkg-config
EOF

# ------------------------------------------------------------------
# 8. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"