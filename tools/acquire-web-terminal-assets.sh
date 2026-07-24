#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/android-terminal/upstream
TARGET=$ROOT/app/src/main/assets/terminal/vendor
TMP=$(mktemp -d "${TMPDIR:-/tmp}/android-terminal-assets.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT
MAX_ARCHIVE_BYTES=$((16 * 1024 * 1024))
MAX_METADATA_BYTES=$((1024 * 1024))
mkdir -p -- "$CACHE"

fetch() {
  local url=$1 destination=$2 maximum=${3:-$MAX_ARCHIVE_BYTES}
  if [ -f "$destination" ]; then
    local existing_size
    existing_size=$(wc -c < "$destination")
    if [ "$existing_size" -gt 0 ] && [ "$existing_size" -le "$maximum" ]; then
      printf 'REUSE %s\n' "$destination"
      return
    fi
    rm -f -- "$destination"
  fi
  local partial=$destination.partial.$$
  rm -f -- "$partial"
  curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --retry-all-errors \
    --connect-timeout 20 --max-time 180 --output "$partial" "$url"
  local size
  size=$(wc -c < "$partial")
  if [ "$size" -le 0 ] || [ "$size" -gt "$maximum" ]; then
    printf 'invalid download size: %s bytes for %s\n' "$size" "$url" >&2
    rm -f -- "$partial"
    exit 1
  fi
  mv -f -- "$partial" "$destination"
}

resolve_integrity() {
  local encoded_name=$1 expected_name=$2 version=$3 expected_tarball=$4
  local metadata=$CACHE/metadata-${encoded_name//%/}-${version}.json
  fetch "https://registry.npmjs.org/${encoded_name}/${version}" "$metadata" "$MAX_METADATA_BYTES" >&2
  python3 - "$metadata" "$expected_name" "$version" "$expected_tarball" <<'PYMETA'
import json, pathlib, sys
path, expected_name, expected_version, expected_tarball = sys.argv[1:]
data = json.loads(pathlib.Path(path).read_text(encoding='utf-8'))
if data.get('name') != expected_name or data.get('version') != expected_version:
    raise SystemExit('registry metadata identity mismatch')
dist = data.get('dist')
if not isinstance(dist, dict) or dist.get('tarball') != expected_tarball:
    raise SystemExit('registry metadata tarball mismatch')
integrity = dist.get('integrity')
if not isinstance(integrity, str) or not integrity.startswith('sha512-'):
    raise SystemExit('registry metadata lacks SHA-512 integrity')
print(integrity)
PYMETA
}

XTERM_URL='https://registry.npmjs.org/@xterm/xterm/-/xterm-6.0.0.tgz'
XTERM_INTEGRITY='sha512-TQwDdQGtwwDt+2cgKDLn0IRaSxYu1tSUjgKarSDkUM0ZNiSRXFpjxEsvc/Zgc5kq5omJ+V0a8/kIM2WD3sMOYg=='
FIT_URL='https://registry.npmjs.org/@xterm/addon-fit/-/addon-fit-0.11.0.tgz'
FIT_INTEGRITY='sha512-jYcgT6xtVYhnhgxh3QgYDnnNMYTcf8ElbxxFzX0IZo+vabQqSPAjC3c1wJrKB5E19VwQei89QCiZZP86DCPF7g=='
SERIALIZE_URL='https://registry.npmjs.org/@xterm/addon-serialize/-/addon-serialize-0.13.0.tgz'
SERIALIZE_INTEGRITY='sha512-kGs8o6LWAmN1l2NpMp01/YkpxbmO4UrfWybeGu79Khw5K9+Krp7XhXbBTOTc3GJRRhd6EmILjpR8k5+odY39YQ=='
WEBGL_URL='https://registry.npmjs.org/@xterm/addon-webgl/-/addon-webgl-0.19.0.tgz'
WEBGL_INTEGRITY='sha512-b3fMOsyLVuCeNJWxolACEUED0vm7qC0cy4wRvf3oURSzDTYVQiGPhTnhWZwIHdvC48Y+oLhvYXnY4XDXPoJo6A=='
WEB_LINKS_URL='https://registry.npmjs.org/@xterm/addon-web-links/-/addon-web-links-0.12.0.tgz'
WEB_LINKS_INTEGRITY='sha512-4Smom3RPyVp7ZMYOYDoC/9eGJJJqYhnPLGGqJ6wOBfB8VxPViJNSKdgRYb8NpaM6YSelEKbA2SStD7lGyqaobw=='
CLIPBOARD_URL='https://registry.npmjs.org/@xterm/addon-clipboard/-/addon-clipboard-0.2.0.tgz'
IMAGE_URL='https://registry.npmjs.org/@xterm/addon-image/-/addon-image-0.9.0.tgz'
PROGRESS_URL='https://registry.npmjs.org/@xterm/addon-progress/-/addon-progress-0.2.0.tgz'
SEARCH_URL='https://registry.npmjs.org/@xterm/addon-search/-/addon-search-0.16.0.tgz'
UNICODE11_URL='https://registry.npmjs.org/@xterm/addon-unicode11/-/addon-unicode11-0.9.0.tgz'
WEB_FONTS_URL='https://registry.npmjs.org/@xterm/addon-web-fonts/-/addon-web-fonts-0.1.0.tgz'
LIGATURES_URL='https://registry.npmjs.org/@xterm/addon-ligatures/-/addon-ligatures-0.10.0.tgz'
CLIPBOARD_INTEGRITY=$(resolve_integrity '%40xterm%2Faddon-clipboard' '@xterm/addon-clipboard' '0.2.0' "$CLIPBOARD_URL")
IMAGE_INTEGRITY=$(resolve_integrity '%40xterm%2Faddon-image' '@xterm/addon-image' '0.9.0' "$IMAGE_URL")
PROGRESS_INTEGRITY=$(resolve_integrity '%40xterm%2Faddon-progress' '@xterm/addon-progress' '0.2.0' "$PROGRESS_URL")
SEARCH_INTEGRITY=$(resolve_integrity '%40xterm%2Faddon-search' '@xterm/addon-search' '0.16.0' "$SEARCH_URL")
UNICODE11_INTEGRITY=$(resolve_integrity '%40xterm%2Faddon-unicode11' '@xterm/addon-unicode11' '0.9.0' "$UNICODE11_URL")
WEB_FONTS_INTEGRITY=$(resolve_integrity '%40xterm%2Faddon-web-fonts' '@xterm/addon-web-fonts' '0.1.0' "$WEB_FONTS_URL")
LIGATURES_INTEGRITY=$(resolve_integrity '%40xterm%2Faddon-ligatures' '@xterm/addon-ligatures' '0.10.0' "$LIGATURES_URL")

for spec in \
  'XTERM xterm-6.0.0' \
  'FIT addon-fit-0.11.0' \
  'SERIALIZE addon-serialize-0.13.0' \
  'WEBGL addon-webgl-0.19.0' \
  'WEB_LINKS addon-web-links-0.12.0' \
  'CLIPBOARD addon-clipboard-0.2.0' \
  'IMAGE addon-image-0.9.0' \
  'PROGRESS addon-progress-0.2.0' \
  'SEARCH addon-search-0.16.0' \
  'UNICODE11 addon-unicode11-0.9.0' \
  'WEB_FONTS addon-web-fonts-0.1.0' \
  'LIGATURES addon-ligatures-0.10.0'; do
  set -- $spec
  variable=$1 filename=$2
  eval "url=\${${variable}_URL}"
  archive=$CACHE/$filename.tgz
  eval "${variable}_ARCHIVE=\$archive"
  fetch "$url" "$archive"
done

python3 "$ROOT/tools/provision-web-terminal-assets.py" \
  --xterm-archive "$XTERM_ARCHIVE" --xterm-url "$XTERM_URL" --xterm-integrity "$XTERM_INTEGRITY" \
  --fit-archive "$FIT_ARCHIVE" --fit-url "$FIT_URL" --fit-integrity "$FIT_INTEGRITY" \
  --serialize-archive "$SERIALIZE_ARCHIVE" --serialize-url "$SERIALIZE_URL" --serialize-integrity "$SERIALIZE_INTEGRITY" \
  --webgl-archive "$WEBGL_ARCHIVE" --webgl-url "$WEBGL_URL" --webgl-integrity "$WEBGL_INTEGRITY" \
  --web-links-archive "$WEB_LINKS_ARCHIVE" --web-links-url "$WEB_LINKS_URL" --web-links-integrity "$WEB_LINKS_INTEGRITY" \
  --clipboard-archive "$CLIPBOARD_ARCHIVE" --clipboard-url "$CLIPBOARD_URL" --clipboard-integrity "$CLIPBOARD_INTEGRITY" \
  --image-archive "$IMAGE_ARCHIVE" --image-url "$IMAGE_URL" --image-integrity "$IMAGE_INTEGRITY" \
  --progress-archive "$PROGRESS_ARCHIVE" --progress-url "$PROGRESS_URL" --progress-integrity "$PROGRESS_INTEGRITY" \
  --search-archive "$SEARCH_ARCHIVE" --search-url "$SEARCH_URL" --search-integrity "$SEARCH_INTEGRITY" \
  --unicode11-archive "$UNICODE11_ARCHIVE" --unicode11-url "$UNICODE11_URL" --unicode11-integrity "$UNICODE11_INTEGRITY" \
  --web-fonts-archive "$WEB_FONTS_ARCHIVE" --web-fonts-url "$WEB_FONTS_URL" --web-fonts-integrity "$WEB_FONTS_INTEGRITY" \
  --ligatures-archive "$LIGATURES_ARCHIVE" --ligatures-url "$LIGATURES_URL" --ligatures-integrity "$LIGATURES_INTEGRITY" \
  --destination "$TMP/vendor"

BACKUP=$TMP/vendor.previous
if [ -e "$TARGET" ]; then mv -- "$TARGET" "$BACKUP"; fi
if mv -- "$TMP/vendor" "$TARGET"; then rm -rf -- "$BACKUP"; else
  rm -rf -- "$TARGET"; [ ! -e "$BACKUP" ] || mv -- "$BACKUP" "$TARGET"; exit 1
fi
python3 "$ROOT/tools/verify-web-assets.py" "$ROOT"
printf 'PASS acquired pinned xterm.js assets into %s\n' "$TARGET"
