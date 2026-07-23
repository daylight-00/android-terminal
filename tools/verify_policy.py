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
    session_service = read_required(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSessionService.kt",
        failures,
    )
    session_title = read_required(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSessionTitle.kt",
        failures,
    )
    strings_default = read_required(root, "app/src/main/res/values/strings.xml", failures)
    strings_ko = read_required(root, "app/src/main/res/values-ko/strings.xml", failures)
    replay_buffer = read_required(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/SessionReplayBuffer.kt",
        failures,
    )
    geometry = read_required(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalGeometry.kt",
        failures,
    )
    platform_adapter = read_required(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalPlatformAdapter.kt",
        failures,
    )
    platform_policy = read_required(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalPlatformPolicy.kt",
        failures,
    )
    platform_state = read_required(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalPlatformState.kt",
        failures,
    )
    document_policy = read_required(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalDocumentPolicy.kt",
        failures,
    )
    document_transport = read_required(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalDocumentTransport.kt",
        failures,
    )
    frontend_recovery = read_required(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalFrontendRecoveryState.kt",
        failures,
    )
    web_client = read_required(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/LocalAssetWebViewClient.kt",
        failures,
    )
    html = read_required(root, "app/src/main/assets/terminal/bridge/index.html", failures)
    contract_js = read_required(root, "app/src/main/assets/terminal/bridge/terminal-contract.js", failures)
    javascript = read_required(root, "app/src/main/assets/terminal/bridge/terminal-bridge.js", failures)
    renderer = read_required(root, "app/src/main/assets/terminal/bridge/terminal-renderer.js", failures)
    codec = read_required(root, "app/src/main/assets/terminal/bridge/terminal-codec.js", failures)
    platform_js = read_required(root, "app/src/main/assets/terminal/bridge/terminal-platform.js", failures)
    customization_js = read_required(
        root,
        "app/src/main/assets/terminal/customization/customization.js",
        failures,
    )
    customization_css = read_required(
        root,
        "app/src/main/assets/terminal/customization/customization.css",
        failures,
    )
    customization_kt = read_required(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalCustomization.kt",
        failures,
    )
    terminal_contract = read_required(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt",
        failures,
    )
    host_appearance = read_required(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalHostAppearance.kt",
        failures,
    )
    shared_storage = read_required(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSharedStorage.kt",
        failures,
    )
    acquisition = read_required(root, "tools/acquire-web-terminal-assets.sh", failures)
    native_build = read_required(root, "tools/build-native-bridge.sh", failures)
    sdk_prepare = read_required(root, "tools/prepare-android-sdk.sh", failures)
    cmake_build = read_required(root, "tools/build-native-bridge-cmake.sh", failures)
    cmake_project = read_required(root, "app/src/main/c/CMakeLists.txt", failures)
    build_tools_project = read_required(root, "build-tools/pyproject.toml", failures)
    font_scale_test = read_required(root, "tools/test-font-scale.sh", failures)

    settings = read_required(root, "settings.gradle", failures)
    readme = read_required(root, "README.md", failures)
    capability_matrix = read_required(root, "docs/capability-matrix.md", failures)
    capability_inventory = read_required(root, "docs/upstream-capabilities.json", failures)

    require("rootProject.name = 'android-terminal'" in settings, "root project must be android-terminal", failures)
    require("namespace 'io.github.daylight00.androidterminal'" in build, "namespace must match android-terminal", failures)
    require("applicationId 'io.github.daylight00.androidterminal'" in build, "application ID must match android-terminal", failures)
    require('android:label="Terminal"' in manifest, "installed app label must be Terminal", failures)
    require(readme.startswith("# Android Terminal\n\nA thin terminal frontend for Android’s native shell, powered by xterm.js."), "README title/description must match product identity", failures)
    require('"official_addons"' in capability_inventory and "@xterm/addon-clipboard" in capability_inventory and "@xterm/addon-image" in capability_inventory, "machine-readable upstream capability authority is incomplete", failures)
    require("Layer 3 scaffold rule" in capability_matrix and "Layer 2 must operate when the scaffold is empty or omitted" in capability_matrix, "capability matrix must bind the optional Layer 3 boundary", failures)
    require("minSdk 29" in build, "minSdk must be 29", failures)
    require("targetSdk 28" in build, "targetSdk compatibility boundary must be 28", failures)
    require("versionCode 16" in build, "versionCode must identify the core-host integration release", failures)
    require("versionName '0.18.0'" in build, "versionName must identify the core-host integration release", failures)
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
    require("EXTERNAL_STORAGE=%s" in native, "shared-storage root must be exposed to the child", failures)
    require("ANDROID_STORAGE=/storage" in native, "Android storage coordinate must be exposed to the child", failures)

    require("WebView(activity)" in controller, "frontend must use platform WebView", failures)
    require("createWebMessageChannel()" in controller, "bridge must use WebMessagePort", failures)
    require("addJavascriptInterface" not in controller, "JavaScript object bridge is forbidden", failures)
    require("allowFileAccess = false" in controller, "WebView file access must be disabled", failures)
    require("allowContentAccess = false" in controller, "WebView content access must be disabled", failures)
    require("MIXED_CONTENT_NEVER_ALLOW" in controller, "mixed content must be blocked", failures)
    require("MAX_QUEUED_BYTES" in controller, "output backpressure cap is required", failures)
    require("Base64" in controller, "API 29 string message bridge must preserve PTY bytes", failures)
    require("shouldInterceptRequest" in web_client, "local asset interception is required", failures)
    require("TerminalContract.HOST" in web_client, "local asset host must come from TerminalContract", failures)
    require("override fun onRenderProcessGone" in web_client, "WebView renderer termination must be handled", failures)
    require("onRendererGone(detail.didCrash())" in web_client, "renderer termination must be forwarded without inspecting terminal semantics", failures)
    for asset_path in (
        "/terminal/vendor/addon-web-links.js",
        "/terminal/customization/customization.css",
        "/terminal/customization/customization.js",
    ):
        require(asset_path in web_client, f"local asset allowlist is missing: {asset_path}", failures)
    require('ORIGIN = "https://app.local"' in terminal_contract, "synthetic local HTTPS origin must remain pinned", failures)
    require("PROTOCOL_VERSION = 6" in terminal_contract, "terminal contract version 6 must be explicit", failures)
    require("protocolVersion: 6" in contract_js, "web terminal contract version 6 must be explicit", failures)
    require("session-attach-v2" in terminal_contract and "session-attach-v2" in contract_js, "session attach v2 capability must match", failures)
    require("geometry-dedup-v1" in terminal_contract and "geometry-dedup-v1" in contract_js, "geometry dedupe capability must match", failures)
    require("android-window-geometry" in terminal_contract, "native Android window geometry capability is required", failures)
    require("webview-renderer-recovery" in terminal_contract, "native WebView renderer recovery capability is required", failures)
    require("platform-bridge-v2" in terminal_contract and "platform-bridge-v2" in contract_js, "platform bridge capability must match", failures)
    for capability in (
        "android-clipboard",
        "android-external-uri",
        "android-haptic-bell",
        "android-system-theme",
        "android-accessibility-state",
        "android-hardware-keyboard-state",
        "android-document-transport",
        "android-shared-storage-direct-path",
        "xterm-serialized-state",
    ):
        require(capability in terminal_contract, f"native platform capability is required: {capability}", failures)
    require("class TerminalGeometryState" in geometry, "terminal geometry state must be explicit", failures)
    require("if (!candidate.isUsable()) return null" in geometry, "zero terminal geometry must be rejected", failures)
    require("if (sanitized == current) return null" in geometry, "duplicate terminal geometry must be rejected", failures)
    require("measureGeometry(type)" in javascript, "web terminal geometry must be measured after addon-fit", failures)
    require("geometryKey(geometry)" in javascript, "web terminal geometry must be deduplicated", failures)
    require("visualViewport.addEventListener('resize'" in javascript, "IME viewport changes must trigger geometry synchronization", failures)
    require("requestGeometrySync()" in activity, "Android lifecycle must signal frontend geometry changes", failures)
    require("setOnApplyWindowInsetsListener" in activity, "Android window insets must trigger geometry synchronization", failures)
    require("addOnLayoutChangeListener" in activity, "Android root layout changes must trigger geometry synchronization", failures)
    require("Content-Security-Policy" in web_client, "local page needs a CSP", failures)
    require("connect-src 'none'" in web_client, "local page must not make network connections", failures)
    require("window.Terminal" in javascript, "frontend must use xterm.js", failures)
    require("FitAddon" in javascript, "frontend must use addon-fit", failures)
    require("AndroidTerminalPlatform" in javascript, "Layer 2 must expose the bounded Android platform facade", failures)
    require("terminal.hasSelection()" in javascript and "terminal.getSelection()" in javascript, "clipboard copy must use xterm selection APIs", failures)
    require("terminal.paste(text)" in javascript, "clipboard paste must use xterm paste API", failures)
    require("terminal.options.linkHandler" in javascript, "OSC 8 links must use xterm linkHandler", failures)
    require("terminal.onBell(" in javascript, "terminal bell must use the public xterm event", failures)
    require("importDocument(options = {})" in javascript, "Layer 2 must expose SAF import", failures)
    require("exportDocument(path, options = {})" in javascript, "Layer 2 must expose SAF export", failures)
    require("document-transport-v1" in terminal_contract and "document-transport-v1" in contract_js, "document transport capability must match", failures)
    for token in ("Intent.ACTION_OPEN_DOCUMENT", "Intent.ACTION_CREATE_DOCUMENT", "OpenableColumns.DISPLAY_NAME", "openInputStream", "openOutputStream", "activity.filesDir"):
        require(token in document_transport, f"SAF private-file transport token is required: {token}", failures)
    for token in ("validatedRelativeHomePath", "resolvePrivateExportSource", "MAX_DOCUMENT_BYTES", "uniqueImportTarget"):
        require(token in document_policy, f"document policy token is required: {token}", failures)
    for forbidden in ("ACTION_OPEN_DOCUMENT_TREE", "takePersistableUriPermission", "DocumentsContract", "FUSE"):
        require(forbidden not in document_transport and forbidden not in document_policy and forbidden not in activity, f"SAF virtual mount behavior is forbidden: {forbidden}", failures)
    for unselected_upstream in ("ClipboardAddon", "osc52-clipboard", "ImageAddon"):
        require(
            unselected_upstream not in javascript and unselected_upstream not in contract_js,
            f"unselected upstream addon must not be claimed: {unselected_upstream}",
            failures,
        )
    require("applyPlatformState" in platform_js, "Layer 2 must map Android platform state", failures)
    require("isExternalUriAllowed" in platform_js, "Layer 2 must define bounded URI activation mapping", failures)
    require("new window.Terminal()" in javascript, "Layer 2 must preserve upstream terminal defaults", failures)
    for option in ("cursorBlink", "cursorStyle", "fontFamily", "letterSpacing", "lineHeight", "scrollback"):
        require(option not in javascript and option not in platform_js, f"product option must not leak into Layer 2: {option}", failures)
    require("fontSize" not in javascript, "font size adaptation must remain isolated in the Android platform mapping", failures)
    require("TerminalHostAppearance.backgroundColor" in controller, "native host appearance mapping must stay in Layer 2", failures)
    require("TerminalPlatformAdapter(activity, view)" in controller, "controller must delegate Android capabilities to the platform adapter", failures)
    require("TerminalContract.MessageType.PLATFORM_REQUEST" in controller, "controller must accept bounded platform requests", failures)
    require("ClipboardManager" in platform_adapter and "ClipData.newPlainText" in platform_adapter, "platform adapter must use Android text clipboard APIs", failures)
    require("Intent.ACTION_VIEW" in platform_adapter, "platform adapter must route validated external URIs through ACTION_VIEW", failures)
    require("performHapticFeedback" in platform_adapter, "platform adapter must expose Android haptic bell capability", failures)
    require("AccessibilityStateChangeListener" in platform_adapter, "platform adapter must observe Android accessibility state", failures)
    require("TouchExplorationStateChangeListener" in platform_adapter, "platform adapter must observe touch exploration state", failures)
    require("data class TerminalPlatformState" in platform_state, "platform state contract must be explicit", failures)
    require("MAX_CLIPBOARD_CHARACTERS" in platform_policy, "clipboard text must be bounded", failures)
    require("scheme !in allowedSchemes" in platform_policy, "external URI schemes must be allowlisted", failures)
    require("parsed.userInfo != null" in platform_policy, "credential-bearing external URIs must be rejected", failures)
    require("ALLOWED_EXTERNAL_URI_SCHEMES" in platform_policy, "native URI scheme policy must stay in Layer 2", failures)
    require("TerminalPlatformPolicy.ALLOWED_EXTERNAL_URI_SCHEMES" in platform_adapter, "platform adapter must consume the Layer 2 URI allowlist", failures)
    require("hapticBellEnabled" not in platform_adapter, "Layer 2 bell integration must not depend on optional Layer 3 policy", failures)
    require("sharedStorageAccessGranted" in platform_state and "sharedStoragePath" in platform_state, "platform state must report shared-storage status", failures)
    require("TerminalSessionService.LocalBinder" in controller, "WebView transport must attach to the service session host", failures)
    require("TerminalSession(" not in controller, "WebView transport must not own the PTY session", failures)
    require("class TerminalSessionService : Service()" in session_service, "platform Service must own the shell session", failures)
    require("SessionReplayBuffer(REPLAY_LIMIT_BYTES)" in session_service, "service must own bounded raw replay", failures)
    require("TerminalSession(" in session_service, "service must create the PTY session", failures)
    require("connectionGeneration" in session_service and "sessionId" in session_service, "service attachment identity is required", failures)
    require("maximumBytes" in replay_buffer and "snapshotAfter" in replay_buffer and "removeFirst()" in replay_buffer, "bounded rolling replay tail is required", failures)
    serialized_snapshot = read_required(root, "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSerializedSnapshot.kt", failures)
    require("class TerminalSerializedSnapshotStore" in serialized_snapshot and "bytes.copyOf()" in serialized_snapshot, "opaque serialized xterm snapshot storage is required", failures)
    require("TerminalSerializedSnapshotStore(TerminalContract.MAX_SERIALIZED_SNAPSHOT_BYTES)" in session_service, "service must own bounded serialized xterm state", failures)
    require("serialize-state-v1" in terminal_contract and "serialize-state-v1" in contract_js, "serialize page capability must match", failures)
    require("new window.SerializeAddon.SerializeAddon()" in javascript and "serializeAddon.serialize()" in javascript, "official xterm serialize addon must own snapshot generation", failures)
    require("webgl-renderer-fallback-v1" in terminal_contract and "webgl-renderer-fallback-v1" in contract_js, "WebGL fallback page capability must match", failures)
    require("android-font-scale-v1" in terminal_contract and "android-font-scale-v1" in contract_js, "font-scale page capability must match", failures)
    require("android-font-scale-state" in terminal_contract and "android-font-scale-state" in contract_js, "native font-scale capability must match", failures)
    require("web-links-v1" in terminal_contract and "web-links-v1" in contract_js, "official Web Links page capability must match", failures)
    require("new window.WebLinksAddon.WebLinksAddon(" in javascript, "official Web Links addon must be loaded through its public constructor", failures)
    require("platform.openExternalUri(uri)" in javascript, "plain-text links must use the bounded Android URI operation", failures)
    require("window.open(" not in javascript, "Web Links must not navigate the local WebView directly", failures)
    require("fontScale" in platform_state and "configuration.fontScale.toDouble().coerceIn(0.5, 3.0)" in platform_adapter, "Android font-scale state must be bounded and transported", failures)
    require("const upstreamFontSizes = new WeakMap()" in platform_js, "font-scale mapping must capture each upstream terminal default", failures)
    require("Number(terminal.options.fontSize)" in platform_js, "font-scale mapping must consume the upstream font size", failures)
    require("upstreamFontSizes.get(terminal) * boundedFontScale(value)" in platform_js, "font-scale mapping must scale from the upstream baseline without compounding", failures)
    require("applyFontScale(terminal, state.fontScale)" in platform_js, "Android font scale must map through the public xterm option", failures)
    require("contractVersion: 4" in platform_js and "platformIntegration.contractVersion !== 4" in javascript, "platform integration contract must be version 4", failures)
    require("contractVersion: 2" in javascript, "stable Layer 2 capability contract must be version 2", failures)
    require("TerminalContract.MessageType.SESSION_TITLE" in controller and "handleSessionTitle" in controller, "controller must accept neutral session-title state", failures)
    require("fun updateTitle(" in session_service and "title = TerminalSessionTitle.sanitize(value)" in session_service, "service must own bounded terminal-title state", failures)
    require("MAX_CODE_POINTS = 1024" in session_title and "codePointAt(index)" in session_title, "terminal title must be Unicode-code-point bounded", failures)
    require("terminal.onTitleChange(" in javascript and "onTitleState" in javascript and "getTitleState()" in javascript, "Layer 2 must expose neutral title state to Layer 3", failures)
    require("configuration.locales[0].toLanguageTag()" in platform_adapter, "Android locale tag must enter platform state", failures)
    require("R.string.xterm_prompt_label" in platform_adapter and "R.string.xterm_too_much_output" in platform_adapter, "Android resources must supply xterm localizable strings", failures)
    require('name="xterm_prompt_label"' in strings_default and 'name="xterm_too_much_output"' in strings_default, "default xterm localization resources are required", failures)
    require('name="xterm_prompt_label"' in strings_ko and 'name="xterm_too_much_output"' in strings_ko, "Korean xterm localization resources are required", failures)
    require("terminal.strings.promptLabel" in platform_js and "terminal.strings.tooMuchOutput" in platform_js, "Layer 2 must apply Android-localized upstream strings", failures)
    for capability in ("session-title-state-v1", "localized-xterm-strings-v1", "safe-window-reports-v1"):
        require(capability in terminal_contract and capability in contract_js, f"core host capability must match: {capability}", failures)
    require("android-localized-xterm-strings" in terminal_contract and "android-localized-xterm-strings" in contract_js, "localized-string native capability must match", failures)
    for token in ("getWinSizePixels: true", "getCellSizePixels: true", "getWinSizeChars: true", "pushTitle: true", "popTitle: true", "registerCsiHandler({final: 't'}", "terminal.refresh(", "terminal.input("):
        require(token in platform_js, f"safe window-report integration token is required: {token}", failures)
    for forbidden in ("fullscreenWin: true", "setWinPosition: true", "getScreenSizePixels: true", "getScreenSizeChars: true", "setWinSizePixels: true", "setWinSizeChars: true"):
        require(forbidden not in platform_js, f"unsafe or desktop-only window operation must remain disabled: {forbidden}", failures)
    require('android:configChanges="fontScale|' in manifest, "Activity must receive font-scale configuration changes without replacing the PTY host", failures)
    require("upstream-default=preserved" in font_scale_test and "Android font scale was not applied" in font_scale_test, "font-scale semantic test must cover upstream ownership and positive behavior", failures)
    require("new WebglAddon.WebglAddon(false)" in renderer, "official xterm WebGL addon must own accelerated rendering", failures)
    require("candidate.onContextLoss" in renderer and "fallback('context-loss')" in renderer, "WebGL context loss must fall back through the public addon event", failures)
    require("permanentlyFellBack" in renderer, "a failed WebGL frontend must not retry in a loop", failures)
    require("function activate()" in renderer and "rendererController.activate()" in javascript, "Layer 2 must automatically attempt WebGL", failures)
    require("policy-disabled" not in renderer and "preferWebgl" not in renderer and "preferWebgl" not in javascript, "WebGL must not depend on Layer 3 policy", failures)
    require("Color.BLACK" in host_appearance and "WEB_TEXT_ZOOM" in host_appearance, "Layer 2 host appearance mapping must be explicit", failures)
    require("terminal.write" in javascript, "PTY output must be passed to xterm.js", failures)
    require("terminal.onData" in javascript, "xterm.js input callback is required", failures)
    require("NativeShellCodec" in codec, "byte-preserving web codec is required", failures)
    require("/terminal/vendor/xterm.js" in html, "pinned xterm.js asset must be local", failures)
    require("/terminal/vendor/addon-fit.js" in html, "pinned addon-fit asset must be local", failures)
    require("/terminal/vendor/addon-serialize.js" in html, "pinned addon-serialize asset must be local", failures)
    require("/terminal/vendor/addon-web-links.js" in html, "pinned addon-web-links asset must be local", failures)
    require("/terminal/vendor/addon-webgl.js" in html, "pinned addon-webgl asset must be local", failures)
    require("/terminal/bridge/terminal-contract.js" in html, "stable web contract must load locally", failures)
    require("/terminal/bridge/terminal-renderer.js" in html, "Layer 2 renderer controller must load locally", failures)
    require("/terminal/bridge/terminal-platform.js" in html, "Layer 2 platform mapping must load locally", failures)
    require("/terminal/bridge/terminal-bridge.js" in html, "Layer 2 terminal bridge must load locally", failures)
    require("/terminal/customization/customization.css" in html, "Layer 3 stylesheet scaffold must load locally", failures)
    require("/terminal/customization/customization.js" in html, "Layer 3 JavaScript scaffold must load locally", failures)
    require(html.find("/terminal/bridge/terminal-bridge.js") < html.find("/terminal/customization/customization.js"), "Layer 3 must load after Layer 2", failures)
    require('id="custom-ui-root"' not in html, "Layer 3 must not reserve product UI before a feature decision", failures)
    require("window.AndroidTerminalLayer2 = Object.freeze" in javascript, "Layer 2 must expose the stable customization capability", failures)
    require("AndroidTerminalCustomization" not in javascript and "/terminal/customization/" not in javascript, "Layer 2 must not depend on Layer 3", failures)
    require("terminal.options.theme" not in platform_js and "darkTheme" not in platform_js and "lightTheme" not in platform_js, "project palettes must not remain in Layer 2", failures)
    require("window.AndroidTerminalCustomization" in customization_js and "layer2.onPlatformState" in customization_js, "Layer 3 JavaScript scaffold must consume the public Layer 2 capability", failures)
    require("layer2.terminal.options.theme" in customization_js, "project palette must be owned by Layer 3", failures)
    require("CONTRACT_VERSION = 1" in customization_kt, "Layer 3 native scaffold contract is required", failures)
    require("nativePort" not in customization_js and "NativePty" not in customization_kt, "Layer 3 must not bypass Layer 2 internals", failures)

    require("@xterm/xterm/-/xterm-6.0.0.tgz" in acquisition, "xterm.js URL must be pinned", failures)
    require("@xterm/addon-fit/-/addon-fit-0.11.0.tgz" in acquisition, "addon-fit URL must be pinned", failures)
    require("@xterm/addon-serialize/-/addon-serialize-0.13.0.tgz" in acquisition, "addon-serialize URL must be pinned", failures)
    require("@xterm/addon-webgl/-/addon-webgl-0.19.0.tgz" in acquisition, "addon-webgl URL must be pinned", failures)
    require("@xterm/addon-web-links/-/addon-web-links-0.12.0.tgz" in acquisition, "addon-web-links URL must be pinned", failures)
    require("sha512-TQwDdQGt" in acquisition, "xterm.js npm integrity must be pinned", failures)
    require("sha512-jYcgT6xt" in acquisition, "addon-fit npm integrity must be pinned", failures)
    require("sha512-kGs8o6LW" in acquisition, "addon-serialize npm integrity must be pinned", failures)
    require("sha512-b3fMOsyL" in acquisition, "addon-webgl npm integrity must be pinned", failures)
    require("sha512-4Smom3RP" in acquisition, "addon-web-links npm integrity must be pinned", failures)
    provisioner = read_required(root, "tools/provision-web-terminal-assets.py", failures)
    require('"package/package.json": "PACKAGE.addon-serialize.json"' in provisioner, "addon-serialize package metadata must be retained", failures)
    require('"license": "MIT"' in provisioner, "addon-serialize MIT package declaration must be validated", failures)
    require('"package/LICENSE": "LICENSE.addon-serialize.txt"' not in provisioner, "provisioner must not require a nonexistent addon-serialize LICENSE member", failures)
    require('"package/package.json": "PACKAGE.addon-webgl.json"' in provisioner, "addon-webgl package metadata must be retained", failures)
    require('"package/LICENSE": "LICENSE.addon-webgl.txt"' not in provisioner, "provisioner must not synthesize an addon-webgl license member", failures)
    require('"package/package.json": "PACKAGE.addon-web-links.json"' in provisioner, "addon-web-links package metadata must be retained", failures)
    require('"package/LICENSE": "LICENSE.addon-web-links.txt"' not in provisioner, "provisioner must not synthesize an addon-web-links license member", failures)

    for token in (
        "android.permission.MANAGE_EXTERNAL_STORAGE",
        "android.permission.READ_EXTERNAL_STORAGE",
        "android.permission.WRITE_EXTERNAL_STORAGE",
        'android:requestLegacyExternalStorage="true"',
    ):
        require(token in manifest, f"storage manifest adaptation is required: {token}", failures)
    for token in (
        "Environment.isExternalStorageManager()",
        "Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION",
        "Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION",
        "Os.symlink",
        "prepareHomeLink",
    ):
        require(token in shared_storage, f"shared-storage adapter token is required: {token}", failures)
    require("TerminalSharedStorage.requestAccess(this)" in activity, "Activity storage access flow is required", failures)
    require("TerminalSharedStorage.prepareHomeLink(homeDirectory)" in session, "HOME/storage preparation is required", failures)
    require("layer3-scaffold-v1" in terminal_contract and "layer3-scaffold-v1" in contract_js, "Layer 3 scaffold capability must match", failures)

    require("android.permission.INTERNET" not in manifest, "application must not request INTERNET", failures)
    require("android:usesCleartextTraffic=\"false\"" in manifest, "cleartext traffic must be disabled", failures)
    require('android:name=".TerminalSessionService"' in manifest, "session service must be declared", failures)
    require('android:exported="false"' in manifest, "session service must not be exported", failures)
    require('android:stopWithTask="true"' in manifest, "task-removal session policy must be explicit", failures)
    require("bindService(serviceIntent, serviceConnection" in activity, "Activity must bind the session service", failures)
    require("startService(serviceIntent)" in activity, "session host must survive Activity replacement", failures)
    require("TerminalSession(" not in activity, "Activity must not own the PTY session", failures)
    require("installFrontend(binder)" in activity, "renderer replacement must reuse the bound session host", failures)
    require("recoverRenderer(" in activity, "Activity must replace a failed WebView frontend", failures)
    require("class TerminalFrontendRecoveryState" in frontend_recovery, "renderer recovery coordinator must be explicit", failures)
    require("beginRecovery" in frontend_recovery and "completeRecovery" in frontend_recovery, "renderer recovery must reject duplicate and stale callbacks", failures)
    require("shutdown(rendererProcessGone = true)" in controller, "controller must destroy only the failed frontend after renderer loss", failures)
    require("sessionHost.detach" in controller, "renderer loss must invalidate the stale service attachment", failures)
    require("Upstream capability matrix" in capability_matrix, "capability matrix must be documented", failures)
    require("Layer 2 completion" in capability_matrix, "capability matrix must remain the Layer 2 completion authority", failures)
    require("direct shared-storage" in capability_matrix.lower() or "shared-storage" in capability_matrix.lower(), "capability matrix must track direct shared storage", failures)
    require("Frontend lifecycle" in capability_matrix and "replacement frontend" in capability_matrix, "capability matrix must track frontend reconnection", failures)
    require("renderer fallback" in capability_matrix or "DOM fallback" in capability_matrix, "capability matrix must track renderer recovery", failures)
    require("| Explicit clipboard actions |" in capability_matrix and "| OSC 8 links |" in capability_matrix, "capability matrix must track connected Android platform capabilities", failures)
    require("| `@xterm/addon-web-links` |" in capability_matrix and "Detected links use validated Android `ACTION_VIEW` bridge" in capability_matrix, "capability matrix must track official Web Links integration", failures)
    require("| Font scale |" in capability_matrix and "captured upstream default" in capability_matrix, "capability matrix must track completed Android font scaling", failures)
    require("| Terminal title |" in capability_matrix and "Connected with bounds" in capability_matrix, "capability matrix must track service-owned terminal title", failures)
    require("| Localizable xterm strings |" in capability_matrix and "Android locale resources" in capability_matrix, "capability matrix must track Android-localized xterm strings", failures)
    require("| Safe window reports |" in capability_matrix and "desktop/screen/position/resize operations disabled" in capability_matrix, "capability matrix must track the safe Android window-report subset", failures)
    validation = read_required(root, "docs/VALIDATION.md", failures)
    require("ADB runtime validation is deferred" in validation, "ADB non-claim must be documented", failures)

    source_texts = "\n".join((root_build, build, manifest, activity, session, session_service, controller, web_client, customization_kt))
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
