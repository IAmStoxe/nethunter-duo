#!/usr/bin/env bash
set -euo pipefail

serial_args=()
if [[ -n ${ANDROID_SERIAL:-} ]]; then
  serial_args=(-s "$ANDROID_SERIAL")
fi
adb_bin=${ADB:-adb}
adb_cmd=("$adb_bin" "${serial_args[@]}")

root() {
  # Encode the script so native Linux adb and Windows adb.exe invoked through
  # WSL transport identical bytes without nested shell/argv quoting damage.
  local encoded
  encoded=$(printf '%s' "$1" | base64 | tr -d '\r\n')
  "${adb_cmd[@]}" shell "printf '%s' '$encoded' | su -c '/data/adb/magisk/busybox base64 -d | /system/bin/sh'"
}

test "$("${adb_cmd[@]}" get-state 2>/dev/null | tr -d '\r')" = device
build=$("${adb_cmd[@]}" shell getprop ro.build.version.incremental | tr -d '\r')
release=$("${adb_cmd[@]}" shell uname -r | tr -d '\r')
[[ "$build" == 202209020048 ]]
[[ "$release" == 4.14.190-duo-p-0_0_0+ ]]

printf 'Android build: %s\nKernel: %s\n' "$build" "$release"

printf '\n== Toolkit integrity ==\n'
root 'duo-modprobe verify' >/dev/null
root 'duo-modprobe status'

printf '\n== Stock vendor modules ==\n'
root '
  failed=0
  checked=0
  for file in $(cat /vendor/lib/modules/modules.load); do
    # Qualcomm vendor filenames are packaging names (for example,
    # audio_apr.ko); the ELF module name is different (apr_dlkm). Read the
    # embedded modinfo name instead of guessing from the filename.
    name=$(grep -a -o "name=[A-Za-z0-9_-]*" "/vendor/lib/modules/$file" | sed "s/^name=//" | grep . | tail -n 1)
    [ -n "$name" ] || { echo "no embedded module name: $file" >&2; failed=1; continue; }
    checked=$((checked + 1))
    if ! grep -q "^$name " /proc/modules; then
      case "$name" in
        mpq_adapter|mpq_dmx_hw_plugin|tspp|rmnet_shs|rmnet_perf|rdbg)
          # These entries are also dormant on the unmodified Duo boot image;
          # they are available vendor modules, not boot-time requirements.
          echo "stock-optional not loaded: $file"
          ;;
        *)
          echo "required vendor module not loaded: $file" >&2
          failed=1
          ;;
      esac
    fi
  done
  echo "checked=$checked"
  exit "$failed"
'

printf '\n== Managed Wi-Fi ==\n'
root 'cmd wifi status 2>/dev/null || dumpsys wifi | head -40'
root 'ip link show wlan0'

printf '\n== Optional module probes ==\n'
root 'duo-modprobe load usbserial cdc_acm cdc_eem qmi_wwan can can_raw can_dev vcan hackrf mac80211 ath ath9k_hw ath9k_common ath9k_htc usbip_core nbd cifs macvlan vxlan ip_set sch_fq_codel'

printf '\n== SocketCAN loopback ==\n'
root "duo-kali run 'ip link del vcan0 2>/dev/null || true; ip link add dev vcan0 type vcan; ip link set vcan0 up; (sleep 1; cansend vcan0 123#DEADBEEF) & timeout 5 candump -n 1 vcan0; ip link del vcan0'"

printf '\n== Kali installation ==\n'
root 'duo-kali verify'

printf '\n== Audio and camera services ==\n'
root "service list | grep -Ei 'audio|camera'"
root 'cat /proc/asound/cards 2>/dev/null || true'

printf '\n== Kernel fault scan ==\n'
faults=$(root "dmesg | grep -E 'Kernel panic|(^|[^[:alnum:]_])BUG:|Oops:|Call trace:' || true")
if [[ -n "$faults" ]]; then
  printf '%s\n' "$faults" >&2
  exit 1
fi
echo 'No kernel panic/oops/call-trace signatures found.'

printf '\nRuntime smoke test passed. HID delivery, internal monitor/injection,\n'
printf 'physical radios, audible audio, and saved camera output remain separate tests.\n'
