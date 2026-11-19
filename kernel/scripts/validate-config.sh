#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
root="$DUO_KERNEL_ROOT"
project="$DUO_PROJECT_ROOT"
kernel="$root/kernel/msm-4.14"
out="$root/out/config-check"
fragment="${DUO_FEATURE_CONFIG:-$project/kernel/config/nethunter-duo.config}"
if [[ ! -f "$fragment" ]]; then
  fragment="$root/kernel/config/nethunter-duo.config"
fi
local_fragment="$out/nethunter-duo.config"

test -d "$kernel"
test -f "$fragment"

mkdir -p "$out"
cp "$fragment" "$local_fragment"
make -C "$kernel" O="$out" ARCH=arm64 PYTHON=python3 \
  vendor/surfaceduo-perf_defconfig
"$kernel/scripts/kconfig/merge_config.sh" -m -O "$out" \
  "$out/.config" "$local_fragment"
make -C "$kernel" O="$out" ARCH=arm64 PYTHON=python3 olddefconfig

failed=0
while IFS= read -r requested; do
  symbol="${requested%%=*}"
  actual="$(grep -E "^${symbol}=|^# ${symbol} is not set$" "$out/.config" || true)"
  if [[ "$actual" != "$requested" ]]; then
    printf 'MISMATCH requested=%s actual=%s\n' "$requested" "${actual:-missing}"
    failed=1
  fi
done < <(grep -E '^CONFIG_[A-Za-z0-9_]+=' "$fragment")

if (( failed )); then
  printf '\nConfig validation failed. Unsupported or dependency-altered symbols are listed above.\n' >&2
  exit 1
fi

printf 'Validated %s requested settings.\n' "$(grep -c -E '^CONFIG_[A-Za-z0-9_]+=' "$fragment")"
printf 'Merged config: %s\n' "$out/.config"
