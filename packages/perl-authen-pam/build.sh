#!/bin/bash
# build.sh — perl-authen-pam (Layer 0: CPAN Perl module, no PVE deps)
#
# Build pipeline:
#   1. setup_env      — Export WORKDIR, PKG_NAME, VERSION, RELEASE; detect build type
#   2. fetch_source   — Download CPAN tarball and extract
#   3. build_perl     — Makefile.PL / Build.PL build
#   4. install_perl   — Install to staging root
#   5. package_rpm    — Create .pkg.tar intermediate
#   6. cleanup        — Remove temporary files
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail

PKG_NAME="perl-authen-pam"
REPO_URL="https://www.cpan.org/authors/id/N/NI/NIKIP/Authen-PAM-0.16.tar.gz"
CPAN_VERSION="0.16"
PKG_DESCRIPTION="PAM authentication interface for Perl"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-template.sh"

# Dependencies — AlmaLinux RPM names
PKG_DEPENDS=$'perl\npam'

setup_env
fetch_source
build_perl
install_perl
package_rpm
cleanup
