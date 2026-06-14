#!/bin/bash
# build.sh — pve-storage (Layer 4: Perl, storage library for ZFS/LVM/Ceph/iSCSI)
#
# Proxmox VE storage library — supports ZFS, LVM, Ceph RBD, iSCSI, NFS,
# GlusterFS, directory, and many other storage backends.
# Pure Perl, source in src/ subdirectory.
#
# Adapted from proxmox-nixos:
#   - sourceRoot = src/
#   - Nix postPatch: strips pvesm.1, bash/zsh completions from bin/Makefile
#   - Nix makeFlags: DESTDIR=$(out) PREFIX= SBINDIR=/bin
#     PERLDIR=/${perl540.libPrefix}/${perl540.version}
#   - Nix postFixup: MASSIVE path substitution list — replaces hard-coded
#     /bin/*, /sbin/*, /usr/bin/*, /usr/sbin/* tool paths with Nix store paths
#   - AlmaLinux: these tools are all in standard FHS paths, so most
#     substitutions are unnecessary. Only strip ENV{'PATH'} lines.
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="pve-storage"
REPO_URL="git://git.proxmox.com/git/pve-storage.git"

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
# Nix: sed -i bin/Makefile -e "s/pvesm.1 pvesm.bash-completion pvesm.zsh-completion//"
#      -e "/pvesm.1/,+3d"
if [[ -f "bin/Makefile" ]]; then
    sed -i "bin/Makefile" \
        -e "s/pvesm.1 pvesm.bash-completion pvesm.zsh-completion//" \
        -e "/pvesm.1/,+3d"
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

# Strip -T taint flag from pvesm (AlmaLinux Perl handles this differently)
if [[ -f "$STAGE/root/usr/sbin/pvesm" ]]; then
    sed -i "$STAGE/root/usr/sbin/pvesm" -e "s/-T//"
fi

# ------------------------------------------------------------------
# 5. Nix→AlmaLinux path substitutions
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Applying path substitutions ==="
# Nix replaces dozens of tool paths (lsblk, mkdir, mount, blkid, lv, vg,
# zfs, zpool, sgdisk, showmount, chattr, file, iscsiadm, qemu, rbd, etc.)
# with Nix store paths. On AlmaLinux, these tools are in standard FHS paths:
#   /usr/bin/  and  /usr/sbin/
# so the hard-coded Debian paths (/bin/*, /sbin/*) need to be mapped to FHS.
find "$STAGE/root" -type f \( -name '*.pl' -o -name '*.pm' \) | while read -r f; do
    sed -i \
        -e "/ENV{'PATH'}/d" \
        -e "s|/usr/share/perl5|/usr/share/perl5/vendor_perl|g" \
        -e "s|/usr/sbin/pvesm|/usr/sbin/pvesm|g" \
        "$f" || true
done

# Map Debian-specific tool paths to AlmaLinux FHS equivalents
find "$STAGE/root" -type f \( -name '*.pl' -o -name '*.pm' -o -name 'pvesm' \) | while read -r f; do
    sed -i \
        -e "s|/bin/lsblk|/usr/bin/lsblk|g" \
        -e "s|/bin/mkdir|/usr/bin/mkdir|g" \
        -e "s|/bin/mount|/usr/bin/mount|g" \
        -e "s|/bin/umount|/usr/bin/umount|g" \
        -e "s|/sbin/blkid|/usr/sbin/blkid|g" \
        -e "s|/sbin/blockdev|/usr/sbin/blockdev|g" \
        -e "s|/sbin/lv|/usr/sbin/lv|g" \
        -e "s|/sbin/mkfs|/usr/sbin/mkfs|g" \
        -e "s|/sbin/pv|/usr/sbin/pv|g" \
        -e "s|/sbin/sgdisk|/usr/sbin/sgdisk|g" \
        -e "s|/sbin/showmount|/usr/sbin/showmount|g" \
        -e "s|/sbin/vg|/usr/sbin/vg|g" \
        -e "s|/usr/bin/cstream|/usr/bin/cstream|g" \
        -e "s|/usr/sbin/ietadm|/usr/sbin/ietadm|g" \
        -e "s|/usr/sbin/sbdadm|/usr/sbin/sbdadm|g" \
        -e "s|/usr/sbin/stmfadm|/usr/sbin/stmfadm|g" \
        -e "s|/usr/libexec/ceph|/usr/libexec/ceph|g" \
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
echo "PVE storage library — ZFS, LVM, Ceph RBD, iSCSI, NFS, and more" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
ceph-common
e2fsprogs
file
glusterfs-cli
iproute
iscsi-initiator-utils
lvm2
nfs-utils
openvswitch
perl
perl-File-chdir
perl-XML-LibXML
pve-cluster
pve-common
smartmontools
targetcli
util-linux
zfs
EOF

# ------------------------------------------------------------------
# 8. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"