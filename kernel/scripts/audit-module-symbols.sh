#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 MODULE.ko MODULE.symvers" >&2
  exit 2
fi

module=$1
symvers=$2
work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT

nm -u "$module" | awk '{ print $2 }' | sort -u > "$work_dir/undefined"
awk '{ print $2 }' "$symvers" | sort -u > "$work_dir/exports"
comm -23 "$work_dir/undefined" "$work_dir/exports" > "$work_dir/missing"

if [[ -s "$work_dir/missing" ]]; then
  echo "Unresolved symbols:" >&2
  cat "$work_dir/missing" >&2
  exit 1
fi

printf 'All %s undefined module references are exported by the target kernel.\n' \
  "$(wc -l < "$work_dir/undefined")"
