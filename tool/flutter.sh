#!/usr/bin/env bash
# Runs flutter with the Telegram API credentials from credential.txt (git-
# ignored) as --dart-defines, for local builds:
#   tool/flutter.sh run
#   tool/flutter.sh build apk --release --split-per-abi
# The file holds the api_id (digits) and api_hash (32 hex characters) from
# my.telegram.org; labels around them are ignored, so both the copied
# my.telegram.org layout and TG_API_ID=... / TG_API_HASH=... lines work.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
file="${LUMINA_CREDENTIALS:-$root/credential.txt}"
[[ -f "$file" ]] || { echo "Missing $file (api_id and api_hash from my.telegram.org)" >&2; exit 1; }

# Values may follow a label on the same line ("api_id: 123", "TG_API_ID=123").
id="$(grep -oE '(^|[^0-9A-Za-z])[0-9]{4,12}([^0-9A-Za-z]|$)' "$file" | grep -oE '[0-9]+' | head -n1 || true)"
hash="$(grep -oE '(^|[^0-9A-Za-z])[0-9a-fA-F]{32}([^0-9A-Za-z]|$)' "$file" | grep -oE '[0-9a-fA-F]{32}' | head -n1 || true)"
[[ -n "$id" && -n "$hash" ]] || { echo "Could not find api_id and api_hash in $file" >&2; exit 1; }

cmd="${1:-}"
case "$cmd" in
  run | build | drive | test | attach)
    shift
    exec flutter "$cmd" "$@" --dart-define=TG_API_ID="$id" --dart-define=TG_API_HASH="$hash"
    ;;
  *) exec flutter "$@" ;;
esac
