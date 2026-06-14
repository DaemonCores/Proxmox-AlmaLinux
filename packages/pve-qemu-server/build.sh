#!/bin/bash
# build.sh — pve-qemu-server (Layer 5: Perl, QEMU/KVM VM management)
#
# Proxmox VE QEMU server — manages QEMU/KVM virtual machines (qm command).
# Mixed C + Perl — C code for qmeventd, Perl for VM management.
# Source in src/ subdirectory.
#
# Adapted from proxmox-nixos:
#   - sourceRoot = src/
#   - Nix postPatch: strips GITVERSION, default.mk, pve-doc-generator,
#     man pages, completions; fixes QEMU version check; fixes libGL/libEGL detection
#   - Nix: dontBuild = true (install-only, Perl + qmeventd C binary)
#   - Nix installPhase: make install PKGSOURCES="qm qmrestore qmextract"
#     DESTDIR=$out PREFIX= SBINDIR=/.bin USRSHAREDIR=... PERLDIR=...
#   - Nix postFixup: MASSIVE path substitutions —
#     /ENV{'PATH'}/d, /usr/lib/qemu-server, /usr/libexec/qemu-server,
#     /usr/share/qemu-server, /usr/share/kvm, /usr/bin/socat, vncterm,
#     qemu-kvm, qemu-system, /var/lib/qemu-server, pve-edk2-firmware,
#     swtpm, virt-fw-vars, proxmox-backup-client, etc.
#   - AlmaLinux: keep FHS paths, strip /usr/bin/ prefixes for PATH-resolved tools
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="pve-qemu-server"
REPO_URL="git://git.proxmox.com/git/qemu-server.git"

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
# 2. Patch Makefiles
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Patching Makefiles ==="
# Nix: sed -i {qmeventd/,bin/}Makefile -e "/GITVERSION/d" -e "/default.mk/d"
#   -e "/pve-doc-generator/d" -e "/install -m 0644 -D qm.bash-completion/,+3d"
#   -e "/install -m 0644 qm.1/,+4d" -e "s/qmeventd docs/qmeventd/"
#   -e "/qmeventd.8/d" -e "/modules-load.conf/d" -e "s,usr/,,g"
for mkfile in qmeventd/Makefile bin/Makefile; do
    if [[ -f "$mkfile" ]]; then
        sed -i "$mkfile" \
            -e "/GITVERSION/d" \
            -e "/default.mk/d" \
            -e "/pve-doc-generator/d" \
            -e "/install -m 0644 -D qm.bash-completion/,+3d" \
            -e "/install -m 0644 qm.1/,+4d" \
            -e "s/qmeventd docs/qmeventd/" \
            -e "/qmeventd.8/d" \
            -e "/modules-load.conf/d"
    fi
done

# Fix QEMU version check (Nix: sed -i PVE/QemuServer/Helpers.pm -e "s/\[,\\\s\]//")
if [[ -f "PVE/QemuServer/Helpers.pm" ]]; then
    sed -i "PVE/QemuServer/Helpers.pm" -e 's/\[,\\\s\]//' 2>/dev/null || true
fi

# Fix libGL detection (Nix: sed -i PVE/QemuServer.pm -e "s|/usr/lib/x86_64-linux-gnu/lib|...|")
if [[ -f "PVE/QemuServer.pm" ]]; then
    sed -i "PVE/QemuServer.pm" -e "s|/usr/lib/x86_64-linux-gnu/lib|/usr/lib64/lib|g" 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 3. Build
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Building ==="
# qmeventd is a C binary; the rest is pure Perl (install-only in Nix)
make -j"$(nproc)" || true

# ------------------------------------------------------------------
# 4. Install to staging root
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Installing to staging root ==="
STAGE="/tmp/pkg/${PKG_NAME}"
rm -rf "$STAGE"
mkdir -p "$STAGE/root" "$STAGE/meta"

# Create systemd unit directory
mkdir -p "$STAGE/root/usr/lib/systemd/system"

make install \
    PKGSOURCES="qm qmrestore qmextract" \
    DESTDIR="$STAGE/root" \
    PREFIX=/usr \
    SBINDIR=/usr/sbin \
    USRSHAREDIR=/usr/share/qemu-server \
    PERLDIR=/usr/share/perl5/vendor_perl \
    || true

find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true

# Strip -T taint flag from qm (AlmaLinux Perl handles this differently)
for script in "$STAGE/root/usr/sbin/"qm*; do
    [[ -f "$script" ]] && sed -i "$script" -e "s/-T//" 2>/dev/null || true
done

# ------------------------------------------------------------------
# 5. Nix→AlmaLinux path substitutions
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Applying path substitutions ==="
# Nix postFixup replaces many paths. On AlmaLinux FHS:
#   /usr/lib/qemu-server   → /usr/lib/qemu-server (same)
#   /usr/libexec/qemu-server → /usr/libexec/qemu-server (same)
#   /usr/share/qemu-server  → /usr/share/qemu-server (same)
#   /usr/share/kvm          → /usr/share/qemu (AlmaLinux QEMU path)
#   /usr/sbin/qm            → /usr/sbin/qm (same)
#   qemu-kvm, qemu-system   → /usr/bin/qemu-kvm, /usr/bin/qemu-system (same)
#   socat, vncterm, etc.    → resolved via PATH
find "$STAGE/root" -type f \( -name '*.pl' -o -name '*.pm' \) | while read -r f; do
    sed -i \
        -e "/ENV{'PATH'}/d" \
        -e "s|/usr/share/kvm|/usr/share/qemu|g" \
        -e "s|/var/lib/qemu-server|/var/lib/qemu-server|g" \
        -e "s|/usr/share/pve-edk2-firmware|/usr/share/pve-edk2-firmware|g" \
        "$f" || true
done

# Also fix scripts in lib/ and libexec/
find "$STAGE/root/usr/lib" "$STAGE/root/usr/libexec" -type f 2>/dev/null | while read -r f; do
    sed -i \
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
echo "PVE QEMU server — QEMU/KVM virtual machine management (qm)" > "$STAGE/meta/description"
echo "Proxmox"                  > "$STAGE/meta/maintainer"
echo "rpm"                      > "$STAGE/meta/source_format"

cat > "$STAGE/meta/depends" << 'EOF'
glib2
json-c
libsysprof-capture
pcre2
perl
perl-Crypt-OpenSSL-Random
perl-Data-Dumper
perl-Digest-SHA
perl-File-Path
perl-FindBin
perl-HTTP-Message
perl-Getopt-Long
perl-IO
perl-IO-Multiplex
perl-IO-Socket-IP
perl-JSON
perl-MIME-Base64
perl-Net-SSLeay
perl-PathTools
perl-Scalar-List-Utils
perl-Socket
perl-Storable
perl-Term-ReadLine
perl-Test-Harness
perl-Test-Mock-Module
perl-Test-Simple
perl-Time-HiRes
perl-UUID
perl-XML-LibXML
pve-common
pve-firewall
pve-guest-common
pve-qemu
pve-storage
socat
EOF

# ------------------------------------------------------------------
# 8. Package as .pkg.tar
# ------------------------------------------------------------------
echo "=== [$PKG_NAME] Creating .pkg.tar ==="
cd "$STAGE"
tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

echo "=== [$PKG_NAME] Done ==="
echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"