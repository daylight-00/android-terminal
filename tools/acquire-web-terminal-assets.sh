#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/android-native-shell/upstream
TARGET=$ROOT/app/src/main/assets/terminal/vendor
TMP=$(mktemp -d "${TMPDIR:-/tmp}/android-native-shell-assets.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT

XTERM_URL='https://registry.npmjs.org/@xterm/xterm/-/xterm-6.0.0.tgz'
XTERM_INTEGRITY='sha512-TQwDdQGtwwDt+2cgKDLn0IRaSxYu1tSUjgKarSDkUM0ZNiSRXFpjxEsvc/Zgc5kq5omJ+V0a8/kIM2WD3sMOYg=='
FIT_URL='https://registry.npmjs.org/@xterm/addon-fit/-/addon-fit-0.11.0.tgz'
FIT_INTEGRITY='sha512-jYcgT6xtVYhnhgxh3QgYDnnNMYTcf8ElbxxFzX0IZo+vabQqSPAjC3c1wJrKB5E19VwQei89QCiZZP86DCPF7g=='
MAX_ARCHIVE_BYTES=$((16 * 1024 * 1024))

mkdir -p -- "$CACHE"

fetch() {
  local url=$1
  local destination=$2
  if [ -f "$destination" ]; then
    printf 'REUSE %s\n' "$destination"
    return
  fi
  local partial=$destination.partial.$$
  rm -f -- "$partial"
  curl \
    --fail \
    --location \
    --proto '=https' \
    --tlsv1.2 \
    --retry 3 \
    --retry-all-errors \
    --connect-timeout 20 \
    --max-time 180 \
    --output "$partial" \
    "$url"
  local size
  size=$(wc -c < "$partial")
  if [ "$size" -le 0 ] || [ "$size" -gt "$MAX_ARCHIVE_BYTES" ]; then
    printf 'invalid archive size: %s bytes for %s\n' "$size" "$url" >&2
    rm -f -- "$partial"
    exit 1
  fi
  mv -f -- "$partial" "$destination"
}

XTERM_ARCHIVE=$CACHE/xterm-6.0.0.tgz
FIT_ARCHIVE=$CACHE/addon-fit-0.11.0.tgz
fetch "$XTERM_URL" "$XTERM_ARCHIVE"
fetch "$FIT_URL" "$FIT_ARCHIVE"

python3 "$ROOT/tools/provision-web-terminal-assets.py" \
  --xterm-archive "$XTERM_ARCHIVE" \
  --xterm-url "$XTERM_URL" \
  --xterm-integrity "$XTERM_INTEGRITY" \
  --fit-archive "$FIT_ARCHIVE" \
  --fit-url "$FIT_URL" \
  --fit-integrity "$FIT_INTEGRITY" \
  --destination "$TMP/vendor"

BACKUP=$TMP/vendor.previous
if [ -e "$TARGET" ]; then
  mv -- "$TARGET" "$BACKUP"
fi
if mv -- "$TMP/vendor" "$TARGET"; then
  rm -rf -- "$BACKUP"
else
  rm -rf -- "$TARGET"
  [ ! -e "$BACKUP" ] || mv -- "$BACKUP" "$TARGET"
  exit 1
fi

python3 "$ROOT/tools/verify-web-assets.py" "$ROOT"
printf 'PASS acquired pinned xterm.js assets into %s\n' "$TARGET"
