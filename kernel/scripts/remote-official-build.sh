#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
source_root="$DUO_KERNEL_ROOT"
profile="${1:-official-baseline}"
mode="${2:-clean}"
[[ "$profile" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
  echo "invalid build profile: $profile" >&2
  exit 2
}
[[ "$mode" == clean || "$mode" == reuse ]] || {
  echo "mode must be clean or reuse" >&2
  exit 2
}
output_root="$source_root/out/$profile"
dist_root="$source_root/dist/$profile"
builder_image=${DUO_BUILDER_IMAGE:-duo-kernel-builder:ubuntu20}

if [[ "$mode" == clean ]]; then
  [[ "$output_root" == "$source_root/out/"* ]]
  [[ "$dist_root" == "$source_root/dist/"* ]]
  rm -rf "$output_root" "$dist_root"
fi
mkdir -p "$output_root" "$dist_root" "$source_root/.ccache"

docker_environment=()
if [[ "$mode" == reuse ]]; then
  docker_environment+=(--env SKIP_MRPROPER=1 --env SKIP_DEFCONFIG=1)
fi

docker run --rm \
  --user "$(id -u):$(id -g)" \
  --workdir /workspace/source \
  --volume "$source_root:/workspace/source" \
  --env BUILD_CONFIG=./kernel/msm-4.14/build.config.perf-config \
  --env KERNEL_DEFCONFIG=surfaceduo-perf_defconfig \
  --env OUT_DIR="/workspace/source/out/$profile" \
  --env DIST_DIR="/workspace/source/dist/$profile" \
  --env CCACHE_DIR=/workspace/source/.ccache \
  --env CCACHE_EXEC=/usr/bin/ccache --env USE_CCACHE=1 \
  "${docker_environment[@]}" \
  "$builder_image" \
  bash build/build.sh

find "$dist_root" -maxdepth 1 -type f -printf '%f %s bytes\n' | sort
