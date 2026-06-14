#!/bin/bash
# build.sh — pve-common (Layer 2: Core PVE Perl library)
#
# The most critical PVE package — foundation for all Layer 2+ packages.
# Depends on 17 Layer 0/1 packages (see packages.yml depends_on list).
#
# Produces a .pkg.tar intermediate with meta/ + root/ for downstream
# conversion to RPM (and deb/pacman) via pkg-build-rpm.sh et al.
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="pve-common"
REPO_URL="git://git.proxmox.com/git/pve-common.git"

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
# 2. Build
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
# pve-common uses Makefile with standard Perl build + additional Makefile
# targets for installing Perl modules and helper scripts.
make -j"$(nproc)" || true
# pve-common primarily installs Perl modules; the "build" step is mostly
# the install phase since it's a pure-Perl + helper-scripts package.

# ------------------------------------------------------------------
# 3. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root" "$STAGE/meta"

make install DESTDIR="$STAGE/root" INSTALLDIRS=vendor

find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true

# pve-common installs several critical helper scripts and Perl modules:
#   /usr/bin/pvesh
#   /usr/share/perl5/PVE/ (core library tree)
#   /usr/share/perl5/PVE/INotify.pm
#   /usr/share/perl5/PVE/ProcFSTools.pm
#   etc.
# The Makefile handles the full install.

# ------------------------------------------------------------------
# 4. Determine version from Makefile or debian/changelog
# ------------------------------------------------------------------
PKG_VERSION=""
if [[ -f "$WORKDIR/debian/changelog" ]]; then
    # Debian changelog first line: pve-common (8.x.y-z) ...
    PKG_VERSION="$(head -1 "$WORKDIR/debian/changelog" | sed 's/.*(\([^)]*\)).*/\1/')"
fi
if [[ -z "${PKG_VERSION:-}" && -f "$WORKDIR/Makefile" ]]; then
    PKG_VERSION="$(grep '^VERSION' "$WORKDIR/Makefile" | head -1 | sed 's/.*= *//; s/ //g')"
fi
if [[ -z "${PKG_VERSION:-}" ]]; then
    PKG_VERSION="${SHORT:-0.0.1}"
fi
# Append git short hash for traceability
PKG_VERSION="${PKG_VERSION}+${SHORT:-git}"

# ------------------------------------------------------------------
# 5. Write meta/ files (intermediate format consumed by pkg-build-rpm.sh)
# ------------------------------------------------------------------
echo "$PKG_NAME"               > "$STAGE/meta/name"
echo "$PKG_VERSION"            > "$STAGE/meta/version"
echo "${TARGET_ARCH:-x86_64}"  > "$STAGE/meta/arch"
echo "PVE common Perl library — core utilities, INotify, ProcFSTools, and more" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

# Dependencies — AlmaLinux RPM names matching packages.yml depends_on
# These MUST match the package IDs in packages.yml that pve-common depends on,
# translated to their RPM package names.
cat > "$STAGE/meta/depends" << 'EOF'
perl
perl-authen-pam
perl-crypt-openssl-random
perl-crypt-openssl-rsa
perl-data-dumper
perl-digest-sha
perl-file-readbackwards
perl-filesys-df
perl-http-daemon
perl-json
perl-linux-inotify2
perl-mail-spamassassin
perl-net-dns
perl-net-ip
perl-net-ssleay
perl-uri
perl-www-perl
perl-xml-parser
proxmox-backup-qemu
EOF

# ------------------------------------------------------------------
# 6. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"