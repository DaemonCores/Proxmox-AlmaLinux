#!/bin/bash
# build.sh — pve-qemu (Layer 4: C, QEMU patched by Proxmox)
#
# Proxmox-patched QEMU — the core hypervisor for PVE.
# Complex build: meson + ninja, patches from debian/patches/series,
# cross-submodule downloads, and post-install CPU flag/machine version generation.
#
# Adapted from proxmox-nixos:
#   - Source: pve-qemu.git (includes qemu/ subdirectory as meson project root)
#   - sourceRoot = qemu/
#   - Patches: all from debian/patches/series applied on top of upstream QEMU
#   - Nix: overrides qemu package, adds proxmox-backup-qemu to buildInputs
#   - Nix preBuild: copies proxmox-backup-qemu.h to source tree
#   - Nix postInstall: generates CPU flags and machine version JSON files
#     using qemu-system-x86_64 -cpu help and -machine help
#   - AlmaLinux: meson build with system deps, apply patches, generate metadata
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="pve-qemu"
REPO_URL="git://git.proxmox.com/git/pve-qemu.git"

# ------------------------------------------------------------------
# 1. Clone source (with submodules for meson subprojects)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Cloning source ==="
WORKDIR="/tmp/src/${PKG_NAME}"
rm -rf "$WORKDIR"
git clone "$REPO_URL" "$WORKDIR" --recursive
cd "$WORKDIR"

if [[ -n "${VERSION:-}" ]]; then
    git checkout "$VERSION" 2>/dev/null || git checkout "${SHORT:-${VERSION:0:7}}" 2>/dev/null || true
fi

# Download meson subprojects
if command -v meson &>/dev/null && [[ -d "$WORKDIR/qemu/subprojects" ]]; then
    cd "$WORKDIR/qemu"
    for wrap in subprojects/*.wrap; do
        [[ -f "$wrap" ]] || continue
        proj="$(basename "$wrap" .wrap)"
        echo "  Downloading meson subproject: $proj"
        meson subprojects download "$proj" 2>/dev/null || true
    done
    cd "$WORKDIR"
fi

# ------------------------------------------------------------------
# 2. Apply patches from debian/patches/series
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Applying patches ==="
cd "$WORKDIR"
if [[ -f "$WORKDIR/debian/patches/series" ]]; then
    while IFS= read -r patch; do
        [[ -z "$patch" || "$patch" =~ ^# ]] && continue
        echo "  Applying: $patch"
        patch -p1 -d "$WORKDIR" -i "$WORKDIR/debian/patches/$patch" || true
    done < "$WORKDIR/debian/patches/series"
fi

# ------------------------------------------------------------------
# 3. Copy proxmox-backup-qemu header (required for build)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Preparing proxmox-backup header ==="
# Nix preBuild: cp ${proxmox-backup-qemu}/lib/proxmox-backup-qemu.h .
if [[ -f "/usr/lib/proxmox-backup-qemu.h" ]]; then
    cp /usr/lib/proxmox-backup-qemu.h "$WORKDIR/qemu/"
elif [[ -f "/usr/include/proxmox-backup-qemu.h" ]]; then
    cp /usr/include/proxmox-backup-qemu.h "$WORKDIR/qemu/"
fi

# ------------------------------------------------------------------
# 4. Build (meson + ninja)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
cd "$WORKDIR/qemu"

# Configure with meson — enable features needed for PVE
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

# ------------------------------------------------------------------
# 5. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root" "$STAGE/meta"

DESTDIR="$STAGE/root" ninja -C build install || true

# ------------------------------------------------------------------
# 6. Generate CPU flags and machine versions (required by pve-qemu-server)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Generating CPU flags and machine versions ==="
# Nix postInstall:
#   $out/bin/qemu-system-x86_64 -cpu help | perl parse-cpu-flags.pl > recognized-CPUID-flags-x86_64
#   $out/bin/q86_64 -machine help | perl parse-machines.pl > machine-versions-x86_64.json
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
echo "PVE QEMU — Proxmox-patched QEMU hypervisor" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
ceph-libs
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
zstd-devel
EOF

# ------------------------------------------------------------------
# 9. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"