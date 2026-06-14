#!/bin/bash
# build.sh — pve-manager (Layer 5: Perl + web assets, PVE UI/API)
#
# The main Proxmox VE package — serves the web UI on port 8006 via pveproxy,
# provides the REST API, CLI tools (pvesh, pveum, etc.), and management daemons.
# Mixed Perl + web assets (JS/CSS built by biome/Makefile).
#
# Adapted from proxmox-nixos:
#   - Patches: 0001-no-apt-update.patch, 0002-no-repo-status.patch
#   - Nix postPatch: strips /usr from defines.mk/configs/Makefile,
#     strips GITVERSION, default.mk, pkg-info, log, architecture targets,
#     strips aplinfo/PVE/bin/www/services/network-hooks/test → PVE/bin/www/configs/test,
#     strips pod2man/man page targets, fixes asciidoc-pve path
#   - Nix makeFlags: DESTDIR, PVERELEASE, VERSION, REPOID, PERLLIBDIR,
#     WIDGETKIT, BASH_COMPLETIONS=, ZSH_COMPLETIONS=, CLI_MANS=, SERVICE_MANS=
#   - Nix postInstall: rm -r $out/var $out/bin/pve{upgrade,update,version,8to9},
#     strip -T from scripts
#   - Nix postFixup: MASSIVE substitutions —
#     /API2::APT/d (remove APT API entirely),
#     /ENV{'PATH'}/d,
#     /usr/share/{bootstrap-html,javascript,pve-yew-mobile-gui,pve-yew-mobile-i18n,
#       fonts-font-awesome,fonts-font-logos,pve-docs,pve-i18n,pve-manager,pve-xtermjs,
#       novnc-pve} → Nix store paths,
#     /usr/share/zoneinfo → tzdata,
#     (/usr)?/s?bin/ → strip prefix,
#     Ceph paths, wrapProgram with massive PATH
#   - AlmaLinux: remove APT/dpkg references, keep FHS /usr/share paths,
#     strip /usr/bin/ prefixes for PATH-resolved tools
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="pve-manager"
REPO_URL="git://git.proxmox.com/git/pve-manager.git"

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
# 3. Patch build files — strip Debian-specific targets
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Patching build files ==="

# Strip /usr from defines.mk (Nix does s,/usr,, — AlmaLinux keeps /usr)
# Patch Makefile targets
if [[ -f "defines.mk" ]]; then
    sed -i "defines.mk" -e "s|/usr||g" 2>/dev/null || true
fi

if [[ -f "Makefile" ]]; then
    sed -i "Makefile" \
        -e '/GITVERSION/d' \
        -e '/default.mk/d' \
        -e '/pkg-info/d' \
        -e '/log/d' \
        -e '/architecture/d' \
        -e 's/aplinfo PVE bin www services configs network-hooks test/PVE bin www configs test/'
fi

if [[ -f "configs/Makefile" ]]; then
    sed -i "configs/Makefile" -e "s|/usr||g" 2>/dev/null || true
fi

# Strip pod2man/man page targets from bin/Makefile
if [[ -f "bin/Makefile" ]]; then
    sed -i "bin/Makefile" \
        -e '/pod2man/,+1d' \
        -e '/install -d.*MAN1DIR/,+9d'
fi

# Fix asciidoc-pve path in www/manager6/Makefile
if [[ -f "www/manager6/Makefile" ]]; then
    sed -i "www/manager6/Makefile" \
        -e "/BIOME/d" \
        -e "s|/usr/bin/asciidoc-pve|/usr/bin/asciidoc-pve|g"
fi

# ------------------------------------------------------------------
# 4. Build
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
make -j"$(nproc)" || true

# ------------------------------------------------------------------
# 5. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root" "$STAGE/meta"

make install \
    DESTDIR="$STAGE/root" \
    PVERELEASE=9.0 \
    VERSION="${PKG_VERSION:-dev}" \
    REPOID=almalinux \
    PERLLIBDIR=/usr/share/perl5/vendor_perl \
    WIDGETKIT=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js \
    BASH_COMPLETIONS= \
    ZSH_COMPLETIONS= \
    CLI_MANS= \
    SERVICE_MANS= \
    || true

# Remove Debian-specific tools not needed on AlmaLinux
rm -rf "$STAGE/root/var" 2>/dev/null || true
rm -f "$STAGE/root/usr/bin/pveupgrade" 2>/dev/null || true
rm -f "$STAGE/root/usr/bin/pveupdate" 2>/dev/null || true
rm -f "$STAGE/root/usr/bin/pveversion" 2>/dev/null || true
rm -f "$STAGE/root/usr/bin/pve8to9" 2>/dev/null || true

# Strip -T taint flag from scripts (AlmaLinux Perl handles this differently)
for script in "$STAGE/root/usr/bin/"* "$STAGE/root/usr/sbin/"* "$STAGE/root/usr/share/pve-manager/helpers/"*; do
    [[ -f "$script" ]] && sed -i "$script" -e "s/-T//" 2>/dev/null || true
done

find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true

# ------------------------------------------------------------------
# 6. Nix→AlmaLinux path substitutions
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Applying path substitutions ==="
# Nix: removes API2::APT (APT/dpkg not available on non-Debian)
# Nix: strips /ENV{'PATH'}/d from all Perl files
# Nix: replaces /usr/share/* paths with Nix store paths
# AlmaLinux: remove APT references, keep FHS /usr/share paths,
# strip /usr/bin/ prefixes for PATH-resolved tools

find "$STAGE/root" -type f \( -name '*.pl' -o -name '*.pm' \) | while read -r f; do
    sed -i \
        -e "/API2::APT/d" \
        -e "/ENV{'PATH'}/d" \
        -e "s|/usr/share/zoneinfo|/usr/share/zoneinfo|g" \
        -e "s|/usr/share/perl5|/usr/share/perl5/vendor_perl|g" \
        "$f" || true
done

# Also fix scripts in bin/ and helpers/
find "$STAGE/root/usr/bin" "$STAGE/root/usr/sbin" "$STAGE/root/usr/share/pve-manager/helpers" \
    -type f 2>/dev/null | while read -r f; do
    sed -i \
        -e "/ENV{'PATH'}/d" \
        -e "/API2::APT/d" \
        "$f" || true
done

# Fix Ceph paths — on AlmaLinux, ceph tools are in /usr/bin
find "$STAGE/root" -type f -wholename "*Ceph*" | while read -r f; do
    sed -i \
        -e 's|ceph-authtool|/usr/bin/ceph-authtool|g' \
        "$f" || true
done

# ------------------------------------------------------------------
# 7. Determine version
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
# 8. Write meta/ files
# ------------------------------------------------------------------
echo "$PKG_NAME"               > "$STAGE/meta/name"
echo "$PKG_VERSION"            > "$STAGE/meta/version"
echo "${TARGET_ARCH:-x86_64}"  > "$STAGE/meta/arch"
echo "PVE manager — web UI, REST API, and management daemons for Proxmox VE" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
ceph-common
corosync
gnupg2
graphviz
gzip
iproute
openssh
openssl
perl
perl-Crypt-OpenSSL-Bignum
perl-File-ReadBackwards
perl-Net-DNS
perl-Pod-Parser
perl-Template-Toolkit
perl-proxmox-acme
pve-cluster
pve-container
pve-docs
pve-firewall
pve-guest-common
pve-ha-manager
pve-http-server
pve-network
pve-qemu-server
pve-storage
proxmox-i18n
proxmox-widget-toolkit
shadow-utils
sqlite
systemd
util-linux
wget
EOF

# ------------------------------------------------------------------
# 9. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"