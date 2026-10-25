#!/usr/bin/env bash
# Prints the cache key of the calls engine: a hash of everything that goes
# into liblumina_calls.so (the pin and fetch logic, the build script, our
# CMake and JNI glue). CI publishes each build as release calls-engine-<key>.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
{
  git hash-object tool/fetch_calls_engine.sh tool/build_calls_engine.sh android/calls-engine/CMakeLists.txt
  find android/calls-engine/src -type f | sort | xargs git hash-object
} | sha256sum | cut -c1-16
