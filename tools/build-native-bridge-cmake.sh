#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
REVISION=27.3.13750724
API=29
ABI=arm64-v8a
SDK_ROOT=${ANDROID_TERMINAL_SDK_ROOT:-"$HOME/Android/Sdk"}
NDK=${ANDROID_NDK_HOME:-"$SDK_ROOT/ndk/$REVISION"}
OUTPUT_FILE=${NATIVE_OUTPUT_FILE:-"$ROOT/out/native-ndk-r27d/libshellbridge.so"}
BUILD_DIR=${NATIVE_CMAKE_BUILD_DIR:-"$ROOT/out/cmake-android-arm64-api29"}

[ -f "$NDK/build/cmake/android.toolchain.cmake" ] || {
  printf 'NDK CMake toolchain not found: %s\n' "$NDK" >&2
  exit 125
}
command -v uv >/dev/null 2>&1 || {
  printf 'uv is required for the CMake build environment.\n' >&2
  exit 125
}

rm -rf -- "$BUILD_DIR"
mkdir -p -- "$BUILD_DIR" "$(dirname -- "$OUTPUT_FILE")"

uv run --project "$ROOT/build-tools" -- \
  cmake -S "$ROOT/app/src/main/c" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ABI" \
    -DANDROID_PLATFORM="android-$API" \
    -DANDROID_STL=none \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo

uv run --project "$ROOT/build-tools" -- \
  cmake --build "$BUILD_DIR" --target shellbridge --parallel

built=$(find "$BUILD_DIR" -type f -name 'libshellbridge.so' -print -quit)
[ -n "$built" ] || {
  printf 'CMake did not produce libshellbridge.so.\n' >&2
  exit 1
}
cp -- "$built" "$OUTPUT_FILE"
printf 'build-native-bridge-cmake: PASS ndk=%s api=%s abi=%s output=%s\n' \
  "$NDK" "$API" "$ABI" "$OUTPUT_FILE"
