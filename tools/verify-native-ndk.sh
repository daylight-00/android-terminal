#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
REVISION=27.3.13750724

candidates=()
[ -n "${ANDROID_NDK_HOME:-}" ] && candidates+=("$ANDROID_NDK_HOME")
[ -n "${ANDROID_NDK_ROOT:-}" ] && candidates+=("$ANDROID_NDK_ROOT")
[ -n "${ANDROID_SDK_ROOT:-}" ] && candidates+=("$ANDROID_SDK_ROOT/ndk/$REVISION")
[ -n "${ANDROID_HOME:-}" ] && candidates+=("$ANDROID_HOME/ndk/$REVISION")
candidates+=(
  "$HOME/Android/Sdk/ndk/$REVISION"
  "$HOME/opt/android-ndk-r27d"
  "${PREFIX:-}/opt/android-ndk-r27d"
)

NDK=
for candidate in "${candidates[@]}"; do
  if [ -x "$candidate/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android29-clang" ]; then
    NDK=$candidate
    break
  fi
  if [ -x "$candidate/toolchains/llvm/prebuilt/linux-aarch64/bin/aarch64-linux-android29-clang" ]; then
    NDK=$candidate
    break
  fi
done

if [ -z "$NDK" ]; then
  printf 'NDK r27d (%s) was not found. Set ANDROID_NDK_HOME.\n' "$REVISION" >&2
  exit 125
fi

HOST_TAG=
for tag in linux-x86_64 linux-aarch64; do
  if [ -d "$NDK/toolchains/llvm/prebuilt/$tag" ]; then HOST_TAG=$tag; break; fi
done
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"
CLANG="$TOOLCHAIN/aarch64-linux-android29-clang"
READELF="$TOOLCHAIN/llvm-readelf"
OUT="$ROOT/out/native-ndk-r27d"
rm -rf -- "$OUT"
mkdir -p -- "$OUT"

"$CLANG" \
  -std=c11 \
  -fPIC \
  -shared \
  -Wall -Wextra -Werror -Wconversion -Wformat=2 -Wshadow -Wstrict-prototypes \
  -Wno-unused-parameter \
  -fvisibility=hidden -fstack-protector-strong -ffunction-sections -fdata-sections \
  -Wl,--gc-sections -Wl,-z,relro -Wl,-z,now -Wl,--no-undefined \
  "$ROOT/app/src/main/c/shell_bridge.c" \
  -o "$OUT/libshellbridge.so"

"$READELF" -h "$OUT/libshellbridge.so" | tee "$OUT/elf-header.txt"
"$READELF" -d "$OUT/libshellbridge.so" | tee "$OUT/elf-dynamic.txt"
"$READELF" --dyn-syms --wide "$OUT/libshellbridge.so" | tee "$OUT/elf-symbols.txt"

grep -Fq 'Machine:                           AArch64' "$OUT/elf-header.txt"
grep -Fq 'Shared object file' "$OUT/elf-header.txt"
grep -Fq 'Shared library: [libc.so]' "$OUT/elf-dynamic.txt"
if grep -E 'Shared library: \[(libc\+\+|libstdc\+\+|libgnustl)' "$OUT/elf-dynamic.txt"; then
  printf 'unexpected C++ runtime dependency\n' >&2
  exit 1
fi
for symbol in spawn read write resize signalProcessGroup waitFor destroy; do
  grep -Fq "Java_io_github_daylight00_androidterminal_NativePty_${symbol}" "$OUT/elf-symbols.txt"
done

sha256sum "$OUT/libshellbridge.so" | tee "$OUT/libshellbridge.so.sha256"
printf 'verify-native-ndk: PASS ndk=%s api=29 abi=arm64-v8a\n' "$NDK"
