#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE="$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalDocumentPolicy.kt"

if command -v kotlinc >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  cat > "$WORK/TestDocumentPolicy.kt" <<'KT'
package io.github.daylight00.androidterminal

import java.io.File

fun main() {
    check(TerminalDocumentPolicy.sanitizedDisplayName("folder/name.txt") == "name.txt")
    check(TerminalDocumentPolicy.sanitizedDisplayName("../") == "document")
    check(TerminalDocumentPolicy.sanitizedDisplayName("a\u0000b.txt") == "a_b.txt")
    check(TerminalDocumentPolicy.boundedMimeType("text/plain") == "text/plain")
    check(TerminalDocumentPolicy.boundedMimeType("bad value") == "application/octet-stream")
    check(TerminalDocumentPolicy.boundedMimeType("*/*", "*/*") == "*/*")

    check(TerminalDocumentPolicy.validatedRelativeHomePath("incoming/a.txt") == "incoming/a.txt")
    check(TerminalDocumentPolicy.validatedRelativeHomeDirectory("") == "")
    check(TerminalDocumentPolicy.validatedRelativeHomeDirectory("incoming") == "incoming")
    check(TerminalDocumentPolicy.validatedRelativeHomeDirectory("../escape") == null)
    check(TerminalDocumentPolicy.validatedRelativeHomePath("/absolute") == null)
    check(TerminalDocumentPolicy.validatedRelativeHomePath("../escape") == null)
    check(TerminalDocumentPolicy.validatedRelativeHomePath("a//b") == null)
    check(TerminalDocumentPolicy.validatedRelativeHomePath("a\\b") == null)

    val root = File(System.getProperty("java.io.tmpdir"), "terminal-document-policy-${System.nanoTime()}")
    check(root.mkdirs())
    try {
        check(TerminalDocumentPolicy.resolvePrivateImportDirectory(root, "") == root.canonicalFile)
        val nested = checkNotNull(TerminalDocumentPolicy.resolvePrivateImportDirectory(root, "incoming"))
        check(nested == File(root, "incoming").canonicalFile)
        val file = File(nested, "value.txt")
        file.writeText("value")
        check(TerminalDocumentPolicy.resolvePrivateExportSource(root, "incoming/value.txt") == file.canonicalFile)
        check(TerminalDocumentPolicy.resolvePrivateExportSource(root, "../value.txt") == null)
        check(TerminalDocumentPolicy.uniqueImportTarget(nested, "value.txt").name == "value (1).txt")
    } finally {
        root.deleteRecursively()
    }
    println("PASS terminal-document-policy runtime=kotlinc private-home=bounded")
}
KT
  kotlinc "$SOURCE" "$WORK/TestDocumentPolicy.kt" -include-runtime -d "$WORK/document-policy.jar"
  java -jar "$WORK/document-policy.jar"
else
  python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
for token in (
    "MAX_DOCUMENT_BYTES",
    "sanitizedDisplayName",
    "boundedMimeType",
    "validatedRelativeHomePath",
    "validatedRelativeHomeDirectory",
    "resolvePrivateImportDirectory",
    "resolvePrivateExportSource",
    "uniqueImportTarget",
):
    if token not in source:
        raise SystemExit(f"missing document policy token: {token}")
print("PASS terminal-document-policy static-python kotlinc=unavailable")
PY
fi
