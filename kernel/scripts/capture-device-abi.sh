#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 EMPTY_DESTINATION" >&2
  exit 2
fi

destination=$1
if [[ -e "$destination" ]] && find "$destination" -mindepth 1 -print -quit | grep -q .; then
  echo "destination must be empty: $destination" >&2
  exit 1
fi

command -v adb >/dev/null
test "$(adb get-state 2>/dev/null)" = device

build=$(adb shell getprop ro.build.version.incremental | tr -d '\r')
if [[ "$build" != 202209020048 ]]; then
  printf 'Expected Surface Duo build 202209020048, found %s\n' "$build" >&2
  exit 1
fi

module_dir=$(adb shell 'for d in /vendor/lib/modules /vendor_dlkm/lib/modules; do [ -d "$d" ] && { echo "$d"; break; }; done' |
  tr -d '\r' | head -n 1)
case "$module_dir" in
  /vendor/lib/modules|/vendor_dlkm/lib/modules) ;;
  *) echo 'vendor module directory not found' >&2; exit 1 ;;
esac

mkdir -p "$destination/modules"
adb exec-out "su -c 'tar -C $module_dir -cf - .'" |
  tar -xf - -C "$destination/modules"
adb exec-out "su -c 'cat /proc/config.gz'" > "$destination/config.gz"
gzip -t "$destination/config.gz"

{
  printf 'build=%s\n' "$build"
  printf 'kernel='
  adb shell uname -r | tr -d '\r'
  printf 'module_dir=%s\n' "$module_dir"
  printf 'module_count=%s\n' "$(find "$destination/modules" -type f -name '*.ko' | wc -l)"
} > "$destination/device.txt"

cat "$destination/device.txt"
printf 'Private ABI inputs captured in %s\n' "$destination"
