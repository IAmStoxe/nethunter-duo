#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
source_root="$DUO_KERNEL_ROOT"
profile="${1:-official-baseline}"
output_config="$source_root/out/$profile/kernel/msm-4.14/.config"
perf_config="$output_config.microsoft-perf"

if [[ ! -f "$output_config" ]]; then
  printf 'Existing build config not found: %s\n' "$output_config" >&2
  exit 1
fi

if [[ ! -f "$perf_config" ]]; then
  cp "$output_config" "$perf_config"
fi
cp "$perf_config" "$output_config"

config_tool="$source_root/kernel/msm-4.14/scripts/config"
for option in \
  DEBUG_FS IPA_UT MODULE_SIG_FORCE MSM_IDLE_STATS MSM_TZ_LOG PAGE_EXTENSION PAGE_OWNER QTI_RPM_STATS_LOG
do
  "$config_tool" --file "$output_config" -d "$option"
done

docker run --rm \
  --user "$(id -u):$(id -g)" \
  --workdir /workspace/source \
  --volume "$source_root:/workspace/source" \
  duo-kernel-builder:ubuntu20 \
  make -C kernel/msm-4.14 \
    O="/workspace/source/out/$profile/kernel/msm-4.14" \
    ARCH=arm64 olddefconfig

printf 'Applied stock-performance and custom-module trust-policy delta to %s\n' "$output_config"
