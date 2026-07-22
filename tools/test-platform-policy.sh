#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE="$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalPlatformPolicy.kt"

if command -v kotlinc >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  cat > "$WORK/TestPlatformPolicy.kt" <<'KT'
package io.github.daylight00.androidterminal

fun main() {
    val schemes = setOf("http", "https")
    check(TerminalPlatformPolicy.validatedExternalUri("https://example.com/path?q=1", schemes) != null)
    check(TerminalPlatformPolicy.validatedExternalUri("http://example.com", schemes) != null)
    check(TerminalPlatformPolicy.validatedExternalUri("HTTPS://example.com/path", schemes) != null)
    check(TerminalPlatformPolicy.validatedExternalUri("javascript:alert(1)", schemes) == null)
    check(TerminalPlatformPolicy.validatedExternalUri("file:///system/build.prop", schemes) == null)
    check(TerminalPlatformPolicy.validatedExternalUri("https://user:pass@example.com", schemes) == null)
    check(TerminalPlatformPolicy.validatedExternalUri("https://user@example.com", schemes) == null)
    check(TerminalPlatformPolicy.validatedExternalUri("https://example.com\\@evil.example", schemes) == null)
    check(TerminalPlatformPolicy.validatedExternalUri("https://", schemes) == null)
    check(TerminalPlatformPolicy.validatedExternalUri("https://example.com", emptySet()) == null)

    check(TerminalPlatformPolicy.boundedClipboardText(null) == null)
    check(TerminalPlatformPolicy.boundedClipboardText("") == null)
    check(TerminalPlatformPolicy.boundedClipboardText("", allowEmpty = true) == "")
    check(TerminalPlatformPolicy.boundedClipboardText("hello") == "hello")
    check(
        TerminalPlatformPolicy.boundedClipboardText(
            "x".repeat(TerminalPlatformPolicy.MAX_CLIPBOARD_CHARACTERS + 1),
        ) == null,
    )
    println("PASS terminal-platform-policy runtime=kotlinc uri=allowlisted clipboard=bounded")
}
KT
  kotlinc "$SOURCE" "$WORK/TestPlatformPolicy.kt" -include-runtime -d "$WORK/platform-policy.jar"
  java -jar "$WORK/platform-policy.jar"
else
  python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
for token in (
    "MAX_CLIPBOARD_CHARACTERS",
    "MAX_EXTERNAL_URI_CHARACTERS",
    "boundedClipboardText",
    "validatedExternalUri",
    "scheme !in allowedSchemes",
    "parsed.userInfo != null",
    "parsed.host.isNullOrBlank()",
):
    if token not in source:
        raise SystemExit(f"missing platform policy token: {token}")
print("PASS terminal-platform-policy static-python kotlinc=unavailable")
PY
fi
