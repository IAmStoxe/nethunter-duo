#!/usr/bin/env bash
set -euo pipefail

channel=${1:-1}
case "$channel" in *[!0-9]*|'') echo 'channel must be numeric' >&2; exit 2;; esac

serial_args=()
if [[ -n ${ANDROID_SERIAL:-} ]]; then
  serial_args=(-s "$ANDROID_SERIAL")
fi
adb_bin=${ADB:-adb}
adb_cmd=("$adb_bin" "${serial_args[@]}")

root() {
  local encoded
  encoded=$(printf '%s' "$1" | base64 | tr -d '\r\n')
  "${adb_cmd[@]}" shell "printf '%s' '$encoded' | su -c '/data/adb/magisk/busybox base64 -d | /system/bin/sh'"
}

test "$("${adb_cmd[@]}" get-state 2>/dev/null | tr -d '\r')" = device
[[ "$("${adb_cmd[@]}" shell getprop ro.build.version.incremental | tr -d '\r')" == 202209020048 ]]
[[ "$("${adb_cmd[@]}" shell uname -r | tr -d '\r')" == 4.14.190-duo-p-0_0_0+ ]]

printf 'Switching internal WLAN to monitor mode on channel %s.\n' "$channel"
root "duo-wifi monitor $channel"
root 'duo-wifi test'
root "dmesg | tail -n 250 | grep -Ei 'inject|monitor|wlan' | tail -n 40 || true"

printf 'Restoring Android managed Wi-Fi with a clean reboot.\n'
root 'duo-wifi normal' || true
"${adb_cmd[@]}" wait-for-device

for _ in $(seq 1 90); do
  if [[ "$("${adb_cmd[@]}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then
    break
  fi
  sleep 2
done
[[ "$("${adb_cmd[@]}" shell getprop sys.boot_completed | tr -d '\r')" == 1 ]]
root 'svc wifi enable'
root 'cmd wifi status 2>/dev/null || dumpsys wifi | head -40'
root 'ip link show wlan0'
printf 'Internal monitor/injection smoke test passed; managed Android Wi-Fi restored.\n'
