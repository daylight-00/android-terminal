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
    root_build = read_required(root, "build.gradle", failures)
    build = read_required(root, "app/build.gradle", failures)
    manifest = read_required(root, "app/src/main/AndroidManifest.xml", failures)
    native = read_required(root, "app/src/main/c/shell_bridge.c", failures)
    activity = read_required(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/MainActivity.kt",
        failures,
    )
    session = read_required(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSession.kt",
        failures,
    )
    controller = read_required(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalController.kt",
        failures,
    )
    web_client = read_required(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/LocalAssetWebViewClient.kt",
        failures,
    )
    html = read_required(root, "app/src/main/assets/terminal/index.html", failures)
    javascript = read_required(root, "app/src/main/assets/terminal/terminal.js", failures)
    codec = read_required(root, "app/src/main/assets/terminal/terminal-codec.js", failures)
    acquisition = read_required(root, "tools/acquire-web-terminal-assets.sh", failures)
    native_build = read_required(root, "tools/build-native-bridge.sh", failures)
    sdk_prepare = read_required(root, "tools/prepare-android-sdk.sh", failures)
    cmake_build = read_required(root, "tools/build-native-bridge-cmake.sh", failures)
    cmake_project = read_required(root, "app/src/main/c/CMakeLists.txt", failures)
    build_tools_project = read_required(root, "build-tools/pyproject.toml", failures)

    settings = read_required(root, "settings.gradle", failures)
    readme = read_required(root, "README.md", failures)

    require("rootProject.name = 'android-terminal'" in settings, "root project must be android-terminal", failures)
    require("namespace 'io.github.daylight00.androidterminal'" in build, "namespace must match android-terminal", failures)
    require("applicationId 'io.github.daylight00.androidterminal'" in build, "application ID must match android-terminal", failures)
    require('android:label="Terminal"' in manifest, "installed app label must be Terminal", failures)
    require(readme.startswith("# Android Terminal\n\nA thin terminal frontend for Android’s native shell, powered by xterm.js."), "README title/description must match product identity", failures)
    require("minSdk 29" in build, "minSdk must be 29", failures)
    require("targetSdk 29" in build, "targetSdk must be 29", failures)
    require("compileSdk 35" in build, "compileSdk must be 35", failures)
    require(
        "ndkVersion '27.3.13750724'" in build,
        "NDK must be r27d (27.3.13750724)",
        failures,
    )
    require("abiFilters 'arm64-v8a'" in build, "ABI must be arm64-v8a only", failures)
    require("buildConfig true" in build, "BuildConfig generation must be enabled", failures)
    require("buildNativeBridge" in build, "Gradle must build the native bridge through the host-aware task", failures)
    require("generated/jniLibs" in build, "generated JNI directory must be configured", failures)
    require("externalNativeBuild" not in build, "Gradle must not invoke non-native NDK host binaries", failures)
    require("host-native-clang-ndk-sysroot" in native_build, "Termux host-native clang fallback is required", failures)
    require("--target=${TRIPLE}${API}" in native_build, "native fallback must target Android API 29", failures)
    require("--sysroot=$SYSROOT" in native_build, "native fallback must retain the NDK sysroot", failures)
    require("--ld-path=$HOST_LLD" in native_build, "native fallback must use a host-native linker", failures)
    require('SDK_ROOT=${ANDROID_TERMINAL_SDK_ROOT:-"$HOME/Android/Sdk"}' in sdk_prepare, "standard SDK root must default to ~/Android/Sdk", failures)
    require('platforms/android-${SDK_API}/android.jar' in sdk_prepare, "existing SDK platform API 35 must be verified", failures)
    require('build-tools/${BUILD_TOOLS_VERSION}' in sdk_prepare, "existing build-tools 35.0.0 must be verified", failures)
    require('ndk/${NDK_REVISION}' in sdk_prepare, "existing NDK r27d must be verified", failures)
    require("curl " not in sdk_prepare and "sdkmanager" not in sdk_prepare, "SDK helper must not download or install a second SDK", failures)
    require("pkg install" not in sdk_prepare, "SDK helper must not mutate Termux packages", failures)
    require("sdk.dir=$SDK_ROOT" in sdk_prepare, "SDK helper must write local.properties", failures)
    require("android.toolchain.cmake" in cmake_build, "x86 Linux build must use the official NDK CMake toolchain", failures)
    require("uv run --project" in cmake_build, "CMake/Ninja must be provided through the separate uv project", failures)
    require("add_library(shellbridge SHARED" in cmake_project, "CMake project must build the JNI shared library", failures)
    require('"cmake>=3.31,<5"' in build_tools_project, "build tools project must declare CMake", failures)
    require('"ninja>=1.12,<2"' in build_tools_project, "build tools project must declare Ninja", failures)
    require("org.jetbrains.kotlin.android" in root_build, "Kotlin Android plugin is required", failures)
    require("com.android.application" in root_build, "Android application plugin is required", failures)

    require("/system/bin/sh" in session, "session must execute /system/bin/sh", failures)
    require("forkpty(" in native, "native bridge must use forkpty", failures)
    require("execve(" in native, "native bridge must use execve", failures)
    require("TIOCSWINSZ" in native, "native bridge must propagate PTY size", failures)
    require("PATH=/system/bin" in native, "PATH must remain /system/bin", failures)
    require("TERM=xterm-256color" in native, "TERM must match xterm.js capabilities", failures)

    require("WebView(activity)" in controller, "frontend must use platform WebView", failures)
    require("createWebMessageChannel()" in controller, "bridge must use WebMessagePort", failures)
    require("addJavascriptInterface" not in controller, "JavaScript object bridge is forbidden", failures)
    require("allowFileAccess = false" in controller, "WebView file access must be disabled", failures)
    require("allowContentAccess = false" in controller, "WebView content access must be disabled", failures)
    require("MIXED_CONTENT_NEVER_ALLOW" in controller, "mixed content must be blocked", failures)
    require("MAX_QUEUED_BYTES" in controller, "output backpressure cap is required", failures)
    require("Base64" in controller, "API 29 string message bridge must preserve PTY bytes", failures)
    require("shouldInterceptRequest" in web_client, "local asset interception is required", failures)
    require("https://app.local" in web_client, "synthetic local HTTPS origin must remain pinned", failures)
    require("Content-Security-Policy" in web_client, "local page needs a CSP", failures)
    require("connect-src 'none'" in web_client, "local page must not make network connections", failures)
    require("window.Terminal" in javascript, "frontend must use xterm.js", failures)
    require("FitAddon" in javascript, "frontend must use addon-fit", failures)
    require("terminal.write" in javascript, "PTY output must be passed to xterm.js", failures)
    require("terminal.onData" in javascript, "xterm.js input callback is required", failures)
    require("NativeShellCodec" in codec, "byte-preserving web codec is required", failures)
    require("/terminal/vendor/xterm.js" in html, "pinned xterm.js asset must be local", failures)
    require("/terminal/vendor/addon-fit.js" in html, "pinned addon-fit asset must be local", failures)

    require("@xterm/xterm/-/xterm-6.0.0.tgz" in acquisition, "xterm.js URL must be pinned", failures)
    require("@xterm/addon-fit/-/addon-fit-0.11.0.tgz" in acquisition, "addon-fit URL must be pinned", failures)
    require("sha512-TQwDdQGt" in acquisition, "xterm.js npm integrity must be pinned", failures)
    require("sha512-jYcgT6xt" in acquisition, "addon-fit npm integrity must be pinned", failures)

    require("android.permission.INTERNET" not in manifest, "application must not request INTERNET", failures)
    require("android:usesCleartextTraffic=\"false\"" in manifest, "cleartext traffic must be disabled", failures)
    require("setContentView(terminal.view)" in activity, "Activity must remain a thin frontend host", failures)

    source_texts = "\n".join((root_build, build, manifest, activity, session, controller, web_client))
    require("androidx." not in source_texts, "AndroidX is not allowed", failures)
    require("compose" not in source_texts.lower(), "Compose is not allowed", failures)

    forbidden_extensions = {".rs"}
    forbidden_names = {
        "sh",
        "bash",
        "toybox",
        "busybox",
        "libc.so",
        "linker",
        "linker64",
    }
    main_root = root / "app/src/main"
    if main_root.is_dir():
        for path in main_root.rglob("*"):
            if not path.is_file():
                continue
            if path.name in forbidden_names:
                failures.append(f"bundled userland artifact is forbidden: {path.relative_to(root)}")
            if path.suffix in forbidden_extensions:
                failures.append(f"Rust source is outside the selected architecture: {path.relative_to(root)}")

    java_root = root / "app/src/main/java"
    if java_root.exists() and any(path.is_file() for path in java_root.rglob("*")):
        failures.append("Java application sources must remain absent")
    removed_terminal_names = {"TerminalBuffer", "TerminalEmulator", "TerminalView"}
    for source_root in (root / "app/src/main", root / "app/src/test"):
        if not source_root.exists():
            continue
        for path in source_root.rglob("*"):
            if path.is_file() and path.stem in removed_terminal_names:
                failures.append(
                    f"removed custom terminal implementation returned: {path.relative_to(root)}"
                )

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
