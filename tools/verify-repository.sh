#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT" || exit 1

RC=0
check() {
  local label=$1
  shift
  if "$@"; then
    printf 'PASS %s\n' "$label"
  else
    local stage_rc=$?
    printf 'FAIL %s rc=%d\n' "$label" "$stage_rc" >&2
    RC=1
  fi
}

check git-diff-check git diff --check
check terminal-core "$ROOT/tools/test-terminal-core.sh"
check policy-verifier python3 "$ROOT/tools/verify_policy.py" "$ROOT"
check verifier-fixtures "$ROOT/tools/test-verifier.sh"
check shell-syntax bash -n "$ROOT/tools/test-terminal-core.sh" "$ROOT/tools/verify-repository.sh" "$ROOT/tools/verify-native-ndk.sh" "$ROOT/tools/test-verifier.sh"
check identity-name test "$(git config --local user.name)" = 'daylight-00'
check identity-email test "$(git config --local user.email)" = 'hwjang00@snu.ac.kr'
check main-branch test "$(git branch --show-current)" = 'main'
check min-api grep -Fxq '        minSdk 29' app/build.gradle
check target-api grep -Fxq '        targetSdk 29' app/build.gradle
check ndk-r27d grep -Fxq "    ndkVersion '27.3.13750724'" app/build.gradle
check arm64-only grep -Fxq "            abiFilters 'arm64-v8a'" app/build.gradle
check system-shell grep -Fq '"/system/bin/sh"' app/src/main/java/io/github/daylight00/nativeshell/TerminalSession.java
check native-exec grep -Fq 'execve(shell_path, arguments, environment);' app/src/main/c/shell_bridge.c
check no-androidx sh -c '! grep -R --exclude-dir=.git -E "androidx\.|com.android.support" app'
check no-userland-payload sh -c '! find app/src/main -type f \( -name sh -o -name bash -o -name toybox -o -name busybox -o -name "libc.so*" -o -name "linker*" \) | grep .'
check manifest-no-network sh -c '! grep -Fq "android.permission.INTERNET" app/src/main/AndroidManifest.xml'


exit "$RC"
