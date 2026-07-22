#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OUT="$ROOT/out/native-ndk-r27d"
OUTPUT="$OUT/libshellbridge.so"

NATIVE_OUTPUT_FILE="$OUTPUT" "$ROOT/tools/build-native-bridge.sh"

READELF=
for candidate in "${LLVM_READELF:-}" "$(command -v llvm-readelf || true)" "$(command -v readelf || true)"; do
  [ -n "$candidate" ] || continue
  if "$candidate" --version >/dev/null 2>&1; then
    READELF=$candidate
    break
  fi
done
if [ -z "$READELF" ]; then
  printf 'A host-executable llvm-readelf or readelf is required for native verification.\n' >&2
  exit 125
fi

"$READELF" -h "$OUTPUT" | tee "$OUT/elf-header.txt"
"$READELF" -d "$OUTPUT" | tee "$OUT/elf-dynamic.txt"
"$READELF" --dyn-syms --wide "$OUTPUT" | tee "$OUT/elf-symbols.txt"

grep -Eq 'Machine:[[:space:]]+AArch64' "$OUT/elf-header.txt"
grep -Eq 'Type:[[:space:]]+DYN.*Shared object file' "$OUT/elf-header.txt"
grep -Fq 'Shared library: [libc.so]' "$OUT/elf-dynamic.txt"
if grep -E 'Shared library: \[(libc\+\+|libstdc\+\+|libgnustl)' "$OUT/elf-dynamic.txt"; then
  printf 'unexpected C++ runtime dependency\n' >&2
  exit 1
fi
for symbol in spawn read write resize signalProcessGroup waitFor destroy; do
  grep -Fq "Java_io_github_daylight00_androidterminal_NativePty_${symbol}" "$OUT/elf-symbols.txt"
done

sha256sum "$OUTPUT" | tee "$OUT/libshellbridge.so.sha256"
printf 'verify-native-ndk: PASS api=29 abi=arm64-v8a readelf=%s\n' "$READELF"
