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
python3 "$ROOT/tools/verify-upstream-capabilities.py" "$SUCCESS" >/dev/null
python3 "$ROOT/tools/verify-layer2-completion.py" "$SUCCESS" >/dev/null
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


ENVIRONMENT_NEGATIVE=$TMP/environment-negative
copy_fixture "$ENVIRONMENT_NEGATIVE"
printf '\n/* PATH=/system/bin */\n' >> "$ENVIRONMENT_NEGATIVE/app/src/main/c/session_environment.c"
if python3 "$ROOT/tools/verify_policy.py" "$ENVIRONMENT_NEGATIVE" >/dev/null 2>&1; then
  printf 'FAIL verifier-environment-negative unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-environment-negative\n'

HOME_LINK_NEGATIVE=$TMP/home-link-negative
copy_fixture "$HOME_LINK_NEGATIVE"
printf '\n// prepareHomeLink Os.symlink\n' >> "$HOME_LINK_NEGATIVE/app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSharedStorage.kt"
if python3 "$ROOT/tools/verify-layer-boundaries.py" "$HOME_LINK_NEGATIVE" >/dev/null 2>&1; then
  printf 'FAIL verifier-home-link-negative unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-home-link-negative\n'

TMPDIR_NEGATIVE=$TMP/tmpdir-negative
copy_fixture "$TMPDIR_NEGATIVE"
python3 - "$TMPDIR_NEGATIVE/app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSessionService.kt" <<'PYNEG'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
path.write_text(text.replace('java.io.File(cacheDir, "tmp")', 'cacheDir', 1), encoding='utf-8')
PYNEG
if python3 "$ROOT/tools/verify_policy.py" "$TMPDIR_NEGATIVE" >/dev/null 2>&1; then
  printf 'FAIL verifier-tmpdir-negative unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-tmpdir-negative\n'

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

CAPABILITY_NEGATIVE=$TMP/capability-negative
copy_fixture "$CAPABILITY_NEGATIVE"
python3 - "$CAPABILITY_NEGATIVE/docs/upstream-capabilities.json" <<'PY'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["official_addons"] = [
    row for row in data["official_addons"]
    if row["package"] != "@xterm/addon-image"
]
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
if python3 "$ROOT/tools/verify-upstream-capabilities.py" "$CAPABILITY_NEGATIVE" >/dev/null 2>&1; then
  printf 'FAIL verifier-capability-negative unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-capability-negative\n'

CAPABILITY_INCOMPLETE=$TMP/capability-incomplete
copy_fixture "$CAPABILITY_INCOMPLETE"
rm -f -- "$CAPABILITY_INCOMPLETE/docs/upstream-capabilities.json"
if python3 "$ROOT/tools/verify-upstream-capabilities.py" "$CAPABILITY_INCOMPLETE" >/dev/null 2>&1; then
  printf 'FAIL verifier-capability-incomplete unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-capability-incomplete\n'

LAYER3_NEGATIVE=$TMP/layer3-negative
copy_fixture "$LAYER3_NEGATIVE"
printf '\nconst nativePort = null;\n' >> "$LAYER3_NEGATIVE/app/src/main/assets/terminal/customization/customization.js"
if python3 "$ROOT/tools/verify-layer-boundaries.py" "$LAYER3_NEGATIVE" >/dev/null 2>&1; then
  printf 'FAIL verifier-layer3-negative unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-layer3-negative\n'

LAYER3_INCOMPLETE=$TMP/layer3-incomplete
copy_fixture "$LAYER3_INCOMPLETE"
rm -f -- "$LAYER3_INCOMPLETE/app/src/main/assets/terminal/customization/customization.js"
if python3 "$ROOT/tools/verify_policy.py" "$LAYER3_INCOMPLETE" >/dev/null 2>&1; then
  printf 'FAIL verifier-layer3-incomplete unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-layer3-incomplete\n'

LAYER2_DEPENDENCY_NEGATIVE=$TMP/layer2-dependency-negative
copy_fixture "$LAYER2_DEPENDENCY_NEGATIVE"
printf '\nvoid window.AndroidTerminalCustomization;\n' >> "$LAYER2_DEPENDENCY_NEGATIVE/app/src/main/assets/terminal/bridge/terminal-bridge.js"
if python3 "$ROOT/tools/verify-layer-boundaries.py" "$LAYER2_DEPENDENCY_NEGATIVE" >/dev/null 2>&1; then
  printf 'FAIL verifier-layer2-dependency-negative unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-layer2-dependency-negative\n'

THEME_AUTHORITY_NEGATIVE=$TMP/theme-authority-negative
copy_fixture "$THEME_AUTHORITY_NEGATIVE"
printf '\nterminal.options.theme = {};\n' >> "$THEME_AUTHORITY_NEGATIVE/app/src/main/assets/terminal/bridge/terminal-platform.js"
if python3 "$ROOT/tools/verify-layer-boundaries.py" "$THEME_AUTHORITY_NEGATIVE" >/dev/null 2>&1; then
  printf 'FAIL verifier-theme-authority-negative unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-theme-authority-negative\n'

ASSET_ALLOWLIST_NEGATIVE=$TMP/asset-allowlist-negative
copy_fixture "$ASSET_ALLOWLIST_NEGATIVE"
python3 - "$ASSET_ALLOWLIST_NEGATIVE/app/src/main/kotlin/io/github/daylight00/androidterminal/LocalAssetWebViewClient.kt" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace(
    '''            "/terminal/customization/customization.js" to Asset(\n                "terminal/customization/customization.js",\n                "application/javascript",\n            ),\n''',
    '',
    1,
)
path.write_text(text, encoding="utf-8")
PY
if python3 "$ROOT/tools/verify-layer-boundaries.py" "$ASSET_ALLOWLIST_NEGATIVE" >/dev/null 2>&1; then
  printf 'FAIL verifier-asset-allowlist-negative unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-asset-allowlist-negative\n'

CORE_HOST_NEGATIVE=$TMP/core-host-negative
copy_fixture "$CORE_HOST_NEGATIVE"
python3 - "$CORE_HOST_NEGATIVE/app/src/main/assets/terminal/bridge/terminal-platform.js" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("getWinSizePixels: true", "getScreenSizePixels: true", 1)
path.write_text(text, encoding="utf-8")
PY
if python3 "$ROOT/tools/verify-layer-boundaries.py" "$CORE_HOST_NEGATIVE" >/dev/null 2>&1; then
  printf 'FAIL verifier-core-host-negative unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-core-host-negative\n'

CORE_HOST_TITLE_NEGATIVE=$TMP/core-host-title-negative
copy_fixture "$CORE_HOST_TITLE_NEGATIVE"
python3 - "$CORE_HOST_TITLE_NEGATIVE/app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSessionService.kt" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("title = TerminalSessionTitle.sanitize(value)", "title = value", 1)
path.write_text(text, encoding="utf-8")
PY
if python3 "$ROOT/tools/verify_policy.py" "$CORE_HOST_TITLE_NEGATIVE" >/dev/null 2>&1; then
  printf 'FAIL verifier-core-host-title-negative unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-core-host-title-negative\n'

CORE_HOST_INCOMPLETE=$TMP/core-host-incomplete
copy_fixture "$CORE_HOST_INCOMPLETE"
rm -f -- "$CORE_HOST_INCOMPLETE/app/src/main/res/values/strings.xml"
if python3 "$ROOT/tools/verify_policy.py" "$CORE_HOST_INCOMPLETE" >/dev/null 2>&1; then
  printf 'FAIL verifier-core-host-incomplete unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-core-host-incomplete\n'

STABLE_ADDON_NEGATIVE=$TMP/stable-addon-negative
copy_fixture "$STABLE_ADDON_NEGATIVE"
python3 - "$STABLE_ADDON_NEGATIVE/app/src/main/assets/terminal/bridge/terminal-bridge.js" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace(
    "new window.ClipboardAddon.ClipboardAddon(undefined, clipboardProvider)",
    "new window.ClipboardAddon.ClipboardAddon(clipboardProvider)",
    1,
)
path.write_text(text, encoding="utf-8")
PY
if python3 "$ROOT/tools/verify_policy.py" "$STABLE_ADDON_NEGATIVE" >/dev/null 2>&1; then
  printf 'FAIL verifier-stable-addon-negative unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-stable-addon-negative\n'

STABLE_ADDON_INCOMPLETE=$TMP/stable-addon-incomplete
copy_fixture "$STABLE_ADDON_INCOMPLETE"
python3 - "$STABLE_ADDON_INCOMPLETE/app/src/main/assets/terminal/bridge/index.html" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace('  <script src="/terminal/vendor/addon-image.js"></script>\n', '', 1)
path.write_text(text, encoding="utf-8")
PY
if python3 "$ROOT/tools/verify-layer-boundaries.py" "$STABLE_ADDON_INCOMPLETE" >/dev/null 2>&1; then
  printf 'FAIL verifier-stable-addon-incomplete unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-stable-addon-incomplete\n'

LOGIN_SHELL_NEGATIVE=$TMP/login-shell-negative
copy_fixture "$LOGIN_SHELL_NEGATIVE"
python3 - "$LOGIN_SHELL_NEGATIVE/app/src/main/c/shell_bridge.c" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace('char *const arguments[] = {"-sh", NULL};', 'char *const arguments[] = {shell_path, NULL};', 1)
path.write_text(text, encoding="utf-8")
PY
if python3 "$ROOT/tools/verify_policy.py" "$LOGIN_SHELL_NEGATIVE" >/dev/null 2>&1; then
  printf 'FAIL verifier-login-shell-negative unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS verifier-login-shell-negative\n'
