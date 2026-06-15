#!/bin/bash
# build.sh — perl-mimebase32 (Layer 0: CPAN Perl module, no PVE deps)
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

PKG_NAME="perl-mimebase32"
REPO_URL="https://www.cpan.org/authors/id/R/RE/REHSACK/MIME-Base32-1.303.tar.gz"
CPAN_VERSION="1.303"
PKG_DESCRIPTION="MIME::Base32 - Base32 encoding/decoding for Perl"

source ../../scripts/build-template.sh

# Dependencies — AlmaLinux RPM names
PKG_DEPENDS=$'perl'

setup_env
fetch_source
build_perl
install_perl
package_rpm
cleanup
