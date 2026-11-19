#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
root="$DUO_KERNEL_ROOT"
cache="$DUO_DOWNLOAD_CACHE"
destination="$root/proprietary/llvm-arm-toolchain-ship/8.0"
filename=snapdragon-llvm-8.0.6-linux64.tar.gz
expected_sha256=8dcd0979171fd71b8aa477543a6a434834d848e2231e012b6f459e87d3d26b9e

verify_compiler() {
  local version
  version=$("$destination/bin/clang" --version)
  grep -Fq 'Snapdragon LLVM ARM Compiler 8.0.6' <<< "$version"
  printf '%s\n' "$version"
}

if [[ -x "$destination/bin/clang" ]]; then
  verify_compiler
  exit 0
fi

archive=${1:-${DUO_SNAPDRAGON_LLVM_ARCHIVE:-}}
if [[ -z "$archive" && -s "$cache/$filename" ]]; then
  archive="$cache/$filename"
fi
if [[ -z "$archive" || ! -s "$archive" ]]; then
  cat >&2 <<EOF
Snapdragon LLVM for Android 8.0.6 is required but was not found.

Download $filename from Qualcomm using Microsoft's official Surface Duo kernel
instructions, then set DUO_SNAPDRAGON_LLVM_ARCHIVE or pass the archive path to:

  kernel/scripts/docker-build.sh sources /path/to/$filename

Microsoft instructions:
https://github.com/microsoft/surface-duo-oss/blob/main/surfaceduo/kernel.md
EOF
  exit 2
fi

archive=$(realpath -- "$archive")
printf '%s  %s\n' "$expected_sha256" "$archive" | sha256sum --check --strict -

mkdir -p "$cache" "$destination"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT
tar -xzf "$archive" -C "$temp_dir"
clang_path="$(find "$temp_dir" -path '*/prebuilt/linux-x86_64/bin/clang' -print -quit)"
if [[ -z "$clang_path" ]]; then
  printf 'Could not find the expected prebuilt bin/clang in %s\n' "$archive" >&2
  exit 1
fi
toolchain_root="${clang_path%/bin/clang}"
cp -a "$toolchain_root"/. "$destination"/

verify_compiler
