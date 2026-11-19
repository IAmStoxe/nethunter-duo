#!/usr/bin/env bash

# Shared, host-independent paths. Keep the large source/output tree on a native
# Linux filesystem by setting DUO_KERNEL_ROOT when building from WSL.
DUO_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DUO_PROJECT_ROOT="${DUO_PROJECT_ROOT:-$(cd -- "$DUO_SCRIPT_DIR/../.." && pwd)}"
DUO_CACHE_ROOT="${DUO_CACHE_ROOT:-${XDG_CACHE_HOME:-$HOME/.cache}/surface-duo-nethunter}"
DUO_KERNEL_ROOT="${DUO_KERNEL_ROOT:-$DUO_CACHE_ROOT/source}"
NETHUNTER_BUILDER_ROOT="${NETHUNTER_BUILDER_ROOT:-$DUO_CACHE_ROOT/kali-nethunter-kernel-builder}"
DUO_DOWNLOAD_CACHE="${DUO_DOWNLOAD_CACHE:-$DUO_CACHE_ROOT/downloads}"

export DUO_PROJECT_ROOT DUO_CACHE_ROOT DUO_KERNEL_ROOT
export NETHUNTER_BUILDER_ROOT DUO_DOWNLOAD_CACHE
