#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 STOCK_MODULE_DIR MICROSOFT_MODULE_SYMVERS FEATURE_MODULE_SYMVERS" >&2
  exit 2
fi

module_dir=$1
stock_symvers=$2
feature_symvers=$3

for path in "$module_dir" "$stock_symvers" "$feature_symvers"; do
  if [[ ! -e "$path" ]]; then
    echo "missing input: $path" >&2
    exit 2
  fi
done

command -v modprobe >/dev/null || {
  echo "modprobe is required (install package kmod)" >&2
  exit 2
}

work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT

requirements=$work_dir/requirements.tsv
stock_exports=$work_dir/stock-exports.tsv
feature_exports=$work_dir/feature-exports.tsv

find "$module_dir" -type f -name '*.ko' -print0 |
  while IFS= read -r -d '' module; do
    modprobe --dump-modversions "$module" |
      awk -v module="${module#"$module_dir"/}" '{ print module "\t" $2 "\t" tolower($1) }'
  done >"$requirements"

awk 'NF >= 2 { print $2 "\t" tolower($1) }' "$stock_symvers" |
  sort -u >"$stock_exports"
awk 'NF >= 2 { print $2 "\t" tolower($1) }' "$feature_symvers" |
  sort -u >"$feature_exports"

awk -F '\t' '
  BEGIN {
    vendor_dependency = 0
    kernel_requirements = 0
    matched = 0
    missing = 0
    mismatch = 0
  }
  FILENAME == ARGV[1] { stock[$1] = $2; next }
  FILENAME == ARGV[2] { feature[$1] = $2; next }
  {
    module = $1; symbol = $2; required = $3
    if (!(symbol in stock)) {
      vendor_dependency++
      next
    }
    kernel_requirements++
    if (!(symbol in feature)) {
      print "MISSING\t" module "\t" symbol "\tstock=" stock[symbol]
      missing++
    } else if (feature[symbol] != required) {
      print "MISMATCH\t" module "\t" symbol "\trequired=" required "\tfeature=" feature[symbol] "\tstock=" stock[symbol]
      mismatch++
    } else {
      matched++
    }
  }
  END {
    print "SUMMARY\tkernel_requirements=" kernel_requirements \
          "\tmatched=" matched \
          "\tmismatched=" mismatch \
          "\tmissing=" missing \
          "\tvendor_module_dependencies=" vendor_dependency
    if (mismatch || missing) exit 1
  }
' "$stock_exports" "$feature_exports" "$requirements"
