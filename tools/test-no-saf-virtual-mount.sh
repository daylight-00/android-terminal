#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p \
  "$WORK/app/src/main/kotlin" \
  "$WORK/app/src/main/c" \
  "$WORK/app/src/main/assets/terminal/bridge" \
  "$WORK/app/src/main/assets/terminal/customization" \
  "$WORK/app/src/main/assets/terminal/vendor"
printf '<manifest/>\n' > "$WORK/app/src/main/AndroidManifest.xml"
printf 'object SafeLayer\n' > "$WORK/app/src/main/kotlin/SafeLayer.kt"
printf '/* safe native bridge */\n' > "$WORK/app/src/main/c/safe.c"
printf '/* safe bridge */\n' > "$WORK/app/src/main/assets/terminal/bridge/safe.js"
printf '/* safe customization */\n' > "$WORK/app/src/main/assets/terminal/customization/safe.js"
printf 'upstream bytes may contain FUSE as an unrelated token\n' > "$WORK/app/src/main/assets/terminal/vendor/xterm.js"

"$ROOT/tools/verify-no-saf-virtual-mount.sh" "$WORK" >/dev/null
printf '// forbidden authored token: FUSE\n' >> "$WORK/app/src/main/kotlin/SafeLayer.kt"
if "$ROOT/tools/verify-no-saf-virtual-mount.sh" "$WORK" >/dev/null 2>&1; then
  printf 'FAIL no-saf-virtual-mount-fixture authored-token-was-not-rejected\n' >&2
  exit 1
fi
printf 'PASS no-saf-virtual-mount-fixture vendor=false-positive-ignored authored=true-positive-rejected\n'
