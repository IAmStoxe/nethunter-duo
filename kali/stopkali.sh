#!/system/bin/sh
BB=/data/adb/magisk/busybox
K=/data/local/nhsystem/kali-arm64
echo "== mounts under nhsystem BEFORE =="
$BB mount | $BB grep nhsystem
echo "== unmounting known submounts (deepest first) =="
for m in dev/pts dev/shm dev/shm/tmp system_dev proc sys dev sdcard system_root; do
  if $BB umount "$K/$m" 2>/dev/null; then echo "umounted $m"; fi
done
echo "== sweep any remaining nhsystem mounts (longest path first) =="
$BB mount | $BB grep nhsystem | $BB awk '{print $3}' | $BB awk '{ print length, $0 }' | $BB sort -rn | $BB cut -d" " -f2- | while read mp; do
  $BB umount "$mp" 2>/dev/null || $BB umount -l "$mp" 2>/dev/null
  echo "cleared: $mp"
done
echo "== mounts under nhsystem AFTER =="
$BB mount | $BB grep nhsystem
echo "AFTER-COUNT=$($BB mount | $BB grep -c nhsystem)"
echo "DONE"
