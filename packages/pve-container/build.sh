#!/bin/bash
# build.sh — pve-container (Layer 5: Perl, LXC container management)
#
# Proxmox VE container manager — manages LXC containers (pct command).
# Pure Perl, source in src/ subdirectory.
#
# Adapted from proxmox-nixos:
#   - sourceRoot = src/
#   - Nix postPatch: strips man pages, completions, pve-doc-generator,
#     PVE_GENERATING_DOCS, SERVICEDIR, BASHCOMPLDIR, ZSHCOMPLDIR, MAN1DIR, MAN5DIR
#     from Makefile; replaces /usr/share/lxc with Nix lxc path
#   - Nix makeFlags: DESTDIR=$(out) PREFIX=$(out) SBINDIR=$(out)/.bin
#     PERLDIR=$(out)/${perl540.libPrefix}/${perl540.version}
#   - Nix postFixup: massive path substitutions — dtach, ssh, vncterm,
#     termproxy, lxc, /usr/share/lxc, /usr/share/zoneinfo
#   - AlmaLinux: keep FHS paths, adapt zoneinfo and lxc paths
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="pve-container"
REPO_URL="git://git.proxmox.com/git/pve-container.git"

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
# Nix: strips man pages, completions, doc targets from Makefile
if [[ -f "Makefile" ]]; then
    sed -i "Makefile" \
        -e "s/pct.1 pct.conf.5 pct.bash-completion pct.zsh-completion//" \
        -e "/pve-doc-generator/d" \
        -e "/PVE_GENERATING_DOCS/d" \
        -e "/SERVICEDIR/d" \
        -e "/BASHCOMPLDIR/d" \
        -e "/ZSHCOMPLDIR/d" \
        -e "/MAN1DIR/d" \
        -e "/MAN5DIR/d"
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

# Copy LXC templates from system if available
if [[ -d "/usr/share/lxc" ]]; then
    mkdir -p "$STAGE/root/usr/share/lxc"
    cp -r /usr/share/lxc/* "$STAGE/root/usr/share/lxc/" 2>/dev/null || true
fi

find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true

# ------------------------------------------------------------------
# 5. Nix→AlmaLinux path substitutions
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Applying path substitutions ==="
# Nix postFixup replaces:
#   /usr/bin/dtach      → ${dtach}/bin/dtach        → /usr/bin/dtach (FHS, same)
#   /usr/bin/ssh         → ${openssh}/bin/ssh         → /usr/bin/ssh (FHS, same)
#   /bin/true            → true
#   /usr/bin/vncterm     → (empty, optional)          → /usr/bin/vncterm
#   /usr/bin/termproxy   → (empty, optional)          → /usr/bin/termproxy
#   /usr/bin/lxc         → ${lxc}/bin/lxc             → /usr/bin/lxc (FHS, same)
#   /usr/share/lxc       → $out/share/lxc             → /usr/share/lxc (FHS, same)
#   /usr/share/zoneinfo  → ${tzdata}/share/zoneinfo   → /usr/share/zoneinfo (FHS, same)
# On AlmaLinux, FHS paths are correct. Only fix /bin/true.
find "$STAGE/root" -type f \( -name '*.pl' -o -name '*.pm' \) | while read -r f; do
    sed -i \
        -e "s|/bin/true|true|g" \
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
echo "PVE container manager — LXC container management (pct)" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
dtach
lxc
perl
pve-common
pve-guest-common
pve-storage
EOF

# ------------------------------------------------------------------
# 8. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"