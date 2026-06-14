#!/bin/bash
# compute-chains.sh — Compute build chains from packages.yml for AlmaBuilder
#
# Simplified from AlmaBuilder: single device (almabuilder),
# single architecture (x86_64), single distro (almalinux-10).
# Reads package definitions, applies bin-packing into 4 parallel chains
# by build_time, and outputs chain matrices split into
# independent/dependent levels.
#
# Inputs (env vars):
#   VERSIONS_JSON  — JSON object: { "package-id": "version-string", ... }
#   MARKERS_LIST   — Newline-separated list of existing success-* cache keys
#   FORCE          — "true" to force rebuild all
#   GITHUB_OUTPUT  — Path to GitHub Actions output file
#
# Outputs (to $GITHUB_OUTPUT):
#   chain_1_ind .. chain_4_ind  — Independent packages per chain
#   chain_1_dep .. chain_4_dep  — Dependent packages per chain
#   aggregators                 — Aggregator packages (need all chains)
#   any_build                   — "true" if at least one package needs building
#   versions_json               — Aggregated versions for save-trackers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse packages.yml only (no emulators.yml, no devices.yml)
PKGS_JSON=$(yq -o=json '.packages' "$ROOT_DIR/packages.yml")

# Single node configuration — hardcoded for AlmaBuilder
# TODO: Extract to nodes.yml if multi-node support is needed later
NODE_ID="almabuilder"
NODE_ARCH="x86_64"
NODE_RUNNER="ubuntu-latest"
NODE_PLATFORM="linux/amd64"
NODE_CFLAGS=""
NODE_CXXFLAGS=""
NODE_SOURCE_DISTRO="almalinux-10"

pkg_count=$(echo "$PKGS_JSON" | jq 'length')

# --- Step 1: Compute hashes (build script + package config entry) ---
HASHES="{}"
for (( i=0; i<pkg_count; i++ )); do
  pkg_id=$(echo "$PKGS_JSON" | jq -r ".[$i].id")
  base_dir=$(echo "$PKGS_JSON" | jq -r '._base_dir // "packages"')
  script_path="$ROOT_DIR/$base_dir/$pkg_id/build.sh"
  config_entry=$(echo "$PKGS_JSON" | jq -c ".[$i]")
  if [[ -f "$script_path" ]]; then
    hash=$(cat "$script_path" <(echo -n "$config_entry") | sha256sum | cut -d' ' -f1)
  else
    hash=$(echo -n "$config_entry" | sha256sum | cut -d' ' -f1)
  fi
  HASHES=$(echo "$HASHES" | jq --arg id "$pkg_id" --arg h "$hash" '. + {($id): $h}')
  echo "hash_${pkg_id//-/_}=$hash" >> "$GITHUB_OUTPUT"
done

# --- Step 2: Decide build/skip per package ---
BUILDS="{}"
for (( i=0; i<pkg_count; i++ )); do
  pkg_id=$(echo "$PKGS_JSON" | jq -r ".[$i].id")
  version_source=$(echo "$PKGS_JSON" | jq -r ".[$i].version_source")
  tracker_file=$(echo "$PKGS_JSON" | jq -r ".[$i].tracker_file // empty")
  hash=$(echo "$HASHES" | jq -r ".\"$pkg_id\"")

  # Get version from VERSIONS_JSON
  version=""
  short=""
  if [[ -n "${VERSIONS_JSON:-}" ]] && [[ "$version_source" != "hash-only" ]]; then
    version=$(echo "$VERSIONS_JSON" | jq -r ".\"$pkg_id\" // empty")
    if [[ "$version_source" == "github-commit" ]]; then
      short="${version:0:7}"
    fi
  fi

  # Output version for save-trackers
  if [[ -n "$version" ]]; then
    echo "version_${pkg_id//-/_}=$version" >> "$GITHUB_OUTPUT"
    if [[ -n "$short" ]]; then
      echo "short_${pkg_id//-/_}=$short" >> "$GITHUB_OUTPUT"
    fi
  fi

  # Check if version changed (applies to all targets equally)
  ver_changed="false"
  if [[ -n "$tracker_file" ]] && [[ -n "$version" ]]; then
    current=$(cat "$ROOT_DIR/.trackers/$tracker_file" 2>/dev/null || echo "")
    if [[ "$version" != "$current" ]]; then
      ver_changed="true"
    fi
  fi

  # Package-level flag: always true at this stage. The real per-target skip
  # decision happens in step 4, which checks the exact marker
  # success-<pkg>-<target>-<hash> for each (pkg, target) pair.
  BUILDS=$(echo "$BUILDS" | jq --arg id "$pkg_id" '. + {($id): true}')
  echo "  $pkg_id: CONSIDER (force=${FORCE:-false} ver_changed=$ver_changed)"
done

# --- Step 2b: If a dependent package needs building, force its deps too ---
changed="true"
while [[ "$changed" == "true" ]]; do
  changed="false"
  for (( i=0; i<pkg_count; i++ )); do
    pkg_id=$(echo "$PKGS_JSON" | jq -r ".[$i].id")
    should_build=$(echo "$BUILDS" | jq -r ".\"$pkg_id\"")
    [[ "$should_build" != "true" ]] && continue

    deps=$(echo "$PKGS_JSON" | jq -r ".[$i].depends_on // [] | .[]")
    for dep_id in $deps; do
      dep_build=$(echo "$BUILDS" | jq -r ".\"$dep_id\"")
      if [[ "$dep_build" != "true" ]]; then
        BUILDS=$(echo "$BUILDS" | jq --arg id "$dep_id" '. + {($id): true}')
        echo "  $dep_id: BUILD (required by $pkg_id)"
        changed="true"
      fi
    done
  done
done

# --- Step 3: Assign packages to 4 chains using build_time bin-packing ---
# 4 chains × max-parallel 3 = 12 concurrent jobs
# Each chain has 2 levels: ind (independent) and dep (dependent)
# Aggregators run after all chains complete
NUM_CHAINS=4

CHAINS="{}"  # package_id → chain number (1-4, or 0 for aggregators)
LEVELS="{}"  # package_id → "ind" | "dep" | "agg"

# Initialize chain loads
declare -a CHAIN_LOADS
for (( c=0; c<NUM_CHAINS; c++ )); do
  CHAIN_LOADS[$c]=0
done

# Sort packages by build_time descending for greedy bin-packing
SORTED=$(echo "$PKGS_JSON" | jq -r '
  [range(length) as $i | {idx: $i, id: .[$i].id, bt: (.[$i].build_time // 30)}]
  | sort_by(-.bt)
  | .[] | "\(.idx) \(.id) \(.bt)"')

# Pass 1: Bin-pack independent packages (no depends_on, not aggregator)
while IFS=' ' read -r idx pkg_id build_time; do
  [[ -z "$pkg_id" ]] && continue
  should_build=$(echo "$BUILDS" | jq -r ".\"$pkg_id\"")
  [[ "$should_build" != "true" ]] && continue
  dep_count=$(echo "$PKGS_JSON" | jq ".[$idx].depends_on // [] | length")
  [[ "$dep_count" -ne 0 ]] && continue
  is_agg=$(echo "$PKGS_JSON" | jq -r ".[$idx].is_aggregator // false")
  [[ "$is_agg" == "true" ]] && continue

  # Find chain with lowest load
  best=0
  for (( c=1; c<NUM_CHAINS; c++ )); do
    (( CHAIN_LOADS[c] < CHAIN_LOADS[best] )) && best=$c
  done

  CHAINS=$(echo "$CHAINS" | jq --arg id "$pkg_id" --argjson c "$(( best + 1 ))" '. + {($id): $c}')
  LEVELS=$(echo "$LEVELS" | jq --arg id "$pkg_id" '. + {($id): "ind"}')
  CHAIN_LOADS[$best]=$(( CHAIN_LOADS[best] + build_time ))
done <<< "$SORTED"

# Pass 2: Assign dependent packages (non-aggregator) to same chain as first dependency
while IFS=' ' read -r idx pkg_id build_time; do
  [[ -z "$pkg_id" ]] && continue
  should_build=$(echo "$BUILDS" | jq -r ".\"$pkg_id\"")
  [[ "$should_build" != "true" ]] && continue
  deps=$(echo "$PKGS_JSON" | jq -c ".[$idx].depends_on // []")
  dep_count=$(echo "$deps" | jq 'length')
  [[ "$dep_count" -eq 0 ]] && continue
  is_agg=$(echo "$PKGS_JSON" | jq -r ".[$idx].is_aggregator // false")
  [[ "$is_agg" == "true" ]] && continue

  # Assign to same chain as first dependency
  first_dep=$(echo "$deps" | jq -r '.[0]')
  chain=$(echo "$CHAINS" | jq -r ".\"$first_dep\" // 1")

  CHAINS=$(echo "$CHAINS" | jq --arg id "$pkg_id" --argjson c "$chain" '. + {($id): $c}')
  LEVELS=$(echo "$LEVELS" | jq --arg id "$pkg_id" '. + {($id): "dep"}')
  CHAIN_LOADS[$((chain - 1))]=$(( CHAIN_LOADS[chain - 1] + build_time ))
done <<< "$SORTED"

# Pass 3: Aggregators (depend on entries across all chains)
while IFS=' ' read -r idx pkg_id build_time; do
  [[ -z "$pkg_id" ]] && continue
  should_build=$(echo "$BUILDS" | jq -r ".\"$pkg_id\"")
  [[ "$should_build" != "true" ]] && continue
  is_agg=$(echo "$PKGS_JSON" | jq -r ".[$idx].is_aggregator // false")
  [[ "$is_agg" != "true" ]] && continue

  CHAINS=$(echo "$CHAINS" | jq --arg id "$pkg_id" '. + {($id): 0}')
  LEVELS=$(echo "$LEVELS" | jq --arg id "$pkg_id" '. + {($id): "agg"}')
done <<< "$SORTED"

echo "Chain load distribution:"
for (( c=0; c<NUM_CHAINS; c++ )); do
  echo "  Chain $(( c + 1 )): ${CHAIN_LOADS[$c]} minutes"
done

# --- Step 4: Build matrix entries, accumulate into ALL_ENTRIES with chain/level fields ---
ALL_ENTRIES="[]"

# Start the build-matrix report in $GITHUB_STEP_SUMMARY.
source "$SCRIPT_DIR/report.sh"
report_section "Build matrix"
report_table "Package" "Target" "Status" "Reason" "Version"
report_build_count=0
report_skip_marker=0

# Single node: iterate packages once (no multi-device, no multi-arch)
TARGET_ID="$NODE_ID"
TARGET_ARCH="$NODE_ARCH"
TARGET_RUNNER="$NODE_RUNNER"
TARGET_PLATFORM="$NODE_PLATFORM"
TARGET_CFLAGS="$NODE_CFLAGS"
TARGET_CXXFLAGS="$NODE_CXXFLAGS"
TARGET_SOURCE_DISTRO="$NODE_SOURCE_DISTRO"

for (( i=0; i<pkg_count; i++ )); do
  pkg_id=$(echo "$PKGS_JSON" | jq -r ".[$i].id")

  should_build=$(echo "$BUILDS" | jq -r ".\"$pkg_id\"")
  if [[ "$should_build" != "true" ]]; then
    continue
  fi

  chain=$(echo "$CHAINS" | jq -r ".\"$pkg_id\" // 1")
  level=$(echo "$LEVELS" | jq -r ".\"$pkg_id\" // \"ind\"")
  pkg_data=$(echo "$PKGS_JSON" | jq -c ".[$i]")
  base_dir=$(echo "$pkg_data" | jq -r '._base_dir // "packages"')
  artifact_type=$(echo "$pkg_data" | jq -r '.artifact_type // "pkg"')
  is_aggregator=$(echo "$pkg_data" | jq -r '.is_aggregator // false')
  noarch_single_build=$(echo "$pkg_data" | jq -r '.noarch_single_build // false')
  extra_cache_key=$(echo "$pkg_data" | jq -r '.extra_caches[0].key // empty')
  extra_cache_path=$(echo "$pkg_data" | jq -r '.extra_caches[0].path // empty')
  extra_cache_mount=$(echo "$pkg_data" | jq -r '.extra_caches[0].mount // empty')
  extra_cache_save=$(echo "$pkg_data" | jq -r '.extra_caches[0].save // false')
  hash=$(echo "$HASHES" | jq -r ".\"$pkg_id\"")

  # Get version info
  version=""
  short=""
  if [[ -n "${VERSIONS_JSON:-}" ]]; then
    version=$(echo "$VERSIONS_JSON" | jq -r ".\"$pkg_id\" // empty")
    version_source=$(echo "$pkg_data" | jq -r '.version_source')
    if [[ "$version_source" == "github-commit" ]]; then
      short="${version:0:7}"
    fi
  fi
  # For hash-only packages use the first 7 chars of the build hash
  version_source=$(echo "$pkg_data" | jq -r '.version_source')
  if [[ "$version_source" == "hash-only" ]]; then
    version_short="${hash:0:7}"
  else
    version_short="${short:-$version}"
  fi

  # Skip this target if it already has a success marker for the exact
  # (pkg, target, hash) triple — unless forced / version changed.
  if [[ "${FORCE:-false}" != "true" ]] && [[ "$ver_changed" != "true" ]]; then
    per_target_marker="success-${pkg_id}-${TARGET_ID}-${hash}"
    if echo "${MARKERS_LIST:-}" | grep -qF "$per_target_marker"; then
      echo "  SKIP $pkg_id on $TARGET_ID (marker exists: $per_target_marker)"
      report_row "CACHED" "$pkg_id" "$TARGET_ID" "marker already present" "${version:-${hash:0:7}}"
      report_skip_marker=$((report_skip_marker+1))
      continue
    fi
  fi

  # Resolve placeholders in extra_caches key
  resolved_cache_key=""
  if [[ -n "$extra_cache_key" ]]; then
    resolved_cache_key="${extra_cache_key//\{arch\}/$TARGET_ARCH}"
    resolved_cache_key="${resolved_cache_key//\{target_id\}/$TARGET_ID}"
  fi

  # Build JSON entry — single target (almabuilder/x86_64)
  entry=$(jq -n -c \
    --arg pkg_id "$pkg_id" \
    --arg base_dir "$base_dir" \
    --arg version "$version" \
    --arg version_short "$version_short" \
    --arg hash "$hash" \
    --argjson chain "$chain" \
    --arg level "$level" \
    --arg artifact_type "$artifact_type" \
    --arg is_aggregator "$is_aggregator" \
    --arg noarch_single_build "$noarch_single_build" \
    --arg extra_cache_key "$resolved_cache_key" \
    --arg extra_cache_path "$extra_cache_path" \
    --arg extra_cache_mount "$extra_cache_mount" \
    --arg extra_cache_save "$extra_cache_save" \
    --arg fallback_run_id "" \
    --arg target_id "$TARGET_ID" \
    --arg target_arch "$TARGET_ARCH" \
    --arg target_runner "$TARGET_RUNNER" \
    --arg target_platform "$TARGET_PLATFORM" \
    --arg target_cflags "$TARGET_CFLAGS" \
    --arg target_cxxflags "$TARGET_CXXFLAGS" \
    --arg target_source_distro "$TARGET_SOURCE_DISTRO" \
    --arg target_devices "$NODE_ID" \
    '{
      package_id: $pkg_id,
      base_dir: $base_dir,
      target_id: $target_id,
      target_arch: $target_arch,
      target_runner: $target_runner,
      target_platform: $target_platform,
      target_cflags: $target_cflags,
      target_cxxflags: $target_cxxflags,
      target_source_distro: $target_source_distro,
      target_devices: $target_devices,
      version: $version,
      version_short: $version_short,
      hash: $hash,
      chain: $chain,
      level: $level,
      artifact_type: $artifact_type,
      is_aggregator: $is_aggregator,
      noarch_single_build: $noarch_single_build,
      extra_cache_key: $extra_cache_key,
      extra_cache_path: $extra_cache_path,
      extra_cache_mount: $extra_cache_mount,
      extra_cache_save: $extra_cache_save,
      fallback_run_id: $fallback_run_id
    }')

  ALL_ENTRIES=$(echo "$ALL_ENTRIES" | jq --argjson e "$entry" '. + [$e]')
  report_row "BUILT" "$pkg_id" "$TARGET_ID" "queued for build" "${version:-${hash:0:7}}"
  report_build_count=$((report_build_count+1))
done

# Footer
report_table_end
report_counts "Queued: $report_build_count · Cached (marker): $report_skip_marker"

# --- Step 5: Split by chain+level and output ---
any_build="false"
for chain_num in 1 2 3 4; do
  for level in ind dep; do
    chain_json=$(echo "$ALL_ENTRIES" | jq -c \
      --argjson c "$chain_num" --arg l "$level" \
      '[.[] | select(.chain == $c and .level == $l) | del(.chain, .level)]')
    count=$(echo "$chain_json" | jq 'length')
    echo "chain_${chain_num}_${level}=${chain_json}" >> "$GITHUB_OUTPUT"
    echo "Chain ${chain_num} ${level}: $count entries"
    if (( count > 0 )); then
      any_build="true"
    fi
  done
done

# Aggregators
agg_json=$(echo "$ALL_ENTRIES" | jq -c '[.[] | select(.level == "agg") | del(.chain, .level)]')
agg_count=$(echo "$agg_json" | jq 'length')
echo "aggregators=${agg_json}" >> "$GITHUB_OUTPUT"
echo "Aggregators: $agg_count entries"
if (( agg_count > 0 )); then
  any_build="true"
fi

# Output aggregated versions JSON for downstream jobs (save-trackers)
echo "versions_json=$(echo "${VERSIONS_JSON:-\{\}}" | jq -c '.')" >> "$GITHUB_OUTPUT"

echo "any_build=$any_build" >> "$GITHUB_OUTPUT"
echo "=== Done: any_build=$any_build ==="