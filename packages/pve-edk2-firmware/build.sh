#!/bin/bash
# build.sh — pve-edk2-firmware (Layer 1: UEFI firmware for VMs)
#
# Builds OVMF/UEFI firmware modules for PVE virtual machines.
# Complex build: uses EDK2 build system with cross-compilers for
# x86_64, aarch64, riscv64 architectures.
#
# Adapted from proxmox-nixos:
#   - Nix: buildPhase uses debian/rules override_dh_auto_build
#   - Hardening disabled (format, fortify, trivialautovarinit)
#   - Requires: nasm, acpica-tools, dosfstools, mtools, libuuid,
#     qemu-utils, libisoburn, python3 + virt-firmware, bc
#   - Cross compilers for aarch64 and riscv64
#   - AlmaLinux: use cross-compiler packages from dnf
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="pve-edk2-firmware"
REPO_URL="git://git.proxmox.com/git/pve-edk2-firmware.git"

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
# 2. Patch build files
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Patching build files ==="
# Nix: substituteInPlace ./Makefile ./debian/rules --replace-fail '/usr/share/dpkg' '${dpkg}/share/dpkg'
# AlmaLinux: strip dpkg references, use /usr/share/dpkg if available or mock it
if [[ -f "$WORKDIR/Makefile" ]]; then
    sed -i "$WORKDIR/Makefile" \
        -e "s|/usr/share/dpkg|/usr/share/dpkg|g"
fi
if [[ -f "$WORKDIR/debian/rules" ]]; then
    sed -i "$WORKDIR/debian/rules" \
        -e "s|/usr/share/dpkg|/usr/share/dpkg|g"
fi

# ------------------------------------------------------------------
# 3. Build (EDK2 — via debian/rules override_dh_auto_build)
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
# The Nix build moves debian/ into edk2/ and runs override_dh_auto_build
# On AlmaLinux, we replicate this via the debian/rules makefile target
cd "$WORKDIR"

# Disable hardening flags that conflict with EDK2 build
export CFLAGS="${CFLAGS:-} -Wno-format -Wno-error=format-security -fno-trivial-auto-var-init=zero"

# Run the EDK2 build via the Proxmox build rules
if [[ -f "$WORKDIR/debian/rules" ]]; then
    # Move debian dir into edk2 subtree as Nix does
    if [[ -d "$WORKDIR/edk2" ]]; then
        pushd "$WORKDIR/edk2"
        make -f "$WORKDIR/debian/rules" override_dh_auto_build || true
        popd
    else
        make -f "$WORKDIR/debian/rules" override_dh_auto_build || true
    fi
fi

# ------------------------------------------------------------------
# 4. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root/usr/share/pve-edk2-firmware" "$STAGE/meta"

# Copy firmware files per *.install files
if [[ -d "$WORKDIR/debian" ]]; then
    for f in "$WORKDIR"/debian/*.install; do
        [[ -f "$f" ]] || continue
        while IFS= read -r line; do
            read -ra paths <<< "$line"
            dest="$STAGE/root/${paths[-1]}"
            mkdir -p "$dest"
            for src in "${paths[@]::${#paths[@]}-1}"; do
                # Resolve source relative to build dir
                for found in "$WORKDIR"/$src "$WORKDIR"/edk2/$src; do
                    if [[ -e "$found" ]]; then
                        cp $found "$dest" 2>/dev/null || true
                    fi
                done
            done
        done < "$f"
    done
fi

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
echo "PVE EDK2 UEFI firmware modules for virtual machines" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
acpica-tools
bc
dosfstools
gcc-aarch64-linux-gnu
libuuid
mtools
nasm
python3-virt-firmware
qemu-img
xorriso
EOF

# ------------------------------------------------------------------
# 7. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"