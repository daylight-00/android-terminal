#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PACKAGE_ROOT="$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal"
BRIDGE="$ROOT/app/src/main/assets/terminal/bridge/terminal-bridge.js"
PLATFORM="$ROOT/app/src/main/assets/terminal/bridge/terminal-platform.js"
CONTRACT="$ROOT/app/src/main/assets/terminal/bridge/terminal-contract.js"
VALUES="$ROOT/app/src/main/res/values/strings.xml"
VALUES_KO="$ROOT/app/src/main/res/values-ko/strings.xml"

python3 - "$PACKAGE_ROOT" "$BRIDGE" "$PLATFORM" "$CONTRACT" "$VALUES" "$VALUES_KO" <<'PY'
from pathlib import Path
import sys

package_root, bridge_path, platform_path, contract_path, values_path, values_ko_path = map(Path, sys.argv[1:])
service = (package_root / "TerminalSessionService.kt").read_text(encoding="utf-8")
controller = (package_root / "TerminalController.kt").read_text(encoding="utf-8")
adapter = (package_root / "TerminalPlatformAdapter.kt").read_text(encoding="utf-8")
contract_kt = (package_root / "TerminalContract.kt").read_text(encoding="utf-8")
bridge = bridge_path.read_text(encoding="utf-8")
platform = platform_path.read_text(encoding="utf-8")
contract = contract_path.read_text(encoding="utf-8")
values = values_path.read_text(encoding="utf-8")
values_ko = values_ko_path.read_text(encoding="utf-8")

required = {
    "service-owned title": (service, "fun updateTitle(", "title = TerminalSessionTitle.sanitize(value)", "title = \"\"", "title = title"),
    "controller title transport": (controller, "TerminalContract.MessageType.SESSION_TITLE", "handleSessionTitle", '.put("title", attachment.title)'),
    "page title bridge": (bridge, "terminal.onTitleChange(", "onTitleState", "getTitleState()", "contract.messages.sessionTitle"),
    "Android localization": (adapter, "configuration.locales[0].toLanguageTag()", "R.string.xterm_prompt_label", "R.string.xterm_too_much_output"),
    "page localization": (platform, "terminal.strings.promptLabel", "terminal.strings.tooMuchOutput", "MAX_LOCALIZED_STRING_CHARACTERS"),
    "safe window reports": (platform, "getWinSizePixels: true", "getCellSizePixels: true", "getWinSizeChars: true", "pushTitle: true", "popTitle: true", "registerCsiHandler({final: 't'}", "terminal.refresh(", "terminal.input("),
    "capability contract": (contract + contract_kt, "session-title-state-v1", "localized-xterm-strings-v1", "safe-window-reports-v1", "android-localized-xterm-strings"),
    "default strings": (values, 'name="xterm_prompt_label"', 'name="xterm_too_much_output"'),
    "Korean strings": (values_ko, 'name="xterm_prompt_label"', 'name="xterm_too_much_output"'),
}
for label, (text, *tokens) in required.items():
    for token in tokens:
        if token not in text:
            raise SystemExit(f"{label} missing token: {token}")

for forbidden in (
    "fullscreenWin: true",
    "setWinPosition: true",
    "getScreenSizePixels: true",
    "getScreenSizeChars: true",
    "setWinSizePixels: true",
    "setWinSizeChars: true",
):
    if forbidden in platform:
        raise SystemExit(f"unsafe or desktop-only window operation enabled: {forbidden}")

print("PASS core-host-integration static title=service-owned localization=android-resources window-reports=safe-subset")
PY

if command -v kotlinc >/dev/null 2>&1; then
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  cat > "$WORK/TestTerminalSessionTitle.kt" <<'KT'
package io.github.daylight00.androidterminal

fun main() {
    check(TerminalSessionTitle.sanitize("build\u0007 title\u007f") == "build title")
    val emoji = "😀"
    val bounded = TerminalSessionTitle.sanitize("x".repeat(1023) + emoji + "tail")
    check(bounded.codePointCount(0, bounded.length) == TerminalSessionTitle.MAX_CODE_POINTS)
    check(bounded.endsWith(emoji))
    check(!bounded.endsWith(emoji.substring(0, 1)))
    println("PASS terminal-session-title runtime=kotlinc controls=removed codepoints=1024 surrogate-safe=yes")
}
KT
  kotlinc -nowarn \
    "$PACKAGE_ROOT/TerminalSessionTitle.kt" \
    "$WORK/TestTerminalSessionTitle.kt" \
    -include-runtime -d "$WORK/title-test.jar"
  java -jar "$WORK/title-test.jar"
else
  echo "PASS terminal-session-title static kotlinc=unavailable controls=removed codepoints=1024"
fi
