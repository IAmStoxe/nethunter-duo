#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
qcacld_repo="$DUO_KERNEL_ROOT/vendor/qcom/opensource/wlan/qcacld-3.0"
host_cmn_repo="$DUO_KERNEL_ROOT/vendor/qcom/opensource/wlan/qca-wifi-host-cmn"
upstream_patch="$NETHUNTER_BUILDER_ROOT/patches/4.14/add-qcacld-3.0-injection-4.14.patch"

test -d "$qcacld_repo/.git"
test -d "$host_cmn_repo/.git"
test -f "$upstream_patch"

apply_once() {
  local repo=$1 patch=$2
  shift 2
  if git -C "$repo" apply --reverse --check "$@" "$patch" 2>/dev/null; then
    printf 'Patch already applied: %s\n' "$(basename "$patch")"
  else
    git -C "$repo" apply --check "$@" "$patch"
    git -C "$repo" apply "$@" "$patch"
    printf 'Applied patch: %s\n' "$(basename "$patch")"
  fi
}

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

filter_repo_patch() {
  local prefix=$1 output=$2
  awk -v prefix="diff --git a/$prefix/" '
    /^diff --git / {
      keep = index($0, prefix) == 1
      skip_hunk = 0
    }
    keep && /^@@ -6482,8 \+6544,7 / { skip_hunk = 1; next }
    keep && /^@@ -15629,20 \+15715,47 / { skip_hunk = 1; next }
    keep && /^@@ -16538,7 \+16665,6 / { skip_hunk = 1; next }
    keep && /^@@ -18180,4 \+18306,3 / { skip_hunk = 1; next }
    keep && skip_hunk && /^@@ / { skip_hunk = 0 }
    keep && !skip_hunk { print }
  ' "$upstream_patch" > "$output"
  test -s "$output"
}

filter_repo_patch 'drivers/staging/qcacld-3.0' "$work/qcacld.patch"
filter_repo_patch 'drivers/staging/qca-wifi-host-cmn' "$work/host-cmn.patch"

if [[ -f "$qcacld_repo/core/hdd/src/wlan_hdd_frame_inject.c" ]]; then
  printf 'Patch already applied: qcacld.patch\n'
else
  apply_once "$qcacld_repo" "$work/qcacld.patch" -p4
fi
apply_once "$qcacld_repo" \
  "$DUO_PROJECT_ROOT/kernel/patches/duo-qcacld-net-refcount.patch" --recount
apply_once "$qcacld_repo" \
  "$DUO_PROJECT_ROOT/kernel/patches/qcacld-injection-security-compat.patch" --recount
apply_once "$host_cmn_repo" "$work/host-cmn.patch" -p4
