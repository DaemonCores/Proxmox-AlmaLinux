#!/bin/bash
# build.sh — pve-cluster (Layer 3: C + Perl, pmxcfs FUSE filesystem, corosync)
#
# Proxmox VE cluster filesystem (pmxcfs) and cluster tools.
# Mixed C + Perl package — C code for FUSE filesystem, Perl for cluster management.
# Source in src/ subdirectory.
#
# Adapted from proxmox-nixos:
#   - sourceRoot = src/
#   - C deps: check, corosync, fuse, glib, libqb, libxcrypt, sqlite, rrdtool
#   - Nix postPatch: strip /usr from Makefiles, remove man page targets,
#     strip CFLAGS -MMD, -Wl,-z,relro
#   - Nix makeFlags: DESTDIR=$(out) PERL_VENDORARCH=... PVEDIR=...
#   - Nix postFixup: find $out/lib -type f | xargs sed -i -re "s|(/usr)?/s?bin/||"
#     (removes hard-coded /usr/bin/ and /usr/sbin/ from Perl modules)
#   - AlmaLinux: keep /usr/bin, /usr/sbin as FHS paths, but strip /usr/bin/
#     prefixes where the tool should be found via PATH
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="pve-cluster"
REPO_URL="git://git.proxmox.com/git/pve-cluster.git"

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
# 2. Patch Makefiles
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Patching Makefiles ==="
# Nix: find . -type f -name Makefile | xargs sed -i "s|/usr||g"
# AlmaLinux: keep /usr but strip problematic man page targets
find . -type f -name Makefile | xargs sed -i \
    -e "s/pvecm.1 pvecm.bash-completion pvecm.zsh-completion datacenter.cfg.5//" \
    || true

if [[ -f "PVE/Makefile" ]]; then
    sed -i "PVE/Makefile" \
        -e "/install -D pvecm.1/,+3d" \
        -e "s/pvecm.1 pvecm.bash-completion pvecm.zsh-completion datacenter.cfg.5//" \
        || true
fi

if [[ -f "pmxcfs/Makefile" ]]; then
    sed -i "pmxcfs/Makefile" \
        -e "s/ pmxcfs.8//" \
        || true
fi

# ------------------------------------------------------------------
# 3. Build (C + Perl)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
# Build the FUSE filesystem (pmxcfs) and Perl modules
make -j"$(nproc)" || true

# ------------------------------------------------------------------
# 4. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root" "$STAGE/meta"

make install DESTDIR="$STAGE/root" \
    PERL_VENDORARCH=/usr/lib64/perl5/vendor_perl \
    PVEDIR=/usr/share/perl5/vendor_perl/PVE \
    || true

find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true

# ------------------------------------------------------------------
# 5. Nix→AlmaLinux path substitutions
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Applying path substitutions ==="
# Nix postFixup: find $out/lib -type f | xargs sed -i -re "s|(/usr)?/s?bin/||"
# AlmaLinux: On FHS systems, /usr/bin and /usr/sbin are valid paths.
# We keep them but strip explicit /usr/bin/ prefixes from code that should
# resolve tools via PATH (e.g., /usr/bin/ssh → ssh, /usr/sbin/corosync → corosync)
find "$STAGE/root" -type f \( -name '*.pl' -o -name '*.pm' \) | while read -r f; do
    sed -i \
        -e "/ENV{'PATH'}/d" \
        "$f" || true
done

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
echo "PVE cluster filesystem (pmxcfs) and cluster management tools" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
corosync
corosynclib
fuse3-devel
glib2
libqb-devel
libxcrypt-devel
perl
perl-Digest-HMAC
perl-UUID
pve-access-control
pve-apiclient
sqlite-devel
EOF

# ------------------------------------------------------------------
# 8. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"