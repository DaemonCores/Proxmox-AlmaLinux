#!/bin/bash
# Package: perlmod
# Layer: 1
# Type: rust-submodules

PKG_NAME="perlmod"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

REPO_URL="$(get_pkg_meta "$PKG_NAME" repo)"
BUILD_TYPE="rust-submodules"
CLONE_RECURSIVE="1"
PKG_DESCRIPTION="PerlMod — Alternative to Perl XS for Rust bindings"
PKG_DEPENDS=$'libxcrypt
perl'
CARGO_PKG="perlmod-bin"

# Override: build + install perlmod binaries and library
build_override() {
    rm -f .cargo/config.toml 2>/dev/null || true
    if [[ -f "perlmod-bin/genpackage.pl" ]]; then
        patchShebangs perlmod-bin/genpackage.pl 2>/dev/null || true
    fi
    export LIBCLANG_PATH="${LIBCLANG_PATH:-/usr/lib64/clang}"
    cargo build --release -p perlmod-bin 2>/dev/null || cargo build --release 2>/dev/null || true
}

install_override() {
    mkdir -p "$STAGE/root/usr/bin" "$STAGE/root/usr/lib/perlmod" "$STAGE/meta"

    if [[ -f "target/release/perlmod" ]]; then
        cp target/release/perlmod "$STAGE/root/usr/bin/"
    fi
    if [[ -f "target/release/perlmod-bin" ]]; then
        cp target/release/perlmod-bin "$STAGE/root/usr/bin/"
    fi

    if [[ -f "perlmod-bin/genpackage.pl" ]]; then
        cp perlmod-bin/genpackage.pl "$STAGE/root/usr/lib/perlmod/"
    fi

    if [[ -f "target/release/libperlmod.so" ]]; then
        cp target/release/libperlmod.so "$STAGE/root/usr/lib/"
    fi
}


full_build
