#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/android-terminal-verifier.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT

copy_fixture() {
  local destination=$1
  mkdir -p -- "$destination"
  tar -C "$ROOT" \
    --exclude=.git \
    --exclude=out \
    -cf - app tools build-tools docs build.gradle settings.gradle README.md | tar -C "$destination" -xf -
}

SUCCESS=$TMP/success
copy_fixture "$SUCCESS"
python3 "$ROOT/tools/verify_policy.py" "$SUCCESS" >/dev/null
python3 "$ROOT/tools/verify-layer-boundaries.py" "$SUCCESS" >/dev/null
python3 "$ROOT/tools/verify-web-assets.py" "$SUCCESS" >/dev/null
printf 'PASS verifier-success-fixture\n'

NEGATIVE=$TMP/negative
copy_fixture "$NEGATIVE"
python3 - "$NEGATIVE/app/build.gradle" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(text.replace("minSdk 29", "minSdk 28", 1), encoding="utf-8")
PY
if python3 "$ROOT/tools/verify_policy.py" "$NEGATIVE" >/dev/null 2>&1; then
  printf 'FAIL verifier-negative-fixture unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-negative-fixture\n'

TARGET_NEGATIVE=$TMP/target-negative
copy_fixture "$TARGET_NEGATIVE"
python3 - "$TARGET_NEGATIVE/app/build.gradle" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(text.replace("targetSdk 28", "targetSdk 29", 1), encoding="utf-8")
PY
if python3 "$ROOT/tools/verify_policy.py" "$TARGET_NEGATIVE" >/dev/null 2>&1; then
  printf 'FAIL verifier-target-negative unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-target-negative\n'

INCOMPLETE=$TMP/incomplete
copy_fixture "$INCOMPLETE"
rm -f -- "$INCOMPLETE/app/src/main/c/shell_bridge.c"
if python3 "$ROOT/tools/verify_policy.py" "$INCOMPLETE" >/dev/null 2>&1; then
  printf 'FAIL verifier-incomplete-fixture unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-incomplete-fixture\n'

PARTIAL=$TMP/partial-assets
copy_fixture "$PARTIAL"
printf 'partial' > "$PARTIAL/app/src/main/assets/terminal/vendor/xterm.js"
if python3 "$ROOT/tools/verify-web-assets.py" "$PARTIAL" >/dev/null 2>&1; then
  printf 'FAIL verifier-partial-assets unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-partial-assets\n'


BOUNDARY=$TMP/layer-boundary
copy_fixture "$BOUNDARY"
printf '\nconst fontSize = 99;\n' >> "$BOUNDARY/app/src/main/assets/terminal/bridge/terminal-bridge.js"
if python3 "$ROOT/tools/verify-layer-boundaries.py" "$BOUNDARY" >/dev/null 2>&1; then
  printf 'FAIL verifier-layer-boundary-negative unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-layer-boundary-negative\n'

STORAGE_NEGATIVE=$TMP/storage-negative
copy_fixture "$STORAGE_NEGATIVE"
python3 - "$STORAGE_NEGATIVE/app/src/main/AndroidManifest.xml" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(
    text.replace(
        '    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />\n',
        '',
        1,
    ),
    encoding="utf-8",
)
PY
if python3 "$ROOT/tools/verify_policy.py" "$STORAGE_NEGATIVE" >/dev/null 2>&1; then
  printf 'FAIL verifier-storage-negative unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-storage-negative\n'

STORAGE_INCOMPLETE=$TMP/storage-incomplete
copy_fixture "$STORAGE_INCOMPLETE"
rm -f -- "$STORAGE_INCOMPLETE/app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSharedStorage.kt"
if python3 "$ROOT/tools/verify-layer-boundaries.py" "$STORAGE_INCOMPLETE" >/dev/null 2>&1; then
  printf 'FAIL verifier-storage-incomplete unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-storage-incomplete\n'

FONT_SCALE_NEGATIVE=$TMP/font-scale-negative
copy_fixture "$FONT_SCALE_NEGATIVE"
python3 - "$FONT_SCALE_NEGATIVE/app/src/main/assets/terminal/bridge/terminal-platform.js" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(
    text.replace(
        "upstreamFontSizes.get(terminal) * boundedFontScale(value)",
        "Number(terminal.options.fontSize) * boundedFontScale(value)",
        1,
    ),
    encoding="utf-8",
)
PY
if python3 "$ROOT/tools/verify-layer-boundaries.py" "$FONT_SCALE_NEGATIVE" >/dev/null 2>&1; then
  printf 'FAIL verifier-font-scale-negative unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-font-scale-negative\n'

FONT_SCALE_INCOMPLETE=$TMP/font-scale-incomplete
copy_fixture "$FONT_SCALE_INCOMPLETE"
rm -f -- "$FONT_SCALE_INCOMPLETE/tools/test-font-scale.sh"
if python3 "$ROOT/tools/verify_policy.py" "$FONT_SCALE_INCOMPLETE" >/dev/null 2>&1; then
  printf 'FAIL verifier-font-scale-incomplete unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-font-scale-incomplete\n'

WEB_LINKS_NEGATIVE=$TMP/web-links-negative
copy_fixture "$WEB_LINKS_NEGATIVE"
python3 - "$WEB_LINKS_NEGATIVE/app/src/main/assets/terminal/bridge/terminal-bridge.js" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(
    text.replace(
        "platform.openExternalUri(uri).catch(() => {});",
        "window.open(uri);",
        1,
    ),
    encoding="utf-8",
)
PY
if python3 "$ROOT/tools/verify-layer-boundaries.py" "$WEB_LINKS_NEGATIVE" >/dev/null 2>&1; then
  printf 'FAIL verifier-web-links-negative unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-web-links-negative\n'

WEB_LINKS_INCOMPLETE=$TMP/web-links-incomplete
copy_fixture "$WEB_LINKS_INCOMPLETE"
python3 - "$WEB_LINKS_INCOMPLETE/app/src/main/assets/terminal/bridge/index.html" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(
    text.replace(
        '  <script src="/terminal/vendor/addon-web-links.js"></script>\n',
        '',
        1,
    ),
    encoding="utf-8",
)
PY
if python3 "$ROOT/tools/verify_policy.py" "$WEB_LINKS_INCOMPLETE" >/dev/null 2>&1; then
  printf 'FAIL verifier-web-links-incomplete unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-web-links-incomplete\n'
