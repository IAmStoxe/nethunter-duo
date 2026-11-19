#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"

if [[ $# -ne 4 ]]; then
  cat >&2 <<'EOF'
usage: package-test-boot.sh SOURCE_BOOT.img KERNEL_IMAGE MAGISK.apk OUTPUT.img

Repack a matching local Surface Duo boot image with a candidate kernel. The
private boot image and Magisk APK are explicit inputs and are never downloaded
or copied into the public source tree.
EOF
  exit 2
fi

source_boot=$(realpath -- "$1")
kernel=$(realpath -- "$2")
apk=$(realpath -- "$3")
output=$(realpath -m -- "$4")

test -f "$source_boot"
test -f "$kernel"
test -f "$apk"
[[ "$source_boot" != "$output" ]] || {
  echo "output must not overwrite the source boot image" >&2
  exit 2
}
mkdir -p "$(dirname -- "$output")"

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
cd "$work"

unzip -p "$apk" lib/x86_64/libmagiskboot.so > magiskboot
chmod 0755 magiskboot
cp -- "$source_boot" boot.img

mkdir original repacked
cd original
../magiskboot unpack -h ../boot.img
cp -- kernel kernel.original
cp -- "$kernel" kernel
../magiskboot repack ../boot.img ../new-boot.img
cd ../repacked
../magiskboot unpack -h ../new-boot.img

for component in ramdisk.cpio second dtb extra recovery_dtbo kernel_dtb; do
  if [[ -e "../original/$component" || -e "$component" ]]; then
    cmp -- "../original/$component" "$component"
    printf 'Preserved component: %s\n' "$component"
  fi
done
cd ..

test -s new-boot.img
test "$(stat -c %s new-boot.img)" -eq "$(stat -c %s boot.img)"
cp -- new-boot.img "$output"

printf 'Original kernel: '
sha256sum original/kernel.original
printf 'New kernel:      '
sha256sum original/kernel
printf 'Test boot image: '
sha256sum "$output"
stat -c 'Test boot size: %s bytes' "$output"
