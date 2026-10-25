#!/usr/bin/env bash
# Prints the cache key of libtdjson.so: a hash of the TDLib pin and the build
# script. CI publishes each build as release tdlib-<key>.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
git hash-object packages/lumina_tdlib/schema/VERSION tool/build_tdlib.sh | sha256sum | cut -c1-16
