#!/bin/bash
# build.sh — pve-ha-manager (Layer 4: Perl, high availability manager)
#
# Proxmox VE HA manager — manages high availability for VMs and containers.
# Pure Perl, source in src/ subdirectory.
#
# Adapted from proxmox-nixos:
#   - sourceRoot = src/
#   - Nix postPatch: strips man pages, completions from Makefile,
#     changes -Werror to -Wno-error, strips PVE_GENERATING_DOCS
#   - Nix makeFlags: DESTDIR=$(out) PREFIX= SBINDIR=/bin
#     PERLDIR=/${perl540.libPrefix}/${perl540.version}
#   - Nix postInstall: copies pct and qemu-server bins from deps
#   - AlmaLinux: standard FHS paths
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="pve-ha-manager"
REPO_URL="git://git.proxmox.com/git/pve-ha-manager.git"

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
# Nix: strips man pages, completions, changes -Werror to -Wno-error
if [[ -f "Makefile" ]]; then
    sed -i "Makefile" \
        -e "s/ha-manager.1 pve-ha-crm.8 pve-ha-lrm.8 ha-manager.bash-completion pve-ha-lrm.bash-completion //" \
        -e "s/pve-ha-crm.bash-completion ha-manager.zsh-completion pve-ha-lrm.zsh-completion pve-ha-crm.zsh-completion //" \
        -e "/install -m 0644 -D pve-ha-crm.bash-completion/,+5d" \
        -e "/install -m 0644 pve-ha-crm.8/,+6d" \
        -e "s/Werror/Wno-error/" \
        -e "/PVE_GENERATING_DOCS/d" \
        -e "/shell \/d"
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

make install DESTDIR="$STAGE/root" PREFIX=/usr SBINDIR=/usr/sbin \
    PERLDIR=/usr/share/perl5/vendor_perl || true

find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true

# Remove the simulator (not needed in production)
rm -f "$STAGE/root/usr/sbin/pve-ha-simulator" 2>/dev/null || true

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
echo "PVE HA manager — high availability for VMs and containers" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
perl
pve-cluster
pve-common
pve-container
pve-firewall
pve-guest-common
pve-qemu-server
pve-storage
EOF

# ------------------------------------------------------------------
# 7. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"