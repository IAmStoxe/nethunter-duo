#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
source_root="$DUO_KERNEL_ROOT"
project_root="$DUO_PROJECT_ROOT"
profile="${1:-field}"
builder_image=${DUO_BUILDER_IMAGE:-duo-kernel-builder:ubuntu20}
mkdir -p "$source_root/out/$profile"

docker run --rm \
  --user "$(id -u):$(id -g)" \
  --workdir "/workspace/source/out/$profile" \
  --volume "$source_root:/workspace/source" \
  --volume "$project_root:/workspace/project:ro" \
  --env DUO_KERNEL_ROOT=/workspace/source \
  --env DUO_PROJECT_ROOT=/workspace/project \
  "$builder_image" \
  bash /workspace/project/kernel/scripts/build-kernel.sh "$@"
