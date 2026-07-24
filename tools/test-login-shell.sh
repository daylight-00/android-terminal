#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE="$ROOT/app/src/main/c/shell_bridge.c"
grep -Fq 'char *const arguments[] = {"-sh", NULL};' "$SOURCE"
grep -Fq 'execve(shell_path, arguments, environment);' "$SOURCE"
grep -Fq '"SHELL=/system/bin/sh"' "$SOURCE"
! grep -Eq 'arguments\[\].*"-l"|/system/bin/sh -l|system\(|popen\(' "$SOURCE"
grep -Fq 'login-shell-v1' "$ROOT/app/src/main/assets/terminal/bridge/terminal-contract.js"
printf 'PASS login-shell\n'
