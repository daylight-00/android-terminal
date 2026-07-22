#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path


def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def read_required(root: Path, relative: str, failures: list[str]) -> str:
    path = root / relative
    if not path.is_file():
        failures.append(f"missing required file: {relative}")
        return ""
    return path.read_text(encoding="utf-8")


def verify(root: Path) -> list[str]:
    failures: list[str] = []
    build = read_required(root, "app/build.gradle", failures)
    manifest = read_required(root, "app/src/main/AndroidManifest.xml", failures)
    native = read_required(root, "app/src/main/c/shell_bridge.c", failures)
    session = read_required(
        root,
        "app/src/main/java/io/github/daylight00/nativeshell/TerminalSession.java",
        failures,
    )
    terminal_view = read_required(
        root,
        "app/src/main/java/io/github/daylight00/nativeshell/TerminalView.java",
        failures,
    )

    require("minSdk 29" in build, "minSdk must be 29", failures)
    require("targetSdk 29" in build, "targetSdk must be 29", failures)
    require("compileSdk 35" in build, "compileSdk must be 35", failures)
    require(
        "ndkVersion '27.3.13750724'" in build,
        "NDK must be r27d (27.3.13750724)",
        failures,
    )
    require("abiFilters 'arm64-v8a'" in build, "ABI must be arm64-v8a only", failures)
    require("ANDROID_STL=none" in build, "C++ runtime must remain disabled", failures)
    require("/system/bin/sh" in session, "session must execute /system/bin/sh", failures)
    require("forkpty(" in native, "native bridge must use forkpty", failures)
    require("execve(" in native, "native bridge must use execve", failures)
    require("TIOCSWINSZ" in native, "native bridge must propagate PTY size", failures)
    require("PATH=/system/bin" in native, "PATH must remain /system/bin", failures)
    require("TERM=vt100" in native, "TERM must honestly remain vt100", failures)
    require("InputConnection" in terminal_view, "terminal view must expose InputConnection", failures)
    require("Canvas" in terminal_view, "terminal view must use platform Canvas", failures)
    require("android.permission.INTERNET" not in manifest, "v0.1 must not request INTERNET", failures)
    require("androidx." not in terminal_view, "AndroidX is not allowed", failures)

    main_root = root / "app/src/main"
    if main_root.is_dir():
        forbidden_names = {
            "sh",
            "bash",
            "toybox",
            "busybox",
            "libc.so",
            "linker",
            "linker64",
        }
        for path in main_root.rglob("*"):
            if path.is_file() and path.name in forbidden_names:
                failures.append(f"bundled userland artifact is forbidden: {path.relative_to(root)}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", default=".")
    arguments = parser.parse_args()
    root = Path(arguments.root).resolve()
    failures = verify(root)
    if failures:
        for failure in failures:
            print(f"FAIL policy: {failure}", file=sys.stderr)
        return 1
    print("PASS policy")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
