#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/android-native-shell-verifier.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT

copy_fixture() {
  local destination=$1
  mkdir -p -- "$destination"
  tar -C "$ROOT" \
    --exclude=.git \
    --exclude=out \
    -cf - app tools | tar -C "$destination" -xf -
}

SUCCESS="$TMP/success"
copy_fixture "$SUCCESS"
python3 "$ROOT/tools/verify_policy.py" "$SUCCESS" >/dev/null
printf 'PASS verifier-success-fixture\n'

NEGATIVE="$TMP/negative"
copy_fixture "$NEGATIVE"
python3 - "$NEGATIVE/app/build.gradle" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
path.write_text(text.replace('minSdk 29', 'minSdk 28', 1), encoding='utf-8')
PY
if python3 "$ROOT/tools/verify_policy.py" "$NEGATIVE" >/dev/null 2>&1; then
  printf 'FAIL verifier-negative-fixture unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-negative-fixture\n'

INCOMPLETE="$TMP/incomplete"
copy_fixture "$INCOMPLETE"
rm -f -- "$INCOMPLETE/app/src/main/c/shell_bridge.c"
if python3 "$ROOT/tools/verify_policy.py" "$INCOMPLETE" >/dev/null 2>&1; then
  printf 'FAIL verifier-incomplete-fixture unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-incomplete-fixture\n'
