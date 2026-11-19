#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
root="$DUO_KERNEL_ROOT"
kernel="$root/kernel/msm-4.14"
out="$root/out/baseline"
cross64="$root/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-"
cross32="$root/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-"

make -s -C "$kernel" O="$out" ARCH=arm64 PYTHON=python2 \
  REAL_CC=/usr/bin/clang CLANG_TRIPLE=aarch64-linux-gnu- \
  CROSS_COMPILE="$cross64" CROSS_COMPILE_ARM32="$cross32" \
  --eval='print-duo-vars: ; @echo "CC=$(CC)"; echo "CC_NAME=$(cc-name)"; echo "CLANG_FLAGS=$(CLANG_FLAGS)"; echo "KBUILD_CPPFLAGS=$(KBUILD_CPPFLAGS)"; echo "CC_OPTION_CFLAGS=$(CC_OPTION_CFLAGS)"; echo "KBUILD_CFLAGS=$(KBUILD_CFLAGS)"' \
  print-duo-vars
