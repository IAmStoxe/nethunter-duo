#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
profile="${1:-field}"
action="${2:-build}"
root="$DUO_KERNEL_ROOT"
project="$DUO_PROJECT_ROOT"
kernel="$root/kernel/msm-4.14"
out="$root/out/$profile"
staging="$root/out/$profile-modules"

case "$profile" in
  baseline|field) ;;
  *) printf 'usage: %s [baseline|field] [config|build]\n' "$0" >&2; exit 2 ;;
esac
case "$action" in
  config|build) ;;
  *) printf 'usage: %s [baseline|field] [config|build]\n' "$0" >&2; exit 2 ;;
esac

cross64="$root/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-"
cross32="$root/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-"
fragment="$project/kernel/config/nethunter-duo.config"

test -x "${cross64}gcc"
test -x "${cross32}gcc"
test -x /usr/bin/clang
test -f "$fragment"

mkdir -p "$out" "$staging"

make_args=(
  -C "$kernel"
  O="$out"
  ARCH=arm64
  PYTHON=python2
  REAL_CC=/usr/bin/clang
  CLANG_TRIPLE=aarch64-linux-gnu-
  CROSS_COMPILE="$cross64"
  CROSS_COMPILE_ARM32="$cross32"
  KERNEL_DEFCONFIG=surfaceduo-perf_defconfig
  V="${V:-0}"
)

# Microsoft's retail/performance configuration is also what its version hook
# maps to the shipping "duo-p" suffix. KERNEL_DEFCONFIG above is required;
# selecting the make target alone does not inform scripts/setlocalversion.
make "${make_args[@]}" vendor/surfaceduo-perf_defconfig

if [[ "$profile" == field ]]; then
  cp "$fragment" "$out/nethunter-duo.config"
  "$kernel/scripts/kconfig/merge_config.sh" -m -O "$out" \
    "$out/.config" "$out/nethunter-duo.config"
  make "${make_args[@]}" olddefconfig
fi

if [[ "$action" == config ]]; then
  printf 'Configured: %s\n' "$out/.config"
  exit 0
fi

# The generic dtbs target also builds unrelated SA8155 automotive overlays.
# Duo boot testing preserves the stock DTB, so only build the kernel and the
# modules here. Duo-specific DTBs can be built explicitly when needed.
jobs="${JOBS:-$(nproc)}"
make -j"$jobs" "${make_args[@]}" Image modules
make -j"$jobs" "${make_args[@]}" \
  INSTALL_MOD_PATH="$staging" INSTALL_MOD_STRIP=1 modules_install

printf '\nKernel:  %s\n' "$out/arch/arm64/boot/Image"
printf 'Modules: %s\n' "$staging"
sha256sum "$out/arch/arm64/boot/Image"
