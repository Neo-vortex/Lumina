#!/usr/bin/env bash
# Builds liblumina_calls.so (tgcalls + WebRTC + Lumina's JNI glue) for one or
# more ABIs from the sources tool/fetch_calls_engine.sh prepared.
#
#   tool/build_calls_engine.sh                 # arm64-v8a and x86_64
#   tool/build_calls_engine.sh x86_64
#   JOBS=6 tool/build_calls_engine.sh          # parallelism (WebRTC is big)
#
# Output: build/calls-engine/out/<abi>/liblumina_calls.so, and a copy in
# android/app/src/main/jniLibs/<abi>/ (git-ignored) for local app builds.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
engine="${CALLS_ENGINE_DIR:-$root/build/calls-engine}"
jni="$engine/telegram/TMessagesProj/jni"
[[ -f "$jni/lumina/lumina_calls_jni.cpp" ]] || "$root/tool/fetch_calls_engine.sh"

ndk="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [[ -z "$ndk" ]]; then
  sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  [[ -n "$sdk" ]] || sdk="$(sed -n 's/^sdk.dir=//p' "$root/android/local.properties" 2>/dev/null)"
  # Telegram builds this code with NDK 27; prefer it over newer ones.
  ndk="$(ls -d "$sdk"/ndk/27.* 2>/dev/null | sort -V | tail -n1)"
  [[ -n "$ndk" ]] || ndk="$(ls -d "$sdk"/ndk/* 2>/dev/null | sort -V | tail -n1)"
fi
[[ -f "$ndk/build/cmake/android.toolchain.cmake" ]] || { echo "NDK not found (set ANDROID_NDK_HOME)" >&2; exit 1; }
echo "NDK: $ndk"
# Telegram's build expects CMake 3.22 (newer ones dropped AndroidNdkModules).
sdk="${sdk:-$(cd "$ndk/../.." && pwd)}"
cmake_bin="$(ls -d "$sdk"/cmake/3.22*/bin 2>/dev/null | sort -V | tail -n1)"
[[ -n "$cmake_bin" ]] && export PATH="$cmake_bin:$PATH"
echo "CMake: $(command -v cmake) ($(cmake --version | head -n1))"

abis=("$@")
((${#abis[@]})) || abis=(arm64-v8a x86_64)
for abi in "${abis[@]}"; do
  build="$engine/build-$abi"
  cmake -S "$jni" -B "$build" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$abi" \
    -DANDROID_PLATFORM=android-24 \
    -DANDROID_STL=c++_static \
    -DCMAKE_BUILD_TYPE=Release \
    ${CMAKE_C_COMPILER_LAUNCHER:+-DCMAKE_C_COMPILER_LAUNCHER=$CMAKE_C_COMPILER_LAUNCHER} \
    ${CMAKE_CXX_COMPILER_LAUNCHER:+-DCMAKE_CXX_COMPILER_LAUNCHER=$CMAKE_CXX_COMPILER_LAUNCHER}
  cmake --build "$build" --target lumina_calls -j "${JOBS:-$(nproc)}"
  out="$engine/out/$abi"
  mkdir -p "$out" "$root/android/app/src/main/jniLibs/$abi"
  "$ndk"/toolchains/llvm/prebuilt/*/bin/llvm-strip --strip-unneeded -o "$out/liblumina_calls.so" \
    "$build/liblumina_calls.so"
  cp "$out/liblumina_calls.so" "$root/android/app/src/main/jniLibs/$abi/"
  ls -l "$out/liblumina_calls.so"
done
