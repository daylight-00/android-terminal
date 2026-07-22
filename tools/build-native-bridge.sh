#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
REVISION=27.3.13750724
API=29
TRIPLE=aarch64-linux-android
SOURCE="$ROOT/app/src/main/c/shell_bridge.c"
OUTPUT_FILE=${NATIVE_OUTPUT_FILE:-"$ROOT/out/native-ndk-r27d/libshellbridge.so"}
OUTPUT_DIR=$(dirname -- "$OUTPUT_FILE")

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
PREBUILT=
for candidate in "${candidates[@]}"; do
  [ -d "$candidate" ] || continue
  for tag in linux-aarch64 linux-x86_64 darwin-arm64 darwin-x86_64; do
    if [ -d "$candidate/toolchains/llvm/prebuilt/$tag/sysroot" ]; then
      NDK=$candidate
      PREBUILT="$candidate/toolchains/llvm/prebuilt/$tag"
      break 2
    fi
  done
done

if [ -z "$NDK" ] || [ -z "$PREBUILT" ]; then
  printf 'NDK r27d (%s) sysroot was not found. Set ANDROID_NDK_HOME.\n' "$REVISION" >&2
  exit 125
fi

SYSROOT="$PREBUILT/sysroot"
NDK_CLANG="$PREBUILT/bin/${TRIPLE}${API}-clang"
NDK_LLD="$PREBUILT/bin/ld.lld"
MODE=
COMPILER=()

# Official NDK host tools are preferred when both compiler and linker execute on the
# current host. On native Android/Termux, the official linux-x86_64 linker can be
# present but rejected by Bionic; in that case use the host-native Termux toolchain
# while retaining the exact NDK r27d sysroot, API stubs, headers and compiler runtime.
if [ -x "$NDK_CLANG" ] && [ -x "$NDK_LLD" ] && \
   "$NDK_CLANG" --version >/dev/null 2>&1 && "$NDK_LLD" --version >/dev/null 2>&1; then
  MODE=ndk-host-toolchain
  COMPILER=("$NDK_CLANG")
else
  HOST_CLANG=${HOST_CLANG:-$(command -v clang || true)}
  HOST_LLD=${HOST_LLD:-$(command -v ld.lld || true)}
  if [ -z "$HOST_CLANG" ] || [ -z "$HOST_LLD" ]; then
    printf 'The NDK host linker is not executable and host-native clang/ld.lld were not found.\n' >&2
    exit 125
  fi
  RESOURCE_DIR=$(find "$PREBUILT/lib/clang" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort -V | tail -n 1)
  if [ -z "$RESOURCE_DIR" ] || [ ! -d "$RESOURCE_DIR" ]; then
    printf 'NDK clang resource directory was not found under %s.\n' "$PREBUILT/lib/clang" >&2
    exit 125
  fi
  MODE=host-native-clang-ndk-sysroot
  COMPILER=(
    "$HOST_CLANG"
    "--target=${TRIPLE}${API}"
    "--sysroot=$SYSROOT"
    "-resource-dir=$RESOURCE_DIR"
    "--ld-path=$HOST_LLD"
  )
fi

rm -rf -- "$OUTPUT_DIR"
mkdir -p -- "$OUTPUT_DIR"

"${COMPILER[@]}" \
  -std=c11 \
  -fPIC \
  -shared \
  -Wall -Wextra -Werror -Wconversion -Wformat=2 -Wshadow -Wstrict-prototypes \
  -Wno-unused-parameter \
  -fvisibility=hidden -fstack-protector-strong -ffunction-sections -fdata-sections \
  -Wl,--gc-sections -Wl,-z,relro -Wl,-z,now -Wl,--no-undefined \
  -Wl,-soname,libshellbridge.so \
  "$SOURCE" \
  -o "$OUTPUT_FILE"

{
  printf 'mode=%s\n' "$MODE"
  printf 'ndk=%s\n' "$NDK"
  printf 'prebuilt=%s\n' "$PREBUILT"
  printf 'sysroot=%s\n' "$SYSROOT"
  printf 'output=%s\n' "$OUTPUT_FILE"
  printf 'compiler='; printf '%q ' "${COMPILER[@]}"; printf '\n'
} >"$OUTPUT_DIR/compiler-receipt.txt"

printf 'build-native-bridge: PASS mode=%s ndk=%s api=%s abi=arm64-v8a output=%s\n' \
  "$MODE" "$NDK" "$API" "$OUTPUT_FILE"
