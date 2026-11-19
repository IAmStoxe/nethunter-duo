#!/bin/sh
set -eu

printf '%s\n' '== NetHunter package =='
dpkg-query -W -f='${Package} ${Version} ${Status}\n' kali-nethunter-full

printf '%s\n' '== dpkg audit =='
audit=$(dpkg --audit)
if [ -n "$audit" ]; then
  printf '%s\n' "$audit"
  exit 1
fi
printf '%s\n' 'dpkg database clean'

printf '%s\n' '== Required commands =='
failed=0
for command_name in \
  aircrack-ng airmon-ng iw kismet nmap msfconsole sqlmap tshark \
  ssh sshd vncserver rtl_test hackrf_info gpsd tmux mosh; do
  if command_path=$(command -v "$command_name" 2>/dev/null); then
    printf '%-14s %s\n' "$command_name" "$command_path"
  else
    printf '%-14s MISSING\n' "$command_name" >&2
    failed=1
  fi
done

printf '%s\n' '== Runtime =='
uname -a
df -h / | tail -n 1
du -sh /var/cache/apt/archives 2>/dev/null || true

exit "$failed"
