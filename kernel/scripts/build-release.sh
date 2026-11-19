#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/_paths.sh"

if [[ $# -ne 2 ]]; then
  cat >&2 <<'EOF'
usage: build-release.sh STOCK_CONFIG_GZ STOCK_MODULE_DIRECTORY

Build a cached ABI reference and the complete technician profile, prove the
candidate against the live OTA modules, and stage an Android module payload.
Run capture-device-abi.sh first to obtain the two private inputs.
EOF
  exit 2
fi

stock_config=$(realpath -- "$1")
stock_modules=$(realpath -- "$2")
test -r "$stock_config"
test -d "$stock_modules"
gzip -t "$stock_config"

"$script_dir/docker-build.sh" image
"$script_dir/docker-build.sh" sources

DUO_BUILD_PROFILE=abi-stock \
  "$script_dir/docker-build.sh" technician \
    "$stock_config" \
    "$DUO_PROJECT_ROOT/kernel/config/technician-peripherals.config"

DUO_BUILD_PROFILE=technician-full DUO_BUILD_EXT_MODULES=1 \
  "$script_dir/docker-build.sh" technician \
    "$stock_config" \
    "$DUO_PROJECT_ROOT/kernel/config/technician-peripherals.config" \
    "$DUO_PROJECT_ROOT/kernel/config/technician-extended.config" \
    "$DUO_PROJECT_ROOT/kernel/config/nethunter-radio.config" \
    "$DUO_PROJECT_ROOT/kernel/config/nethunter-can.config"

reference_symvers="$DUO_KERNEL_ROOT/out/abi-stock/kernel/msm-4.14/Module.symvers"
candidate_out="$DUO_KERNEL_ROOT/out/technician-full/kernel/msm-4.14"
candidate_symvers="$candidate_out/Module.symvers"
audit="$DUO_KERNEL_ROOT/dist/technician-full/stock-module-abi.txt"

"$script_dir/audit-stock-module-abi.sh" \
  "$stock_modules" "$reference_symvers" "$candidate_symvers" | tee "$audit"
grep -Eq $'^SUMMARY\t.*\tmismatched=0\tmissing=0(\t|$)' "$audit"

wlan_module="$DUO_KERNEL_ROOT/dist/technician-full/wlan.ko"
test -s "$wlan_module"
wlan_audit_dir=$(mktemp -d)
trap 'rm -rf -- "$wlan_audit_dir"' EXIT
cp -- "$wlan_module" "$wlan_audit_dir/"
"$script_dir/audit-stock-module-abi.sh" \
  "$wlan_audit_dir" "$reference_symvers" "$candidate_symvers" |
  tee "$DUO_KERNEL_ROOT/dist/technician-full/wlan-module-abi.txt"
grep -Eq $'^SUMMARY\t.*\tmismatched=0\tmissing=0(\t|$)' \
  "$DUO_KERNEL_ROOT/dist/technician-full/wlan-module-abi.txt"

image_hash=$(sha256sum "$candidate_out/arch/arm64/boot/Image" | awk '{print $1}')
payload="$DUO_KERNEL_ROOT/dist/technician-full/module-payload-${image_hash:0:12}"
if [[ -d "$payload" ]]; then
  grep -Fxq "image_sha256=$image_hash" "$payload/build-info"
  (
    cd "$payload/modules"
    sha256sum --check --strict ../modules.sha256 >/dev/null
  )
  printf 'Reusing verified module payload %s\n' "$payload"
else
  "$script_dir/stage-module-payload.sh" "$candidate_out" "$payload"
fi
cp -- "$wlan_module" "$payload/wlan-injection.ko"
(
  cd "$payload"
  sha256sum -- wlan-injection.ko > wlan-injection.sha256
)

printf '\nRelease candidate passed the stock-module ABI gate.\n'
printf 'Image:   %s\n' "$candidate_out/arch/arm64/boot/Image"
printf 'SHA-256: %s\n' "$image_hash"
printf 'Modules: %s\n' "$payload"
printf 'Count:   %s\n' "$(find "$payload/modules" -maxdepth 1 -type f -name '*.ko' | wc -l)"
printf 'WLAN:    %s\n' "$payload/wlan-injection.ko"
printf 'Audit:   %s\n' "$audit"
