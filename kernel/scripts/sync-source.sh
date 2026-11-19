#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
root="$DUO_KERNEL_ROOT"

mkdir -p "$root"

clone_revision() {
  local url="$1"
  local path="$2"
  local revision="$3"
  if [[ -d "$root/$path/.git" ]]; then
    if [[ "$(git -C "$root/$path" rev-parse HEAD)" != "$revision" ]]; then
      git -C "$root/$path" fetch --depth 1 origin "$revision"
      git -C "$root/$path" checkout --detach "$revision"
    fi
    printf 'present  %s @ %s\n' "$path" "${revision:0:12}"
    return
  fi
  mkdir -p "$root/$path"
  git -C "$root/$path" init
  git -C "$root/$path" remote add origin "$url"
  git -C "$root/$path" fetch --depth 1 origin "$revision"
  git -C "$root/$path" checkout --detach "$revision"
}

clone_external_revision() {
  local url="$1"
  local path="$2"
  local revision="$3"
  if [[ -d "$path/.git" ]]; then
    if [[ "$(git -C "$path" rev-parse HEAD)" != "$revision" ]]; then
      git -C "$path" fetch --depth 1 origin "$revision"
      git -C "$path" checkout --detach "$revision"
    fi
    printf 'present  %s @ %s\n' "$path" "${revision:0:12}"
    return
  fi
  mkdir -p "$path"
  git -C "$path" init
  git -C "$path" remote add origin "$url"
  git -C "$path" fetch --depth 1 origin "$revision"
  git -C "$path" checkout --detach "$revision"
}

clone_revision 'https://github.com/microsoft/surface-duo-oss-kernel.build.git' \
  'build' '02c99909808bca5cf53c26fdbece13174245735c'
clone_revision 'https://github.com/microsoft/surface-duo-oss-kernel.msm-4..14.git' \
  'kernel/msm-4.14' 'ea2a9d14b73c1122c6c2d82fb39f0f11a293d9bf'
clone_revision 'https://github.com/microsoft/surface-duo-oss-platform.vendor.opensource.audio-kernel.git' \
  'vendor/qcom/opensource/audio-kernel' 'dfa4b4f5933ef01785b43b780a4e268091c3274c'
clone_revision 'https://github.com/microsoft/surface-duo-oss-platform.vendor.qcom-opensource.data-kernel.git' \
  'vendor/qcom/opensource/data-kernel' '1869a32cc9656af809f73f8d068668dab53fddcf'
clone_revision 'https://github.com/microsoft/surface-duo-oss-platform.vendor.qcom-opensource.wlan.qca-wifi-host-cmn.git' \
  'vendor/qcom/opensource/wlan/qca-wifi-host-cmn' 'cad7594173b2981a44bac37ba641988915207484'
clone_revision 'https://github.com/microsoft/surface-duo-oss-platform.vendor.qcom-opensource.wlan.qcacld-3..0.git' \
  'vendor/qcom/opensource/wlan/qcacld-3.0' '5c1caa2fa7bc8bdf1aa9524c67bbd84a50b6914d'
clone_revision 'https://github.com/microsoft/surface-duo-oss-platform.vendor.qcom-opensource.wlan.fw-api.git' \
  'vendor/qcom/opensource/wlan/fw-api' '24a9971cdf2f22be5ea3a50a4922889935e89044'

clone_revision 'https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9' \
  'prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9' \
  '961622e926a1b21382dba4dd9fe0e5fb3ee5ab7c'
clone_revision 'https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9' \
  'prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9' \
  'cb7b3ac1b7fdb49474ff68761909934d1142f594'
clone_revision 'https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8' \
  'prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8' \
  '639243dd5cb2c5ea1313f033c75c8c533813a484'
clone_revision 'https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86' \
  'prebuilts-master/clang/host/linux-x86' \
  '4b1f275e6b3826c86f791ae8c4d5ec3563c2fc11'
clone_revision 'https://android.googlesource.com/platform/prebuilts/misc' \
  'prebuilts-master/misc' '15560bb32cdb9b47db48eb4865b736df9708a8fe'

clone_external_revision \
  'https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-kernel-builder.git' \
  "$NETHUNTER_BUILDER_ROOT" \
  'e49544f3dea44724f354aa6fce76a59e781b18e7'

printf '\nSource root: %s\n' "$root"
du -sh "$root"
df -h "$root"
