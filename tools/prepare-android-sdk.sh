#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SDK_API=35
BUILD_TOOLS_VERSION=35.0.0
CMDLINE_TOOLS_REVISION=15859902
CMDLINE_TOOLS_ARCHIVE=commandlinetools-linux-15859902_latest.zip
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/${CMDLINE_TOOLS_ARCHIVE}"
CMDLINE_TOOLS_SHA256=4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583
CACHE_ROOT=${ANDROID_SDK_CACHE_ROOT:-"$HOME/.cache/HW-T/android-sdk"}
SDK_ENV_FILE=${SDK_ENV_FILE:-}

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

for command in java curl unzip python3 sha256sum; do
  command -v "$command" >/dev/null 2>&1 || fail "required command not found: $command"
done

choose_sdk_root() {
  local candidate
  if [ -n "${ANDROID_SDK_ROOT:-}" ]; then
    printf '%s\n' "$ANDROID_SDK_ROOT"
    return
  fi
  if [ -n "${ANDROID_HOME:-}" ]; then
    printf '%s\n' "$ANDROID_HOME"
    return
  fi
  for candidate in \
    "$HOME/Android/Sdk" \
    "$HOME/android-sdk" \
    "$HOME/opt/android-sdk" \
    "${PREFIX:-/nonexistent}/opt/android-sdk" \
    "${PREFIX:-/nonexistent}/share/android-sdk"; do
    if [ -f "$candidate/platforms/android-${SDK_API}/android.jar" ] || \
       [ -x "$candidate/cmdline-tools/latest/bin/sdkmanager" ]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
  printf '%s\n' "$HOME/opt/android-sdk"
}

SDK_ROOT=$(choose_sdk_root)
mkdir -p "$SDK_ROOT" "$CACHE_ROOT"

sdk_complete() {
  [ -f "$SDK_ROOT/platforms/android-${SDK_API}/android.jar" ] && \
  [ -d "$SDK_ROOT/build-tools/${BUILD_TOOLS_VERSION}" ]
}

find_sdkmanager() {
  local path
  for path in \
    "$SDK_ROOT/cmdline-tools/${CMDLINE_TOOLS_REVISION}/bin/sdkmanager" \
    "$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" \
    "$SDK_ROOT/cmdline-tools/bin/sdkmanager"; do
    if [ -x "$path" ]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

install_cmdline_tools() {
  local archive="$CACHE_ROOT/$CMDLINE_TOOLS_ARCHIVE"
  local staging="$CACHE_ROOT/cmdline-tools.${CMDLINE_TOOLS_REVISION}.tmp"
  local destination="$SDK_ROOT/cmdline-tools/${CMDLINE_TOOLS_REVISION}"

  if [ -f "$archive" ] && [ "$(sha256sum "$archive" | awk '{print $1}')" != "$CMDLINE_TOOLS_SHA256" ]; then
    rm -f -- "$archive"
  fi
  if [ ! -f "$archive" ]; then
    rm -f -- "$archive.part"
    curl --fail --location --retry 4 --retry-delay 2 \
      --connect-timeout 20 --output "$archive.part" "$CMDLINE_TOOLS_URL"
    printf '%s  %s\n' "$CMDLINE_TOOLS_SHA256" "$archive.part" | sha256sum -c -
    mv -- "$archive.part" "$archive"
  fi

  python3 - "$archive" <<'PY'
from pathlib import Path, PurePosixPath
from zipfile import ZipFile
import sys
archive = Path(sys.argv[1])
seen = set()
with ZipFile(archive) as zf:
    for info in zf.infolist():
        name = info.filename
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or '\\' in name:
            raise SystemExit(f'unsafe command-line tools member: {name}')
        if name in seen:
            raise SystemExit(f'duplicate command-line tools member: {name}')
        seen.add(name)
PY

  rm -rf -- "$staging"
  mkdir -p "$staging"
  unzip -q "$archive" -d "$staging"
  [ -x "$staging/cmdline-tools/bin/sdkmanager" ] || fail "sdkmanager missing from command-line tools archive"
  rm -rf -- "$destination"
  mkdir -p "$(dirname -- "$destination")"
  mv -- "$staging/cmdline-tools" "$destination"
  rm -rf -- "$staging"
  ln -sfn "$CMDLINE_TOOLS_REVISION" "$SDK_ROOT/cmdline-tools/latest"
}

if ! sdk_complete; then
  SDKMANAGER=$(find_sdkmanager || true)
  if [ -z "$SDKMANAGER" ]; then
    log "Installing pinned Android SDK command-line tools ${CMDLINE_TOOLS_REVISION}"
    install_cmdline_tools
    SDKMANAGER=$(find_sdkmanager || true)
  fi
  [ -n "$SDKMANAGER" ] || fail "sdkmanager is unavailable"

  log "Installing Android SDK platform ${SDK_API} and build-tools ${BUILD_TOOLS_VERSION}"
  set +o pipefail
  yes | REPO_OS_OVERRIDE=linux "$SDKMANAGER" --sdk_root="$SDK_ROOT" --licenses >/dev/null 2>&1
  set -o pipefail
  set +o pipefail
  yes | REPO_OS_OVERRIDE=linux "$SDKMANAGER" --sdk_root="$SDK_ROOT" \
    "platforms;android-${SDK_API}" "build-tools;${BUILD_TOOLS_VERSION}"
  install_rc=${PIPESTATUS[1]}
  set -o pipefail
  [ "$install_rc" -eq 0 ] || fail "sdkmanager package installation failed"
fi

sdk_complete || fail "Android SDK platform/build-tools are incomplete under $SDK_ROOT"

AAPT2_PATH=${AAPT2_PATH:-}
if [ -z "$AAPT2_PATH" ]; then
  AAPT2_PATH=$(command -v aapt2 || true)
fi
if [ -z "$AAPT2_PATH" ] && command -v pkg >/dev/null 2>&1; then
  log "Installing Termux ARM64 aapt2"
  pkg install -y aapt2
  AAPT2_PATH=$(command -v aapt2 || true)
fi
[ -n "$AAPT2_PATH" ] && [ -x "$AAPT2_PATH" ] || fail "host-native aapt2 is unavailable"
"$AAPT2_PATH" version

cat > "$ROOT/local.properties" <<EOF_LOCAL
sdk.dir=$SDK_ROOT
EOF_LOCAL

if [ -n "$SDK_ENV_FILE" ]; then
  mkdir -p "$(dirname -- "$SDK_ENV_FILE")"
  {
    printf 'export ANDROID_SDK_ROOT=%q\n' "$SDK_ROOT"
    printf 'export ANDROID_HOME=%q\n' "$SDK_ROOT"
    printf 'export AAPT2_PATH=%q\n' "$AAPT2_PATH"
  } > "$SDK_ENV_FILE"
fi

log "ANDROID_SDK_ROOT=$SDK_ROOT"
log "AAPT2_PATH=$AAPT2_PATH"
log "ANDROID_PLATFORM=android-${SDK_API}"
log "ANDROID_BUILD_TOOLS=$BUILD_TOOLS_VERSION"
