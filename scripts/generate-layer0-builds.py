#!/usr/bin/env python3
"""Generate build.sh for all Layer 0 packages from packages.yml.

Parses packages.yml and generates packages/<id>/build.sh for each
Layer 0 package, using the functions from scripts/build-template.sh.

Two build types are generated:
  - perl-git   : for git.proxmox.com repos (clone + build_perl pipeline)
  - perl-cpan  : for CPAN tarballs (download + extract + build_perl pipeline)
"""

import os
import stat
import yaml

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKAGES_YML = os.path.join(PROJECT_DIR, "packages.yml")
PACKAGES_DIR = os.path.join(PROJECT_DIR, "packages")

# Human-readable descriptions for each package
DESC_MAP = {
    "perl-authen-pam": "PAM authentication interface for Perl",
    "perl-crypt-openssl-random": "Crypt::OpenSSL::Random - OpenSSL random number generator for Perl",
    "perl-crypt-openssl-rsa": "Crypt::OpenSSL::RSA - RSA encoding/decoding for Perl",
    "perl-data-dumper": "Data::Dumper - stringified Perl data structures",
    "perl-digest-sha": "Digest::SHA - SHA-1/256/512 digest for Perl",
    "perl-file-readbackwards": "File::ReadBackwards - read a file backwards by lines",
    "perl-filesys-df": "Filesys::Df - disk space information for Perl",
    "perl-http-daemon": "HTTP::Daemon - simple HTTP server for Perl",
    "perl-json": "JSON - JSON encoding and decoding for Perl",
    "perl-linux-inotify2": "Linux::Inotify2 - Linux inotify interface for Perl",
    "perl-mail-spamassassin": "Mail::SpamAssassin - spam filter modules for Perl",
    "perl-net-dns": "Net::DNS - DNS resolver for Perl",
    "perl-net-ip": "Net::IP - IPv4/IPv6 address manipulation for Perl",
    "perl-net-ssleay": "Net::SSLeay - Perl extension for OpenSSL",
    "perl-proxmox-acme": "Proxmox ACME client Perl module",
    "perl-uri": "URI - Uniform Resource Identifiers for Perl",
    "perl-www-perl": "LWP - WWW library for Perl (libwww-perl)",
    "perl-xml-parser": "XML::Parser - XML parsing for Perl",
    "perl-findbin": "FindBin - locate directory of running Perl script",
    "perl-iosocketip": "IO::Socket::IP - IPv4/IPv6 socket support for Perl",
    "perl-mimebase32": "MIME::Base32 - Base32 encoding/decoding for Perl",
    "perl-mimebase64": "MIME::Base64 - Base64 encoding/decoding for Perl",
    "perl-netsubnet": "Net::Subnet - IP subnet matching for Perl",
    "perl-posixstrptime": "POSIX::strptime - strptime for Perl",
    "perl-socket": "Socket - networking constants and structures for Perl",
    "perl-termreadline": "Term::ReadLine - terminal line editing for Perl",
    "perl-testharness": "Test::Harness - Perl test framework",
    "perl-uuid": "UUID - UUID generation for Perl",
}

# Dependencies (AlmaLinux RPM names) for each package
# Layer 0 packages only depend on system packages
DEP_MAP = {
    "perl-authen-pam": ["perl", "pam"],
    "perl-crypt-openssl-random": ["perl", "openssl-libs"],
    "perl-crypt-openssl-rsa": ["perl", "openssl-libs"],
    "perl-data-dumper": ["perl"],
    "perl-digest-sha": ["perl"],
    "perl-file-readbackwards": ["perl"],
    "perl-filesys-df": ["perl"],
    "perl-http-daemon": ["perl", "perl-http-date", "perl-lwp-mediatypes", "perl-io-socket-ip"],
    "perl-json": ["perl"],
    "perl-linux-inotify2": ["perl"],
    "perl-mail-spamassassin": ["perl", "perl-net-dns", "perl-io-socket-ssl", "perl-mail-spf", "perl-netaddr-ip"],
    "perl-net-dns": ["perl", "perl-digest-hmac", "perl-net-ip", "perl-io-socket-ip"],
    "perl-net-ip": ["perl"],
    "perl-net-ssleay": ["perl", "openssl-libs"],
    "perl-proxmox-acme": ["perl", "openssl-libs"],
    "perl-uri": ["perl"],
    "perl-www-perl": ["perl", "perl-uri", "perl-net-http", "perl-www-robotrules", "perl-io-socket-ip"],
    "perl-xml-parser": ["perl", "expat"],
    "perl-findbin": ["perl"],
    "perl-iosocketip": ["perl"],
    "perl-mimebase32": ["perl"],
    "perl-mimebase64": ["perl"],
    "perl-netsubnet": ["perl"],
    "perl-posixstrptime": ["perl"],
    "perl-socket": ["perl"],
    "perl-termreadline": ["perl"],
    "perl-testharness": ["perl"],
    "perl-uuid": ["perl"],
}

HEADER = """\
#!/bin/bash
# build.sh — {pkg_id} ({build_type_label})
#
# Build pipeline:
#   1. setup_env      — Export WORKDIR, PKG_NAME, VERSION, RELEASE; detect build type
#   2. fetch_source   — {fetch_desc}
#   3. build_perl     — Makefile.PL / Build.PL build
#   4. install_perl   — Install to staging root
#   5. package_rpm    — Create .pkg.tar intermediate
#   6. cleanup        — Remove temporary files
#
# Environment (injected by build-chain.yml):
#   VERSION, COMMIT, SHORT, TARGET_ID, TARGET_ARCH,
#   TARGET_CFLAGS, TARGET_CXXFLAGS, SOURCE_DISTRO
set -euo pipefail
"""


def _format_depends(depends):
    """Format dependency list for bash $'...' quoting.

    Uses bash $'...' quoting which interprets \\n as a real newline,
    so that package_rpm() writes each dep on its own line in meta/depends.
    """
    return "\\n".join(depends)


def generate_git_build_sh(pkg_id, repo_url, description, depends):
    """Generate build.sh for a git-sourced Perl module."""
    depends_str = _format_depends(depends)
    build_type_label = "Layer 0: Perl git module, no PVE deps"
    fetch_desc = "Git clone from git.proxmox.com"

    lines = []
    lines.append(HEADER.format(
        pkg_id=pkg_id,
        build_type_label=build_type_label,
        fetch_desc=fetch_desc,
    ))
    lines.append(f'PKG_NAME="{pkg_id}"')
    lines.append(f'REPO_URL="{repo_url}"')
    lines.append(f'PKG_DESCRIPTION="{description}"')
    lines.append("")
    lines.append("source ../../scripts/build-template.sh")
    lines.append("")
    lines.append("# Dependencies — AlmaLinux RPM names")
    lines.append(f"PKG_DEPENDS=$'{depends_str}'")
    lines.append("")
    lines.append("setup_env")
    lines.append("fetch_source")
    lines.append("build_perl")
    lines.append("install_perl")
    lines.append("package_rpm")
    lines.append("cleanup")
    lines.append("")
    return "\n".join(lines)


def generate_cpan_build_sh(pkg_id, cpan_url, cpan_version, description, depends):
    """Generate build.sh for a CPAN-sourced Perl module."""
    depends_str = _format_depends(depends)
    build_type_label = "Layer 0: CPAN Perl module, no PVE deps"
    fetch_desc = "Download CPAN tarball and extract"

    lines = []
    lines.append(HEADER.format(
        pkg_id=pkg_id,
        build_type_label=build_type_label,
        fetch_desc=fetch_desc,
    ))
    lines.append(f'PKG_NAME="{pkg_id}"')
    lines.append(f'REPO_URL="{cpan_url}"')
    if cpan_version:
        lines.append(f'CPAN_VERSION="{cpan_version}"')
    lines.append(f'PKG_DESCRIPTION="{description}"')
    lines.append("")
    lines.append("source ../../scripts/build-template.sh")
    lines.append("")
    lines.append("# Dependencies — AlmaLinux RPM names")
    lines.append(f"PKG_DEPENDS=$'{depends_str}'")
    lines.append("")
    lines.append("setup_env")
    lines.append("fetch_source")
    lines.append("build_perl")
    lines.append("install_perl")
    lines.append("package_rpm")
    lines.append("cleanup")
    lines.append("")
    return "\n".join(lines)


def main():
    with open(PACKAGES_YML, "r") as f:
        data = yaml.safe_load(f)

    layer0 = [p for p in data["packages"] if p.get("layer") == 0]

    print("=== generate-layer0-builds.py ===")
    print(f"Parsing packages.yml... Found {len(layer0)} Layer 0 packages")

    generated = 0
    for pkg in layer0:
        pkg_id = pkg["id"]
        repo = pkg["repo"]
        is_cpan = "cpan.org" in repo
        description = DESC_MAP.get(pkg_id, f"Perl module - {pkg_id}")
        depends = DEP_MAP.get(pkg_id, ["perl"])

        target_dir = os.path.join(PACKAGES_DIR, pkg_id)
        target_file = os.path.join(target_dir, "build.sh")

        if not os.path.isdir(target_dir):
            print(f"  WARNING: Directory {target_dir} does not exist, creating it")
            os.makedirs(target_dir, exist_ok=True)

        if is_cpan:
            tarball_name = repo.rsplit("/", 1)[-1]
            source_dir = tarball_name.replace(".tar.gz", "").replace(".tgz", "")
            parts = source_dir.rsplit("-", 1)
            cpan_version = parts[1] if len(parts) == 2 else ""
            content = generate_cpan_build_sh(pkg_id, repo, cpan_version, description, depends)
            pkg_type = "perl-cpan"
        else:
            content = generate_git_build_sh(pkg_id, repo, description, depends)
            pkg_type = "perl-git"

        with open(target_file, "w") as f:
            f.write(content)

        # Make executable
        os.chmod(target_file, 0o755)

        print(f"  [OK] {target_file} ({pkg_type})")
        generated += 1

    print()
    print("=== Summary ===")
    print(f"  Build.sh files generated: {generated}")
    print("=== Done ===")


if __name__ == "__main__":
    main()