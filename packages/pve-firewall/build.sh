#!/bin/bash
# build.sh — pve-firewall (Layer 4: Perl, firewall management iptables/nftables)
#
# Proxmox VE firewall — manages iptables/nftables rules, ipsets, and
# security groups for VMs and containers.
# Mixed C + Perl — C code for libnetfilter_conntrack/log, Perl for rule management.
# Source in src/ subdirectory.
#
# Adapted from proxmox-nixos:
#   - sourceRoot = src/
#   - C deps: glib, libnetfilter_conntrack, libnetfilter_log, libnfnetlink
#   - Nix postPatch: strips man pages and completions from Makefile,
#     strips dpkg-buildflags
#   - Nix makeFlags: DESTDIR=$(out) PREFIX= SBINDIR=$(out)/bin
#     PERLDIR=$(out)/${perl540.libPrefix}/${perl540.version}
#   - Nix postFixup: wrapProgram pve-firewall with PATH for ipset, iptables
#   - AlmaLinux: use standard FHS paths, wrap with /usr/sbin paths
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="pve-firewall"
REPO_URL="git://git.proxmox.com/git/pve-firewall.git"

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
# 2. Patch Makefile
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Patching Makefile ==="
# Nix: strips man pages, completions, dpkg-buildflags from Makefile
if [[ -f "Makefile" ]]; then
    sed -i "Makefile" \
        -e "s/pve-firewall.8 pve-firewall.bash-completion pve-firewall.zsh-completion//" \
        -e "/install -m 0644 pve-firewall.8/,+4d" \
        -e "s/pve-firewall.8//" \
        -e "/dpkg-buildflags/d"
fi

# ------------------------------------------------------------------
# 3. Build (C + Perl)
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

make install DESTDIR="$STAGE/root" PREFIX=/usr SBINDIR=/usr/sbin \
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
echo "PVE firewall — iptables/nftables rule management for VMs and containers" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
glib2
ipset
iptables
iptables-nft
libnetfilter_conntrack
libnetfilter_log
libnfnetlink
perl
pve-access-control
pve-cluster
pve-common
pve-network
EOF

# ------------------------------------------------------------------
# 7. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"