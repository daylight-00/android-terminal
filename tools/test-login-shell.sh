#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE="$ROOT/app/src/main/c/shell_bridge.c"
ENVIRONMENT="$ROOT/app/src/main/c/session_environment.c"
grep -Fq 'char *const arguments[] = {"-sh", NULL};' "$SOURCE"
grep -Fq 'execve(shell_path, arguments, environment);' "$SOURCE"
grep -Fq 'session_environment_merge(' "$SOURCE"
for forbidden in \
  'PATH=/system/bin' \
  'SHELL=/system/bin/sh' \
  'LANG=C.UTF-8' \
  'ANDROID_ROOT=/system' \
  'ANDROID_DATA=/data' \
  'ANDROID_STORAGE=/storage' \
  'EXTERNAL_STORAGE='; do
  ! grep -Fq "$forbidden" "$SOURCE"
done
for override in '"HOME"' '"TMPDIR"' '"TERM"'; do
  grep -Fq "$override" "$ENVIRONMENT"
done
! grep -Eq 'arguments\[\].*"-l"|/system/bin/sh -l|system\(|popen\(' "$SOURCE"
grep -Fq 'login-shell-v1' "$ROOT/app/src/main/assets/terminal/bridge/terminal-contract.js"
printf 'PASS login-shell direct=yes argv0=-sh environment=inherited\n'
