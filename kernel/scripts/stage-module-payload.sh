#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: stage-module-payload.sh KERNEL_OUT DESTINATION

Collect every loadable module from a completed kernel output tree into a flat,
Android-friendly payload.  The script also writes a dependency map, hashes,
and build metadata.  DESTINATION must not already contain kernel modules.
EOF
}

if [[ $# -ne 2 ]]; then
  usage >&2
  exit 2
fi

kernel_out=$(realpath -- "$1")
destination=$2
command -v modinfo >/dev/null
test -r "$kernel_out/include/config/kernel.release"

if [[ -d "$destination/modules" ]] && find "$destination/modules" -maxdepth 1 -type f -name '*.ko' -print -quit | grep -q .; then
  echo "destination already contains modules: $destination" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/modules"

declare -A source_by_name=()
declare -A file_by_normalized_name=()
while IFS= read -r -d '' module; do
  filename=${module##*/}
  normalized=${filename%.ko}
  normalized=${normalized//-/_}
  if [[ -n ${source_by_name[$filename]:-} ]]; then
    printf 'duplicate module filename: %s\n' "$filename" >&2
    exit 1
  fi
  if [[ -n ${file_by_normalized_name[$normalized]:-} ]]; then
    printf 'duplicate normalized module name: %s\n' "$normalized" >&2
    exit 1
  fi
  source_by_name[$filename]=$module
  file_by_normalized_name[$normalized]=$filename
done < <(find "$kernel_out" -type f -name '*.ko' -print0)

if (( ${#source_by_name[@]} == 0 )); then
  echo "no modules found below $kernel_out" >&2
  exit 1
fi

mapfile -t filenames < <(printf '%s\n' "${!source_by_name[@]}" | LC_ALL=C sort)
for filename in "${filenames[@]}"; do
  cp -- "${source_by_name[$filename]}" "$work/modules/$filename"
done

: > "$work/modules.dep"
for filename in "${filenames[@]}"; do
  dependencies=()
  IFS=, read -r -a declared <<< "$(modinfo -F depends "$work/modules/$filename")"
  for dependency in "${declared[@]}"; do
    dependency=${dependency//-/_}
    [[ -n $dependency ]] || continue
    if [[ -n ${file_by_normalized_name[$dependency]:-} ]]; then
      dependencies+=("${file_by_normalized_name[$dependency]}")
    fi
  done
  printf '%s:' "$filename" >> "$work/modules.dep"
  if (( ${#dependencies[@]} )); then
    printf ' %s' "${dependencies[@]}" >> "$work/modules.dep"
  fi
  printf '\n' >> "$work/modules.dep"
done

(
  cd "$work/modules"
  sha256sum -- *.ko > ../modules.sha256
)

release=$(<"$kernel_out/include/config/kernel.release")
{
  printf 'kernel_release=%s\n' "$release"
  printf 'module_count=%s\n' "${#filenames[@]}"
  if [[ -r "$kernel_out/arch/arm64/boot/Image" ]]; then
    printf 'image_sha256='
    sha256sum "$kernel_out/arch/arm64/boot/Image" | awk '{print $1}'
  fi
} > "$work/build-info"

mkdir -p "$destination/modules"
cp -- "$work/modules/"*.ko "$destination/modules/"
cp -- "$work/modules.dep" "$work/modules.sha256" "$work/build-info" "$destination/"

printf 'Staged %d modules for %s in %s\n' \
  "${#filenames[@]}" "$release" "$destination"
