#!/bin/bash
# Package: cstream
# Layer: 1
# Type: c-hash

PKG_NAME="cstream"
BUILD_TYPE="c-hash"
PKG_DESCRIPTION="cstream — General-purpose stream handling tool like dd"
CSTREAM_VERSION="4.0.0"
CSTREAM_URL="https://www.cons.org/cracauer/download/cstream-4.0.0.tar.gz"
DOWNLOAD_URL="https://www.cons.org/cracauer/download/cstream-4.0.0.tar.gz"
DOWNLOAD_VERSION="4.0.0"
DOWNLOAD_EXTRACT_DIR="cstream-4.0.0"

# Override: version from download URL
detect_version() { echo "${CSTREAM_VERSION}+${SHORT:-git}"; }

source ../../scripts/build-template.sh

full_build
