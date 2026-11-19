#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 MODULE_SOURCE.tgz OUTPUT.zip" >&2
  exit 2
fi

source_archive=$1
output=$(realpath -m -- "$2")
work_dir=$(mktemp -d)
mkdir -p "$(dirname -- "$output")"
temporary_output=$(mktemp --tmpdir="$(dirname -- "$output")" ".$(basename -- "$output").XXXXXX")
trap 'rm -rf -- "$work_dir"; rm -f -- "$temporary_output"' EXIT
rm -f -- "$temporary_output"

tar -xzf "$source_archive" -C "$work_dir"
(
  cd "$work_dir"
  if command -v zip >/dev/null 2>&1; then
    zip -qr "$temporary_output" .
  elif command -v jar >/dev/null 2>&1; then
    jar cMf "$temporary_output" .
  else
    echo 'zip or a JDK jar command is required' >&2
    exit 2
  fi
)

entry_list="$work_dir/zip-entries.txt"
zipinfo -1 "$temporary_output" > "$entry_list"
if grep -q '\\' "$entry_list"; then
  echo "invalid Windows path separator in module ZIP" >&2
  exit 1
fi

grep -qx 'module.prop' "$entry_list"
grep -qx 'system/bin/duo-wifi' "$entry_list"
grep -qx 'system/bin/duo-usb' "$entry_list"
grep -qx 'payload/hid-pointer' "$entry_list"
grep -qx 'payload/wlan-injection.ko' "$entry_list"
grep -qx 'payload/wlan-injection.sha256' "$entry_list"
mv -f -- "$temporary_output" "$output"
