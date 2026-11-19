#!/system/bin/sh
# Kali NetHunter chroot launcher for Surface Duo (Magisk root)
# Usage:
#   startkali.sh            -> interactive Kali shell
#   startkali.sh -c "cmd"   -> run one command inside Kali (for automation)
BB=/data/adb/magisk/busybox
KROOT=/data/local/nhsystem/kali-arm64
set -e
[ "$(id -u)" = 0 ] || { echo 'Run this launcher as root.' >&2; exit 1; }
[ -x "$KROOT/bin/bash" ] || { echo "Kali rootfs missing at $KROOT" >&2; exit 1; }

# Every Kali process gets a mount namespace whose propagation is recursively
# slave. Android mount changes remain visible, while Kali mounts and unmounts
# can never propagate back into Android. Long-lived daemons such as sshd keep
# this namespace alive after the launcher exits.
if [ "${DUO_KALI_MOUNTNS:-}" != 1 ]; then
  DUO_KALI_MOUNTNS=1
  export DUO_KALI_MOUNTNS
  exec "$BB" unshare -m --propagation slave "$0" "$@"
fi

# --- DNS + hosts (refresh each launch) ---
[ -e "$KROOT/etc/resolv.conf" ] || printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > "$KROOT/etc/resolv.conf"

# --- ensure mount points exist ---
for d in dev sys proc dev/pts dev/shm mnt/shared; do mkdir -p "$KROOT/$d"; done

# --- bind/virtual mounts (idempotent) ---
mountpoint_ok() { $BB mount | grep -q " $1 "; }
mountpoint_ok "$KROOT/dev"     || $BB mount -o rbind /dev      "$KROOT/dev"
mountpoint_ok "$KROOT/sys"     || $BB mount -o rbind /sys      "$KROOT/sys"
mountpoint_ok "$KROOT/proc"    || $BB mount -o rbind /proc     "$KROOT/proc"
# Binding Android /dev hides the mountpoints created above. Recreate them in
# the now-visible bind mount before mounting devpts and tmpfs.
mkdir -p "$KROOT/dev/pts" "$KROOT/dev/shm"
mountpoint_ok "$KROOT/dev/pts" || $BB mount -t devpts devpts  "$KROOT/dev/pts"
mountpoint_ok "$KROOT/dev/shm" || $BB mount -t tmpfs tmpfs    "$KROOT/dev/shm"
mountpoint_ok "$KROOT/mnt/shared" || $BB mount -o rbind /sdcard "$KROOT/mnt/shared"

export PATH_IN="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

if [ "${1:-}" = "-c" ]; then
  [ "$#" = 2 ] || { echo 'Usage: startkali.sh [-c "command"]' >&2; exit 2; }
  shift
  exec "$BB" chroot "$KROOT" /usr/bin/env PATH="$PATH_IN" HOME=/root TERM=xterm-256color LANG=C.UTF-8 /bin/bash -c "$1"
elif [ "${1:-}" = "--" ]; then
  shift
  [ "$#" -gt 0 ] || { echo 'Usage: startkali.sh -- PROGRAM [ARG...]' >&2; exit 2; }
  exec "$BB" chroot "$KROOT" /usr/bin/env PATH="$PATH_IN" HOME=/root TERM=xterm-256color LANG=C.UTF-8 "$@"
else
  $BB chroot "$KROOT" /bin/bash -c "export PATH=$PATH_IN HOME=/root TERM=xterm-256color LANG=C.UTF-8; cd /root; exec bash"
fi
