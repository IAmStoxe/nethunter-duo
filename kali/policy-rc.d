#!/bin/sh
# NetHunter runs inside an Android chroot without a normal init system.
# Keep package post-install scripts from attempting to start daemons.
exit 101
