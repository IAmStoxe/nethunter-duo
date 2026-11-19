#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
stock_gz="${1:-$DUO_PROJECT_ROOT/kernel/config/stock-duo-p.config.gz}"
built="${2:-$DUO_KERNEL_ROOT/dist/official-baseline/.config}"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

gzip -dc "$stock_gz" > "$temp_dir/stock.config"
grep '^CONFIG_.*=' "$temp_dir/stock.config" | sort > "$temp_dir/stock.enabled"
grep '^CONFIG_.*=' "$built" | sort > "$temp_dir/built.enabled"

printf 'stock enabled: '; wc -l < "$temp_dir/stock.enabled"
printf 'built enabled: '; wc -l < "$temp_dir/built.enabled"
printf 'enabled-line differences: '
diff -U 0 "$temp_dir/stock.enabled" "$temp_dir/built.enabled" > "$temp_dir/enabled.diff" || true
grep -cE '^[+-]CONFIG_' "$temp_dir/enabled.diff" || true

printf '\nABI/debug-sensitive settings:\n'
grep -E '^(CONFIG_(LOCALVERSION|MODVERSIONS|MODULE_SIG|DEBUG_INFO|DEBUG_FS|PAGE_OWNER|SLUB_DEBUG|KASAN|KPROBES|FTRACE|TRACING|STACKTRACE|FRAME_POINTER|USB_CONFIGFS|USB_CONFIGFS_F_HID|HIDRAW|UHID)=|# CONFIG_(MODVERSIONS|DEBUG_FS|PAGE_OWNER|KASAN) is not set)' \
  "$temp_dir/stock.config" > "$temp_dir/stock.sensitive" || true
grep -E '^(CONFIG_(LOCALVERSION|MODVERSIONS|MODULE_SIG|DEBUG_INFO|DEBUG_FS|PAGE_OWNER|SLUB_DEBUG|KASAN|KPROBES|FTRACE|TRACING|STACKTRACE|FRAME_POINTER|USB_CONFIGFS|USB_CONFIGFS_F_HID|HIDRAW|UHID)=|# CONFIG_(MODVERSIONS|DEBUG_FS|PAGE_OWNER|KASAN) is not set)' \
  "$built" > "$temp_dir/built.sensitive" || true
diff -U 2 "$temp_dir/stock.sensitive" "$temp_dir/built.sensitive" || true

printf '\nFirst 160 enabled-line differences:\n'
sed -n '1,180p' "$temp_dir/enabled.diff"
