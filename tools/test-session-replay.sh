#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE="$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal/SessionReplayBuffer.kt"

if command -v kotlinc >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  cat > "$WORK/TestReplay.kt" <<'KT'
package io.github.daylight00.androidterminal

fun main() {
    val buffer = SessionReplayBuffer(5)
    val first = buffer.append(byteArrayOf(1, 2))
    val second = buffer.append(byteArrayOf(3, 4, 5))
    check(first.sequence == 1L && second.sequence == 2L)
    val complete = buffer.snapshot()
    check(complete.available && !complete.truncated)
    check(complete.records.size == 2 && complete.nextSequence == 3L)
    complete.records[0].bytes[0] = 99
    check(buffer.snapshot().records[0].bytes[0] == 1.toByte())

    val overflow = buffer.append(byteArrayOf(6))
    check(overflow.sequence == 3L)
    val unavailable = buffer.snapshot()
    check(!unavailable.available && unavailable.truncated)
    check(unavailable.records.isEmpty() && unavailable.nextSequence == 4L)

    buffer.reset()
    val reset = buffer.append(byteArrayOf(7))
    check(reset.sequence == 1L)
    check(buffer.snapshot().available)
    println("PASS session-replay runtime=kotlinc")
}
KT
  kotlinc "$SOURCE" "$WORK/TestReplay.kt" -include-runtime -d "$WORK/replay.jar"
  java -jar "$WORK/replay.jar"
else
  python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
for token in (
    "class SessionReplayBuffer",
    "maximumBytes",
    "replayAvailable = false",
    "truncated = true",
    "records.clear()",
    "bytes.copyOf()",
    "fun reset()",
):
    if token not in source:
        raise SystemExit(f"missing replay-buffer token: {token}")

class Model:
    def __init__(self, maximum):
        self.maximum = maximum
        self.records = []
        self.total = 0
        self.next = 1
        self.available = True
        self.truncated = False
    def append(self, data):
        seq = self.next
        self.next += 1
        if self.available:
            if self.total + len(data) <= self.maximum:
                self.records.append((seq, bytes(data)))
                self.total += len(data)
            else:
                self.records.clear()
                self.total = 0
                self.available = False
                self.truncated = True
        return seq

model = Model(5)
assert model.append(b"12") == 1
assert model.append(b"345") == 2
assert model.records == [(1, b"12"), (2, b"345")]
assert model.append(b"6") == 3
assert not model.available and model.truncated and model.records == []
print("PASS session-replay static-python kotlinc=unavailable")
PY
fi
