#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OUT="$ROOT/out/terminal-core-test"
rm -rf -- "$OUT"
mkdir -p -- "$OUT"

javac -Werror -Xlint:all -d "$OUT" \
  "$ROOT/app/src/main/java/io/github/daylight00/nativeshell/TerminalBuffer.java" \
  "$ROOT/app/src/main/java/io/github/daylight00/nativeshell/TerminalEmulator.java" \
  "$ROOT/app/src/test/java/io/github/daylight00/nativeshell/TerminalEmulatorTest.java"

java -cp "$OUT" io.github.daylight00.nativeshell.TerminalEmulatorTest
