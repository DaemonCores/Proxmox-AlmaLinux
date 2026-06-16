#!/bin/bash
# Package: pve-qemu
# Layer: 4
# Type: rust-qemu

PKG_NAME="pve-qemu"
REPO_URL="$(get_pkg_meta "$PKG_NAME" repo)"
BUILD_TYPE="rust-qemu"
PKG_DESCRIPTION="PVE QEMU — Proxmox-patched QEMU hypervisor (meson + ninja build)"
PKG_DEPENDS=$'ceph-libs
glusterfs-libs
glib2
libaio-devel
libcurl-devel
libfdt-devel
libiscsi-devel
libnfs-devel
libpmem-devel
libssh-devel
libuuid-devel
lzo-devel
meson
ninja-build
pixman-devel
proxmox-backup-qemu
python3
snappy-devel
systemd-devel
usbredir-devel
virglrenderer-devel
zstd-devel'

# Override: QEMU complex build with meson + ninja
build_override() {
    cd "$WORKDIR/qemu"

    # Copy proxmox-backup-qemu header if available
    if [[ -f "/usr/lib/proxmox-backup-qemu.h" ]]; then
        cp /usr/lib/proxmox-backup-qemu.h "$WORKDIR/qemu/"
    elif [[ -f "/usr/include/proxmox-backup-qemu.h" ]]; then
        cp /usr/include/proxmox-backup-qemu.h "$WORKDIR/qemu/"
    fi

    # Configure with meson
    meson setup build \
        --prefix=/usr \
        --libdir=/usr/lib64 \
        --sysconfdir=/etc \
        --localstatedir=/var \
        -Ddocs=disabled \
        -Dglusterfs=enabled \
        -Dceph=enabled \
        || true

    # Build with ninja
    ninja -C build -j"$(nproc)" || true
}

install_override() {
    mkdir -p "$STAGE/root" "$STAGE/meta"

    DESTDIR="$STAGE/root" ninja -C build install || true

    # Generate CPU flags and machine versions for pve-qemu-server
    if [[ -f "$STAGE/root/usr/bin/qemu-system-x86_64" ]]; then
        mkdir -p "$STAGE/root/usr/share/qemu"
        if [[ -f "$WORKDIR/debian/parse-cpu-flags.pl" ]]; then
            "$STAGE/root/usr/bin/qemu-system-x86_64" -cpu help 2>/dev/null | \
                perl "$WORKDIR/debian/parse-cpu-flags.pl" > \
                "$STAGE/root/usr/share/qemu/recognized-CPUID-flags-x86_64" 2>/dev/null || true
        fi
        if [[ -f "$WORKDIR/debian/parse-machines.pl" ]]; then
            "$STAGE/root/usr/bin/qemu-system-x86_64" -machine help 2>/dev/null | \
                perl "$WORKDIR/debian/parse-machines.pl" > \
                "$STAGE/root/usr/share/qemu/machine-versions-x86_64.json" 2>/dev/null || true
        fi
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

full_build
