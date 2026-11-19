#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
source_root=$DUO_KERNEL_ROOT
stock_config=${1:?Supply the verified /proc/config.gz from the Duo}
shift
feature_configs=("$@")
kernel_source=$source_root/kernel/msm-4.14
clean_source=$source_root/kernel/msm-4.14-technician
profile=${DUO_BUILD_PROFILE:-technician}
[[ "$profile" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
  echo "invalid build profile: $profile" >&2
  exit 2
}
out=$source_root/out/$profile/kernel/msm-4.14
hid_patch=$DUO_PROJECT_ROOT/kernel/patches/duo-hid-superspeed-plus.patch
max_speed_patch=$DUO_PROJECT_ROOT/kernel/patches/configfs-gadget-max-speed.patch
dwc3_speed_patch=$DUO_PROJECT_ROOT/kernel/patches/dwc3-gadget-max-speed.patch
midi_configfs_patch=$DUO_PROJECT_ROOT/kernel/patches/configfs-midi-legacy-device.patch
ath6kl_patch=$DUO_PROJECT_ROOT/kernel/patches/ath6kl-parentheses.patch
can_peak_patch=$DUO_PROJECT_ROOT/kernel/patches/can-peak-varargs.patch
can_pernet_patch=$DUO_PROJECT_ROOT/kernel/patches/can-pernet-generic.patch
wifi_injection_patch=$NETHUNTER_BUILDER_ROOT/patches/4.14/add-wifi-injection-4.14.patch
builder_image=${DUO_BUILDER_IMAGE:-duo-kernel-builder:ubuntu20}
build_external_modules=${DUO_BUILD_EXT_MODULES:-0}

apply_once() {
  local patch=$1
  if git -C "$clean_source" apply --reverse --check "$patch" 2>/dev/null; then
    printf 'Patch already applied: %s\n' "$(basename "$patch")"
  else
    git -C "$clean_source" apply --check "$patch"
    git -C "$clean_source" apply "$patch"
    printf 'Applied patch: %s\n' "$(basename "$patch")"
  fi
}

if [[ ! -d "$clean_source" ]]; then
  git -C "$kernel_source" worktree add --detach "$clean_source" HEAD
fi
test "$(git -C "$kernel_source" rev-parse HEAD)" = "$(git -C "$clean_source" rev-parse HEAD)"
if grep -Fqx $'\t\t\thidg_ss_descriptors);' \
     "$clean_source/drivers/usb/gadget/function/f_hid.c"; then
  printf 'HID SuperSpeed Plus patch already applied.\n'
else
  git -C "$clean_source" apply --check "$hid_patch"
  git -C "$clean_source" apply "$hid_patch"
fi
apply_once "$max_speed_patch"
apply_once "$dwc3_speed_patch"
apply_once "$midi_configfs_patch"
test -f "$wifi_injection_patch"
apply_once "$ath6kl_patch"
apply_once "$can_peak_patch"
apply_once "$can_pernet_patch"
apply_once "$wifi_injection_patch"
if [[ "$build_external_modules" == 1 ]]; then
  "$DUO_PROJECT_ROOT/kernel/scripts/apply-qcacld-patches.sh"
fi
unexpected="$(git -C "$clean_source" status --porcelain | grep -Ev '^ M (drivers/usb/dwc3/gadget.c|drivers/usb/gadget/configfs.c|drivers/usb/gadget/function/f_hid.c|drivers/usb/gadget/function/f_midi.c|drivers/net/can/usb/peak_usb/pcan_usb_pro.c|drivers/net/wireless/ath/ath6kl/main.c|drivers/net/wireless/realtek/rtl818x/rtl8187/dev.c|drivers/net/wireless/zydas/zd1211rw/zd_mac.c|include/net/net_namespace.h|include/net/netns/can.h|net/can/af_can.c|net/can/bcm.c|net/can/gw.c|net/can/proc.c|net/mac80211/cfg.c|net/mac80211/tx.c|net/wireless/chan.c)$' || true)"
test -z "$unexpected"
gzip -t "$stock_config"
mkdir -p "$out" "$source_root/.ccache"
gzip -dc "$stock_config" > "$out/.config"

# Preserve the device configuration and limit additions to USB console drivers.
# The locally generated signing key cannot authenticate the OTA vendor modules.
"$clean_source/scripts/config" --file "$out/.config" \
  -d MODULE_SIG_FORCE -m USB_ACM -m USB_SERIAL \
  -m USB_SERIAL_FTDI_SIO -m USB_SERIAL_CP210X -m USB_SERIAL_CH341 -m USB_SERIAL_PL2303

if (( ${#feature_configs[@]} )); then
  "$clean_source/scripts/kconfig/merge_config.sh" -m -O "$out" \
    "$out/.config" "${feature_configs[@]}"
fi

docker_environment=(
  --env BUILD_CONFIG=./kernel/msm-4.14/build.config.perf-config
  --env KERNEL_DEFCONFIG=surfaceduo-perf_defconfig
  --env OUT_DIR="/workspace/source/out/$profile"
  --env DIST_DIR="/workspace/source/dist/$profile"
  --env CCACHE_DIR=/workspace/source/.ccache
  --env CCACHE_EXEC=/usr/bin/ccache --env USE_CCACHE=1
  --env SKIP_MRPROPER=1 --env SKIP_DEFCONFIG=1
)
if [[ "$build_external_modules" != 1 ]]; then
  docker_environment+=(--env SKIP_EXT_MODULES=1)
fi

docker run --rm \
  --user "$(id -u):$(id -g)" \
  --workdir /workspace/source \
  --volume "$source_root:/workspace/source" \
  --volume "$clean_source:/workspace/source/kernel/msm-4.14:ro" \
  "${docker_environment[@]}" \
  "$builder_image" bash -ec '
    make -C kernel/msm-4.14 O="$OUT_DIR/kernel/msm-4.14" ARCH=arm64 olddefconfig
    exec bash build/build.sh
  '

for option in USB_ACM USB_SERIAL USB_SERIAL_FTDI_SIO USB_SERIAL_CP210X USB_SERIAL_CH341 USB_SERIAL_PL2303; do
  grep -qx "CONFIG_${option}=m" "$out/.config"
done
grep -qx 'CONFIG_MODVERSIONS=y' "$out/.config"
grep -qx 'CONFIG_USB_CONFIGFS_F_HID=y' "$out/.config"
grep -Fxq '4.14.190-duo-p-0_0_0+' "$out/include/config/kernel.release"
if [[ "$build_external_modules" == 1 ]]; then
  test -s "$source_root/dist/$profile/wlan.ko"
fi

if (( ${#feature_configs[@]} )); then
  while IFS= read -r setting; do
    if ! grep -Fxq "$setting" "$out/.config"; then
      printf 'Kconfig did not retain %s\n' "$setting" >&2
      exit 1
    fi
  done < <(grep -hE '^CONFIG_[A-Z0-9_]+=' "${feature_configs[@]}")
fi
