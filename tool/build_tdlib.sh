#!/usr/bin/env bash
# Builds libtdjson.so for one Android ABI at the TDLib commit pinned in
# packages/lumina_tdlib/schema/VERSION, with TDLib's own example/android
# scripts (JSON interface, static OpenSSL 1.1.1 and libc++).
#   tool/build_tdlib.sh arm64-v8a   ->  build/tdlib/out/arm64-v8a/libtdjson.so
# Needs ANDROID_HOME with "ndk;28.2.13676358" and "cmake;3.22.1", plus gperf,
# php, perl and a JDK (TDLib's check-environment.sh lists them).
set -euo pipefail
abi="${1:?usage: tool/build_tdlib.sh <abi>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
pin="$root/packages/lumina_tdlib/schema/VERSION"
version="$(sed -n 's/^version=//p' "$pin")"
commit="$(sed -n 's/^commit=//p' "$pin")"
ndk_version=28.2.13676358
api_level=24 # the app's minSdk
work="$root/build/tdlib"
out="$work/out/$abi"

mkdir -p "$work"
if [[ ! -d "$work/td/.git" ]]; then
  git init -q "$work/td"
  git -C "$work/td" remote add origin https://github.com/tdlib/td.git
fi
git -C "$work/td" fetch -q --depth 1 origin "$commit"
git -C "$work/td" checkout -q --force FETCH_HEAD

cd "$work/td/example/android"
# 16 KB LOAD alignment (NDK r28 defaults to it; this keeps it explicit).
export LDFLAGS="-Wl,-z,max-page-size=16384"
if [[ ! -d "$work/openssl" ]]; then
  ./build-openssl.sh "$ANDROID_HOME" "$ndk_version" "$work/openssl" OpenSSL_1_1_1w
fi
./build-tdlib.sh "$ANDROID_HOME" "$ndk_version" "$work/openssl" c++_static JSON "$api_level" "$abi"

mkdir -p "$out"
cp "tdlib/libs/$abi/libtdjson.so" "$out/"

# The binary must be the release the Dart API was generated from.
# grep without -q reads all input, so strings never gets SIGPIPE under pipefail.
strings "$out/libtdjson.so" | grep -Fx "$version" >/dev/null || { echo "libtdjson.so is not TDLib $version" >&2; exit 1; }
if readelf -lW "$out/libtdjson.so" | awk '$1 == "LOAD" && $NF != "0x4000" { bad = 1 } END { exit !bad }'; then
  echo "libtdjson.so has LOAD segments that aren't 16 KB aligned" >&2
  exit 1
fi
ls -l "$out/libtdjson.so"
