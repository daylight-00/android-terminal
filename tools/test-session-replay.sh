#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
REPLAY="$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal/SessionReplayBuffer.kt"
SNAPSHOT="$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSerializedSnapshot.kt"

if command -v kotlinc >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  cat > "$WORK/TestReplay.kt" <<'KT'
package io.github.daylight00.androidterminal

fun main() {
    val buffer = SessionReplayBuffer(5)
    check(buffer.append(byteArrayOf(1, 2)).sequence == 1L)
    check(buffer.append(byteArrayOf(3, 4, 5)).sequence == 2L)
    val full = buffer.snapshotAfter(0L)
    check(full.available && !full.truncated && full.records.map { it.sequence } == listOf(1L, 2L))
    full.records[0].bytes[0] = 99
    check(buffer.snapshotAfter(0L).records[0].bytes[0] == 1.toByte())

    check(buffer.append(byteArrayOf(6)).sequence == 3L)
    val rolling = buffer.snapshotAfter(1L)
    check(rolling.available && rolling.truncated)
    check(rolling.records.map { it.sequence } == listOf(2L, 3L))
    check(!buffer.snapshotAfter(0L).available)

    val store = TerminalSerializedSnapshotStore(8)
    val original = byteArrayOf(10, 11, 12)
    check(store.update(2L, buffer.latestSequence(), original))
    original[0] = 99
    val stored = checkNotNull(store.snapshot())
    check(stored.throughSequence == 2L && stored.bytes[0] == 10.toByte())
    stored.bytes[0] = 88
    check(store.snapshot()!!.bytes[0] == 10.toByte())
    check(buffer.snapshotAfter(stored.throughSequence).records.map { it.sequence } == listOf(3L))
    check(!store.update(1L, buffer.latestSequence(), byteArrayOf(1)))
    check(!store.update(4L, buffer.latestSequence(), byteArrayOf(1)))
    check(!store.update(3L, buffer.latestSequence(), ByteArray(9)))

    buffer.reset()
    store.reset()
    check(buffer.append(byteArrayOf(7)).sequence == 1L)
    check(buffer.snapshotAfter(0L).available)
    check(store.snapshot() == null)
    println("PASS session-replay-and-snapshot runtime=kotlinc")
}
KT
  kotlinc "$REPLAY" "$SNAPSHOT" "$WORK/TestReplay.kt" -include-runtime -d "$WORK/replay.jar"
  java -jar "$WORK/replay.jar"
else
  python3 - "$REPLAY" "$SNAPSHOT" <<'PY'
from pathlib import Path
import sys
replay = Path(sys.argv[1]).read_text(encoding="utf-8")
snapshot = Path(sys.argv[2]).read_text(encoding="utf-8")
for token in (
    "class SessionReplayBuffer", "snapshotAfter", "removeFirst()", "latestSequence()",
    "bytes.copyOf()", "earliestSequence", "fun reset()",
):
    if token not in replay:
        raise SystemExit(f"missing rolling replay token: {token}")
for token in (
    "class TerminalSerializedSnapshotStore", "throughSequence", "latestSequence",
    "maximumBytes", "bytes.copyOf()", "fun reset()",
):
    if token not in snapshot:
        raise SystemExit(f"missing serialized snapshot token: {token}")
print("PASS session-replay-and-snapshot static-python kotlinc=unavailable")
PY
fi
