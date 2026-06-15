#!/bin/bash
# build.sh — perl-mimebase32 (Layer 0: Perl leaf module, no PVE deps)
#
# MIME::Base32 — Base32 encoder and decoder for Perl.
# CPAN-sourced: https://metacpan.org/pod/MIME::Base32
# Note: depends on Exporter (core Perl module, no separate package needed).
#
# Produces a .pkg.tar intermediate with meta/ + root/ for downstream
# conversion to RPM via pkg-build-rpm.sh.
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="perl-mimebase32"
CPAN_URL="https://www.cpan.org/authors/id/R/RE/REHSACK/MIME-Base32-1.303.tar.gz"

# ------------------------------------------------------------------
# 1. Download source from CPAN
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Downloading source from CPAN ==="
WORKDIR="/tmp/src/${PKG_NAME}"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
curl -L -o "/tmp/${PKG_NAME}.tar.gz" "$CPAN_URL"
tar xzf "/tmp/${PKG_NAME}.tar.gz" -C "/tmp/src"
mv "/tmp/src/MIME-Base32-1.303" "$WORKDIR"
cd "$WORKDIR"

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
echo "MIME::Base32 — Perl module for Base32 encoding and decoding" > "$STAGE/meta/description"
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