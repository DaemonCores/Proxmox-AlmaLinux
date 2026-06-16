#!/bin/bash
# build-template.sh — Master template for Proxmox AlmaLinux package builds
#
# Sourced by each package's build.sh via:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/../../scripts/build-template.sh"
#
# Provides common functions for the 6-step build pipeline:
#   1. setup_env     — Export WORKDIR, PKG_NAME, VERSION, RELEASE; detect build type
#   2. fetch_source  — Download tarball (cpan) or git clone (git repo)
#   3. build_perl     — Perl Makefile.PL / Build.PL build
#   4. build_rust     — Cargo build --release
#   5. build_c        — ./configure or cmake build
#   6. build_node     — npm ci && npm run build
#   7. build_python   — pip install . or python setup.py install
#   8. apply_debian_patches — Apply patches from debian/patches/series
#   9. package_rpm   — Create .pkg.tar intermediate for RPM conversion
#  10. cleanup        — Remove temporary files except RPMs
#
# Environment variables (injected by build-chain.yml):
#   VERSION          — Full git commit hash
#   COMMIT           — Same as VERSION
#   SHORT            — Short hash (7 chars)
#   TARGET_ID        — "proxmox-almalinux"
#   TARGET_ARCH      — "x86_64" (default)
#   TARGET_CFLAGS    — (empty for AlmaLinux)
#   TARGET_CXXFLAGS  — (empty for AlmaLinux)
#   SOURCE_DISTRO    — "almalinux-10"
#
# Configurable variables (override in each build.sh BEFORE sourcing):
#   PKG_NAME         — Package identifier (must match packages/<id>)
#   REPO_URL         — Git repository URL or CPAN tarball URL
#   PKG_DESCRIPTION  — One-line description for RPM metadata
#   PKG_MAINTAINER   — Maintainer string (default: "Proxmox AlmaLinux <guillou.gabriel@gmail.com>")
#   PKG_DEPENDS      — Newline-separated dependency list for meta/depends
#   BUILD_SUBDIR     — Subdirectory within repo for monorepo packages
#   EXTRA_CONFIGURE  — Extra flags passed to ./configure or cmake
#   CARGO_BIN        — Specific binary to install from cargo workspace
#   CPAN_VERSION     — Override version for CPAN-sourced packages
#   NODE_BUILD_DIR   — Subdirectory for Node.js monorepo packages
#
# All functions exit with explicit error codes on failure.
# Logs are redirected to $WORKDIR/build.log when WORKDIR is set.
# ============================================================================

set -euo pipefail

# ============================================================================
# 0. get_pkg_meta — Read package metadata from packages.yml (single source of truth)
# ============================================================================
# Uses python3+PyYAML (or yq as fallback) to extract fields from packages.yml.
# The YAML file is THE source of truth — build.sh files should NOT hardcode
# URLs that are already in packages.yml.
#
# Usage in build.sh:
#   REPO_URL="$(get_pkg_meta "$PKG_NAME" repo)"
#   CPAN_VERSION="$(get_pkg_meta "$PKG_NAME" repo | sed 's/.*-\([0-9.]*\)\.tar\.gz/\1/')"
#   BUILD_TYPE="$(get_pkg_meta "$PKG_NAME" build_type)"
#
# Available fields: id, repo, version_source, build_time, artifact_type, layer,
#   depends_on, tracker_file, branch
get_pkg_meta() {
    local pkg_id="$1"
    local field="$2"
    local yaml_path="${BUILD_YAML_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]:-${0}}")" && pwd)/../packages.yml}"

    # Try yq first (fastest, no python dependency)
    if command -v yq &>/dev/null; then
        yq -r ".packages[] | select(.id == \"$pkg_id\") | .$field" "$yaml_path" 2>/dev/null
        return
    fi

    # Fallback to python3+PyYAML
    if command -v python3 &>/dev/null; then
        python3 -c "
import yaml, sys
with open('$yaml_path') as f:
    data = yaml.safe_load(f)
for pkg in data.get('packages', []):
    if pkg.get('id') == '$pkg_id':
        val = pkg.get('$field', '')
        if isinstance(val, list):
            print('\\n'.join(str(v) for v in val))
        else:
            print(val)
        sys.exit(0)
sys.exit(1)
" 2>/dev/null
        return
    fi

    echo "ERROR: get_pkg_meta requires yq or python3 with PyYAML" >&2
    return 1
}

# Derive CPAN_VERSION from the repo URL in packages.yml.
# Extracts the version number from CPAN tarball URLs like:
#   https://cpan.metacpan.org/authors/id/.../Module-1.23.tar.gz → "1.23"
#   https://www.cpan.org/authors/id/.../Module-1.23.tar.gz     → "1.23"
# For non-CPAN URLs, returns empty string.
get_cpan_version() {
    local pkg_id="$1"
    local repo_url
    repo_url="$(get_pkg_meta "$pkg_id" repo)"
    if [[ "$repo_url" =~ cpan\.org ]]; then
        local tarball
        tarball="$(basename "$repo_url")"
        # Module-Version.tar.gz → extract Version
        local base="${tarball%.tar.gz}"
        base="${base%.tgz}"
        # Extract version: everything after the last hyphen that starts with a digit
        echo "$base" | sed 's/.*-\([0-9][0-9.]*\)$/\1/'
    fi
}

# ============================================================================
# 1. setup_env — Export environment, create WORKDIR, detect build type
# ============================================================================
# Sets:
#   WORKDIR    — /tmp/src/$PKG_NAME
#   STAGE      — /tmp/pkg/$PKG_NAME
#   BUILD_TYPE — one of: perl, rust, c, node, python, patch, static
#   RELEASE    — derived from SHORT or "1"
#
# Build type detection heuristic (in priority order):
#   - If REPO_URL contains "cpan.org"           → perl (CPAN module)
#   - If Cargo.toml exists in source tree        → rust
#   - If CMakeLists.txt exists in source tree     → c (cmake variant)
#   - If configure/Makefile.PL/Build.PL exists   → c or perl
#   - If package.json exists                     → node
#   - If setup.py/pyproject.toml exists          → python
#   - If debian/patches/series exists            → patch (patches applied, no build)
#   - Otherwise                                  → static (asset copy)
setup_env() {
    # Validate mandatory variables
    if [[ -z "${PKG_NAME:-}" ]]; then
        echo "ERROR: PKG_NAME must be set before sourcing build-template.sh" >&2
        exit 1
    fi

    # Export standard directories
    export WORKDIR="/tmp/src/${PKG_NAME}"
    export STAGE="/tmp/pkg/${PKG_NAME}"
    export RELEASE="${SHORT:-1}"

    # Auto-derive CPAN_VERSION from packages.yml if not set explicitly
    if [[ -z "${CPAN_VERSION:-}" && -n "${REPO_URL:-}" && "${REPO_URL}" =~ cpan\.org ]]; then
        local _tarball
        _tarball="$(basename "$REPO_URL")"
        local _base="${_tarball%.tar.gz}"
        _base="${_base%.tgz}"
        CPAN_VERSION="$(echo "$_base" | sed 's/.*-\([0-9][0-9.]*\)$/\1/')"
        echo "=== [$PKG_NAME] Auto-derived CPAN_VERSION=$CPAN_VERSION from URL ==="
    fi

    # Set defaults for optional variables
    PKG_DESCRIPTION="${PKG_DESCRIPTION:-${PKG_NAME} — Proxmox VE package for AlmaLinux}"
    PKG_MAINTAINER="${PKG_MAINTAINER:-Proxmox AlmaLinux <guillou.gabriel@gmail.com>}"
    EXTRA_CONFIGURE="${EXTRA_CONFIGURE:-}"
    BUILD_SUBDIR="${BUILD_SUBDIR:-}"
    CARGO_BIN="${CARGO_BIN:-}"
    CPAN_VERSION="${CPAN_VERSION:-}"
    NODE_BUILD_DIR="${NODE_BUILD_DIR:-}"
    CLONE_RECURSIVE="${CLONE_RECURSIVE:-}"
    DOWNLOAD_URL="${DOWNLOAD_URL:-}"
    DOWNLOAD_VERSION="${DOWNLOAD_VERSION:-}"
    DOWNLOAD_EXTRACT_DIR="${DOWNLOAD_EXTRACT_DIR:-}"
    PKG_DEPENDS="${PKG_DEPENDS:-}"

    # Clean and create directories
    rm -rf "$WORKDIR" "$STAGE"
    mkdir -p "$WORKDIR" "$STAGE/root" "$STAGE/meta"

    # Set up log redirection
    exec > >(tee -a "$WORKDIR/build.log") 2>&1

    # Detect build type — only if not already set explicitly by the stub
    if [[ -z "${BUILD_TYPE:-}" ]]; then
        if [[ -n "${REPO_URL:-}" && "${REPO_URL}" =~ cpan\.org ]]; then
            BUILD_TYPE="perl"
            echo "=== [$PKG_NAME] Detected build type: perl (CPAN source) ==="
        else
            # Will be refined after fetch_source when source tree is available
            BUILD_TYPE="auto"
            echo "=== [$PKG_NAME] Build type: auto-detect (will refine after source fetch) ==="
        fi
    else
        echo "=== [$PKG_NAME] Build type: $BUILD_TYPE (explicit) ==="
    fi

    echo "=== [$PKG_NAME] Environment setup complete ==="
    echo "  WORKDIR   = $WORKDIR"
    echo "  STAGE     = $STAGE"
    echo "  RELEASE   = $RELEASE"
    echo "  BUILD_TYPE= ${BUILD_TYPE}"
}

# Refine BUILD_TYPE after source is available (called by fetch_source or manually)
# Priority: Cargo.toml > CMakeLists.txt > Makefile.PL/Build.PL > configure/Makefile >
#           package.json > setup.py/pyproject.toml > debian/patches (patch-only) > static
refine_build_type() {
    local src_dir="${1:-$WORKDIR}"
    if [[ -n "$BUILD_SUBDIR" ]]; then
        src_dir="$src_dir/$BUILD_SUBDIR"
    fi

    if [[ -f "$src_dir/Cargo.toml" ]]; then
        BUILD_TYPE="rust"
    elif [[ -f "$src_dir/CMakeLists.txt" ]]; then
        BUILD_TYPE="c"
    elif [[ -f "$src_dir/Makefile.PL" || -f "$src_dir/Build.PL" ]]; then
        BUILD_TYPE="perl"
    elif [[ -f "$src_dir/configure" || -f "$src_dir/Makefile" ]]; then
        BUILD_TYPE="c"
    elif [[ -f "$src_dir/package.json" ]]; then
        BUILD_TYPE="node"
    elif [[ -f "$src_dir/setup.py" || -f "$src_dir/pyproject.toml" ]]; then
        BUILD_TYPE="python"
    elif [[ -f "$src_dir/debian/patches/series" ]]; then
        BUILD_TYPE="patch"
    else
        BUILD_TYPE="static"
    fi
    echo "=== [$PKG_NAME] Refined build type: $BUILD_TYPE ==="
}

# ============================================================================
# 2. fetch_source — Download tarball (CPAN) or git clone (git repo)
# ============================================================================
# Uses REPO_URL to determine source acquisition method:
#   - cpan.org URLs → curl download + tar extraction
#   - git:// or https://git.* URLs → git clone with depth=1 + submodules
#   - Other URLs (tarballs) → curl download + tar extraction
#
# For CPAN: derives directory name from the tarball filename
# For git: checks out VERSION or SHORT if set
# For tarballs: extracts and uses the top-level directory
fetch_source() {
    echo "=== [$PKG_NAME] Fetching source ==="

    if [[ -z "${REPO_URL:-}" ]]; then
        echo "ERROR: REPO_URL must be set for fetch_source" >&2
        exit 1
    fi

    if [[ "${REPO_URL}" =~ cpan\.org ]]; then
        # CPAN tarball download
        echo "  Source type: CPAN tarball"
        local tarball_name
        tarball_name="$(basename "$REPO_URL")"
        curl -L -o "/tmp/${PKG_NAME}.tar.gz" "$REPO_URL"

        # Extract and find the top-level directory
        tar xzf "/tmp/${PKG_NAME}.tar.gz" -C "/tmp/src"

        # CPAN tarballs typically extract to Module-Version/
        # Try to find the extracted directory
        local extracted_dir
        if [[ -n "${CPAN_VERSION:-}" ]]; then
            # Use CPAN_VERSION to find the directory if provided
            extracted_dir=$(find /tmp/src -maxdepth 1 -type d -name "*${CPAN_VERSION}*" | head -1)
        else
            # Take the first directory that was extracted
            extracted_dir=$(find /tmp/src -maxdepth 1 -type d -newer /tmp/${PKG_NAME}.tar.gz | head -1)
        fi

        if [[ -z "$extracted_dir" ]]; then
            # Fallback: try to derive from tarball name
            local base_name="${tarball_name%.tar.gz}"
            base_name="${base_name%.tgz}"
            extracted_dir="/tmp/src/${base_name}"
        fi

        # Move to expected WORKDIR
        if [[ -d "$extracted_dir" && "$extracted_dir" != "$WORKDIR" ]]; then
            rm -rf "$WORKDIR"
            mv "$extracted_dir" "$WORKDIR"
        fi
        cd "$WORKDIR"

    elif [[ "${REPO_URL}" =~ ^git:// || "${REPO_URL}" =~ git\.proxmox\.com ]]; then
        # Git clone from Proxmox or git:// URL
        echo "  Source type: git clone"
        rm -rf "$WORKDIR"
        local clone_flags="--depth=1"
        if [[ "${CLONE_RECURSIVE:-0}" == "1" ]]; then
            clone_flags="$clone_flags --recursive"
        fi
        git clone $clone_flags "$REPO_URL" "$WORKDIR"
        cd "$WORKDIR"

        # Checkout specific version if provided
        if [[ -n "${VERSION:-}" ]]; then
            git checkout "$VERSION" 2>/dev/null \
                || git checkout "${SHORT:-${VERSION:0:7}}" 2>/dev/null \
                || true
        fi

        # Initialize submodules if not already cloned recursively
        if [[ "${CLONE_RECURSIVE:-0}" != "1" ]]; then
            git submodule update --init --recursive 2>/dev/null || true
        fi

    else
        # Generic tarball download (GitHub releases, etc.)
        echo "  Source type: tarball download"
        curl -L -o "/tmp/${PKG_NAME}.tar.gz" "$REPO_URL"
        tar xzf "/tmp/${PKG_NAME}.tar.gz" -C "/tmp/src"

        # Find extracted directory
        local extracted_dir
        extracted_dir=$(find /tmp/src -maxdepth 1 -type d -newer /tmp/${PKG_NAME}.tar.gz | head -1)
        if [[ -z "$extracted_dir" ]]; then
            # Try common naming patterns
            local base_name
            base_name="$(basename "$REPO_URL")"
            base_name="${base_name%.tar.gz}"
            base_name="${base_name%.tgz}"
            base_name="${base_name%.tar.bz2}"
            base_name="${base_name%.tbz2}"
            extracted_dir="/tmp/src/${base_name}"
        fi

        if [[ -d "$extracted_dir" && "$extracted_dir" != "$WORKDIR" ]]; then
            rm -rf "$WORKDIR"
            mv "$extracted_dir" "$WORKDIR"
        fi
        cd "$WORKDIR"
    fi

    # Handle monorepo subdirectory
    if [[ -n "$BUILD_SUBDIR" ]]; then
        echo "  Monorepo subdirectory: $BUILD_SUBDIR"
        cd "$WORKDIR/$BUILD_SUBDIR"
    fi

    # Refine build type now that source is available
    if [[ "$BUILD_TYPE" == "auto" ]]; then
        refine_build_type "$WORKDIR"
    fi

    echo "=== [$PKG_NAME] Source fetched successfully ==="
}

# ============================================================================
# 3. build_perl — Build Perl modules (Makefile.PL or Build.PL)
# ============================================================================
# Handles:
#   - Standard Makefile.PL (ExtUtils::MakeMaker)
#   - Module::Build (Build.PL)
#   - Monorepo packages (BUILD_SUBDIR to cd into)
#   - INSTALLDIRS=vendor for system-wide Perl module installation
#   - Cleanup of .packlist and perllocal.pod
#
# Environment:
#   BUILD_SUBDIR — subdirectory within WORKDIR for monorepo packages
build_perl() {
    echo "=== [$PKG_NAME] Building (Perl) ==="

    local build_dir="$WORKDIR"
    if [[ -n "$BUILD_SUBDIR" ]]; then
        build_dir="$WORKDIR/$BUILD_SUBDIR"
    fi
    cd "$build_dir"

    # Apply Debian patches if present (common for Proxmox Perl packages)
    apply_debian_patches

    if [[ -f "Build.PL" ]]; then
        echo "  Using Module::Build (Build.PL)"
        perl Build.PL --installdirs vendor
        ./Build -j"$(nproc)"
    elif [[ -f "Makefile.PL" ]]; then
        echo "  Using ExtUtils::MakeMaker (Makefile.PL)"
        perl Makefile.PL INSTALLDIRS=vendor NO_PACKLIST=1 NO_PERLLOCAL=1
        make -j"$(nproc)"
    else
        # Some Proxmox Perl packages have a plain Makefile
        if [[ -f "Makefile" ]]; then
            echo "  Using existing Makefile"
            make -j"$(nproc)"
        else
            echo "ERROR: No Build.PL, Makefile.PL, or Makefile found in $build_dir" >&2
            exit 1
        fi
    fi

    echo "=== [$PKG_NAME] Perl build complete ==="
}

# Install Perl module to staging root
# Must be called after build_perl()
install_perl() {
    echo "=== [$PKG_NAME] Installing Perl to staging root ==="

    local build_dir="$WORKDIR"
    if [[ -n "$BUILD_SUBDIR" ]]; then
        build_dir="$WORKDIR/$BUILD_SUBDIR"
    fi
    cd "$build_dir"

    if [[ -f "Build.PL" && -f "Build" ]]; then
        ./Build install destdir="$STAGE/root" --installdirs vendor
    else
        make install DESTDIR="$STAGE/root" INSTALLDIRS=vendor || true
    fi

    # Prune .packlist and perllocal.pod
    find "$STAGE/root" -name '.packlist' -delete 2>/dev/null || true
    find "$STAGE/root" -name 'perllocal.pod' -delete 2>/dev/null || true

    echo "=== [$PKG_NAME] Perl install complete ==="
}

# ============================================================================
# 4. build_rust — Build Rust crates (cargo build --release)
# ============================================================================
# Handles:
#   - Standard cargo build --release
#   - Workspace crates (CARGO_BIN for specific binary)
#   - BUILD_SUBDIR for workspace member crates
#
# Environment:
#   CARGO_BIN     — specific binary to install from workspace
#   BUILD_SUBDIR  — workspace member subdirectory
build_rust() {
    echo "=== [$PKG_NAME] Building (Rust) ==="

    local build_dir="$WORKDIR"
    if [[ -n "$BUILD_SUBDIR" ]]; then
        build_dir="$WORKDIR/$BUILD_SUBDIR"
    fi
    cd "$build_dir"

    # Apply Debian patches if present
    apply_debian_patches

    # Build all workspace crates or specific package
    if [[ -n "$CARGO_BIN" ]]; then
        echo "  Building specific binary: $CARGO_BIN"
        cargo build --release --bin "$CARGO_BIN"
    else
        cargo build --release
    fi

    echo "=== [$PKG_NAME] Rust build complete ==="
}

# Install Rust artifacts to staging root
install_rust() {
    echo "=== [$PKG_NAME] Installing Rust to staging root ==="

    local build_dir="$WORKDIR"
    if [[ -n "$BUILD_SUBDIR" ]]; then
        build_dir="$WORKDIR/$BUILD_SUBDIR"
    fi

    # Install binaries
    if [[ -n "$CARGO_BIN" ]]; then
        mkdir -p "$STAGE/root/usr/bin"
        install -m755 "$build_dir/target/release/$CARGO_BIN" "$STAGE/root/usr/bin/"
    elif [[ -d "$build_dir/target/release" ]]; then
        # Find and install all built binaries (skip .d files)
        mkdir -p "$STAGE/root/usr/bin"
        for bin in "$build_dir/target/release/"*; do
            [[ -f "$bin" && -x "$bin" && ! "$bin" =~ \.d$ ]] || continue
            # Skip shared library files
            file "$bin" | grep -q 'shared object' && continue
            install -m755 "$bin" "$STAGE/root/usr/bin/"
        done
    fi

    # Install library artifacts (.rlib, .so) if present
    if [[ -d "$build_dir/target/release" ]]; then
        local has_libs=false
        for ext in rlib so; do
            if ls "$build_dir/target/release/"*.${ext} 2>/dev/null; then
                has_libs=true
                break
            fi
        done

        if [[ "$has_libs" == "true" ]]; then
            mkdir -p "$STAGE/root/usr/lib/${PKG_NAME}"
            find "$build_dir/target/release" -maxdepth 1 -name "lib*.rlib" \
                -exec cp {} "$STAGE/root/usr/lib/${PKG_NAME}/" \; 2>/dev/null || true
            find "$build_dir/target/release" -maxdepth 1 -name "lib*.so" \
                -exec cp {} "$STAGE/root/usr/lib/" \; 2>/dev/null || true
        fi
    fi

    echo "=== [$PKG_NAME] Rust install complete ==="
}

# ============================================================================
# 5. build_c — Build C/C++ projects (autotools or cmake)
# ============================================================================
# Handles:
#   - autotools: ./configure --prefix=/usr && make && make install DESTDIR=
#   - cmake: mkdir build && cmake -DCMAKE_INSTALL_PREFIX=/usr .. && make install
#   - EXTRA_CONFIGURE for additional flags
#
# Environment:
#   EXTRA_CONFIGURE — extra flags for ./configure or cmake
#   TARGET_CFLAGS   — compiler flags from build-chain
#   TARGET_CXXFLAGS — C++ compiler flags from build-chain
build_c() {
    echo "=== [$PKG_NAME] Building (C/C++) ==="

    local build_dir="$WORKDIR"
    if [[ -n "$BUILD_SUBDIR" ]]; then
        build_dir="$WORKDIR/$BUILD_SUBDIR"
    fi
    cd "$build_dir"

    # Apply Debian patches if present
    apply_debian_patches

    if [[ -f "CMakeLists.txt" ]]; then
        echo "  Using CMake"
        mkdir -p build
        cd build
        cmake \
            -DCMAKE_INSTALL_PREFIX=/usr \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_C_FLAGS="${TARGET_CFLAGS:-} ${EXTRA_CONFIGURE}" \
            -DCMAKE_CXX_FLAGS="${TARGET_CXXFLAGS:-} ${EXTRA_CONFIGURE}" \
            ..
        make -j"$(nproc)"
    elif [[ -f "configure" ]]; then
        echo "  Using autotools (./configure)"
        ./configure \
            --prefix=/usr \
            --disable-static \
            ${EXTRA_CONFIGURE}
        make -j"$(nproc)"
    elif [[ -f "Makefile" ]]; then
        echo "  Using existing Makefile"
        make -j"$(nproc)"
    else
        echo "ERROR: No CMakeLists.txt, configure, or Makefile found in $build_dir" >&2
        exit 1
    fi

    echo "=== [$PKG_NAME] C/C++ build complete ==="
}

# Install C/C++ project to staging root
install_c() {
    echo "=== [$PKG_NAME] Installing C/C++ to staging root ==="

    if [[ -f "CMakeLists.txt" ]]; then
        cd build
        make install DESTDIR="$STAGE/root" || true
    elif [[ -f "Makefile" ]]; then
        make install DESTDIR="$STAGE/root" PREFIX=/usr || true
    else
        echo "WARN: No Makefile found for install step" >&2
    fi

    echo "=== [$PKG_NAME] C/C++ install complete ==="
}

# ============================================================================
# 6. build_node — Build Node.js projects (npm ci && npm run build)
# ============================================================================
# Handles:
#   - npm ci for deterministic dependency installation
#   - npm run build for the build step
#   - NODE_BUILD_DIR for monorepo subdirectory
#   - Static JS assets (no build step needed)
#
# Environment:
#   NODE_BUILD_DIR — subdirectory for Node.js monorepo packages
build_node() {
    echo "=== [$PKG_NAME] Building (Node.js) ==="

    local build_dir="$WORKDIR"
    if [[ -n "$NODE_BUILD_DIR" ]]; then
        build_dir="$WORKDIR/$NODE_BUILD_DIR"
    elif [[ -n "$BUILD_SUBDIR" ]]; then
        build_dir="$WORKDIR/$BUILD_SUBDIR"
    fi
    cd "$build_dir"

    # Apply Debian patches if present
    apply_debian_patches

    if [[ -f "package.json" ]]; then
        if [[ -f "package-lock.json" || -f "npm-shrinkwrap.json" ]]; then
            npm ci
        else
            npm install
        fi

        # Check if build script exists
        if npm run env 2>/dev/null | grep -q '"build"'; then
            npm run build
        else
            echo "  No build script found, assuming pre-built assets"
        fi
    else
        echo "  No package.json found, assuming static assets"
    fi

    echo "=== [$PKG_NAME] Node.js build complete ==="
}

# Install Node.js project to staging root
# Override in build.sh for custom install logic (different JS projects
# install to wildly different locations)
install_node() {
    echo "=== [$PKG_NAME] Installing Node.js to staging root ==="
    echo "  WARN: Default Node.js install is a no-op." >&2
    echo "  Override install_node() in your build.sh for specific install paths." >&2
}

# ============================================================================
# 7. build_python — Build Python projects (pip install or setup.py)
# ============================================================================
# Handles:
#   - Modern: pip install . (PEP 517/518, pyproject.toml)
#   - Legacy: python setup.py install
#   - BUILD_SUBDIR for monorepo subdirectory
#
# Environment:
#   BUILD_SUBDIR — workspace member subdirectory
build_python() {
    echo "=== [$PKG_NAME] Building (Python) ==="

    local build_dir="$WORKDIR"
    if [[ -n "$BUILD_SUBDIR" ]]; then
        build_dir="$WORKDIR/$BUILD_SUBDIR"
    fi
    cd "$build_dir"

    # Apply Debian patches if present
    apply_debian_patches

    if [[ -f "pyproject.toml" ]]; then
        echo "  Using PEP 517 build (pyproject.toml)"
        pip install --no-build-isolation --no-deps --target="$STAGE/root/usr/lib/python3/site-packages" .
    elif [[ -f "setup.py" ]]; then
        echo "  Using setup.py"
        python setup.py install --root="$STAGE/root" --prefix=/usr --install-lib=/usr/lib/python3/site-packages
    else
        echo "ERROR: No pyproject.toml or setup.py found in $build_dir" >&2
        exit 1
    fi

    echo "=== [$PKG_NAME] Python build complete ==="
}

# ============================================================================
# 8. apply_debian_patches — Apply patches from debian/patches/series
# ============================================================================
# If DEBIAN_PATCHES_DIR is set, applies patches from that directory.
# Otherwise, looks for debian/patches/series in WORKDIR (or BUILD_SUBDIR).
# Patches are applied with patch -p1.
#
# Environment:
#   DEBIAN_PATCHES_DIR — override directory containing patches
#   BUILD_SUBDIR       — subdirectory within WORKDIR
apply_debian_patches() {
    local patches_dir="${DEBIAN_PATCHES_DIR:-}"

    if [[ -z "$patches_dir" ]]; then
        local source_dir="$WORKDIR"
        if [[ -n "$BUILD_SUBDIR" ]]; then
            source_dir="$WORKDIR/$BUILD_SUBDIR"
        fi

        if [[ -f "$source_dir/debian/patches/series" ]]; then
            patches_dir="$source_dir/debian/patches"
        else
            return 0
        fi
    fi

    local series_file="$patches_dir/series"
    if [[ ! -f "$series_file" ]]; then
        # Try DEBIAN_PATCHES_DIR directly (might be the patches dir itself)
        if [[ -f "$DEBIAN_PATCHES_DIR/series" ]]; then
            series_file="$DEBIAN_PATCHES_DIR/series"
            patches_dir="$DEBIAN_PATCHES_DIR"
        else
            echo "  No patch series file found, skipping patches"
            return 0
        fi
    fi

    echo "=== [$PKG_NAME] Applying Debian patches ==="

    local patch_dir_abs
    patch_dir_abs="$(cd "$patches_dir" && pwd)"

    local applied=0
    local failed=0
    while IFS= read -r patch_file; do
        # Skip comments and empty lines
        [[ -z "$patch_file" || "$patch_file" =~ ^[[:space:]]*# ]] && continue

        local patch_path="$patch_dir_abs/$patch_file"
        if [[ -f "$patch_path" ]]; then
            echo "  Applying: $patch_file"
            if patch -p1 -d "$WORKDIR" -i "$patch_path"; then
                applied=$((applied + 1))
            else
                echo "  WARN: Patch $patch_file failed (continuing)" >&2
                failed=$((failed + 1))
            fi
        else
            echo "  WARN: Patch file not found: $patch_path" >&2
            failed=$((failed + 1))
        fi
    done < "$series_file"

    echo "  Applied: $applied, Failed: $failed"
}

# ============================================================================
# 9. package_rpm — Create .pkg.tar intermediate for RPM conversion
# ============================================================================
# Creates the intermediate package format (meta/ + root/) that
# pkg-build-rpm.sh consumes to produce RPM packages.
#
# The intermediate format is:
#   meta/name           — Package name
#   meta/version        — Package version (+SHORT hash)
#   meta/arch           — Architecture (default: x86_64)
#   meta/description    — One-line description
#   meta/maintainer     — Maintainer string
#   meta/source_format  — "rpm"
#   meta/depends        — Newline-separated dependency list
#   meta/provides       — (optional) Provided capabilities
#   meta/conflicts      — (optional) Conflict packages
#   meta/replaces        — (optional) Replaced packages
#   meta/conffiles      — (optional) Configuration files (absolute paths)
#   meta/scripts/       — (optional) Pre/post install/remove scripts
#   root/               — File tree to install
#
# Environment:
#   PKG_NAME        — Package identifier
#   PKG_VERSION     — Version (detected from source if not set)
#   PKG_DESCRIPTION — One-line description
#   PKG_MAINTAINER  — Maintainer string
#   PKG_DEPENDS     — Newline-separated dependency list (or file path)
#   PKG_PROVIDES    — (optional) Newline-separated provides list
#   PKG_CONFLICTS    — (optional) Newline-separated conflicts list
#   PKG_REPLACES    — (optional) Newline-separated replaces list
#   PKG_CONFFILES   — (optional) Newline-separated config file paths
#   TARGET_ARCH     — Target architecture (default: x86_64)
#   SHORT           — Short git hash for version suffix
package_rpm() {
    echo "=== [$PKG_NAME] Creating .pkg.tar ==="

    # Ensure stage directories exist
    mkdir -p "$STAGE/root" "$STAGE/meta"

    # Determine version from multiple sources
    if [[ -z "${PKG_VERSION:-}" ]]; then
        PKG_VERSION="$(detect_version)"
    fi
    # Append SHORT hash for traceability
    PKG_VERSION="${PKG_VERSION}+${SHORT:-git}"

    # Write metadata files
    echo "$PKG_NAME"               > "$STAGE/meta/name"
    echo "$PKG_VERSION"            > "$STAGE/meta/version"
    echo "${TARGET_ARCH:-x86_64}"  > "$STAGE/meta/arch"
    echo "$PKG_DESCRIPTION"        > "$STAGE/meta/description"
    echo "$PKG_MAINTAINER"         > "$STAGE/meta/maintainer"
    echo "rpm"                      > "$STAGE/meta/source_format"

    # Dependencies — can be a string, a heredoc file, or empty
    if [[ -n "${PKG_DEPENDS:-}" ]]; then
        if [[ -f "$PKG_DEPENDS" ]]; then
            cp "$PKG_DEPENDS" "$STAGE/meta/depends"
        else
            printf '%s\n' "$PKG_DEPENDS" > "$STAGE/meta/depends"
        fi
    else
        touch "$STAGE/meta/depends"
    fi

    # Optional metadata: provides, conflicts, replaces
    for field in provides conflicts replaces; do
        local var_name="PKG_$(echo "$field" | tr '[:lower:]' '[:upper:]')"
        local var_value="${!var_name:-}"
        if [[ -n "$var_value" ]]; then
            if [[ -f "$var_value" ]]; then
                cp "$var_value" "$STAGE/meta/$field"
            else
                printf '%s\n' "$var_value" > "$STAGE/meta/$field"
            fi
        fi
    done

    # Config files
    if [[ -n "${PKG_CONFFILES:-}" ]]; then
        if [[ -f "$PKG_CONFFILES" ]]; then
            cp "$PKG_CONFFILES" "$STAGE/meta/conffiles"
        else
            printf '%s\n' "$PKG_CONFFILES" > "$STAGE/meta/conffiles"
        fi
    fi

    # Install scripts (preinst, postinst, prerm, postrm)
    mkdir -p "$STAGE/meta/scripts"
    for script in preinst postinst prerm postrm; do
        local script_path="$STAGE/meta/scripts/$script"
        local env_var="PKG_SCRIPT_${script^^}"
        if [[ -n "${!env_var:-}" && -f "${!env_var}" ]]; then
            cp "${!env_var}" "$script_path"
        fi
    done

    # Create .pkg.tar intermediate
    cd "$STAGE"
    tar cf "/workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar" meta root

    echo "=== [$PKG_NAME] Done ==="
    echo "Artifact: /workspace/${PKG_NAME}_${PKG_VERSION}_${TARGET_ARCH:-x86_64}.pkg.tar"
}

# ============================================================================
# Version detection helper — tries multiple sources for version string
# ============================================================================
# Detection priority:
#   1. debian/changelog first line (Debian package convention)
#   2. Cargo.toml [package] version (Rust crates)
#   3. Makefile VERSION variable (Perl modules, C projects)
#   4. pyproject.toml version (Python projects)
#   5. package.json version (Node.js projects)
#   6. SHORT hash fallback
detect_version() {
    local src_dir="${1:-$WORKDIR}"
    local version=""

    # 1. Debian changelog
    if [[ -f "$src_dir/debian/changelog" ]]; then
        version="$(head -1 "$src_dir/debian/changelog" | sed 's/.*(\([^)]*\)).*/\1/')"
    fi

    # 2. Cargo.toml (Rust)
    if [[ -z "$version" && -f "$src_dir/Cargo.toml" ]]; then
        version="$(grep '^version' "$src_dir/Cargo.toml" | head -1 | sed 's/.*= *["'"'"']*\([^"'"'"']*\)["'"'"']*.*/\1/')"
    fi

    # 3. Makefile (Perl / C)
    if [[ -z "$version" && -f "$src_dir/Makefile" ]]; then
        version="$(grep '^VERSION' "$src_dir/Makefile" | head -1 | sed 's/.*= *//; s/ //g')"
    fi

    # 4. pyproject.toml (Python)
    if [[ -z "$version" && -f "$src_dir/pyproject.toml" ]]; then
        version="$(grep '^version' "$src_dir/pyproject.toml" | head -1 | sed 's/.*= *["'"'"']*\([^"'"'"']*\)["'"'"']*.*/\1/')"
    fi

    # 5. package.json (Node.js)
    if [[ -z "$version" && -f "$src_dir/package.json" ]]; then
        version="$(grep '"version"' "$src_dir/package.json" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')"
    fi

    # 6. Fallback to SHORT hash
    if [[ -z "$version" ]]; then
        version="${SHORT:-0.0.1}"
    fi

    echo "$version"
}

# ============================================================================
# 10. cleanup — Remove temporary files except RPM artifacts
# ============================================================================
# Removes:
#   - WORKDIR (/tmp/src/$PKG_NAME) — source tree
#   - STAGE/meta and STAGE/root — intermediate staging
# Preserves:
#   - /workspace/*.pkg.tar — the build artifact
#   - /workspace/*.rpm — if RPM was built directly
#   - build.log — preserved in WORKDIR before cleanup
cleanup() {
    echo "=== [$PKG_NAME] Cleaning up ==="

    # Save build log before removing workdir
    local log_file="/workspace/${PKG_NAME}_build.log"
    if [[ -f "$WORKDIR/build.log" ]]; then
        cp "$WORKDIR/build.log" "$log_file" 2>/dev/null || true
    fi

    # Remove source and staging directories
    rm -rf "$WORKDIR" 2>/dev/null || true
    rm -rf "$STAGE" 2>/dev/null || true

    # Remove downloaded tarballs
    rm -f "/tmp/${PKG_NAME}.tar.gz" 2>/dev/null || true

    echo "=== [$PKG_NAME] Cleanup complete ==="
    echo "  Build log preserved: $log_file"
}

# ============================================================================
# 11. build_docs — Build documentation (asciidoc/pandoc)
# ============================================================================
# Handles documentation packages that use make for generation.
# Calls pre_build_hook if defined by the stub.
build_docs() {
    echo "=== [$PKG_NAME] Building (docs) ==="

    local build_dir="$WORKDIR"
    if [[ -n "$BUILD_SUBDIR" ]]; then
        build_dir="$WORKDIR/$BUILD_SUBDIR"
    fi
    cd "$build_dir"

    # Call pre-build hook if defined (for patching Makefiles etc.)
    if declare -f pre_build_hook >/dev/null 2>&1; then
        pre_build_hook
    fi

    make -j"$(nproc)" DOCRELEASE="${PKG_VERSION:-dev}" || true

    echo "=== [$PKG_NAME] Docs build complete ==="
}

# Install documentation to staging root
install_docs() {
    echo "=== [$PKG_NAME] Installing docs to staging root ==="

    local build_dir="$WORKDIR"
    if [[ -n "$BUILD_SUBDIR" ]]; then
        build_dir="$WORKDIR/$BUILD_SUBDIR"
    fi
    cd "$build_dir"

    make install DESTDIR="$STAGE/root" DOCRELEASE="${PKG_VERSION:-dev}" || true

    echo "=== [$PKG_NAME] Docs install complete ==="
}

# ============================================================================
# 12. build_i18n — Build internationalization files (gettext)
# ============================================================================
build_i18n() {
    echo "=== [$PKG_NAME] Building (i18n) ==="

    cd "$WORKDIR"

    # Call pre-build hook if defined (for patching Makefiles etc.)
    if declare -f pre_build_hook >/dev/null 2>&1; then
        pre_build_hook
    fi

    make -j"$(nproc)" || true

    echo "=== [$PKG_NAME] i18n build complete ==="
}

# Install i18n to staging root
install_i18n() {
    echo "=== [$PKG_NAME] Installing i18n to staging root ==="

    cd "$WORKDIR"
    make install DESTDIR="$STAGE/root" || true

    echo "=== [$PKG_NAME] i18n install complete ==="
}

# ============================================================================
# 13. build_firmware — Build EDK2 UEFI firmware
# ============================================================================
# Complex build: uses EDK2 build system with cross-compilers.
# Calls pre_build_hook for Makefile patching.
build_firmware() {
    echo "=== [$PKG_NAME] Building (firmware) ==="

    cd "$WORKDIR"

    # Call pre-build hook if defined (for patching build files etc.)
    if declare -f pre_build_hook >/dev/null 2>&1; then
        pre_build_hook
    fi

    # Disable hardening flags that conflict with EDK2 build
    export CFLAGS="${CFLAGS:-} -Wno-format -Wno-error=format-security -fno-trivial-auto-var-init=zero"

    if [[ -f "$WORKDIR/debian/rules" ]]; then
        if [[ -d "$WORKDIR/edk2" ]]; then
            pushd "$WORKDIR/edk2"
            make -f "$WORKDIR/debian/rules" override_dh_auto_build || true
            popd
        else
            make -f "$WORKDIR/debian/rules" override_dh_auto_build || true
        fi
    fi

    echo "=== [$PKG_NAME] Firmware build complete ==="
}

# Install firmware to staging root
# Calls install_override if defined by the stub for custom install logic.
install_firmware() {
    echo "=== [$PKG_NAME] Installing firmware to staging root ==="

    # Call install_override if defined by the stub
    if declare -f install_override >/dev/null 2>&1; then
        install_override
    else
        mkdir -p "$STAGE/root/usr/share/$PKG_NAME" "$STAGE/meta"
        # Copy firmware files per *.install files if debian/ exists
        if [[ -d "$WORKDIR/debian" ]]; then
            for f in "$WORKDIR"/debian/*.install; do
                [[ -f "$f" ]] || continue
                while IFS= read -r line; do
                    read -ra paths <<< "$line"
                    dest="$STAGE/root/${paths[-1]}"
                    mkdir -p "$dest"
                    for src in "${paths[@]::${#paths[@]}-1}"; do
                        for found in "$WORKDIR"/$src "$WORKDIR"/edk2/$src; do
                            if [[ -e "$found" ]]; then
                                cp $found "$dest" 2>/dev/null || true
                            fi
                        done
                    done
                done < "$f"
            done
        fi
    fi

    echo "=== [$PKG_NAME] Firmware install complete ==="
}

# ============================================================================
# 14. build_c_patched — Build C with Makefile patching
# ============================================================================
# For C packages that need Makefile patching before build.
# Calls pre_build_hook for patching.
build_c_patched() {
    echo "=== [$PKG_NAME] Building (C with patches) ==="

    cd "$WORKDIR"

    # Call pre-build hook if defined (for Makefile patching etc.)
    if declare -f pre_build_hook >/dev/null 2>&1; then
        pre_build_hook
    fi

    make -j"$(nproc)" || true

    echo "=== [$PKG_NAME] C build complete ==="
}

# Install C_patched to staging root
# Calls install_override if defined by the stub.
install_c_patched() {
    echo "=== [$PKG_NAME] Installing C to staging root ==="

    # Call install_override if defined by the stub
    if declare -f install_override >/dev/null 2>&1; then
        install_override
    else
        make install DESTDIR="$STAGE/root" PREFIX=/usr || true
    fi

    echo "=== [$PKG_NAME] C install complete ==="
}

# ============================================================================
# 15. install_font — Install font files to staging root
# ============================================================================
install_font() {
    echo "=== [$PKG_NAME] Installing font files to staging root ==="

    mkdir -p "$STAGE/root/usr/share/$PKG_NAME/css" "$STAGE/root/usr/share/$PKG_NAME/fonts"

    # Call install_override if defined by the stub
    if declare -f install_override >/dev/null 2>&1; then
        install_override
    fi

    echo "=== [$PKG_NAME] Font install complete ==="
}

# ============================================================================
# 16. install_generic — Install for hash-only/static packages
# ============================================================================
# Used for packages where files are simply copied to staging.
# Calls install_override if defined by the stub.
install_generic() {
    echo "=== [$PKG_NAME] Installing (generic) ==="

    mkdir -p "$STAGE/root" "$STAGE/meta"

    # Call install_override if defined by the stub
    if declare -f install_override >/dev/null 2>&1; then
        install_override
    fi

    echo "=== [$PKG_NAME] Generic install complete ==="
}

# ============================================================================
# 17. fetch_source_download — Download tarball (for hash-only packages)
# ============================================================================
# Alternative to fetch_source for packages that download a tarball
# instead of git clone. Used by c-hash, font-hash, node-hash types.
# Requires DOWNLOAD_URL and optionally DOWNLOAD_VERSION to be set.
fetch_source_download() {
    echo "=== [$PKG_NAME] Downloading source ==="
    WORKDIR="/tmp/src/${PKG_NAME}"
    rm -rf "$WORKDIR"
    mkdir -p "$WORKDIR"

    if [[ -z "${DOWNLOAD_URL:-}" ]]; then
        echo "ERROR: DOWNLOAD_URL must be set for fetch_source_download" >&2
        exit 1
    fi

    curl -L -o "/tmp/${PKG_NAME}.tar.gz" "$DOWNLOAD_URL"

    # Extract
    tar xzf "/tmp/${PKG_NAME}.tar.gz" -C "/tmp/src"

    # Find and move to expected WORKDIR
    if [[ -n "${DOWNLOAD_VERSION:-}" ]]; then
        mv "/tmp/src/${DOWNLOAD_EXTRACT_DIR:-${PKG_NAME}-${DOWNLOAD_VERSION}}" "$WORKDIR" 2>/dev/null || true
    else
        local extracted_dir
        extracted_dir=$(find /tmp/src -maxdepth 1 -type d -newer "/tmp/${PKG_NAME}.tar.gz" | head -1)
        if [[ -n "$extracted_dir" && "$extracted_dir" != "$WORKDIR" ]]; then
            rm -rf "$WORKDIR"
            mv "$extracted_dir" "$WORKDIR"
        fi
    fi
    cd "$WORKDIR"

    # Refine build type now that source is available
    if [[ "$BUILD_TYPE" == "auto" ]]; then
        refine_build_type "$WORKDIR"
    fi

    echo "=== [$PKG_NAME] Source downloaded successfully ==="
}

# ============================================================================
# Convenience function: full_build — run the entire pipeline
# ============================================================================
# Runs the standard 6-step pipeline based on BUILD_TYPE:
#   1. setup_env
#   2. fetch_source (or fetch_source_download for hash-only)
#   3. Build (dispatches based on BUILD_TYPE)
#   4. Install (dispatches based on BUILD_TYPE)
#   5. package_rpm
#   6. cleanup
#
# Individual build.sh files can override any step by:
#   - Defining pre_build_hook() — called before the build step
#   - Defining install_override() — replaces the default install step
#   - Defining build_override() — replaces the default build step
#   - Or by calling individual steps manually instead of full_build
#
# BUILD_TYPE values:
#   Layer 0: perl, rust, c, node, python, patch, static (auto-detected)
#   Layer 1: rust-workspace, rust-perl, rust-submodules, node (with install_override),
#            node-hash, font, font-hash, c-patched, c-hash, docs, i18n,
#            firmware, generic, perl-git
full_build() {
    setup_env

    # Choose fetch method based on BUILD_TYPE
    case "$BUILD_TYPE" in
        node-hash|font-hash|c-hash|generic)
            fetch_source_download
            ;;
        *)
            fetch_source
            ;;
    esac

    # Call build step — use override if defined, otherwise dispatch by BUILD_TYPE
    if declare -f build_override >/dev/null 2>&1; then
        build_override
    else
        case "$BUILD_TYPE" in
            perl|perl-git)
                build_perl
                ;;
            rust|rust-workspace|rust-submodules)
                build_rust
                ;;
            rust-perl)
                # Rust build + Perl wrapper make — build_override in stub does the make step
                build_rust
                ;;
            c|c-patched|c-hash)
                build_c
                ;;
            node|node-hash)
                build_node
                ;;
            python)
                build_python
                ;;
            docs)
                build_docs
                ;;
            i18n)
                build_i18n
                ;;
            firmware)
                build_firmware
                ;;
            font|font-hash)
                # No build step for font packages
                echo "=== [$PKG_NAME] No build step (font assets) ==="
                ;;
            patch)
                apply_debian_patches
                ;;
            static|generic)
                echo "=== [$PKG_NAME] No build step (static assets) ==="
                ;;
            *)
                echo "ERROR: Unknown BUILD_TYPE: $BUILD_TYPE" >&2
                exit 1
                ;;
        esac
    fi

    # Call install step — use override if defined, otherwise dispatch by BUILD_TYPE
    if declare -f install_override >/dev/null 2>&1; then
        install_override
    else
        case "$BUILD_TYPE" in
            perl|perl-git)
                install_perl
                ;;
            rust|rust-workspace|rust-submodules)
                install_rust
                ;;
            rust-perl)
                # Rust-Perl hybrid: custom install in install_override
                echo "=== [$PKG_NAME] Rust-Perl install (use install_override) ==="
                ;;
            c|c-hash)
                install_c
                ;;
            c-patched)
                install_c_patched
                ;;
            node|node-hash)
                install_node
                ;;
            python)
                # Python install is done in build_python (pip install --target)
                ;;
            docs)
                install_docs
                ;;
            i18n)
                install_i18n
                ;;
            firmware)
                install_firmware
                ;;
            font|font-hash)
                install_font
                ;;
            static|generic|patch)
                install_generic
                ;;
            *)
                echo "ERROR: Unknown BUILD_TYPE for install: $BUILD_TYPE" >&2
                exit 1
                ;;
        esac
    fi

    package_rpm
    cleanup
}