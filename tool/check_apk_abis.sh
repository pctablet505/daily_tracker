#!/usr/bin/env bash
# Fails unless the APK's native libraries are only for the phones we build for.
# A library that ships x86_64 code makes the APK look installable on an x86_64
# device, where the app then crashes because the Flutter engine is not in it.
set -euo pipefail

apk="${1:?usage: check_apk_abis.sh app.apk}"
abis="$(unzip -Z1 "$apk" | sed -n 's#^lib/\([^/]*\)/.*#\1#p' | sort -u)"
echo "native library folders: $(echo $abis)"

if [ -z "$abis" ]; then
  echo "::error::no native libraries found in $apk, is this the right file?"
  exit 1
fi
unexpected="$(echo "$abis" | grep -v -x -E 'arm64-v8a|armeabi-v7a' || true)"
if [ -n "$unexpected" ]; then
  echo "::error::unexpected native library folders: $(echo $unexpected)"
  exit 1
fi
