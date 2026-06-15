#!/bin/bash
# build.sh — perl-mimebase64 (Layer 0: Perl leaf module, no PVE deps)
#
# MIME::Base64 — Base64 encoder and decoder for Perl.
# CPAN-sourced: https://metacpan.org/pod/MIME::Base64
# Note: This is the CPAN version (MIME-Base64 by CAPOEIRAB), which is
# distinct from the core MIME::Base64 module. Proxmox uses this CPAN version.
#
# Produces a .pkg.tar intermediate with meta/ + root/ for downstream
# conversion to RPM via pkg-build-rpm.sh.
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="perl-mimebase64"
CPAN_URL="https://www.cpan.org/authors/id/C/CA/CAPOEIRAB/MIME-Base64-3.16.tar.gz"

# ------------------------------------------------------------------
# 1. Download source from CPAN
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Downloading source from CPAN ==="
WORKDIR="/tmp/src/${PKG_NAME}"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
curl -L -o "/tmp/${PKG_NAME}.tar.gz" "$CPAN_URL"
tar xzf "/tmp/${PKG_NAME}.tar.gz" -C "/tmp/src"
mv "/tmp/src/MIME-Base64-3.16" "$WORKDIR"
cd "$WORKDIR"

# ------------------------------------------------------------------
# 2. Build the Perl module (XS — compiled, needs C library)
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
# 5. Write meta/ files
# ------------------------------------------------------------------
echo "$PKG_NAME"               > "$STAGE/meta/name"
echo "$PKG_VERSION"            > "$STAGE/meta/version"
echo "${TARGET_ARCH:-x86_64}"  > "$STAGE/meta/arch"
echo "MIME::Base64 — Perl module for Base64 encoding and decoding" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
perl
EOF

# ------------------------------------------------------------------
# 6. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"