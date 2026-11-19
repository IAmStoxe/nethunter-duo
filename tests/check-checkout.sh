#!/usr/bin/env bash
set -euo pipefail

# Exercise the documented entry points on the checkout without USB or Docker.
kernel/scripts/docker-build.sh --help >/dev/null
for script in kernel/scripts/capture-device-abi.sh kernel/scripts/build-release.sh magisk/build-module.sh; do
  status=0
  usage=$("$script" 2>&1) || status=$?
  if [[ $status != 2 || $usage != usage:* ]]; then
    printf 'Expected usage from %s, got status %s: %s\n' "$script" "$status" "$usage" >&2
    exit 1
  fi
done
for script in kernel/scripts/*.sh android/*.sh magisk/package-module.sh; do
  [[ $script == */_paths.sh || -x $script ]] || { echo "Missing execute bit: $script" >&2; exit 1; }
done
bash magisk/tests/ssh-policy.sh
