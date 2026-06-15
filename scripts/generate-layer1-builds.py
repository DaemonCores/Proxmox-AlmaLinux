#!/usr/bin/env python3
"""Generate minimal stub build.sh for all Layer 1 packages.

Each generated build.sh is a thin wrapper that sets package-specific
variables and sources ../../scripts/build-template.sh, which provides
all the build pipeline functions. Packages that need custom build or
install logic define build_override() and/or install_override() before
sourcing the template.

The template dispatches to the right build/install functions based on
BUILD_TYPE, and calls any override functions defined by the stub.
"""

import os
import yaml

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKAGES_YML = os.path.join(PROJECT_DIR, "packages.yml")
PACKAGES_DIR = os.path.join(PROJECT_DIR, "packages")

# ---------------------------------------------------------------------------
# Package metadata — description, build type, dependencies, and custom fields
# ---------------------------------------------------------------------------
# Build types map to template dispatch in full_build():
#   rust-workspace   → build_rust + install_rust (workspace monorepo)
#   rust-submodules  → build_rust + install_rust (clone --recursive)
#   rust-perl        → build_rust + install_override (cargo + make hybrid)
#   node             → build_node + install_override (JS/CSS)
#   node-hash        → fetch_source_download + install_override (downloaded JS)
#   perl-git         → build_perl + install_perl (git-sourced Perl)
#   i18n             → build_i18n + install_i18n (gettext)
#   docs             → build_docs + install_docs (asciidoc)
#   firmware         → build_firmware + install_firmware (EDK2)
#   font             → install_font (git-sourced font assets)
#   font-hash         → fetch_source_download + install_override (downloaded font)
#   c-patched        → build_c_patched + install_override (C with Makefile patching)
#   c-hash            → fetch_source_download + build_c + install_c (downloaded C)
#   generic          → install_generic (hash-only downloads)

PKG_META = {
    # --- Rust packages ---
    "proxmox-backup-qemu": {
        "build_type": "rust-submodules",
        "description": "Proxmox Backup client library for QEMU — Rust shared library",
        "depends": [
            "acl", "clang-libs", "libuuid", "libxcrypt", "openssl-libs",
            "pam", "sg3_utils-libs", "zstd",
        ],
        "extra_vars": {
            "CARGO_PKG": "proxmox-backup-qemu",
        },
        "install_logic": "shared_library",
    },
    "proxmox-rs": {
        "build_type": "rust-workspace",
        "description": "Proxmox Rust framework — core types, utilities, and API libraries",
        "depends": ["cargo", "openssl-libs", "pkgconf-pkg-config"],
        "extra_vars": {},
        "install_logic": "workspace",
    },
    "perlmod": {
        "build_type": "rust-submodules",
        "description": "PerlMod — Alternative to Perl XS for Rust bindings",
        "depends": ["libxcrypt", "perl"],
        "extra_vars": {
            "CARGO_PKG": "perlmod-bin",
        },
        "install_logic": "perlmod",
    },
    "termproxy": {
        "build_type": "rust-submodules",
        "description": "Termproxy — Terminal proxy utility for xterm.js web console",
        "depends": [],
        "extra_vars": {},
        "install_logic": "termproxy",
        "subdir": "termproxy",
    },

    # --- Rust + Perl hybrid ---
    "proxmox-perl-rs": {
        "build_type": "rust-perl",
        "description": "Proxmox Rust bindings for Perl — perlmod-generated XS modules",
        "depends": ["cargo", "perl", "libuuid", "openssl-libs", "pkgconf-pkg-config"],
        "extra_vars": {},
        "install_logic": "perl-rs",
        "subdir": "pve-rs",
    },

    # --- Node.js / JS packages ---
    "proxmox-widget-toolkit": {
        "build_type": "node",
        "description": "Proxmox ExtJS widget toolkit — JS/CSS for PVE web UI",
        "depends": ["sassc", "uglify-js"],
        "extra_vars": {},
        "install_logic": "widget-toolkit",
        "subdir": "src",
    },
    "extjs": {
        "build_type": "node",
        "description": "ExtJS JavaScript framework for PVE web UI",
        "depends": [],
        "extra_vars": {},
        "install_logic": "extjs",
    },
    "qrcodejs": {
        "build_type": "node",
        "description": "QRCode.js — Cross-browser QR code generator for JavaScript",
        "depends": [],
        "extra_vars": {},
        "install_logic": "qrcodejs",
        "subdir": "src",
    },

    # --- Hash-only packages (download pre-built assets) ---
    "markedjs": {
        "build_type": "node-hash",
        "description": "Marked — Markdown parser and compiler for JavaScript",
        "depends": [],
        "extra_vars": {
            "MARKED_VERSION": "17.0.4",
            "MARKED_URL": "https://github.com/markedjs/marked/releases/download/v17.0.4/marked.min.js",
            "MARKED_FALLBACK_URL": "https://cdn.jsdelivr.net/npm/marked@17.0.4/marked.min.js",
        },
        "install_logic": "markedjs",
    },
    "unifont-hex": {
        "build_type": "font-hash",
        "description": "GNU Unifont — hex format font data for vncterm",
        "depends": [],
        "extra_vars": {
            "UNIFONT_VERSION": "17.0.03",
            "UNIFONT_URL": "https://ftp.gnu.org/gnu/unifont/unifont-17.0.03/unifont-17.0.03.tar.gz",
        },
        "install_logic": "unifont-hex",
    },
    "cstream": {
        "build_type": "c-hash",
        "description": "cstream — General-purpose stream handling tool like dd",
        "depends": [],
        "extra_vars": {
            "CSTREAM_VERSION": "4.0.0",
            "CSTREAM_URL": "https://www.cons.org/cracauer/download/cstream-4.0.0.tar.gz",
        },
        "install_logic": "cstream",
    },

    # --- Perl packages (git) ---
    "pve-access-control": {
        "build_type": "perl-git",
        "description": "PVE access control framework — user, role, and permission management",
        "depends": ["perl", "perl-authen-pam", "pve-common"],
        "extra_vars": {},
        "install_logic": "access-control",
        "subdir": "src",
    },
    "pve-apiclient": {
        "build_type": "perl-git",
        "description": "PVE API client — Perl library for Proxmox VE REST API",
        "depends": ["perl", "perl-IO-Socket-SSL"],
        "extra_vars": {},
        "install_logic": "apiclient",
        "subdir": "src",
    },

    # --- Translation package ---
    "proxmox-i18n": {
        "build_type": "i18n",
        "description": "Proxmox internationalization — gettext translation files",
        "depends": ["gettext", "perl"],
        "extra_vars": {},
        "install_logic": "i18n",
    },

    # --- Documentation ---
    "pve-docs": {
        "build_type": "docs",
        "description": "PVE documentation — asciidoc-generated HTML/PDF docs",
        "depends": ["asciidoc", "graphviz", "imagemagick", "perl", "perl-JSON", "perl-Template-Toolkit"],
        "extra_vars": {},
        "install_logic": "docs",
    },

    # --- Firmware ---
    "pve-edk2-firmware": {
        "build_type": "firmware",
        "description": "PVE EDK2 UEFI firmware modules for virtual machines",
        "depends": [
            "acpica-tools", "bc", "dosfstools", "gcc-aarch64-linux-gnu",
            "libuuid", "mtools", "nasm", "python3-virt-firmware", "qemu-img",
            "xorriso",
        ],
        "extra_vars": {},
        "install_logic": "firmware",
    },

    # --- Font package (git) ---
    "fonts-font-logos": {
        "build_type": "font",
        "description": "Font logos — Font Awesome + custom font icons for PVE web UI",
        "depends": ["fontconfig"],
        "extra_vars": {},
        "install_logic": "font-logos",
        "subdir": "src",
    },

    # --- C packages ---
    "vncterm": {
        "build_type": "c-patched",
        "description": "vncterm — VNC terminal emulator for Proxmox VE console access",
        "depends": ["gnutls", "libjpeg", "libpng", "libvncserver", "unifont-hex"],
        "extra_vars": {},
        "install_logic": "vncterm",
        "depends_on": ["unifont-hex"],
    },
}


def _fmt_depends(deps):
    """Format dependency list as bash heredoc or empty."""
    if not deps:
        return ""
    lines = []
    for d in deps:
        lines.append(d)
    return "\n".join(lines)


def generate_stub(pkg_id, meta, pkg_data):
    """Generate a minimal stub build.sh that sources the template.

    The stub sets variables and optionally defines override functions,
    then sources ../../scripts/build-template.sh and calls full_build().
    """
    build_type = meta["build_type"]
    description = meta["description"]
    depends = meta.get("depends", [])
    repo_url = pkg_data.get("repo", "")
    version_source = pkg_data.get("version_source", "git")
    install_logic = meta.get("install_logic", build_type)
    subdir = meta.get("subdir", "")
    clone_recursive = meta.get("clone_recursive", False)
    extra_vars = meta.get("extra_vars", {})
    depends_on = pkg_data.get("depends_on", [])

    lines = []
    lines.append("#!/bin/bash")
    lines.append(f"# Package: {pkg_id}")
    lines.append(f"# Layer: 1")
    lines.append(f"# Type: {build_type}")
    lines.append("")
    lines.append(f'PKG_NAME="{pkg_id}"')

    # REPO_URL for git-sourced packages
    if repo_url and version_source == "git":
        lines.append(f'REPO_URL="{repo_url}"')

    # BUILD_TYPE
    lines.append(f'BUILD_TYPE="{build_type}"')

    # BUILD_SUBDIR
    if subdir:
        lines.append(f'BUILD_SUBDIR="{subdir}"')

    # CLONE_RECURSIVE for git packages needing submodules
    if clone_recursive or build_type == "rust-submodules":
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

    # DOWNLOAD_URL/VERSION for hash-only packages
    if version_source == "hash-only":
        if "MARKED_URL" in extra_vars:
            lines.append(f'DOWNLOAD_URL="{extra_vars.get("MARKED_URL", "")}"')
            lines.append(f'DOWNLOAD_VERSION="{extra_vars.get("MARKED_VERSION", "")}"')
            lines.append(f'DOWNLOAD_FALLBACK_URL="{extra_vars.get("MARKED_FALLBACK_URL", "")}"')
        elif "UNIFONT_URL" in extra_vars:
            lines.append(f'DOWNLOAD_URL="{extra_vars.get("UNIFONT_URL", "")}"')
            lines.append(f'DOWNLOAD_VERSION="{extra_vars.get("UNIFONT_VERSION", "")}"')
            lines.append(f'DOWNLOAD_EXTRACT_DIR="unifont-{extra_vars.get("UNIFONT_VERSION", "")}"')
        elif "CSTREAM_URL" in extra_vars:
            lines.append(f'DOWNLOAD_URL="{extra_vars.get("CSTREAM_URL", "")}"')
            lines.append(f'DOWNLOAD_VERSION="{extra_vars.get("CSTREAM_VERSION", "")}"')
            lines.append(f'DOWNLOAD_EXTRACT_DIR="cstream-{extra_vars.get("CSTREAM_VERSION", "")}"')

    # Now add override functions for packages that need custom logic.
    # These override functions are defined BEFORE sourcing the template,
    # so the template's dispatch will call them.
    if install_logic == "shared_library":
        # proxmox-backup-qemu: install .so + header
        lines.append("")
        lines.append("# Override: install shared library + header")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root/usr/lib" "$STAGE/root/usr/include" "$STAGE/meta"')
        lines.append('')
        lines.append(f'    cp target/release/libproxmox_backup_qemu.so "$STAGE/root/usr/lib/libproxmox_backup_qemu.so.0"')
        lines.append('    ln -sf libproxmox_backup_qemu.so.0 "$STAGE/root/usr/lib/libproxmox_backup_qemu.so"')
        lines.append('    cp proxmox-backup-qemu.h "$STAGE/root/usr/lib/"')
        lines.append("}")

    elif install_logic == "workspace":
        # proxmox-rs: workspace monorepo install
        lines.append("")
        lines.append("# Override: install workspace crates")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root/usr/lib" "$STAGE/meta"')
        lines.append('')
        lines.append("    # Install the built Rust libraries (.rlib/.so) to staging")
        lines.append('    cargo install --path . --root "$STAGE/root/usr" --locked || true')
        lines.append('')
        lines.append('    if [[ -d "$WORKDIR/target/release" ]]; then')
        lines.append('        mkdir -p "$STAGE/root/usr/lib/proxmox-rs"')
        lines.append('        find "$WORKDIR/target/release" -maxdepth 1 -name \'libproxmox*.rlib\' -exec cp {} "$STAGE/root/usr/lib/proxmox-rs/" \\; 2>/dev/null || true')
        lines.append('        find "$WORKDIR/target/release" -maxdepth 1 -name \'libproxmox*.so\' -exec cp {} "$STAGE/root/usr/lib/" \\; 2>/dev/null || true')
        lines.append('    fi')
        lines.append("}")

    elif install_logic == "perlmod":
        # perlmod: install binary + .so + genpackage.pl
        lines.append("")
        lines.append("# Override: build + install perlmod binaries and library")
        lines.append("build_override() {")
        lines.append('    rm -f .cargo/config.toml 2>/dev/null || true')
        lines.append('    if [[ -f "perlmod-bin/genpackage.pl" ]]; then')
        lines.append('        patchShebangs perlmod-bin/genpackage.pl 2>/dev/null || true')
        lines.append('    fi')
        lines.append('    export LIBCLANG_PATH="${LIBCLANG_PATH:-/usr/lib64/clang}"')
        lines.append(f'    cargo build --release -p {extra_vars.get("CARGO_PKG", "")} 2>/dev/null || cargo build --release 2>/dev/null || true')
        lines.append("}")
        lines.append("")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root/usr/bin" "$STAGE/root/usr/lib/perlmod" "$STAGE/meta"')
        lines.append('')
        lines.append('    if [[ -f "target/release/perlmod" ]]; then')
        lines.append('        cp target/release/perlmod "$STAGE/root/usr/bin/"')
        lines.append('    fi')
        lines.append('    if [[ -f "target/release/perlmod-bin" ]]; then')
        lines.append('        cp target/release/perlmod-bin "$STAGE/root/usr/bin/"')
        lines.append('    fi')
        lines.append('')
        lines.append('    if [[ -f "perlmod-bin/genpackage.pl" ]]; then')
        lines.append('        cp perlmod-bin/genpackage.pl "$STAGE/root/usr/lib/perlmod/"')
        lines.append('    fi')
        lines.append('')
        lines.append('    if [[ -f "target/release/libperlmod.so" ]]; then')
        lines.append('        cp target/release/libperlmod.so "$STAGE/root/usr/lib/"')
        lines.append('    fi')
        lines.append("}")

    elif install_logic == "termproxy":
        # termproxy: build in subdir, rename binary
        lines.append("")
        lines.append("# Override: build termproxy binary from pve-xtermjs subdirectory")
        lines.append("build_override() {")
        lines.append('    rm -f .cargo/config.toml 2>/dev/null || true')
        lines.append('    rm -f ../.cargo/config.toml 2>/dev/null || true')
        lines.append('    export LIBCLANG_PATH="${LIBCLANG_PATH:-/usr/lib64/clang}"')
        lines.append('    cargo build --release 2>/dev/null || cargo build --release --manifest-path "$WORKDIR/termproxy/Cargo.toml" 2>/dev/null || true')
        lines.append("}")
        lines.append("")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root/usr/bin" "$STAGE/meta"')
        lines.append('')
        lines.append('    # Nix postInstall renames proxmox-termproxy -> termproxy')
        lines.append('    if [[ -f "target/release/proxmox-termproxy" ]]; then')
        lines.append('        cp target/release/proxmox-termproxy "$STAGE/root/usr/bin/termproxy"')
        lines.append('    elif [[ -f "target/release/termproxy" ]]; then')
        lines.append('        cp target/release/termproxy "$STAGE/root/usr/bin/termproxy"')
        lines.append('    elif [[ -f "$WORKDIR/target/release/proxmox-termproxy" ]]; then')
        lines.append('        cp "$WORKDIR/target/release/proxmox-termproxy" "$STAGE/root/usr/bin/termproxy"')
        lines.append('    elif [[ -f "$WORKDIR/target/release/termproxy" ]]; then')
        lines.append('        cp "$WORKDIR/target/release/termproxy" "$STAGE/root/usr/bin/termproxy"')
        lines.append('    fi')
        lines.append("}")

    elif install_logic == "perl-rs":
        # proxmox-perl-rs: hybrid Rust+Perl build
        lines.append("")
        lines.append("# Override: patch Makefiles for AlmaLinux")
        lines.append("pre_build_hook() {")
        lines.append('    for mkfile in common/pkg/Makefile pve-rs/Makefile; do')
        lines.append('        if [[ -f "$WORKDIR/$mkfile" ]]; then')
        lines.append('            sed -i "$WORKDIR/$mkfile" \\')
        lines.append("                -e '/GITVERSION/d' \\")
        lines.append("                -e '/dpkg-architecture/d' \\")
        lines.append("                -e '/pkg-info/d' \\")
        lines.append("                -e '/MConfig/d'")
        lines.append('        fi')
        lines.append('    done')
        lines.append("}")
        lines.append("")
        lines.append("# Override: build Rust + Perl wrapper")
        lines.append("build_override() {")
        lines.append('    cd "$WORKDIR/pve-rs"')
        lines.append('')
        lines.append("    # Build the Rust library")
        lines.append("    cargo build --release")
        lines.append('')
        lines.append("    # Build the Perl module wrapper")
        lines.append('    make BUILDIR="/tmp/src/${PKG_NAME}" BUILD_MODE=release GITVERSION="${SHORT:-git}" || true')
        lines.append("}")
        lines.append("")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root" "$STAGE/meta"')
        lines.append('')
        lines.append("    # Install Perl modules and .so from pve-rs")
        lines.append('    make install DESTDIR="$STAGE/root" \\')
        lines.append('        BUILDIR="/tmp/src/${PKG_NAME}" \\')
        lines.append('        BUILD_MODE=release \\')
        lines.append('        PERL_INSTALLVENDORARCH="/usr/lib64/perl5/vendor_perl" \\')
        lines.append('        PERL_INSTALLVENDORLIB="/usr/share/perl5/vendor_perl" || true')
        lines.append('')
        lines.append("    # Install common/pkg Perl modules")
        lines.append('    cd "$WORKDIR/common/pkg"')
        lines.append('    make install PERL_INSTALLVENDORLIB="$STAGE/root/usr/share/perl5/vendor_perl" || true')
        lines.append('    cd "$WORKDIR"')
        lines.append('')
        lines.append('    find "$STAGE/root" -name \'.packlist\' -delete 2>/dev/null || true')
        lines.append('    find "$STAGE/root" -name \'perllocal.pod\' -delete 2>/dev/null || true')
        lines.append("}")

    elif install_logic == "widget-toolkit":
        # proxmox-widget-toolkit: make + make install with APIViewer
        lines.append("")
        lines.append("# Override: patch defines.mk and Makefile, then make")
        lines.append("pre_build_hook() {")
        lines.append('    if [[ -f "defines.mk" ]]; then')
        lines.append('        sed -i "defines.mk" -e "/BUILD_VERSION=/d"')
        lines.append('    fi')
        lines.append('    if [[ -f "Makefile" ]]; then')
        lines.append('        sed -i "Makefile" \\')
        lines.append("            -e '/BUILD_VERSION=/d' \\")
        lines.append("            -e '/BIOME/d'")
        lines.append('    fi')
        lines.append("}")
        lines.append("")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root" "$STAGE/meta"')
        lines.append('')
        lines.append('    make install DESTDIR="$STAGE/root" || true')
        lines.append('')
        lines.append('    # Copy APIViewer.js (per Nix postInstall)')
        lines.append('    if [[ -f "$WORKDIR/src/api-viewer/APIViewer.js" ]]; then')
        lines.append('        mkdir -p "$STAGE/root/usr/share/javascript/proxmox-widget-toolkit"')
        lines.append('        cp "$WORKDIR/src/api-viewer/APIViewer.js" "$STAGE/root/usr/share/javascript/proxmox-widget-toolkit/"')
        lines.append('    fi')
        lines.append("}")

    elif install_logic == "extjs":
        # extjs: static JS/CSS assets, copy to /usr/share/javascript/extjs/
        lines.append("")
        lines.append("# Override: install ExtJS static assets")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root/usr/share/javascript/extjs" "$STAGE/meta"')
        lines.append('')
        lines.append("    # Copy ExtJS assets per Nix postInstall")
        lines.append('    if [[ -d "$WORKDIR/extjs/build" ]]; then')
        lines.append('        BUILD_DIR="$WORKDIR/extjs/build"')
        lines.append('    elif [[ -d "$WORKDIR/build" ]]; then')
        lines.append('        BUILD_DIR="$WORKDIR/build"')
        lines.append('    else')
        lines.append('        BUILD_DIR="$WORKDIR"')
        lines.append('    fi')
        lines.append('')
        lines.append('    for f in ext-all-debug.js ext-all.js; do')
        lines.append('        if [[ -f "$BUILD_DIR/$f" ]]; then')
        lines.append('            cp "$BUILD_DIR/$f" "$STAGE/root/usr/share/javascript/extjs/"')
        lines.append('        fi')
        lines.append('    done')
        lines.append('')
        lines.append('    if [[ -d "$BUILD_DIR/classic/locale" ]]; then')
        lines.append('        cp -r "$BUILD_DIR/classic/locale" "$STAGE/root/usr/share/javascript/extjs/"')
        lines.append('    fi')
        lines.append('')
        lines.append('    if [[ -d "$BUILD_DIR/classic/theme-crisp" ]]; then')
        lines.append('        cp -r "$BUILD_DIR/classic/theme-crisp" "$STAGE/root/usr/share/javascript/extjs/"')
        lines.append('    fi')
        lines.append('')
        lines.append('    if [[ -f "$BUILD_DIR/packages/charts/classic/charts-debug.js" ]]; then')
        lines.append('        cp "$BUILD_DIR/packages/charts/classic/charts-debug.js" "$STAGE/root/usr/share/javascript/extjs/"')
        lines.append('    fi')
        lines.append('    if [[ -f "$BUILD_DIR/packages/charts/classic/charts.js" ]]; then')
        lines.append('        cp "$BUILD_DIR/packages/charts/classic/charts.js" "$STAGE/root/usr/share/javascript/extjs/"')
        lines.append('    fi')
        lines.append('    if [[ -d "$BUILD_DIR/packages/charts/classic/crisp" ]]; then')
        lines.append('        cp -r "$BUILD_DIR/packages/charts/classic/crisp" "$STAGE/root/usr/share/javascript/extjs/"')
        lines.append('    fi')
        lines.append("}")

    elif install_logic == "qrcodejs":
        # qrcodejs: uglify-js minification
        lines.append("")
        lines.append("# Override: build with uglify-js")
        lines.append("build_override() {")
        lines.append('    if command -v uglifyjs &>/dev/null; then')
        lines.append('        if [[ -f "qrcode.js" ]]; then')
        lines.append('            uglifyjs qrcode.js -o qrcode.min.js || true')
        lines.append('        fi')
        lines.append('    fi')
        lines.append("}")
        lines.append("")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root/usr/share/javascript/qrcodejs" "$STAGE/meta"')
        lines.append('')
        lines.append('    if [[ -f "qrcode.min.js" ]]; then')
        lines.append('        cp qrcode.min.js "$STAGE/root/usr/share/javascript/qrcodejs/"')
        lines.append('    elif [[ -f "qrcode.js" ]]; then')
        lines.append('        cp qrcode.js "$STAGE/root/usr/share/javascript/qrcodejs/"')
        lines.append('    fi')
        lines.append("}")

    elif install_logic == "markedjs":
        # markedjs: download pre-built JS, install to /usr/share/javascript/markedjs/
        lines.append("")
        lines.append("# Override: download pre-built marked.min.js")
        lines.append("fetch_source_download() {")
        lines.append('    echo "=== [$PKG_NAME] Downloading marked.js ==="')
        lines.append('    WORKDIR="/tmp/src/${PKG_NAME}"')
        lines.append('    rm -rf "$WORKDIR"')
        lines.append('    mkdir -p "$WORKDIR"')
        lines.append('    if ! curl -L -o "$WORKDIR/marked.min.js" "$MARKED_URL"; then')
        lines.append('        echo "=== [$PKG_NAME] GitHub release failed, trying npm ==="')
        lines.append('        if ! curl -L -o "$WORKDIR/marked.min.js" "$MARKED_FALLBACK_URL"; then')
        lines.append('            echo "ERROR: Failed to download marked.js"')
        lines.append('            exit 1')
        lines.append('        fi')
        lines.append('    fi')
        lines.append("}")
        lines.append("")
        lines.append("# Override: install marked.js to staging")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root/usr/share/javascript/markedjs" "$STAGE/meta"')
        lines.append('')
        lines.append('    cp "$WORKDIR/marked.min.js" "$STAGE/root/usr/share/javascript/markedjs/marked.js"')
        lines.append("}")
        # For hash-only packages, override version detection
        lines.append("")
        lines.append("# Override: version from download URL")
        lines.append("detect_version() { echo \"${MARKED_VERSION}+${SHORT:-git}\"; }")

    elif install_logic == "unifont-hex":
        # unifont-hex: download tarball, make hex, install hex font
        lines.append("")
        lines.append("# Override: download and extract unifont tarball")
        lines.append("fetch_source_download() {")
        lines.append('    echo "=== [$PKG_NAME] Downloading source from GNU ==="')
        lines.append('    WORKDIR="/tmp/src/${PKG_NAME}"')
        lines.append('    rm -rf "$WORKDIR"')
        lines.append('    mkdir -p "$WORKDIR"')
        lines.append('    curl -L -o "/tmp/${PKG_NAME}.tar.gz" "$UNIFONT_URL"')
        lines.append('    tar xzf "/tmp/${PKG_NAME}.tar.gz" -C "/tmp/src"')
        lines.append('    mv "/tmp/src/unifont-${UNIFONT_VERSION}" "$WORKDIR" 2>/dev/null || true')
        lines.append('    cd "$WORKDIR"')
        lines.append("}")
        lines.append("")
        lines.append("# Override: build hex font data")
        lines.append("build_override() {")
        lines.append('    make -j"$(nproc)" hex || true')
        lines.append("}")
        lines.append("")
        lines.append("# Override: install hex font data")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root/usr/share/unifont" "$STAGE/meta"')
        lines.append('')
        lines.append('    if [[ -f "unifont.hex" ]]; then')
        lines.append('        cp unifont.hex "$STAGE/root/usr/share/unifont/"')
        lines.append('    elif [[ -f "font/plane00/unifont.hex" ]]; then')
        lines.append('        cp font/plane00/unifont.hex "$STAGE/root/usr/share/unifont/"')
        lines.append('    fi')
        lines.append('')
        lines.append('    if [[ -f "wchardata.c" ]]; then')
        lines.append('        cp wchardata.c "$STAGE/root/usr/share/unifont/"')
        lines.append('    fi')
        lines.append("}")
        lines.append("")
        lines.append("# Override: version from download URL")
        lines.append("detect_version() { echo \"${UNIFONT_VERSION}+${SHORT:-git}\"; }")

    elif install_logic == "cstream":
        # cstream: download tarball, autotools build
        lines.append("")
        lines.append("# Override: version from download URL")
        lines.append("detect_version() { echo \"${CSTREAM_VERSION}+${SHORT:-git}\"; }")

    elif install_logic == "access-control":
        # pve-access-control: Perl git with Makefile patching
        lines.append("")
        lines.append("# Override: patch Makefile for AlmaLinux")
        lines.append("pre_build_hook() {")
        lines.append('    if [[ -f "Makefile" ]]; then')
        lines.append('        sed -i "Makefile" \\')
        lines.append('            -e "s/pveum.1 oathkeygen pveum.bash-completion pveum.zsh-completion/oathkeygen/" \\')
        lines.append('            -e "/pveum.1/,+2d"')
        lines.append('    fi')
        lines.append("}")
        lines.append("")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root" "$STAGE/meta"')
        lines.append('')
        lines.append('    make install DESTDIR="$STAGE/root" PREFIX=/usr SBINDIR=/usr/sbin BINDIR=/usr/bin \\')
        lines.append('        PERLDIR=/usr/share/perl5/vendor_perl || true')
        lines.append('')
        lines.append('    find "$STAGE/root" -name \'.packlist\' -delete 2>/dev/null || true')
        lines.append('    find "$STAGE/root" -name \'perllocal.pod\' -delete 2>/dev/null || true')
        lines.append("}")

    elif install_logic == "apiclient":
        # pve-apiclient: simple Perl git, make install
        lines.append("")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root" "$STAGE/meta"')
        lines.append('')
        lines.append('    make install DESTDIR="$STAGE/root" \\')
        lines.append('        PERL5DIR=/usr/share/perl5/vendor_perl \\')
        lines.append('        DOCDIR=/usr/share/doc || true')
        lines.append('')
        lines.append('    find "$STAGE/root" -name \'.packlist\' -delete 2>/dev/null || true')
        lines.append('    find "$STAGE/root" -name \'perllocal.pod\' -delete 2>/dev/null || true')
        lines.append("}")

    elif install_logic == "i18n":
        # proxmox-i18n: patch Makefile, make, make install
        lines.append("")
        lines.append("# Override: patch Makefile — strip Debian-specific targets")
        lines.append("pre_build_hook() {")
        lines.append('    if [[ -f "$WORKDIR/Makefile" ]]; then')
        lines.append('        sed -i "$WORKDIR/Makefile" \\')
        lines.append("            -e '/include.*dpkg.*pkg-info\\.mk/d' \\")
        lines.append("            -e 's|/usr/share|/usr/share|g'")
        lines.append('    fi')
        lines.append("}")

    elif install_logic == "docs":
        # pve-docs: patch Makefile, asciidoc build, make install
        lines.append("")
        lines.append("# Override: patch build files for AlmaLinux")
        lines.append("pre_build_hook() {")
        lines.append('    if [[ -f "Makefile" ]]; then')
        lines.append('        sed -i "Makefile" \\')
        lines.append("            -e '/GITVERSION/d' \\")
        lines.append("            -e '/pkg-info/d' \\")
        lines.append('            -e "s|/usr/share/javascript/proxmox-widget-toolkit-dev|/usr/share/javascript/proxmox-widget-toolkit|g"')
        lines.append('    fi')
        lines.append('')
        lines.append('    if [[ -f "images/Makefile" ]]; then')
        lines.append('        sed -i "images/Makefile" -e "s|/usr/share/pve-docs|/usr/share/pve-docs|g"')
        lines.append('    fi')
        lines.append('')
        lines.append('    if [[ -f "asciidoc-pve.in" ]]; then')
        lines.append("        sed -i 'asciidoc-pve.in' -e '1s|#!/usr/bin/perl|#!/usr/bin/perl|'")
        lines.append('    fi')
        lines.append("}")

    elif install_logic == "firmware":
        # pve-edk2-firmware: patch Debian build files, EDK2 build
        lines.append("")
        lines.append("# Override: patch build files for AlmaLinux")
        lines.append("pre_build_hook() {")
        lines.append('    if [[ -f "$WORKDIR/Makefile" ]]; then')
        lines.append('        sed -i "$WORKDIR/Makefile" \\')
        lines.append('            -e "s|/usr/share/dpkg|/usr/share/dpkg|g"')
        lines.append('    fi')
        lines.append('    if [[ -f "$WORKDIR/debian/rules" ]]; then')
        lines.append('        sed -i "$WORKDIR/debian/rules" \\')
        lines.append('            -e "s|/usr/share/dpkg|/usr/share/dpkg|g"')
        lines.append('    fi')
        lines.append("}")

    elif install_logic == "font-logos":
        # fonts-font-logos: simple copy of CSS + font assets
        lines.append("")
        lines.append("# Override: install font assets")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root/usr/share/fonts-font-logos/css" "$STAGE/root/usr/share/fonts-font-logos/fonts"')
        lines.append('')
        lines.append('    if [[ -d "$WORKDIR/src/font-logos/assets" ]]; then')
        lines.append('        cp -r "$WORKDIR/src/font-logos/assets" "$STAGE/root/usr/share/fonts-font-logos/fonts/"')
        lines.append('    fi')
        lines.append('    if [[ -f "$WORKDIR/src/font-logos.css" ]]; then')
        lines.append('        cp "$WORKDIR/src/font-logos.css" "$STAGE/root/usr/share/fonts-font-logos/css/"')
        lines.append('    fi')
        lines.append("}")

    elif install_logic == "vncterm":
        # vncterm: C with Makefile patching
        lines.append("")
        lines.append("# Override: patch Makefile for AlmaLinux build")
        lines.append("pre_build_hook() {")
        lines.append('    if [[ -f "Makefile" ]]; then')
        lines.append('        sed -i "Makefile" \\')
        lines.append('            -e "/architecture.mk/d" \\')
        lines.append('            -e "/pkg-info/d" \\')
        lines.append('            -e "s|/usr/share/unifont/unifont.hex|/usr/share/unifont/unifont.hex|g" \\')
        lines.append('            -e "s|usr/||g" \\')
        lines.append('            -e "s/Werror/Wno-error/" \\')
        lines.append('            -e "s|wchardata.c|/usr/share/unifont/wchardata.c|g" \\')
        lines.append('            -e "/pod2man/d" \\')
        lines.append('            -e "/man1/d" 2>/dev/null || true')
        lines.append('    fi')
        lines.append('')
        lines.append('    # Apply TLS auth plugin patches from vncpatches/ if they exist')
        lines.append('    if [[ -d "vncpatches" ]]; then')
        lines.append('        for patch in vncpatches/*.patch; do')
        lines.append('            [[ -f "$patch" ]] && patch -p1 -i "$patch" || true')
        lines.append('        done')
        lines.append('    fi')
        lines.append("}")
        lines.append("")
        lines.append("# Override: build vncterm binary")
        lines.append("build_override() {")
        lines.append('    make -j"$(nproc)" VNCLIB="-lvncserver" VNCDIR="/usr/include" DESTDIR="/tmp/pkg/${PKG_NAME}/root" || true')
        lines.append("}")
        lines.append("")
        lines.append("# Override: install vncterm binary")
        lines.append("install_override() {")
        lines.append('    mkdir -p "$STAGE/root/usr/bin" "$STAGE/meta"')
        lines.append('')
        lines.append('    make install DESTDIR="$STAGE/root" PREFIX=/usr SBINDIR=/usr/bin || true')
        lines.append('')
        lines.append('    # Ensure binary is installed')
        lines.append('    if [[ -f "vncterm" ]] && [[ ! -f "$STAGE/root/usr/bin/vncterm" ]]; then')
        lines.append('        install -Dm755 vncterm "$STAGE/root/usr/bin/vncterm"')
        lines.append('    fi')
        lines.append('')
        lines.append('    # Patch /usr reference in binary')
        lines.append('    if [[ -f "$STAGE/root/usr/bin/vncterm" ]]; then')
        lines.append('        sed -i "$STAGE/root/usr/bin/vncterm" -e "s|/usr|$STAGE/root/usr|g" 2>/dev/null || true')
        lines.append('    fi')
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

    layer1 = [p for p in data["packages"] if p.get("layer") == 1]

    print("=== generate-layer1-builds.py ===")
    print(f"Parsing packages.yml... Found {len(layer1)} Layer 1 packages")

    generated = 0
    for pkg in layer1:
        pkg_id = pkg["id"]
        meta = PKG_META.get(pkg_id)
        if meta is None:
            print(f"  [SKIP] {pkg_id}: no metadata in PKG_META, skipping")
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
        line_count = len(content.splitlines())
        print(f"  [OK] {target_file} ({build_type}, {line_count} lines)")
        generated += 1

    print()
    print("=== Summary ===")
    print(f"  Build.sh files generated: {generated}")

    # Print table of packages and build types
    print()
    print("=== Package Build Type Mapping ===")
    for pkg in layer1:
        pkg_id = pkg["id"]
        meta = PKG_META.get(pkg_id, {})
        build_type = meta.get("build_type", "UNKNOWN")
        depends_on = pkg.get("depends_on", [])
        deps_str = f" (depends_on: {', '.join(depends_on)})" if depends_on else ""
        print(f"  {pkg_id:30s} → {build_type}{deps_str}")

    print("=== Done ===")


if __name__ == "__main__":
    main()