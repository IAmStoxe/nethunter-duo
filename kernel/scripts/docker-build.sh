#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/_paths.sh"

image="${DUO_BUILDER_IMAGE:-duo-kernel-builder:ubuntu20}"
dockerfile="$DUO_PROJECT_ROOT/kernel/Dockerfile.ubuntu20"
dockerfile_hash=$(sha256sum "$dockerfile" | awk '{print $1}')
fingerprint_label=org.surface-duo.builder.dockerfile-sha256

usage() {
  cat <<'EOF'
usage: docker-build.sh COMMAND [ARGS]

Commands:
  image                       Build/reuse the Ubuntu 20.04 toolchain image
  rebuild-image               Force a Docker image build (layers may be reused)
  sources [SDLLVM_ARCHIVE]    Fetch pinned sources and verify/install SDLLVM
  baseline [clean|reuse]      Build Microsoft's baseline kernel
  technician STOCK_GZ [FRAG...] Build an ABI-preserving technician profile
  stage-modules PROFILE DEST  Create a flat Android module payload + metadata
  shell                       Open a shell in the cached build environment

Run in a local x86-64 Linux or WSL2 shell with access to Docker.
For a release build, follow docs/development/build.md from the repository root.
Set DUO_KERNEL_ROOT to a path on a native Linux filesystem for fast WSL builds.
The source, output, downloads, and ccache directories are reused between runs.
EOF
}

build_image() {
  docker build \
    --label "$fingerprint_label=$dockerfile_hash" \
    --tag "$image" --file "$dockerfile" "$DUO_PROJECT_ROOT/kernel"
}

ensure_image() {
  local installed_hash
  installed_hash=$(docker image inspect \
    --format "{{ index .Config.Labels \"$fingerprint_label\" }}" \
    "$image" 2>/dev/null || true)
  if [[ "$installed_hash" != "$dockerfile_hash" ]]; then
    build_image
  fi
}

run_builder() {
  ensure_image
  mkdir -p "$DUO_KERNEL_ROOT" "$DUO_KERNEL_ROOT/.ccache"
  docker run --rm --init \
    --user "$(id -u):$(id -g)" \
    --workdir /workspace/source \
    --volume "$DUO_KERNEL_ROOT:/workspace/source" \
    --volume "$DUO_PROJECT_ROOT:/workspace/project:ro" \
    --env DUO_KERNEL_ROOT=/workspace/source \
    --env DUO_PROJECT_ROOT=/workspace/project \
    --env CCACHE_DIR=/workspace/source/.ccache \
    --env USE_CCACHE=1 \
    "$image" "$@"
}

command="${1:-}"
shift || true
case "$command" in
  image)
    ensure_image
    ;;
  rebuild-image)
    build_image
    ;;
  sources)
    "$script_dir/sync-source.sh"
    if (( $# )); then
      "$script_dir/setup-snapdragon-llvm.sh" "$1"
    else
      "$script_dir/setup-snapdragon-llvm.sh"
    fi
    ;;
  baseline)
    ensure_image
    DUO_BUILDER_IMAGE="$image" "$script_dir/remote-official-build.sh" \
      official-baseline "${1:-reuse}"
    ;;
  technician)
    stock="${1:?Supply the verified stock /proc/config.gz}"
    shift
    stock="$(cd -- "$(dirname -- "$stock")" && pwd)/$(basename -- "$stock")"
    test -r "$stock"
    if (( $# )); then
      fragments=("$@")
    else
      fragments=("$DUO_PROJECT_ROOT/kernel/config/technician-peripherals.config")
    fi
    for index in "${!fragments[@]}"; do
      fragment="${fragments[$index]}"
      fragment="$(cd -- "$(dirname -- "$fragment")" && pwd)/$(basename -- "$fragment")"
      test -r "$fragment"
      fragments[$index]="$fragment"
    done
    ensure_image
    DUO_BUILDER_IMAGE="$image" "$script_dir/build-technician-kernel.sh" \
      "$stock" "${fragments[@]}"
    ;;
  stage-modules)
    profile=${1:?Supply the completed build profile name}
    destination=${2:?Supply an empty destination directory}
    "$script_dir/stage-module-payload.sh" \
      "$DUO_KERNEL_ROOT/out/$profile/kernel/msm-4.14" "$destination"
    ;;
  shell)
    run_builder bash
    ;;
  -h|--help|help|'')
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
