#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

go build -trimpath -o "$work/hid-type" "$script_dir/hid-type.go"
go build -trimpath -o "$work/hid-pointer" "$script_dir/hid-pointer.go"

: > "$work/keyboard"
DUO_HID_KEYBOARD="$work/keyboard" "$work/hid-type" --key CTRL+ALT+T
keyboard_hex="$(od -An -tx1 -v "$work/keyboard" | tr -d ' \n')"
test "$keyboard_hex" = 05001700000000000000000000000000

: > "$work/pointer"
DUO_HID_POINTER="$work/pointer" "$work/hid-pointer" move -24 0
pointer_hex="$(od -An -tx1 -v "$work/pointer" | tr -d ' \n')"
test "$pointer_hex" = 00e8000000000000

: > "$work/pointer"
DUO_HID_POINTER="$work/pointer" "$work/hid-pointer" click right
pointer_hex="$(od -An -tx1 -v "$work/pointer" | tr -d ' \n')"
test "$pointer_hex" = 0200000000000000

if DUO_HID_KEYBOARD="$work/keyboard" "$work/hid-type" --key CTRL+ALT >/dev/null 2>&1; then
  echo 'modifier-only HID combo was incorrectly accepted' >&2
  exit 1
fi

CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
  go build -trimpath -o "$work/hid-type-arm64" "$script_dir/hid-type.go"
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
  go build -trimpath -o "$work/hid-pointer-arm64" "$script_dir/hid-pointer.go"

echo 'HID helper report and ARM64 build tests passed.'
