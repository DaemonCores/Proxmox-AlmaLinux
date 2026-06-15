#!/bin/bash
# cross-pkg-helpers.sh — Shared functions for RPM package building
# Sourced by pkg-build-rpm.sh
#
# Handles RPM-specific library relocation and script translation.

# ========================================================================
# relocate_lib_paths: Move library files between distro path conventions
#
# Handles:
#   1. RPM lib64: /usr/lib64/ → target (when target != /usr/lib64)
#   2. /lib/ → /usr/lib/ merge (for merged-usr distros)
#
# Creates compat symlinks from old paths for RPATH/dlopen compatibility.
#
# Usage: relocate_lib_paths <root-dir> <target-libdir>
# ========================================================================
relocate_lib_paths() {
  local root="$1" target_libdir="$2"
  [[ -d "$root" ]] || return 0

  local relocated=false

  # --- 1. RPM lib64 → target (when different) ---
  if [[ -d "$root/usr/lib64" ]] && [[ "$target_libdir" != "/usr/lib64" ]]; then
    local dest_dir="$root$target_libdir"
    mkdir -p "$dest_dir"
    cp -a "$root/usr/lib64"/* "$dest_dir/" 2>/dev/null || true
    rm -rf "$root/usr/lib64"
    ln -sfn "$target_libdir" "$root/usr/lib64"
    relocated=true
  fi

  # --- 2. /lib/ → /usr/lib/ merge ---
  if [[ -d "$root/lib" ]] && [[ "$target_libdir" == /usr/lib* ]]; then
    local dest_dir="$root$target_libdir"
    mkdir -p "$dest_dir"
    for item in "$root/lib"/*; do
      [[ -e "$item" ]] || continue
      local base
      base=$(basename "$item")
      [[ -L "$item" ]] && continue
      [[ "$base" == "firmware" || "$base" == "modules" || "$base" == "udev" ]] && continue
      if [[ -f "$item" || -d "$item" ]]; then
        cp -a "$item" "$dest_dir/" 2>/dev/null || true
        rm -rf "$item"
      fi
    done
    relocated=true
  fi

  if [[ "$relocated" == "true" ]]; then
    echo "  Relocated library paths → $target_libdir"
  fi
}

# ========================================================================
# Translate script: RPM source → RPM target (passthrough)
#
# Usage: translate_script <script-file> <source-fmt> <target-fmt>
#
# Same format (rpm→rpm): strips shebang and set -e, passes through.
# ========================================================================
translate_script() {
  local script_file="$1" source_fmt="$2" target_fmt="$3"
  [[ -f "$script_file" ]] || return

  # Same format: just strip boilerplate
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^#! ]] && continue
    [[ "$line" =~ ^[[:space:]]*set[[:space:]]+-e ]] && continue
    echo "$line"
  done < "$script_file"
}

# ========================================================================
# Extract conffiles list from intermediate format
# Returns one absolute path per line
# ========================================================================
get_conffiles() {
  local intdir="$1"
  if [[ -s "$intdir/meta/conffiles" ]]; then
    grep -v '^$' "$intdir/meta/conffiles" 2>/dev/null || true
  fi
}