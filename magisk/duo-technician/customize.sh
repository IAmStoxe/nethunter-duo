#!/system/bin/sh

ui_print "- Installing Surface Duo Technician Toolkit"
[ "$(getprop ro.product.device)" = duo ] || abort "This module requires a first-generation Surface Duo (duo)."
[ "$(getprop ro.build.version.incremental)" = 202209020048 ] || abort "This module requires Surface Duo firmware 2022.902.48."
ui_print "- Requires the matching technician kernel for unsigned modules"
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/system/bin/duo-wifi" 0 0 0755
set_perm "$MODPATH/system/bin/duo-modprobe" 0 0 0755
set_perm "$MODPATH/system/bin/duo-hid" 0 0 0755
set_perm "$MODPATH/system/bin/duo-usb" 0 0 0755
set_perm "$MODPATH/system/bin/duo-kali" 0 0 0755
set_perm "$MODPATH/system/bin/duo-doctor" 0 0 0755
set_perm "$MODPATH/system/bin/duo-tech" 0 0 0755
set_perm "$MODPATH/payload/injection-selftest" 0 0 0755
set_perm "$MODPATH/payload/hid-type" 0 0 0755
set_perm "$MODPATH/payload/hid-pointer" 0 0 0755
set_perm "$MODPATH/payload/startkali.sh" 0 0 0755
set_perm "$MODPATH/payload/verify-install.sh" 0 0 0755
set_perm "$MODPATH/payload/duo-profile.sh" 0 0 0644
