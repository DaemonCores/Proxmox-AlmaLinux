#!/bin/bash
# build.sh — perl-proxmox-acme (Layer 0: Perl git module, no PVE deps)
#
# Build pipeline:
#   1. setup_env      — Export WORKDIR, PKG_NAME, VERSION, RELEASE; detect build type
#   2. fetch_source   — Git clone from git.proxmox.com
#   3. build_perl     — Makefile.PL / Build.PL build
#   4. install_perl   — Install to staging root
#   5. package_rpm    — Create .pkg.tar intermediate
#   6. cleanup        — Remove temporary files
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="perl-proxmox-acme"
REPO_URL="$(get_pkg_meta "$PKG_NAME" repo)"
PKG_DESCRIPTION="Proxmox ACME client Perl module"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

# Dependencies — AlmaLinux RPM names
PKG_DEPENDS=$'perl\nopenssl-libs'

setup_env
fetch_source
build_perl
install_perl
package_rpm
cleanup
