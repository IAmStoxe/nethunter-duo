#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 KERNEL_PAYLOAD_DIRECTORY OUTPUT.zip" >&2
  exit 2
fi

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source_module="$project_root/magisk/duo-technician"
kernel_payload=$(realpath -- "$1")
output=$(realpath -m -- "$2")

for required in \
  "$kernel_payload/modules" \
  "$kernel_payload/modules.dep" \
  "$kernel_payload/modules.sha256" \
  "$kernel_payload/build-info" \
  "$kernel_payload/wlan-injection.ko" \
  "$kernel_payload/wlan-injection.sha256"; do
  test -e "$required" || { echo "missing payload input: $required" >&2; exit 1; }
done
command -v go >/dev/null

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/module/payload/modules"

(
  cd "$source_module"
  tar \
    --exclude='payload/modules/*.ko' \
    --exclude='payload/modules.dep' \
    --exclude='payload/modules.sha256' \
    --exclude='payload/build-info' \
    --exclude='payload/wlan-injection.ko' \
    --exclude='payload/wlan-injection.sha256' \
    --exclude='payload/hid-type' \
    --exclude='payload/hid-pointer' \
    --exclude='payload/injection-selftest' \
    --exclude='payload/startkali.sh' \
    --exclude='payload/verify-install.sh' \
    -cf - .
) | tar -xf - -C "$work/module"

cp -- "$kernel_payload/modules/"*.ko "$work/module/payload/modules/"
cp -- "$kernel_payload/modules.dep" "$kernel_payload/modules.sha256" \
  "$kernel_payload/build-info" "$kernel_payload/wlan-injection.ko" \
  "$kernel_payload/wlan-injection.sha256" \
  "$work/module/payload/"
cp -- "$project_root/kali/startkali.sh" "$work/module/payload/startkali.sh"
cp -- "$project_root/kali/verify-install.sh" "$work/module/payload/verify-install.sh"

CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
  go build -trimpath -ldflags='-s -w' \
  -o "$work/module/payload/hid-type" "$project_root/kernel/tools/hid-type.go"
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
  go build -trimpath -ldflags='-s -w' \
  -o "$work/module/payload/hid-pointer" "$project_root/kernel/tools/hid-pointer.go"
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
  go build -trimpath -ldflags='-s -w' \
  -o "$work/module/payload/injection-selftest" \
  "$project_root/kernel/tools/injection-selftest.go"

(
  cd "$work/module"
  tar -czf "$work/module-source.tgz" .
)
mkdir -p "$(dirname -- "$output")"
bash "$project_root/magisk/package-module.sh" "$work/module-source.tgz" "$output"
unzip -t "$output" >/dev/null
sha256sum "$output"
