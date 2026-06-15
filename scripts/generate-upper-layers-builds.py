#!/usr/bin/env python3
"""Generate stub build.sh for Layer 2+ packages (Layers 2, 3, 4, 5, 7).

Each generated build.sh is a thin wrapper that:
1. Sets package-specific variables (PKG_NAME, REPO_URL, BUILD_TYPE, etc.)
2. Optionally defines build_override() and/or install_override() for complex packages
3. Sources ../../scripts/build-template.sh
4. Calls full_build()

The template dispatches to the right build/install functions based on BUILD_TYPE,
and calls any override functions defined by the stub.

Build type mapping:
  perl-git      → build_perl + install_perl (standard Perl package from git)
  rust-qemu     → build_override (QEMU meson+ninja) + install_override
  node          → build_node + install_override (JS/TS web assets)
  rust-wasm     → build_override (wasm-pack/cargo) + install_override

All 16 packages use version_source=git (git clone from git.proxmox.com).
"""

import os
import yaml

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKAGES_YML = os.path.join(PROJECT_DIR, "packages.yml")
PACKAGES_DIR = os.path.join(PROJECT_DIR, "packages")

# ---------------------------------------------------------------------------
# Package metadata — description, build type, custom install/build overrides,
# RPM dependencies, and other package-specific fields.
# ---------------------------------------------------------------------------
# BUILD_TYPE values map to build-template.sh dispatch:
#   perl-git     → build_perl + install_perl (or install_override if defined)
#   rust-qemu    → build_override (QEMU complex build) + install_override
#   node         → build_node + install_override (JS web assets)
#   rust-wasm    → build_override (wasm-pack/cargo WASM build) + install_override

PKG_META = {
    # ===================================================================
    # Layer 2 — Foundation (depends on Layer 0 + 1)
    # ===================================================================
    "pve-common": {
        "build_type": "perl-git",
        "description": "PVE common Perl library — core utilities, INotify, ProcFSTools, and more",
        "depends": [
            "perl", "perl-authen-pam", "perl-crypt-openssl-random",
            "perl-crypt-openssl-rsa", "perl-data-dumper", "perl-digest-sha",
            "perl-file-readbackwards", "perl-filesys-df", "perl-findbin",
            "perl-http-daemon", "perl-iosocketip", "perl-json",
            "perl-linux-inotify2", "perl-mail-spamassassin", "perl-mimebase32",
            "perl-mimebase64", "perl-netsubnet", "perl-net-dns", "perl-net-ip",
            "perl-net-ssleay", "perl-posixstrptime", "perl-socket",
            "perl-termreadline", "perl-testharness", "perl-uri", "perl-uuid",
            "perl-www-perl", "perl-xml-parser", "proxmox-backup-qemu",
        ],
        "extra_vars": {},
        "install_logic": "pve-common",
    },
    "pve-guest-common": {
        "build_type": "perl-git",
        "description": "PVE guest-related Perl modules — common code for guest agents",
        "depends": ["perl", "pve-common"],
        "extra_vars": {},
        "install_logic": "pve-guest-common",
        "subdir": "src",
    },

    # ===================================================================
    # Layer 3 — Cluster & Network (depends on Layer 2)
    # ===================================================================
    "pve-cluster": {
        "build_type": "perl-git",
        "description": "PVE cluster filesystem (pmxcfs) and cluster management tools",
        "depends": [
            "corosync", "fuse", "glib2", "libqb", "libxcrypt", "perl",
            "perl-Net-DNS", "perl-IO-Socket-SSL", "pve-access-control",
            "pve-apiclient", "pve-common", "proxmox-perl-rs", "rrdtool", "sqlite",
        ],
        "extra_vars": {},
        "install_logic": "pve-cluster",
        "subdir": "src",
    },
    "pve-http-server": {
        "build_type": "perl-git",
        "description": "PVE HTTP server — serves the Proxmox VE web UI and REST API",
        "depends": [
            "perl", "perl-AnyEvent-HTTP", "proxmox-i18n",
            "proxmox-widget-toolkit", "pve-common",
        ],
        "extra_vars": {},
        "install_logic": "pve-http-server",
        "subdir": "src",
    },
    "pve-network": {
        "build_type": "perl-git",
        "description": "PVE network management — SDN, bridges, VLANs, zones",
        "depends": [
            "perl", "perl-IO-Socket-SSL", "perl-NetAddr-IP", "perl-Net-IP",
            "pve-access-control", "pve-cluster", "pve-common",
        ],
        "extra_vars": {},
        "install_logic": "pve-network",
        "subdir": "src/PVE",
    },

    # ===================================================================
    # Layer 4 — Storage, Compute & Services (depends on Layer 3)
    # ===================================================================
    "pve-storage": {
        "build_type": "perl-git",
        "description": "PVE storage library — ZFS, LVM, Ceph RBD, iSCSI, NFS, and more",
        "depends": [
            "ceph-common", "ceph-libs", "glusterfs-libs", "iperf3",
            "libaio", "libiscsi", "lvm2", "perl", "pve-cluster", "pve-common",
            "pve-rados2", "smartmontools", "targetcli",
        ],
        "extra_vars": {},
        "install_logic": "pve-storage",
        "subdir": "src",
    },
    "pve-firewall": {
        "build_type": "perl-git",
        "description": "PVE firewall — iptables/nftables rules, ipsets, and security groups",
        "depends": [
            "glib2", "libnetfilter_conntrack", "libnetfilter_log",
            "libnfnetlink", "perl", "pve-access-control", "pve-cluster",
            "pve-common", "pve-network",
        ],
        "extra_vars": {},
        "install_logic": "pve-firewall",
        "subdir": "src",
    },
    "pve-ha-manager": {
        "build_type": "perl-git",
        "description": "PVE HA manager — high availability for VMs and containers",
        "depends": ["perl", "pve-cluster", "pve-common"],
        "extra_vars": {},
        "install_logic": "pve-ha-manager",
        "subdir": "src",
    },
    "pve-qemu": {
        "build_type": "rust-qemu",
        "description": "PVE QEMU — Proxmox-patched QEMU hypervisor (meson + ninja build)",
        "depends": [
            "ceph-libs", "glusterfs-libs", "glib2", "libaio-devel",
            "libcurl-devel", "libfdt-devel", "libiscsi-devel", "libnfs-devel",
            "libpmem-devel", "libssh-devel", "libuuid-devel", "lzo-devel",
            "meson", "ninja-build", "pixman-devel", "proxmox-backup-qemu",
            "python3", "snappy-devel", "systemd-devel", "usbredir-devel",
            "virglrenderer-devel", "zstd-devel",
        ],
        "extra_vars": {},
        "install_logic": "pve-qemu",
    },
    "pve-rados2": {
        "build_type": "perl-git",
        "description": "PVE RADOS2 — Perl bindings for Ceph RADOS (librados)",
        "depends": ["ceph-devel", "perl", "pve-common"],
        "extra_vars": {},
        "install_logic": "pve-rados2",
    },

    # ===================================================================
    # Layer 5 — Server & Manager (depends on all above)
    # ===================================================================
    "pve-container": {
        "build_type": "perl-git",
        "description": "PVE container manager — LXC container management (pct command)",
        "depends": [
            "lxc", "lxc-libs", "perl", "pve-common", "pve-guest-common",
            "pve-storage",
        ],
        "extra_vars": {},
        "install_logic": "pve-container",
        "subdir": "src",
    },
    "pve-qemu-server": {
        "build_type": "perl-git",
        "description": "PVE QEMU server — QEMU/KVM VM management (qm command)",
        "depends": [
            "ceph-common", "glusterfs-libs", "perl", "pve-common",
            "pve-guest-common", "pve-qemu", "pve-storage",
        ],
        "extra_vars": {},
        "install_logic": "pve-qemu-server",
        "subdir": "src",
    },
    "pve-manager": {
        "build_type": "perl-git",
        "description": "PVE manager — web UI, REST API, and management daemons",
        "depends": [
            "ceph-common", "corosync", "gnupg2", "graphviz", "gzip",
            "iproute", "openssh", "openssl", "perl",
            "perl-Crypt-OpenSSL-Bignum", "perl-File-ReadBackwards",
            "perl-Net-DNS", "perl-Pod-Parser", "perl-Template-Toolkit",
            "perl-proxmox-acme", "pve-cluster", "pve-container", "pve-docs",
            "pve-firewall", "pve-guest-common", "pve-ha-manager",
            "pve-http-server", "pve-network", "pve-qemu-server", "pve-storage",
            "proxmox-i18n", "proxmox-widget-toolkit", "shadow-utils",
            "sqlite", "systemd", "util-linux", "wget",
        ],
        "extra_vars": {},
        "install_logic": "pve-manager",
    },

    # ===================================================================
    # Layer 7 — Web UI Assets (depends on Layer 5+)
    # ===================================================================
    "pve-novnc": {
        "build_type": "node",
        "description": "PVE noVNC — Web-based VNC client for Proxmox VE",
        "depends": [],
        "extra_vars": {},
        "install_logic": "pve-novnc",
        "clone_recursive": True,
    },
    "pve-xtermjs": {
        "build_type": "node",
        "description": "PVE xterm.js — Web-based terminal emulator for Proxmox VE",
        "depends": ["termproxy"],
        "extra_vars": {},
        "install_logic": "pve-xtermjs",
    },
    "pve-yew-mobile-gui": {
        "build_type": "rust-wasm",
        "description": "PVE Yew Mobile GUI — Mobile web interface (Rust/WASM)",
        "depends": [],
        "extra_vars": {},
        "install_logic": "pve-yew-mobile-gui",
        "clone_recursive": True,
    },
}


def _fmt_depends(deps):
    """Format dependency list as bash heredoc or empty string."""
    if not deps:
        return ""
    return "\n".join(deps)


def generate_stub(pkg_id, meta, pkg_data):
    """Generate a stub build.sh that sources the template.

    The stub sets variables and optionally defines override functions,
    then sources ../../scripts/build-template.sh and calls full_build().
    """
    build_type = meta["build_type"]
    description = meta["description"]
    depends = meta.get("depends", [])
    repo_url = pkg_data.get("repo", "")
    install_logic = meta.get("install_logic", build_type)
    subdir = meta.get("subdir", "")
    clone_recursive = meta.get("clone_recursive", False)
    extra_vars = meta.get("extra_vars", {})
    layer = pkg_data.get("layer", "?")

    lines = []
    lines.append("#!/bin/bash")
    lines.append(f"# Package: {pkg_id}")
    lines.append(f"# Layer: {layer}")
    lines.append(f"# Type: {build_type}")
    lines.append("")
    lines.append(f'PKG_NAME="{pkg_id}"')

    # REPO_URL — all upper-layer packages are git-sourced
    if repo_url:
        lines.append(f'REPO_URL="{repo_url}"')

    # BUILD_TYPE
    lines.append(f'BUILD_TYPE="{build_type}"')

    # BUILD_SUBDIR
    if subdir:
        lines.append(f'BUILD_SUBDIR="{subdir}"')

    # CLONE_RECURSIVE for packages needing submodules
    if clone_recursive:
        lines.append('CLONE_RECURSIVE="1"')

    # PKG_DESCRIPTION
    lines.append(f'PKG_DESCRIPTION="{description}"')

    # PKG_DEPENDS
    deps_str = _fmt_depends(depends)
    if deps_str:
        lines.append(f"PKG_DEPENDS=$'{deps_str}'")

    # Extra variables specific to the package type
    for key, value in extra_vars.items():
        lines.append(f'{key}="{value}"')

    # Now add override functions for packages that need custom logic.
    # These override functions are defined BEFORE sourcing the template,
    # so the template's dispatch will call them.

    # ------------------------------------------------------------------
    # Layer 2 — pve-common
    # ------------------------------------------------------------------
    if install_logic == "pve-common":
        lines.append("")
        lines.append("# Override: install PVE common library")
        lines.append("pre_build_hook() {")
        lines.append('    # Patch Makefile for AlmaLinux — strip Debian-specific targets')
        lines.append('    if [[ -f "Makefile" ]]; then')
        lines.append('        sed -i "Makefile" \\')
        lines.append("            -e '/GITVERSION/d' \\")
        lines.append("            -e '/default.mk/d' \\")
        lines.append("            -e '/pkg-info/d'")
        lines.append('    fi')
        lines.append("}")
        lines.append("")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root" "$STAGE/meta"')
        lines.append('')
        lines.append('    make install DESTDIR="$STAGE/root" INSTALLDIRS=vendor || true')
        lines.append('')
        lines.append('    find "$STAGE/root" -name \'.packlist\' -delete 2>/dev/null || true')
        lines.append('    find "$STAGE/root" -name \'perllocal.pod\' -delete 2>/dev/null || true')
        lines.append("}")

    # ------------------------------------------------------------------
    # Layer 2 — pve-guest-common
    # ------------------------------------------------------------------
    elif install_logic == "pve-guest-common":
        lines.append("")
        lines.append("# Override: install PVE guest-common modules")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root" "$STAGE/meta"')
        lines.append('')
        lines.append('    make install DESTDIR="$STAGE/root" \\')
        lines.append('        PERL5DIR=/usr/share/perl5/vendor_perl \\')
        lines.append('        DOCDIR=/usr/share/doc/pve-guest-common || true')
        lines.append('')
        lines.append('    find "$STAGE/root" -name \'.packlist\' -delete 2>/dev/null || true')
        lines.append('    find "$STAGE/root" -name \'perllocal.pod\' -delete 2>/dev/null || true')
        lines.append("}")

    # ------------------------------------------------------------------
    # Layer 3 — pve-cluster
    # ------------------------------------------------------------------
    elif install_logic == "pve-cluster":
        lines.append("")
        lines.append("# Override: build and install pve-cluster (C + Perl hybrid)")
        lines.append("pre_build_hook() {")
        lines.append('    # Strip Debian-specific targets from Makefiles')
        lines.append('    for mkfile in Makefile src/Makefile; do')
        lines.append('        if [[ -f "$WORKDIR/$mkfile" ]]; then')
        lines.append('            sed -i "$WORKDIR/$mkfile" \\')
        lines.append("                -e '/GITVERSION/d' \\")
        lines.append("                -e '/pkg-info/d' \\")
        lines.append("                -e '/architecture/d' \\")
        lines.append("                -e '/dpkg-buildflags/d'")
        lines.append('        fi')
        lines.append('    done')
        lines.append('}')
        lines.append("")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root" "$STAGE/meta"')
        lines.append('')
        lines.append('    make install DESTDIR="$STAGE/root" PREFIX=/usr SBINDIR=/usr/sbin \\')
        lines.append('        PERLDIR=/usr/share/perl5/vendor_perl || true')
        lines.append('')
        lines.append('    # Strip hard-coded /usr/bin/ and /usr/sbin/ from Perl modules')
        lines.append('    find "$STAGE/root" -type f \\( -name "*.pm" -o -name "*.pl" \\) | while read -r f; do')
        lines.append('        sed -i "$f" -e "s|(/usr)?/s?bin/||g" 2>/dev/null || true')
        lines.append('    done')
        lines.append('')
        lines.append('    find "$STAGE/root" -name \'.packlist\' -delete 2>/dev/null || true')
        lines.append('    find "$STAGE/root" -name \'perllocal.pod\' -delete 2>/dev/null || true')
        lines.append("}")

    # ------------------------------------------------------------------
    # Layer 3 — pve-http-server
    # ------------------------------------------------------------------
    elif install_logic == "pve-http-server":
        lines.append("")
        lines.append("# Override: install PVE HTTP server")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root" "$STAGE/meta"')
        lines.append('')
        lines.append('    make install DESTDIR="$STAGE/root" PERL5DIR=/usr/share/perl5/vendor_perl || true')
        lines.append('')
        lines.append('    # Create expected web asset directories (populated at install time)')
        lines.append('    mkdir -p "$STAGE/root/usr/share/javascript" "$STAGE/root/usr/share/bootstrap-html" 2>/dev/null || true')
        lines.append('')
        lines.append('    find "$STAGE/root" -name \'.packlist\' -delete 2>/dev/null || true')
        lines.append('    find "$STAGE/root" -name \'perllocal.pod\' -delete 2>/dev/null || true')
        lines.append("}")

    # ------------------------------------------------------------------
    # Layer 3 — pve-network
    # ------------------------------------------------------------------
    elif install_logic == "pve-network":
        lines.append("")
        lines.append("# Override: install PVE network modules")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root" "$STAGE/meta"')
        lines.append('')
        lines.append('    make install DESTDIR="$STAGE/root" PERL5DIR=/usr/share/perl5/vendor_perl || true')
        lines.append('')
        lines.append('    find "$STAGE/root" -name \'.packlist\' -delete 2>/dev/null || true')
        lines.append('    find "$STAGE/root" -name \'perllocal.pod\' -delete 2>/dev/null || true')
        lines.append("}")

    # ------------------------------------------------------------------
    # Layer 4 — pve-storage
    # ------------------------------------------------------------------
    elif install_logic == "pve-storage":
        lines.append("")
        lines.append("# Override: patch Makefile and install PVE storage library")
        lines.append("pre_build_hook() {")
        lines.append('    if [[ -f "Makefile" ]]; then')
        lines.append('        sed -i "Makefile" \\')
        lines.append("            -e '/pvesm.1/d' \\")
        lines.append("            -e '/bash-completion/d' \\")
        lines.append("            -e '/zsh-completion/d'")
        lines.append('    fi')
        lines.append('    if [[ -f "bin/Makefile" ]]; then')
        lines.append('        sed -i "bin/Makefile" \\')
        lines.append("            -e '/pvesm.1/d' \\")
        lines.append("            -e '/bash-completion/d' \\")
        lines.append("            -e '/zsh-completion/d'")
        lines.append('    fi')
        lines.append("}")
        lines.append("")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root" "$STAGE/meta"')
        lines.append('')
        lines.append('    make install DESTDIR="$STAGE/root" PREFIX=/usr SBINDIR=/usr/sbin \\')
        lines.append('        PERLDIR=/usr/share/perl5/vendor_perl || true')
        lines.append('')
        lines.append('    find "$STAGE/root" -name \'.packlist\' -delete 2>/dev/null || true')
        lines.append('    find "$STAGE/root" -name \'perllocal.pod\' -delete 2>/dev/null || true')
        lines.append("}")

    # ------------------------------------------------------------------
    # Layer 4 — pve-firewall
    # ------------------------------------------------------------------
    elif install_logic == "pve-firewall":
        lines.append("")
        lines.append("# Override: patch Makefile and install PVE firewall")
        lines.append("pre_build_hook() {")
        lines.append('    if [[ -f "Makefile" ]]; then')
        lines.append('        sed -i "Makefile" \\')
        lines.append("            -e '/pve-firewall.1/d' \\")
        lines.append("            -e '/bash-completion/d' \\")
        lines.append("            -e '/zsh-completion/d' \\")
        lines.append("            -e '/dpkg-buildflags/d' \\")
        lines.append("            -e 's/-Werror/-Wno-error/g'")
        lines.append('    fi')
        lines.append("}")
        lines.append("")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root" "$STAGE/meta"')
        lines.append('')
        lines.append('    make install DESTDIR="$STAGE/root" PREFIX=/usr SBINDIR=/usr/sbin \\')
        lines.append('        PERLDIR=/usr/share/perl5/vendor_perl || true')
        lines.append('')
        lines.append('    find "$STAGE/root" -name \'.packlist\' -delete 2>/dev/null || true')
        lines.append('    find "$STAGE/root" -name \'perllocal.pod\' -delete 2>/dev/null || true')
        lines.append("}")

    # ------------------------------------------------------------------
    # Layer 4 — pve-ha-manager
    # ------------------------------------------------------------------
    elif install_logic == "pve-ha-manager":
        lines.append("")
        lines.append("# Override: patch Makefile and install PVE HA manager")
        lines.append("pre_build_hook() {")
        lines.append('    if [[ -f "Makefile" ]]; then')
        lines.append('        sed -i "Makefile" \\')
        lines.append("            -e '/pve-ha-crm.1/d' \\")
        lines.append("            -e '/pve-ha-lm.1/d' \\")
        lines.append("            -e '/bash-completion/d' \\")
        lines.append("            -e '/zsh-completion/d' \\")
        lines.append("            -e '/PVE_GENERATING_DOCS/d' \\")
        lines.append("            -e 's/-Werror/-Wno-error/g'")
        lines.append('    fi')
        lines.append("}")
        lines.append("")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root" "$STAGE/meta"')
        lines.append('')
        lines.append('    make install DESTDIR="$STAGE/root" PREFIX=/usr SBINDIR=/usr/sbin \\')
        lines.append('        PERLDIR=/usr/share/perl5/vendor_perl || true')
        lines.append('')
        lines.append('    find "$STAGE/root" -name \'.packlist\' -delete 2>/dev/null || true')
        lines.append('    find "$STAGE/root" -name \'perllocal.pod\' -delete 2>/dev/null || true')
        lines.append("}")

    # ------------------------------------------------------------------
    # Layer 4 — pve-qemu (Rust+C, meson+ninja complex build)
    # ------------------------------------------------------------------
    elif install_logic == "pve-qemu":
        lines.append("")
        lines.append("# Override: QEMU complex build with meson + ninja")
        lines.append("build_override() {")
        lines.append('    cd "$WORKDIR/qemu"')
        lines.append('')
        lines.append('    # Copy proxmox-backup-qemu header if available')
        lines.append('    if [[ -f "/usr/lib/proxmox-backup-qemu.h" ]]; then')
        lines.append('        cp /usr/lib/proxmox-backup-qemu.h "$WORKDIR/qemu/"')
        lines.append('    elif [[ -f "/usr/include/proxmox-backup-qemu.h" ]]; then')
        lines.append('        cp /usr/include/proxmox-backup-qemu.h "$WORKDIR/qemu/"')
        lines.append('    fi')
        lines.append('')
        lines.append('    # Configure with meson')
        lines.append('    meson setup build \\')
        lines.append('        --prefix=/usr \\')
        lines.append('        --libdir=/usr/lib64 \\')
        lines.append('        --sysconfdir=/etc \\')
        lines.append('        --localstatedir=/var \\')
        lines.append('        -Ddocs=disabled \\')
        lines.append('        -Dglusterfs=enabled \\')
        lines.append('        -Dceph=enabled \\')
        lines.append('        || true')
        lines.append('')
        lines.append('    # Build with ninja')
        lines.append('    ninja -C build -j"$(nproc)" || true')
        lines.append("}")
        lines.append("")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root" "$STAGE/meta"')
        lines.append('')
        lines.append('    DESTDIR="$STAGE/root" ninja -C build install || true')
        lines.append('')
        lines.append('    # Generate CPU flags and machine versions for pve-qemu-server')
        lines.append('    if [[ -f "$STAGE/root/usr/bin/qemu-system-x86_64" ]]; then')
        lines.append('        mkdir -p "$STAGE/root/usr/share/qemu"')
        lines.append('        if [[ -f "$WORKDIR/debian/parse-cpu-flags.pl" ]]; then')
        lines.append('            "$STAGE/root/usr/bin/qemu-system-x86_64" -cpu help 2>/dev/null | \\')
        lines.append('                perl "$WORKDIR/debian/parse-cpu-flags.pl" > \\')
        lines.append('                "$STAGE/root/usr/share/qemu/recognized-CPUID-flags-x86_64" 2>/dev/null || true')
        lines.append('        fi')
        lines.append('        if [[ -f "$WORKDIR/debian/parse-machines.pl" ]]; then')
        lines.append('            "$STAGE/root/usr/bin/qemu-system-x86_64" -machine help 2>/dev/null | \\')
        lines.append('                perl "$WORKDIR/debian/parse-machines.pl" > \\')
        lines.append('                "$STAGE/root/usr/share/qemu/machine-versions-x86_64.json" 2>/dev/null || true')
        lines.append('        fi')
        lines.append('    fi')
        lines.append("}")

    # ------------------------------------------------------------------
    # Layer 4 — pve-rados2 (Perl XS module)
    # ------------------------------------------------------------------
    elif install_logic == "pve-rados2":
        lines.append("")
        lines.append("# Override: patch Makefile and install pve-rados2 (Perl XS)")
        lines.append("pre_build_hook() {")
        lines.append('    if [[ -f "Makefile" ]]; then')
        lines.append('        sed -i "Makefile" \\')
        lines.append("            -e '/GITVERSION/d' \\")
        lines.append("            -e '/pkg-info/d' \\")
        lines.append("            -e '/architecture/d' 2>/dev/null || true")
        lines.append('    fi')
        lines.append("}")
        lines.append("")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root" "$STAGE/meta"')
        lines.append('')
        lines.append('    make install DESTDIR="$STAGE/root" PREFIX=/usr SBINDIR=/usr/bin \\')
        lines.append('        PERLDIR=/usr/share/perl5/vendor_perl \\')
        lines.append('        PERLSODIR=/usr/lib64/perl5/vendor_perl/auto || true')
        lines.append('')
        lines.append('    find "$STAGE/root" -name \'.packlist\' -delete 2>/dev/null || true')
        lines.append('    find "$STAGE/root" -name \'perllocal.pod\' -delete 2>/dev/null || true')
        lines.append("}")

    # ------------------------------------------------------------------
    # Layer 5 — pve-container
    # ------------------------------------------------------------------
    elif install_logic == "pve-container":
        lines.append("")
        lines.append("# Override: patch Makefile and install PVE container manager")
        lines.append("pre_build_hook() {")
        lines.append('    if [[ -f "Makefile" ]]; then')
        lines.append('        sed -i "Makefile" \\')
        lines.append("            -e '/GITVERSION/d' \\")
        lines.append("            -e '/SERVICEDIR/d' \\")
        lines.append("            -e '/BASHCOMPLDIR/d' \\")
        lines.append("            -e '/ZSHCOMPLDIR/d' \\")
        lines.append("            -e '/MAN1DIR/d' \\")
        lines.append("            -e '/MAN5DIR/d' \\")
        lines.append("            -e '/PVE_GENERATING_DOCS/d' \\")
        lines.append("            -e 's/-Werror/-Wno-error/g'")
        lines.append('    fi')
        lines.append("}")
        lines.append("")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root" "$STAGE/meta"')
        lines.append('')
        lines.append('    make install DESTDIR="$STAGE/root" PREFIX=/usr SBINDIR=/usr/sbin \\')
        lines.append('        PERLDIR=/usr/share/perl5/vendor_perl || true')
        lines.append('')
        lines.append('    find "$STAGE/root" -name \'.packlist\' -delete 2>/dev/null || true')
        lines.append('    find "$STAGE/root" -name \'perllocal.pod\' -delete 2>/dev/null || true')
        lines.append("}")

    # ------------------------------------------------------------------
    # Layer 5 — pve-qemu-server
    # ------------------------------------------------------------------
    elif install_logic == "pve-qemu-server":
        lines.append("")
        lines.append("# Override: patch Makefile and install PVE QEMU server")
        lines.append("pre_build_hook() {")
        lines.append('    if [[ -f "Makefile" ]]; then')
        lines.append('        sed -i "Makefile" \\')
        lines.append("            -e '/GITVERSION/d' \\")
        lines.append("            -e '/default.mk/d' \\")
        lines.append("            -e '/pve-doc-generator/d' \\")
        lines.append("            -e '/MAN1DIR/d' \\")
        lines.append("            -e '/bash-completion/d' \\")
        lines.append("            -e '/zsh-completion/d' \\")
        lines.append("            -e 's/-Werror/-Wno-error/g'")
        lines.append('    fi')
        lines.append('    if [[ -f "bin/Makefile" ]]; then')
        lines.append('        sed -i "bin/Makefile" \\')
        lines.append("            -e '/pod2man/d' \\")
        lines.append("            -e '/MAN1DIR/d'")
        lines.append('    fi')
        lines.append("}")
        lines.append("")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root" "$STAGE/meta"')
        lines.append('')
        lines.append('    make install DESTDIR="$STAGE/root" \\')
        lines.append('        PKGSOURCES="qm qmrestore qmextract" \\')
        lines.append('        PREFIX=/usr SBINDIR=/usr/sbin \\')
        lines.append('        PERLDIR=/usr/share/perl5/vendor_perl \\')
        lines.append('        USRSHAREDIR=/usr/share/qemu-server || true')
        lines.append('')
        lines.append('    find "$STAGE/root" -name \'.packlist\' -delete 2>/dev/null || true')
        lines.append('    find "$STAGE/root" -name \'perllocal.pod\' -delete 2>/dev/null || true')
        lines.append('')
        lines.append('    # Strip ENV{PATH} lines from Perl modules (AlmaLinux uses PATH-resolved tools)')
        lines.append('    find "$STAGE/root" -type f \\( -name "*.pm" -o -name "*.pl" \\) | while read -r f; do')
        lines.append('        sed -i "$f" -e "/ENV{\'PATH\'}/d" 2>/dev/null || true')
        lines.append('    done')
        lines.append("}")

    # ------------------------------------------------------------------
    # Layer 5 — pve-manager
    # ------------------------------------------------------------------
    elif install_logic == "pve-manager":
        lines.append("")
        lines.append("# Override: patch build files, build, and install PVE manager")
        lines.append("pre_build_hook() {")
        lines.append('    # Strip /usr from defines.mk')
        lines.append('    if [[ -f "defines.mk" ]]; then')
        lines.append('        sed -i "defines.mk" -e "s|/usr||g" 2>/dev/null || true')
        lines.append('    fi')
        lines.append('')
        lines.append('    # Patch Makefile — strip Debian-specific targets')
        lines.append('    if [[ -f "Makefile" ]]; then')
        lines.append('        sed -i "Makefile" \\')
        lines.append("            -e '/GITVERSION/d' \\")
        lines.append("            -e '/default.mk/d' \\")
        lines.append("            -e '/pkg-info/d' \\")
        lines.append("            -e '/log/d' \\")
        lines.append("            -e '/architecture/d' \\")
        lines.append("            -e 's/aplinfo PVE bin www services configs network-hooks test/PVE bin www configs test/'")
        lines.append('    fi')
        lines.append('')
        lines.append('    # Strip pod2man/man page targets from bin/Makefile')
        lines.append('    if [[ -f "bin/Makefile" ]]; then')
        lines.append('        sed -i "bin/Makefile" \\')
        lines.append("            -e '/pod2man/,+1d' \\")
        lines.append("            -e '/install -d.*MAN1DIR/,+9d'")
        lines.append('    fi')
        lines.append('')
        lines.append('    # Fix asciidoc-pve path')
        lines.append('    if [[ -f "www/manager6/Makefile" ]]; then')
        lines.append('        sed -i "www/manager6/Makefile" \\')
        lines.append("            -e '/BIOME/d' \\")
        lines.append('            -e "s|/usr/bin/asciidoc-pve|/usr/bin/asciidoc-pve|g"')
        lines.append('    fi')
        lines.append('}')
        lines.append("")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root" "$STAGE/meta"')
        lines.append('')
        lines.append('    make install \\')
        lines.append('        DESTDIR="$STAGE/root" \\')
        lines.append('        PVERELEASE=9.0 \\')
        lines.append('        VERSION="${PKG_VERSION:-dev}" \\')
        lines.append('        REPOID=almalinux \\')
        lines.append('        PERLLIBDIR=/usr/share/perl5/vendor_perl \\')
        lines.append('        WIDGETKIT=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js \\')
        lines.append('        BASH_COMPLETIONS= \\')
        lines.append('        ZSH_COMPLETIONS= \\')
        lines.append('        CLI_MANS= \\')
        lines.append('        SERVICE_MANS= \\')
        lines.append('        || true')
        lines.append('')
        lines.append('    # Remove Debian-specific tools not needed on AlmaLinux')
        lines.append('    rm -rf "$STAGE/root/var" 2>/dev/null || true')
        lines.append('    rm -f "$STAGE/root/usr/bin/pveupgrade" 2>/dev/null || true')
        lines.append('    rm -f "$STAGE/root/usr/bin/pveupdate" 2>/dev/null || true')
        lines.append('    rm -f "$STAGE/root/usr/bin/pveversion" 2>/dev/null || true')
        lines.append('    rm -f "$STAGE/root/usr/bin/pve8to9" 2>/dev/null || true')
        lines.append('')
        lines.append('    # Strip -T taint flag from scripts')
        lines.append('    for script in "$STAGE/root/usr/bin/"* "$STAGE/root/usr/sbin/"* "$STAGE/root/usr/share/pve-manager/helpers/"*; do')
        lines.append('        [[ -f "$script" ]] && sed -i "$script" -e "s/-T//" 2>/dev/null || true')
        lines.append('    done')
        lines.append('')
        lines.append('    # Path substitutions for AlmaLinux')
        lines.append('    find "$STAGE/root" -type f \\( -name "*.pl" -o -name "*.pm" \\) | while read -r f; do')
        lines.append('        sed -i "$f" \\')
        lines.append('            -e "/API2::APT/d" \\')
        lines.append('            -e "/ENV{\'PATH\'}/d" \\')
        lines.append('            -e "s|/usr/share/perl5|/usr/share/perl5/vendor_perl|g" || true')
        lines.append('    done')
        lines.append('')
        lines.append('    find "$STAGE/root/usr/bin" "$STAGE/root/usr/sbin" \\')
        lines.append('        "$STAGE/root/usr/share/pve-manager/helpers" \\')
        lines.append('        -type f 2>/dev/null | while read -r f; do')
        lines.append('        sed -i "$f" \\')
        lines.append('            -e "/ENV{\'PATH\'}/d" \\')
        lines.append('            -e "/API2::APT/d" || true')
        lines.append('    done')
        lines.append('')
        lines.append('    find "$STAGE/root" -name \'.packlist\' -delete 2>/dev/null || true')
        lines.append('    find "$STAGE/root" -name \'perllocal.pod\' -delete 2>/dev/null || true')
        lines.append("}")

    # ------------------------------------------------------------------
    # Layer 7 — pve-novnc (JavaScript web VNC client)
    # ------------------------------------------------------------------
    elif install_logic == "pve-novnc":
        lines.append("")
        lines.append("# Override: build with esbuild and install noVNC web assets")
        lines.append("build_override() {")
        lines.append('    cd "$WORKDIR/novnc" 2>/dev/null || cd "$WORKDIR" || true')
        lines.append('')
        lines.append('    # Apply Debian patches')
        lines.append('    apply_debian_patches')
        lines.append('')
        lines.append('    # Build with esbuild if available')
        lines.append('    if command -v esbuild &>/dev/null; then')
        lines.append('        if [[ -f "app/ui.js" ]]; then')
        lines.append('            esbuild --bundle --format=esm app/ui.js > app.js 2>/dev/null || true')
        lines.append('        fi')
        lines.append('    fi')
        lines.append("}")
        lines.append("")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root/usr/share/novnc-pve" "$STAGE/meta"')
        lines.append('')
        lines.append('    # Copy all web assets')
        lines.append('    if [[ -d "$WORKDIR/novnc" ]]; then')
        lines.append('        cp -r "$WORKDIR/novnc/"* "$STAGE/root/usr/share/novnc-pve/" 2>/dev/null || true')
        lines.append('    elif [[ -d "$WORKDIR" ]]; then')
        lines.append('        for dir in app core vendor images include; do')
        lines.append('            [[ -d "$WORKDIR/$dir" ]] && cp -r "$WORKDIR/$dir" "$STAGE/root/usr/share/novnc-pve/" || true')
        lines.append('        done')
        lines.append('        for f in vnc.html *.js *.css; do')
        lines.append('            [[ -f "$WORKDIR/$f" ]] && cp "$WORKDIR/$f" "$STAGE/root/usr/share/novnc-pve/" || true')
        lines.append('        done')
        lines.append('    fi')
        lines.append('')
        lines.append('    # Copy bundled app.js if built')
        lines.append('    local build_dir="$WORKDIR"')
        lines.append('    [[ -d "$WORKDIR/novnc" ]] && build_dir="$WORKDIR/novnc"')
        lines.append('    if [[ -f "$build_dir/app.js" ]]; then')
        lines.append('        cp "$build_dir/app.js" "$STAGE/root/usr/share/novnc-pve/"')
        lines.append('    fi')
        lines.append("}")

    # ------------------------------------------------------------------
    # Layer 7 — pve-xtermjs (TypeScript/Node terminal)
    # ------------------------------------------------------------------
    elif install_logic == "pve-xtermjs":
        lines.append("")
        lines.append("# Override: install static web assets for xterm.js terminal")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root/usr/share/pve-xtermjs" "$STAGE/meta"')
        lines.append('')
        lines.append('    # Copy all web assets per Nix installPhase')
        lines.append('    if [[ -d "$WORKDIR/xterm.js/src" ]]; then')
        lines.append('        cp -r "$WORKDIR/xterm.js/src/"* "$STAGE/root/usr/share/pve-xtermjs/"')
        lines.append('    elif [[ -d "$WORKDIR/src" ]]; then')
        lines.append('        cp -r "$WORKDIR/src/"* "$STAGE/root/usr/share/pve-xtermjs/"')
        lines.append('    fi')
        lines.append('')
        lines.append('    # Rename template files per Nix postInstall')
        lines.append('    cd "$STAGE/root/usr/share/pve-xtermjs"')
        lines.append('    [[ -f "index.html.hbs.in" ]] && mv index.html.hbs.in index.html.hbs 2>/dev/null || true')
        lines.append('    [[ -f "index.html.tpl.in" ]] && mv index.html.tpl.in index.html.tpl 2>/dev/null || true')
        lines.append("}")

    # ------------------------------------------------------------------
    # Layer 7 — pve-yew-mobile-gui (Rust/WASM)
    # ------------------------------------------------------------------
    elif install_logic == "pve-yew-mobile-gui":
        lines.append("")
        lines.append("# Override: patch Makefile and build Rust→WASM")
        lines.append("pre_build_hook() {")
        lines.append('    # Remove dpkg includes and fix grass path')
        lines.append('    if [[ -f "Makefile" ]]; then')
        lines.append('        sed -i "Makefile" \\')
        lines.append("            -e '/include.*dpkg/d' \\")
        lines.append('            -e "s|rust-grass|grass|g" 2>/dev/null || true')
        lines.append('    fi')
        lines.append('')
        lines.append('    # Remove vendored cargo config')
        lines.append('    rm -f .cargo/config.toml 2>/dev/null || true')
        lines.append("}")
        lines.append("")
        lines.append("build_override() {")
        lines.append('    export LIBCLANG_PATH="${LIBCLANG_PATH:-/usr/lib64/clang}"')
        lines.append('')
        lines.append('    # Try wasm-pack first, then cargo with wasm32 target')
        lines.append('    if command -v wasm-pack &>/dev/null; then')
        lines.append('        wasm-pack build --release --target web 2>/dev/null || true')
        lines.append('    elif command -v cargo &>/dev/null; then')
        lines.append('        rustup target add wasm32-unknown-unknown 2>/dev/null || true')
        lines.append('        cargo build --release --target wasm32-unknown-unknown 2>/dev/null || true')
        lines.append('    fi')
        lines.append('')
        lines.append('    # Also try make if available')
        lines.append('    make -j"$(nproc)" 2>/dev/null || true')
        lines.append("}")
        lines.append("")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root/usr/share/pve-yew-mobile-gui" "$STAGE/meta"')
        lines.append('')
        lines.append('    # Copy WASM output and web assets')
        lines.append('    if [[ -f "pkg/pve_yew_mobile_gui_bg.wasm" ]]; then')
        lines.append('        cp -r pkg/* "$STAGE/root/usr/share/pve-yew-mobile-gui/" 2>/dev/null || true')
        lines.append('    fi')
        lines.append('')
        lines.append('    # Fallback: install from make install')
        lines.append('    make install DESTDIR="$STAGE/root" PREFIX=/usr 2>/dev/null || true')
        lines.append("}")

    # Source the template and run full_build
    lines.append("")
    lines.append("source ../../scripts/build-template.sh")
    lines.append("")
    lines.append("full_build")

    return "\n".join(lines) + "\n"


def main():
    with open(PACKAGES_YML, "r") as f:
        data = yaml.safe_load(f)

    # Filter for Layer >= 2
    upper_layers = [p for p in data["packages"] if p.get("layer", 0) >= 2]

    print("=== generate-upper-layers-builds.py ===")
    print(f"Parsing packages.yml... Found {len(upper_layers)} Layer 2+ packages")

    generated = 0
    skipped = 0
    for pkg in upper_layers:
        pkg_id = pkg["id"]
        meta = PKG_META.get(pkg_id)
        if meta is None:
            print(f"  [SKIP] {pkg_id}: no metadata in PKG_META, skipping")
            skipped += 1
            continue

        target_dir = os.path.join(PACKAGES_DIR, pkg_id)
        target_file = os.path.join(target_dir, "build.sh")

        if not os.path.isdir(target_dir):
            print(f"  WARNING: Directory {target_dir} does not exist, creating it")
            os.makedirs(target_dir, exist_ok=True)

        content = generate_stub(pkg_id, meta, pkg)

        with open(target_file, "w") as f:
            f.write(content)

        # Make executable
        os.chmod(target_file, 0o755)

        build_type = meta["build_type"]
        layer = pkg.get("layer", "?")
        line_count = len(content.splitlines())
        print(f"  [OK] {target_file} (Layer {layer}, {build_type}, {line_count} lines)")
        generated += 1

    print()
    print("=== Summary ===")
    print(f"  Build.sh files generated: {generated}")
    print(f"  Packages skipped (no meta): {skipped}")

    # Print table of packages and build types
    print()
    print("=== Package Build Type Mapping ===")
    for pkg in upper_layers:
        pkg_id = pkg["id"]
        meta = PKG_META.get(pkg_id, {})
        build_type = meta.get("build_type", "UNKNOWN")
        depends_on = pkg.get("depends_on", [])
        deps_str = f" (depends_on: {', '.join(depends_on)})" if depends_on else ""
        print(f"  {pkg_id:30s} → {build_type}{deps_str}")

    print("=== Done ===")


if __name__ == "__main__":
    main()