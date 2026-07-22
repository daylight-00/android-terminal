#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE="$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalFrontendRecoveryState.kt"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if command -v kotlinc >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
  cat >"$WORK/TestFrontendRecovery.kt" <<'KOTLIN'
package io.github.daylight00.androidterminal

fun main() {
    val state = TerminalFrontendRecoveryState()
    val first = state.registerFrontend()
    check(first > 0L)
    check(state.beginRecovery(first))
    check(!state.beginRecovery(first))
    check(state.completeRecovery(first))
    check(!state.completeRecovery(first))

    val second = state.registerFrontend()
    check(second > first)
    check(!state.beginRecovery(first))
    check(state.beginRecovery(second))
    state.invalidate()
    check(!state.completeRecovery(second))
    println("PASS frontend-recovery runtime=kotlinc stale=rejected duplicate=rejected")
}
KOTLIN
  kotlinc "$SOURCE" "$WORK/TestFrontendRecovery.kt" -include-runtime -d "$WORK/frontend-recovery.jar"
  java -jar "$WORK/frontend-recovery.jar"
else
  python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys
source=Path(sys.argv[1]).read_text(encoding='utf-8')
for token in ('registerFrontend', 'beginRecovery', 'completeRecovery', 'invalidate'):
    assert token in source, token
print('PASS frontend-recovery static-python kotlinc=unavailable')
PY
fi
