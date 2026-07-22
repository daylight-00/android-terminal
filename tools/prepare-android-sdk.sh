#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SDK_API=35
BUILD_TOOLS_VERSION=35.0.0
NDK_REVISION=27.3.13750724
SDK_ROOT=${ANDROID_TERMINAL_SDK_ROOT:-"$HOME/Android/Sdk"}
SDK_ENV_FILE=${SDK_ENV_FILE:-}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[ -d "$SDK_ROOT" ] || fail "standard Android SDK root not found: $SDK_ROOT"
[ -f "$SDK_ROOT/platforms/android-${SDK_API}/android.jar" ] || \
  fail "Android platform ${SDK_API} is missing under $SDK_ROOT/platforms"
[ -d "$SDK_ROOT/build-tools/${BUILD_TOOLS_VERSION}" ] || \
  fail "Android build-tools ${BUILD_TOOLS_VERSION} are missing under $SDK_ROOT/build-tools"
[ -d "$SDK_ROOT/ndk/${NDK_REVISION}" ] || \
  fail "Android NDK ${NDK_REVISION} is missing under $SDK_ROOT/ndk"

AAPT2_PATH=${AAPT2_PATH:-$(command -v aapt2 || true)}
[ -n "$AAPT2_PATH" ] && [ -x "$AAPT2_PATH" ] || \
  fail "host-native aapt2 is unavailable; install it in Termux or set AAPT2_PATH"
"$AAPT2_PATH" version >/dev/null

cat > "$ROOT/local.properties" <<EOF_LOCAL
sdk.dir=$SDK_ROOT
EOF_LOCAL

if [ -n "$SDK_ENV_FILE" ]; then
  mkdir -p "$(dirname -- "$SDK_ENV_FILE")"
  {
    printf 'export ANDROID_SDK_ROOT=%q\n' "$SDK_ROOT"
    printf 'export ANDROID_HOME=%q\n' "$SDK_ROOT"
    printf 'export ANDROID_NDK_HOME=%q\n' "$SDK_ROOT/ndk/$NDK_REVISION"
    printf 'export AAPT2_PATH=%q\n' "$AAPT2_PATH"
  } > "$SDK_ENV_FILE"
fi

printf 'ANDROID_SDK_ROOT=%s\n' "$SDK_ROOT"
printf 'ANDROID_NDK_HOME=%s\n' "$SDK_ROOT/ndk/$NDK_REVISION"
printf 'AAPT2_PATH=%s\n' "$AAPT2_PATH"
printf 'ANDROID_PLATFORM=android-%s\n' "$SDK_API"
printf 'ANDROID_BUILD_TOOLS=%s\n' "$BUILD_TOOLS_VERSION"
