#!/usr/bin/env bash
set -euo pipefail
ROOT=${1:-"$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"}
PATTERN='ACTION_OPEN_DOCUMENT_TREE|takePersistableUriPermission|DocumentsContract|FUSE'
TARGETS=(
  "$ROOT/app/src/main/kotlin"
  "$ROOT/app/src/main/c"
  "$ROOT/app/src/main/assets/terminal/bridge"
  "$ROOT/app/src/main/AndroidManifest.xml"
)

for target in "${TARGETS[@]}"; do
  [ -e "$target" ] || {
    printf 'FAIL no-saf-virtual-mount missing-target=%s\n' "$target" >&2
    exit 1
  }
done

if grep -R -n -E "$PATTERN" "${TARGETS[@]}"; then
  printf 'FAIL no-saf-virtual-mount authored-layer-token-detected\n' >&2
  exit 1
fi

printf 'PASS no-saf-virtual-mount scope=authored-layer2 vendor=excluded\n'
