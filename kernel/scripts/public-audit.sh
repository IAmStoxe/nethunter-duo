#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/../.." && pwd)"
cd "$project_root"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'Initialize the publication repository before running this audit.\n' >&2
  exit 2
fi

mapfile -d '' files < <(git ls-files --cached --others --exclude-standard -z)
if ((${#files[@]} == 0)); then
  printf 'No publication candidates found.\n' >&2
  exit 2
fi

failed=0
printf 'Auditing %d publication candidate files...\n' "${#files[@]}"

for file in "${files[@]}"; do
  lower=${file,,}
  case "$lower" in
    *.img|*.apk|*.ko|*.tgz|*.tar|*.tar.*|*.pcap|*.pcapng|*.7z|*.ffu)
      printf 'forbidden artifact: %s\n' "$file" >&2
      failed=1
      ;;
  esac

  if [[ -f "$file" ]]; then
    size=$(stat -c %s -- "$file")
    if ((size > 10485760)); then
      printf 'review large file (%d bytes): %s\n' "$size" "$file" >&2
      failed=1
    fi
  fi
done

identity_pattern='C:\\Users\\[^\\[:space:]]+|/Users/[^/[:space:]]+|/home/[^/[:space:]]+|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}'
search_candidates() {
  local pattern=$1
  local insensitive=${2:-0}
  local output
  local searchable=()
  local candidate
  for candidate in "${files[@]}"; do
    [[ "$candidate" == kernel/scripts/public-audit.sh ]] || searchable+=("$candidate")
  done
  if command -v rg >/dev/null 2>&1; then
    if [[ "$insensitive" == 1 ]]; then
      output=$(rg --no-messages -nIHi -e "$pattern" -- "${searchable[@]}" || true)
    else
      output=$(rg --no-messages -nIH -e "$pattern" -- "${searchable[@]}" || true)
    fi
  else
    if [[ "$insensitive" == 1 ]]; then
      output=$(grep -nIHi -E -e "$pattern" -- "${searchable[@]}" 2>/dev/null || true)
    else
      output=$(grep -nIH -E -e "$pattern" -- "${searchable[@]}" 2>/dev/null || true)
    fi
  fi
  [[ -n "$output" ]] || return 1
  printf '%s\n' "$output"
}

if search_candidates "$identity_pattern"; then
  printf 'Review the identity/network matches above.\n' >&2
  failed=1
fi

if [[ -n "${DUO_PRIVATE_PATTERNS:-}" ]] && \
   search_candidates "$DUO_PRIVATE_PATTERNS" 1; then
  printf 'Private-pattern matches found.\n' >&2
  failed=1
fi

if ((failed)); then
  exit 1
fi

printf 'Public-source audit passed. Review the staged diff before publishing.\n'
