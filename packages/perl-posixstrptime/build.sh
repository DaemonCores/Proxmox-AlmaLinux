#!/bin/bash
# build.sh — perl-posixstrptime (Layer 0: CPAN Perl module, no PVE deps)
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

PKG_NAME="perl-posixstrptime"
REPO_URL="https://www.cpan.org/authors/id/G/GO/GOZER/POSIX-strptime-0.13.tar.gz"
CPAN_VERSION="0.13"
PKG_DESCRIPTION="POSIX::strptime - strptime for Perl"

source ../../scripts/build-template.sh

# Dependencies — AlmaLinux RPM names
PKG_DEPENDS=$'perl'

setup_env
fetch_source
build_perl
install_perl
package_rpm
cleanup
