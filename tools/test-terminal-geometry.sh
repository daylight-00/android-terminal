#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE="$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalGeometry.kt"

if command -v kotlinc >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  cat > "$WORK/TestGeometry.kt" <<'KT'
package io.github.daylight00.androidterminal

fun main() {
    val state = TerminalGeometryState()
    check(state.accept(TerminalDimensions(0, 80, 1080, 1920)) == null)
    check(state.accept(TerminalDimensions(24, 0, 1080, 1920)) == null)
    check(state.accept(TerminalDimensions(24, 80, 0, 1920)) == null)
    check(state.accept(TerminalDimensions(24, 80, 1080, 0)) == null)
    check(state.snapshot() == null)

    val first = state.accept(TerminalDimensions(24, 80, 1080, 1920))
    check(first == TerminalDimensions(24, 80, 1080, 1920))
    check(state.accept(TerminalDimensions(24, 80, 1080, 1920)) == null)

    val changed = state.accept(TerminalDimensions(20, 80, 1080, 1200))
    check(changed == TerminalDimensions(20, 80, 1080, 1200))

    val clamped = state.accept(TerminalDimensions(9999, 9999, 999999, 999999))
    check(clamped == TerminalDimensions(2000, 2000, 65535, 65535))
    check(state.accept(TerminalDimensions(9999, 9999, 999999, 999999)) == null)

    state.reset()
    check(state.snapshot() == null)
    println("PASS terminal-geometry runtime=kotlinc zero=rejected duplicate=rejected")
}
KT
  kotlinc "$SOURCE" "$WORK/TestGeometry.kt" -include-runtime -d "$WORK/geometry.jar"
  java -jar "$WORK/geometry.jar"
else
  python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
for token in (
    "data class TerminalDimensions",
    "fun isUsable(): Boolean",
    "class TerminalGeometryState",
    "if (!candidate.isUsable()) return null",
    "if (sanitized == current) return null",
    "pixelWidth.coerceIn(1, MAX_PIXELS)",
    "fun reset()",
):
    if token not in source:
        raise SystemExit(f"missing geometry token: {token}")
print("PASS terminal-geometry static-python kotlinc=unavailable zero=rejected duplicate=rejected")
PY
fi
