#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
source_root="$DUO_KERNEL_ROOT"
builder="$NETHUNTER_BUILDER_ROOT"
patch_root="$builder/patches/4.14"

apply_once() {
  local repo="$1"
  local patch="$2"
  shift 2

  if git -C "$repo" apply --reverse --check "$@" "$patch" 2>/dev/null; then
    printf 'Already applied: %s\n' "$(basename "$patch")"
    return
  fi

  git -C "$repo" apply --check "$@" "$patch"
  git -C "$repo" apply "$@" "$patch"
  printf 'Applied: %s\n' "$(basename "$patch")"
}

generic="$patch_root/add-wifi-injection-4.14.patch"
qcacld="$patch_root/add-qcacld-3.0-injection-4.14.patch"

test -f "$generic"
test -f "$qcacld"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

filter_repo_patch() {
  local prefix="$1"
  local output="$2"
  awk -v prefix="diff --git a/$prefix/" '
    /^diff --git / {
      keep = index($0, prefix) == 1
      skip_hunk = 0
    }
    keep && /^@@ -6482,8 \+6544,7 / {
      skip_hunk = 1
      next
    }
    keep && /^@@ -15629,20 \+15715,47 / {
      skip_hunk = 1
      next
    }
    keep && /^@@ -16538,7 \+16665,6 / {
      skip_hunk = 1
      next
    }
    keep && /^@@ -18180,4 \+18306,3 / {
      skip_hunk = 1
      next
    }
    keep && skip_hunk && /^@@ / { skip_hunk = 0 }
    keep && !skip_hunk { print }
  ' "$qcacld" > "$output"
  test -s "$output"
}

filter_repo_patch 'drivers/staging/qcacld-3.0' "$work/qcacld.patch"
filter_repo_patch 'drivers/staging/qca-wifi-host-cmn' "$work/host-cmn.patch"

apply_once "$source_root/kernel/msm-4.14" "$generic"
apply_once "$source_root/kernel/msm-4.14" \
  "$source_root/kernel/patches/can-peak-varargs.patch"
apply_once "$source_root/kernel/msm-4.14" \
  "$source_root/kernel/patches/ath6kl-parentheses.patch"
apply_once "$source_root/vendor/qcom/opensource/wlan/qcacld-3.0" "$work/qcacld.patch" -p4
apply_once "$source_root/vendor/qcom/opensource/wlan/qcacld-3.0" \
  "$source_root/kernel/patches/duo-qcacld-net-refcount.patch" --recount
apply_once "$source_root/vendor/qcom/opensource/wlan/qcacld-3.0" \
  "$source_root/kernel/patches/qcacld-injection-security-compat.patch" --recount
apply_once "$source_root/vendor/qcom/opensource/wlan/qca-wifi-host-cmn" "$work/host-cmn.patch" -p4
