#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE="$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSessionDirectories.kt"

if ! command -v kotlinc >/dev/null 2>&1 || ! command -v kotlin >/dev/null 2>&1; then
  python3 - "$SOURCE" "$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSession.kt" "$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSessionService.kt" <<'PY'
from pathlib import Path
import sys
helper, session, service = (Path(value).read_text(encoding='utf-8') for value in sys.argv[1:])
for token in ('prepareTemporaryDirectory', 'directory.mkdirs()', 'directory.canRead()', 'directory.canWrite()'):
    if token not in helper:
        raise SystemExit(f'missing TMPDIR token: {token}')
if 'TerminalSessionDirectories.prepareTemporaryDirectory(temporaryDirectory)' not in session:
    raise SystemExit('session does not prepare TMPDIR')
if 'java.io.File(cacheDir, "tmp")' not in service:
    raise SystemExit('service does not map TMPDIR to cacheDir/tmp')
for forbidden in ('prepareHomeLink', 'File(homeDirectory, "storage")', 'Os.symlink'):
    if forbidden in session or forbidden in helper:
        raise SystemExit(f'HOME mutation remains: {forbidden}')
print('PASS session-directories static-python kotlinc=unavailable tmpdir=cacheDir/tmp home=untouched')
PY
  exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/android-terminal-directories.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$WORK/io/github/daylight00/androidterminal"
cat > "$WORK/io/github/daylight00/androidterminal/Test.kt" <<'KT'
package io.github.daylight00.androidterminal

import java.io.File
import java.io.IOException

fun main(args: Array<String>) {
    val root = File(args.single())
    val home = File(root, "files").apply { check(mkdirs()) }
    val cache = File(root, "cache").apply { check(mkdirs()) }
    val tmp = File(cache, "tmp")
    check(TerminalSessionDirectories.prepareTemporaryDirectory(tmp).canonicalFile == tmp.canonicalFile)
    check(tmp.isDirectory && tmp.canRead() && tmp.canWrite())
    check(home.list()?.isEmpty() == true)
    check(TerminalSessionDirectories.prepareTemporaryDirectory(tmp).canonicalFile == tmp.canonicalFile)

    val invalid = File(cache, "not-a-directory").apply { writeText("x") }
    try {
        TerminalSessionDirectories.prepareTemporaryDirectory(invalid)
        error("non-directory TMPDIR was accepted")
    } catch (_: IOException) {
        // expected
    }
    check(home.list()?.isEmpty() == true)
    println("PASS session-directories tmpdir=cacheDir/tmp home=untouched failure=explicit")
}
KT
kotlinc -nowarn "$SOURCE" "$WORK/io/github/daylight00/androidterminal/Test.kt" -include-runtime -d "$WORK/test.jar"
kotlin -classpath "$WORK/test.jar" io.github.daylight00.androidterminal.TestKt "$WORK/runtime"
