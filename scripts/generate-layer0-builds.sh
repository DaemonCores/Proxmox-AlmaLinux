#!/bin/bash
# generate-layer0-builds.sh — Generate build.sh for all Layer 0 packages
#
# Parses packages.yml and generates packages/<id>/build.sh for each
# Layer 0 package, using the functions from scripts/build-template.sh.
#
# Two build types are generated:
#   - perl-git   : for git.proxmox.com repos (clone + build_perl pipeline)
#   - perl-cpan  : for CPAN tarballs (download + extract + build_perl pipeline)
#
# Usage:
#   ./scripts/generate-layer0-builds.sh          # generate all Layer 0 build.sh
#   ./scripts/generate-layer0-builds.sh --dry-run # preview without writing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGES_YML="$PROJECT_DIR/packages.yml"
PACKAGES_DIR="$PROJECT_DIR/packages"

# Defaults
DRY_RUN=false

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

# Check dependencies
if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 is required" >&2
    exit 1
fi

# --- Python script to parse YAML and output package data ---
PYTHON_SCRIPT='
import yaml
import sys

with open(sys.argv[1], "r") as f:
    data = yaml.safe_load(f)

layer0 = [p for p in data["packages"] if p.get("layer") == 0]

for pkg in layer0:
    pkg_id = pkg["id"]
    repo = pkg["repo"]
    is_cpan = "cpan.org" in repo
    pkg_type = "perl-cpan" if is_cpan else "perl-git"
    version_source = pkg.get("version_source", "git")
    build_time = pkg.get("build_time", 2)

    tarball_name = ""
    source_dir = ""
    cpan_version = ""
    if is_cpan:
        tarball_name = repo.rsplit("/", 1)[-1]
        source_dir = tarball_name.replace(".tar.gz", "").replace(".tgz", "")
        parts = source_dir.rsplit("-", 1)
        if len(parts) == 2:
            cpan_version = parts[1]

    print(f"PKG_ID={pkg_id}")
    print(f"PKG_TYPE={pkg_type}")
    print(f"REPO_URL={repo}")
    print(f"IS_CPAN={is_cpan}")
    print(f"VERSION_SOURCE={version_source}")
    print(f"BUILD_TIME={build_time}")
    if is_cpan:
        print(f"TARBALL_NAME={tarball_name}")
        print(f"SOURCE_DIR={source_dir}")
        print(f"CPAN_VERSION={cpan_version}")
    print("---")
'

# Generate human-readable descriptions for each package
describe_package() {
    local pkg_id="$1"
    case "$pkg_id" in
        perl-authen-pam)           echo "PAM authentication interface for Perl" ;;
        perl-crypt-openssl-random) echo "Crypt::OpenSSL::Random - OpenSSL random number generator for Perl" ;;
        perl-crypt-openssl-rsa)    echo "Crypt::OpenSSL::RSA - RSA encoding/decoding for Perl" ;;
        perl-data-dumper)          echo "Data::Dumper - stringified Perl data structures" ;;
        perl-digest-sha)           echo "Digest::SHA - SHA-1/256/512 digest for Perl" ;;
        perl-file-readbackwards)   echo "File::ReadBackwards - read a file backwards by lines" ;;
        perl-filesys-df)           echo "Filesys::Df - disk space information for Perl" ;;
        perl-http-daemon)          echo "HTTP::Daemon - simple HTTP server for Perl" ;;
        perl-json)                 echo "JSON - JSON encoding and decoding for Perl" ;;
        perl-linux-inotify2)       echo "Linux::Inotify2 - Linux inotify interface for Perl" ;;
        perl-mail-spamassassin)    echo "Mail::SpamAssassin - spam filter modules for Perl" ;;
        perl-net-dns)              echo "Net::DNS - DNS resolver for Perl" ;;
        perl-net-ip)               echo "Net::IP - IPv4/IPv6 address manipulation for Perl" ;;
        perl-net-ssleay)           echo "Net::SSLeay - Perl extension for OpenSSL" ;;
        perl-proxmox-acme)         echo "Proxmox ACME client Perl module" ;;
        perl-uri)                  echo "URI - Uniform Resource Identifiers for Perl" ;;
        perl-www-perl)             echo "LWP - WWW library for Perl (libwww-perl)" ;;
        perl-xml-parser)           echo "XML::Parser - XML parsing for Perl" ;;
        perl-findbin)              echo "FindBin - locate directory of running Perl script" ;;
        perl-iosocketip)           echo "IO::Socket::IP - IPv4/IPv6 socket support for Perl" ;;
        perl-mimebase32)           echo "MIME::Base32 - Base32 encoding/decoding for Perl" ;;
        perl-mimebase64)           echo "MIME::Base64 - Base64 encoding/decoding for Perl" ;;
        perl-netsubnet)            echo "Net::Subnet - IP subnet matching for Perl" ;;
        perl-posixstrptime)        echo "POSIX::strptime - strptime for Perl" ;;
        perl-socket)               echo "Socket - networking constants and structures for Perl" ;;
        perl-termreadline)         echo "Term::ReadLine - terminal line editing for Perl" ;;
        perl-testharness)          echo "Test::Harness - Perl test framework" ;;
        perl-uuid)                 echo "UUID - UUID generation for Perl" ;;
        *)                         echo "Perl module - ${pkg_id}" ;;
    esac
}

# Generate dependencies for each package (AlmaLinux RPM names)
describe_depends() {
    local pkg_id="$1"
    case "$pkg_id" in
        perl-authen-pam)           printf '%s\n' "perl" "pam" ;;
        perl-crypt-openssl-random) printf '%s\n' "perl" "openssl-libs" ;;
        perl-crypt-openssl-rsa)    printf '%s\n' "perl" "openssl-libs" ;;
        perl-data-dumper)          printf '%s\n' "perl" ;;
        perl-digest-sha)           printf '%s\n' "perl" ;;
        perl-file-readbackwards)   printf '%s\n' "perl" ;;
        perl-filesys-df)           printf '%s\n' "perl" ;;
        perl-http-daemon)          printf '%s\n' "perl" "perl-http-date" "perl-lwp-mediatypes" "perl-io-socket-ip" ;;
        perl-json)                 printf '%s\n' "perl" ;;
        perl-linux-inotify2)       printf '%s\n' "perl" ;;
        perl-mail-spamassassin)    printf '%s\n' "perl" "perl-net-dns" "perl-io-socket-ssl" "perl-mail-spf" "perl-netaddr-ip" ;;
        perl-net-dns)              printf '%s\n' "perl" "perl-digest-hmac" "perl-net-ip" "perl-io-socket-ip" ;;
        perl-net-ip)               printf '%s\n' "perl" ;;
        perl-net-ssleay)           printf '%s\n' "perl" "openssl-libs" ;;
        perl-proxmox-acme)         printf '%s\n' "perl" "openssl-libs" ;;
        perl-uri)                  printf '%s\n' "perl" ;;
        perl-www-perl)             printf '%s\n' "perl" "perl-uri" "perl-net-http" "perl-www-robotrules" "perl-io-socket-ip" ;;
        perl-xml-parser)           printf '%s\n' "perl" "expat" ;;
        perl-findbin)              printf '%s\n' "perl" ;;
        perl-iosocketip)           printf '%s\n' "perl" ;;
        perl-mimebase32)           printf '%s\n' "perl" ;;
        perl-mimebase64)           printf '%s\n' "perl" ;;
        perl-netsubnet)            printf '%s\n' "perl" ;;
        perl-posixstrptime)        printf '%s\n' "perl" ;;
        perl-socket)               printf '%s\n' "perl" ;;
        perl-termreadline)         printf '%s\n' "perl" ;;
        perl-testharness)          printf '%s\n' "perl" ;;
        perl-uuid)                 printf '%s\n' "perl" ;;
        *)                         printf '%s\n' "perl" ;;
    esac
}

# Generate a perl-git build.sh by writing it to a temp file
# (avoids heredoc-within-heredoc issues)
generate_git_build_sh() {
    local pkg_id="$1"
    local repo_url="$2"
    local description
    description="$(describe_package "$pkg_id")"
    local depends
    depends="$(describe_depends "$pkg_id")"
    local target_file="$3"

    # Write build.sh line by line
    {
        echo '#!/bin/bash'
        echo "# build.sh — ${pkg_id} (Layer 0: Perl git module, no PVE deps)"
        echo '#'
        echo '# Build pipeline:'
        echo '#   1. setup_env      — Export WORKDIR, PKG_NAME, VERSION, RELEASE; detect build type'
        echo '#   2. fetch_source   — Git clone from git.proxmox.com'
        echo '#   3. build_perl     — Makefile.PL / Build.PL build'
        echo '#   4. install_perl   — Install to staging root'
        echo '#   5. package_rpm    — Create .pkg.tar intermediate'
        echo '#   6. cleanup        — Remove temporary files'
        echo '#'
        echo '# Environment (injected by build-chain.yml):'
        echo '#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,'
        echo '#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO'
        echo 'set -euo pipefail'
        echo ''
        echo "PKG_NAME=\"${pkg_id}\""
        echo "REPO_URL=\"${repo_url}\""
        echo "PKG_DESCRIPTION=\"${description}\""
        echo ''
        echo 'source ../../scripts/build-template.sh'
        echo ''
        echo '# Dependencies — AlmaLinux RPM names'
        printf 'PKG_DEPENDS="%s"\n' "$depends"
        echo ''
        echo 'setup_env'
        echo 'fetch_source'
        echo 'build_perl'
        echo 'install_perl'
        echo 'package_rpm'
        echo 'cleanup'
    } > "$target_file"
}

# Generate a perl-cpan build.sh by writing it to a temp file
generate_cpan_build_sh() {
    local pkg_id="$1"
    local cpan_url="$2"
    local cpan_version="$3"
    local description
    description="$(describe_package "$pkg_id")"
    local depends
    depends="$(describe_depends "$pkg_id")"
    local target_file="$4"

    # Write build.sh line by line
    {
        echo '#!/bin/bash'
        echo "# build.sh — ${pkg_id} (Layer 0: CPAN Perl module, no PVE deps)"
        echo '#'
        echo '# Build pipeline:'
        echo '#   1. setup_env      — Export WORKDIR, PKG_NAME, VERSION, RELEASE; detect build type'
        echo '#   2. fetch_source   — Download CPAN tarball and extract'
        echo '#   3. build_perl     — Makefile.PL / Build.PL build'
        echo '#   4. install_perl   — Install to staging root'
        echo '#   5. package_rpm    — Create .pkg.tar intermediate'
        echo '#   6. cleanup        — Remove temporary files'
        echo '#'
        echo '# Environment (injected by build-chain.yml):'
        echo '#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,'
        echo '#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO'
        echo 'set -euo pipefail'
        echo ''
        echo "PKG_NAME=\"${pkg_id}\""
        echo "REPO_URL=\"${cpan_url}\""
        if [[ -n "$cpan_version" ]]; then
            echo "CPAN_VERSION=\"${cpan_version}\""
        fi
        echo "PKG_DESCRIPTION=\"${description}\""
        echo ''
        echo 'source ../../scripts/build-template.sh'
        echo ''
        echo '# Dependencies — AlmaLinux RPM names'
        printf 'PKG_DEPENDS="%s"\n' "$depends"
        echo ''
        echo 'setup_env'
        echo 'fetch_source'
        echo 'build_perl'
        echo 'install_perl'
        echo 'package_rpm'
        echo 'cleanup'
    } > "$target_file"
}

# --- Main ---
echo "=== generate-layer0-builds.sh ==="
echo "Parsing packages.yml..."

# Parse YAML and generate build.sh for each Layer 0 package
GENERATED=0
SKIPPED=0

while IFS= read -r line; do
    # Parse variable assignments from python output
    case "$line" in
        PKG_ID=*)    PKG_ID="${line#PKG_ID=}" ;;
        PKG_TYPE=*)  PKG_TYPE="${line#PKG_TYPE=}" ;;
        REPO_URL=*)  REPO_URL="${line#REPO_URL=}" ;;
        IS_CPAN=*)   IS_CPAN="${line#IS_CPAN=}" ;;
        VERSION_SOURCE=*) VERSION_SOURCE="${line#VERSION_SOURCE=}" ;;
        BUILD_TIME=*) BUILD_TIME="${line#BUILD_TIME=}" ;;
        TARBALL_NAME=*) TARBALL_NAME="${line#TARBALL_NAME=}" ;;
        SOURCE_DIR=*) SOURCE_DIR="${line#SOURCE_DIR=}" ;;
        CPAN_VERSION=*) CPAN_VERSION="${line#CPAN_VERSION=}" ;;
        ---)
            # End of package block — generate the build.sh
            target_dir="$PACKAGES_DIR/$PKG_ID"
            target_file="$target_dir/build.sh"

            if [[ ! -d "$target_dir" ]]; then
                echo "  WARNING: Directory $target_dir does not exist, creating it"
                if [[ "$DRY_RUN" == "false" ]]; then
                    mkdir -p "$target_dir"
                fi
            fi

            if [[ "$DRY_RUN" == "true" ]]; then
                echo "  [DRY-RUN] Would write: $target_file"
                echo "    Type: $PKG_TYPE, URL: $REPO_URL"
            else
                if [[ "$IS_CPAN" == "True" ]]; then
                    generate_cpan_build_sh "$PKG_ID" "$REPO_URL" "$CPAN_VERSION" "$target_file"
                else
                    generate_git_build_sh "$PKG_ID" "$REPO_URL" "$target_file"
                fi
                chmod +x "$target_file"
                echo "  [OK] $target_file ($PKG_TYPE)"
            fi
            GENERATED=$((GENERATED + 1))

            # Reset variables for next package
            PKG_ID=""
            PKG_TYPE=""
            REPO_URL=""
            IS_CPAN=""
            VERSION_SOURCE=""
            BUILD_TIME=""
            TARBALL_NAME=""
            SOURCE_DIR=""
            CPAN_VERSION=""
            ;;
    esac
done < <(python3 -c "$PYTHON_SCRIPT" "$PACKAGES_YML")

echo ""
echo "=== Summary ==="
echo "  Build.sh files generated: $GENERATED"
echo "  Build.sh files skipped:   $SKIPPED"
if [[ "$DRY_RUN" == "true" ]]; then
    echo "  Mode: DRY-RUN (no files written)"
else
    echo "  Mode: WRITE"
fi
echo "=== Done ==="