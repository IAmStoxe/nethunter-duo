#!/usr/bin/env bash
set -eu
source "$(dirname "$0")/../duo-technician/payload/ssh-policy.sh"

settings=('permitrootlogin prohibit-password' 'authenticationmethods publickey'
          'passwordauthentication no' 'kbdinteractiveauthentication no'
          'pubkeyauthentication yes' 'usepam no')
run() { printf '%s\n' "${settings[@]}"; return "$read_status"; }
read_status=0
verify_ssh_policy
for i in "${!settings[@]}"; do
  saved=${settings[i]}
  settings[i]="${saved% *} invalid"
  if verify_ssh_policy; then echo "accepted invalid $saved" >&2; exit 1; fi
  settings[i]=$saved
done
settings[2]='passwordauthentication yes'
if verify_ssh_policy; then echo 'accepted password authentication' >&2; exit 1; fi
settings[2]='passwordauthentication no'
read_status=1
if verify_ssh_policy; then echo 'ignored failed sshd check' >&2; exit 1; fi
echo 'SSH policy regression checks passed.'
