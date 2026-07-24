#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/android-terminal-env.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT

CC=${CC:-$(command -v cc || command -v clang || command -v gcc || true)}
[ -n "$CC" ] || {
  echo 'FAIL session-environment: C compiler unavailable' >&2
  exit 125
}

cat > "$WORK/test.c" <<'C'
#include "session_environment.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void require(int condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "FAIL session-environment: %s\n", message);
        exit(1);
    }
}

static size_t count_name(char *const environment[], const char *name) {
    const size_t length = strlen(name);
    size_t count = 0U;
    for (size_t index = 0U; environment[index] != NULL; ++index) {
        if (strncmp(environment[index], name, length) == 0 && environment[index][length] == '=') {
            ++count;
        }
    }
    return count;
}

static int contains(char *const environment[], const char *entry) {
    for (size_t index = 0U; environment[index] != NULL; ++index) {
        if (strcmp(environment[index], entry) == 0) {
            return 1;
        }
    }
    return 0;
}

int main(void) {
    char *inherited[] = {
        "PATH=/vendor/bin:/system/bin",
        "HOME=/old/home",
        "LANG=ko_KR.UTF-8",
        "TMPDIR=/old/tmp",
        "ANDROID_ROOT=/system",
        "TERM=vt100",
        "EXTERNAL_STORAGE=/storage/emulated/0",
        "CUSTOM=value=with=equals",
        NULL,
    };
    char **merged = session_environment_merge(
            inherited,
            "/data/user/0/app/files",
            "/data/user/0/app/cache/tmp",
            "xterm-256color");
    require(merged != NULL, "merge returned null");
    require(contains(merged, "PATH=/vendor/bin:/system/bin"), "PATH was not inherited");
    require(contains(merged, "LANG=ko_KR.UTF-8"), "LANG was not inherited");
    require(contains(merged, "ANDROID_ROOT=/system"), "ANDROID_ROOT was not inherited");
    require(contains(merged, "EXTERNAL_STORAGE=/storage/emulated/0"), "EXTERNAL_STORAGE was not inherited");
    require(contains(merged, "CUSTOM=value=with=equals"), "custom variable was not inherited");
    require(contains(merged, "HOME=/data/user/0/app/files"), "HOME override missing");
    require(contains(merged, "TMPDIR=/data/user/0/app/cache/tmp"), "TMPDIR override missing");
    require(contains(merged, "TERM=xterm-256color"), "TERM override missing");
    require(count_name(merged, "HOME") == 1U, "HOME must occur exactly once");
    require(count_name(merged, "TMPDIR") == 1U, "TMPDIR must occur exactly once");
    require(count_name(merged, "TERM") == 1U, "TERM must occur exactly once");
    require(count_name(merged, "SHELL") == 0U, "SHELL must not be synthesized");
    require(count_name(merged, "XDG_CONFIG_HOME") == 0U, "XDG variables must not be synthesized");
    session_environment_destroy(merged);

    char *long_home = malloc(8193U);
    require(long_home != NULL, "long-path allocation failed");
    memset(long_home, 'h', 8192U);
    long_home[0] = '/';
    long_home[8192U] = '\0';
    char *empty[] = {NULL};
    merged = session_environment_merge(empty, long_home, "/tmp", "xterm-256color");
    require(merged != NULL, "dynamic environment path was truncated or rejected");
    require(strlen(merged[0]) == strlen("HOME=") + 8192U, "dynamic HOME length mismatch");
    session_environment_destroy(merged);
    free(long_home);

    errno = 0;
    require(session_environment_merge(NULL, "/home", "/tmp", "xterm") == NULL, "null environment accepted");
    require(errno == EINVAL, "null environment did not report EINVAL");

    puts("PASS session-environment inherited=preserved overrides=HOME,TMPDIR,TERM dynamic-paths=yes");
    return 0;
}
C

"$CC" -std=c11 -Wall -Wextra -Werror -Wconversion -Wshadow -Wstrict-prototypes \
  -I "$ROOT/app/src/main/c" \
  "$ROOT/app/src/main/c/session_environment.c" "$WORK/test.c" \
  -o "$WORK/test"
"$WORK/test"
