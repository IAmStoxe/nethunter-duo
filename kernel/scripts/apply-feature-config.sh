#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
source_root="$DUO_KERNEL_ROOT"
profile="${1:-official-baseline}"
output_config="$source_root/out/$profile/kernel/msm-4.14/.config"
fragment="${DUO_FEATURE_CONFIG:-$source_root/kernel/config/nethunter-duo.config}"
kernel="$source_root/kernel/msm-4.14"

"$source_root/kernel/scripts/apply-stock-config.sh" "$profile"
test -f "$fragment"

"$kernel/scripts/kconfig/merge_config.sh" -m -O "$(dirname "$output_config")" \
  "$output_config" "$fragment"

docker run --rm \
  --user "$(id -u):$(id -g)" \
  --workdir /workspace/source \
  --volume "$source_root:/workspace/source" \
  duo-kernel-builder:ubuntu20 \
  make -C kernel/msm-4.14 \
    O="/workspace/source/out/$profile/kernel/msm-4.14" \
    ARCH=arm64 olddefconfig

failed=0
while IFS= read -r requested; do
  symbol="${requested%%=*}"
  actual="$(grep -E "^${symbol}=|^# ${symbol} is not set$" "$output_config" || true)"
  if [[ "$actual" != "$requested" ]]; then
    printf 'MISMATCH requested=%s actual=%s\n' "$requested" "${actual:-missing}"
    failed=1
  fi
done < <(grep -E '^CONFIG_[A-Za-z0-9_]+=' "$fragment")

grep -q '^# CONFIG_MODULE_SIG_FORCE is not set$' "$output_config"
grep -q '^CONFIG_MODVERSIONS=y$' "$output_config"

if (( failed )); then
  printf 'Feature config validation failed.\n' >&2
  exit 1
fi

printf 'Applied and validated %s feature settings in %s\n' \
  "$(grep -c -E '^CONFIG_[A-Za-z0-9_]+=' "$fragment")" "$output_config"
