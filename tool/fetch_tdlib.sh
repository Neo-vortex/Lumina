#!/usr/bin/env bash
# Puts the CI-built libtdjson.so for the current TDLib pin into the app's
# jniLibs, for local runs and builds. Needs `gh` signed in to this repo.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
key="$(tool/tdlib_key.sh)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
gh release download "tdlib-$key" -p 'libtdjson-*.so' -D "$tmp"
for abi in arm64-v8a x86_64; do
  mkdir -p "android/app/src/main/jniLibs/$abi"
  mv "$tmp/libtdjson-$abi.so" "android/app/src/main/jniLibs/$abi/libtdjson.so"
done
ls -l android/app/src/main/jniLibs/*/libtdjson.so
