#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/duo-technician-android"
gradle_version=8.9
gradle_sha256=d725d707bfabd4dfdc958c624003b3c80accc03f7037b5122c4b1d0ef15cecab
archive="$cache_root/gradle-$gradle_version-bin.zip"
gradle_home="$cache_root/gradle-$gradle_version"
distribution_url="https://services.gradle.org/distributions/gradle-$gradle_version-bin.zip"

android_sdk=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}
if [[ -z "$android_sdk" || ! -d "$android_sdk/platforms/android-34" ]]; then
  echo 'Set ANDROID_SDK_ROOT to an Android SDK containing platform android-34.' >&2
  exit 2
fi
if ! java -version 2>&1 | grep -Eq 'version "(17|18|19|2[0-9])'; then
  echo 'JDK 17 or newer is required.' >&2
  exit 2
fi

mkdir -p "$cache_root" "$project_root/dist"
if [[ ! -s "$archive" ]]; then
  curl --fail --location --retry 4 --output "$archive.part" "$distribution_url"
  mv -- "$archive.part" "$archive"
fi
printf '%s  %s\n' "$gradle_sha256" "$archive" | sha256sum --check --strict -

if [[ ! -x "$gradle_home/bin/gradle" ]]; then
  temporary=$(mktemp -d "$cache_root/extract.XXXXXX")
  trap 'rm -rf -- "$temporary"' EXIT
  unzip -q "$archive" -d "$temporary"
  test -x "$temporary/gradle-$gradle_version/bin/gradle"
  mv -- "$temporary/gradle-$gradle_version" "$gradle_home"
fi

export ANDROID_SDK_ROOT="$android_sdk"
"$gradle_home/bin/gradle" --no-daemon --project-dir "$project_root" \
  :app:lintDebug :app:assembleDebug

apk="$project_root/app/build/outputs/apk/debug/app-debug.apk"
test -s "$apk"
cp -- "$apk" "$project_root/dist/DuoTechnician-1.0.0-debug.apk"
sha256sum "$project_root/dist/DuoTechnician-1.0.0-debug.apk"
