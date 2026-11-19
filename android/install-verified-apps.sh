#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
apps="$project_root/apps"
serial_args=()
if [[ -n ${ANDROID_SERIAL:-} ]]; then
  serial_args=(-s "$ANDROID_SERIAL")
fi
adb_cmd=(adb "${serial_args[@]}")

command -v sha256sum >/dev/null
test "$("${adb_cmd[@]}" get-state 2>/dev/null)" = device
(
  cd "$apps"
  sha256sum -c SHA256SUMS
)

for apk in \
  NetHunterStore.apk \
  NetHunterTerminal.apk \
  NetHunterKeX.apk \
  NetHunter-2026.3.apk; do
  "${adb_cmd[@]}" install -r --user 0 "$apps/$apk"
done

printf '\nInstalled package versions:\n'
for package in \
  com.offsec.nethunter.store \
  com.offsec.nhterm \
  com.offsec.nethunter.kex \
  com.offsec.nethunter; do
  "${adb_cmd[@]}" shell dumpsys package "$package" |
    tr -d '\r' | grep -m1 -E 'versionName=|versionCode=' || true
done
