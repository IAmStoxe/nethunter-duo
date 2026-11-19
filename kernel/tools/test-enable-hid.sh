#!/system/bin/sh
/data/adb/magisk/busybox setsid /data/local/tmp/duo-hid enable 45 >/data/local/tmp/duo-hid.log 2>&1 </dev/null &
