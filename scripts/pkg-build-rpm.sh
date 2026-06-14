#!/bin/bash
# pkg-build-rpm.sh — Build an .rpm from the intermediate format
# Usage: ./pkg-build-rpm.sh <intermediate-dir> <output-dir> [--dep-map <dep-map.conf>]
#
# Supports RPM source format → RPM output.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cross-pkg-helpers.sh
source "$SCRIPT_DIR/cross-pkg-helpers.sh"

INTDIR="$1"
OUTDIR="$2"
DEP_MAP=""
TARGET_DISTRO=""
# Convert to absolute paths
[[ "$INTDIR" != /* ]] && INTDIR="$(cd "$INTDIR" && pwd)"
mkdir -p "$OUTDIR"
[[ "$OUTDIR" != /* ]] && OUTDIR="$(cd "$OUTDIR" && pwd)"

shift 2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dep-map) DEP_MAP="$2"; shift 2 ;;
    --target-distro) TARGET_DISTRO="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -d "$INTDIR/meta" || ! -d "$INTDIR/root" ]]; then
  echo "ERROR: Invalid intermediate directory: $INTDIR" >&2
  exit 1
fi

PKG_NAME=$(cat "$INTDIR/meta/name")
PKG_VERSION=$(cat "$INTDIR/meta/version")
PKG_ARCH=$(cat "$INTDIR/meta/arch")
PKG_DESC=$(cat "$INTDIR/meta/description")
PKG_MAINTAINER=$(cat "$INTDIR/meta/maintainer")

# Map arch
case "$PKG_ARCH" in
  aarch64|arm64)  RPM_ARCH="aarch64" ;;
  x86_64|amd64)   RPM_ARCH="x86_64" ;;
  armhf)          RPM_ARCH="armv7hl" ;;
  all|noarch|any) RPM_ARCH="noarch" ;;
  *)              RPM_ARCH="$PKG_ARCH" ;;
esac

# Target libdir based on arch (Fedora uses lib64 for 64-bit)
case "$RPM_ARCH" in
  aarch64|x86_64) TARGET_LIBDIR="/usr/lib64" ;;
  *)              TARGET_LIBDIR="/usr/lib" ;;
esac

# Clean version for RPM (no colons, strip +suffix, translate hyphens)
RPM_VERSION=$(echo "$PKG_VERSION" | sed 's/+[^-]*//' | tr ':~' '..' | sed 's/-/./g')

# Setup rpmbuild tree
RPMBUILD=$(mktemp -d)
trap 'rm -rf "$RPMBUILD"' EXIT

mkdir -p "$RPMBUILD"/{BUILD,RPMS,SOURCES,SPECS,SRPMS,BUILDROOT}

# Build requires lines
REQUIRES=""
if [[ -s "$INTDIR/meta/depends" ]]; then
  while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue
    REQUIRES="${REQUIRES}Requires: ${dep}
"
  done < "$INTDIR/meta/depends"
fi

# Optional provides/conflicts/obsoletes (prefer distro-specific files if available)
EXTRA_SPEC=""
for field in provides conflicts replaces; do
  field_file="$INTDIR/meta/$field"
  [[ -n "$TARGET_DISTRO" && -s "$INTDIR/meta/${field}.${TARGET_DISTRO}" ]] && field_file="$INTDIR/meta/${field}.${TARGET_DISTRO}"
  if [[ -s "$field_file" ]]; then
    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue
      case "$field" in
        provides)  EXTRA_SPEC="${EXTRA_SPEC}Provides: ${entry}
" ;;
        conflicts) EXTRA_SPEC="${EXTRA_SPEC}Conflicts: ${entry}
" ;;
        replaces)  EXTRA_SPEC="${EXTRA_SPEC}Obsoletes: ${entry}
" ;;
      esac
    done < "$field_file"
  fi
done

# ========================================================================
# Build scriptlet bodies (RPM source: passthrough)
# ========================================================================
PRE_BODY=""
POST_BODY=""
PREUN_BODY=""
POSTUN_BODY=""

if [[ -f "$INTDIR/meta/scripts/preinst" ]]; then
  TRANSLATED=$(translate_script "$INTDIR/meta/scripts/preinst" "rpm" "rpm")
  [[ -n "$TRANSLATED" ]] && PRE_BODY+="$TRANSLATED"$'\n'
fi
if [[ -f "$INTDIR/meta/scripts/postinst" ]]; then
  TRANSLATED=$(translate_script "$INTDIR/meta/scripts/postinst" "rpm" "rpm")
  [[ -n "$TRANSLATED" ]] && POST_BODY+="$TRANSLATED"$'\n'
fi
if [[ -f "$INTDIR/meta/scripts/prerm" ]]; then
  TRANSLATED=$(translate_script "$INTDIR/meta/scripts/prerm" "rpm" "rpm")
  [[ -n "$TRANSLATED" ]] && PREUN_BODY+="$TRANSLATED"$'\n'
fi
if [[ -f "$INTDIR/meta/scripts/postrm" ]]; then
  TRANSLATED=$(translate_script "$INTDIR/meta/scripts/postrm" "rpm" "rpm")
  [[ -n "$TRANSLATED" ]] && POSTUN_BODY+="$TRANSLATED"$'\n'
fi

# Detect systemd unit files and add native RPM handling
SYSTEMD_UNITS=$(find "$INTDIR/root" -name '*.service' -o -name '*.timer' -o -name '*.socket' -o -name '*.path' 2>/dev/null | sed 's|.*/||' | sort -u || true)
if [[ -n "$SYSTEMD_UNITS" ]]; then
  for unit in $SYSTEMD_UNITS; do
    POST_BODY+="systemctl preset $unit >/dev/null 2>&1 || :"$'\n'
    PREUN_BODY+='if [ $1 -eq 0 ]; then systemctl --no-reload disable --now '"$unit"' >/dev/null 2>&1 || :; fi'$'\n'
    POSTUN_BODY+='if [ $1 -ge 1 ]; then systemctl try-restart '"$unit"' >/dev/null 2>&1 || :; fi'$'\n'
  done
fi

# Add ldconfig if package has shared libs
if [[ -n "$(find "$INTDIR/root" \( -name '*.so' -o -name '*.so.*' \) -print -quit 2>/dev/null)" ]]; then
  POST_BODY+="/sbin/ldconfig"$'\n'
  POSTUN_BODY+="/sbin/ldconfig"$'\n'
fi

# Assemble scriptlet sections
SCRIPTLETS=""
[[ -n "${PRE_BODY// /}" ]] && SCRIPTLETS+=$'\n'"%pre"$'\n'"$PRE_BODY"
[[ -n "${POST_BODY// /}" ]] && SCRIPTLETS+=$'\n'"%post"$'\n'"$POST_BODY"
[[ -n "${PREUN_BODY// /}" ]] && SCRIPTLETS+=$'\n'"%preun"$'\n'"$PREUN_BODY"
[[ -n "${POSTUN_BODY// /}" ]] && SCRIPTLETS+=$'\n'"%postun"$'\n'"$POSTUN_BODY"

# ========================================================================
# Generate file list — escape % for RPM spec, mark conffiles %config
# ========================================================================

# Load conffiles set for fast lookup
declare -A CONFFILES_SET
if [[ -s "$INTDIR/meta/conffiles" ]]; then
  while IFS= read -r cf; do
    [[ -z "$cf" ]] && continue
    CONFFILES_SET["$cf"]=1
  done < "$INTDIR/meta/conffiles"
fi

HAS_FILES=false
FILE_LIST=""
DIR_LIST=""
if [[ -d "$INTDIR/root" ]] && [[ -n "$(find "$INTDIR/root" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  HAS_FILES=true

  while IFS= read -r fpath; do
    escaped="${fpath//%/%%}"
    if [[ -n "${CONFFILES_SET[$fpath]+x}" ]]; then
      FILE_LIST+=$'%config(noreplace) '"$escaped"$'\n'
    else
      FILE_LIST+="$escaped"$'\n'
    fi
  done < <(cd "$INTDIR/root" && find . -type f -o -type l | sed 's|^\.|/|' | sort)

  DIR_LIST=$(cd "$INTDIR/root" && find . -type d ! -name '.' | sed 's|^\.|%dir /|' | sort)
fi

# Create spec file
cat > "$RPMBUILD/SPECS/$PKG_NAME.spec" << SPEC
%define _unpackaged_files_terminate_build 0
%define __check_files %{nil}
%define __os_install_post %{nil}
%define _binary_payload w19T0.zstdio
Name:    $PKG_NAME
Version: $RPM_VERSION
Release: 1
Summary: $PKG_DESC
License: GPL
Packager: $PKG_MAINTAINER
AutoReqProv: no
${REQUIRES}${EXTRA_SPEC}
%description
$PKG_DESC
${SCRIPTLETS}
%install
if ls "$INTDIR/root"/* >/dev/null 2>&1; then
  cp -a "$INTDIR/root"/* %{buildroot}/
fi

%files
$FILE_LIST
$DIR_LIST
SPEC

# Build RPM (output to private dir to avoid race conditions in parallel builds)
rpmbuild --define "_topdir $RPMBUILD" \
         --define "_rpmdir $RPMBUILD/RPMS" \
         --define "_arch $RPM_ARCH" \
         --target "$RPM_ARCH" \
         -bb "$RPMBUILD/SPECS/$PKG_NAME.spec"

# Copy RPM to output dir
find "$RPMBUILD/RPMS" -name '*.rpm' -exec cp {} "$OUTDIR/" \;

echo "RPM built: $OUTDIR/${PKG_NAME}-${RPM_VERSION}-1.${RPM_ARCH}.rpm"