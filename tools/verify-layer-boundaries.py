#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path


def fail(message: str, failures: list[str]) -> None:
    failures.append(message)


def read(root: Path, relative: str, failures: list[str]) -> str:
    path = root / relative
    if not path.is_file():
        fail(f"missing layer file: {relative}", failures)
        return ""
    return path.read_text(encoding="utf-8")


def verify(root: Path) -> list[str]:
    failures: list[str] = []
    base = Path("app/src/main/assets/terminal")
    html = read(root, str(base / "bridge/index.html"), failures)
    contract_js = read(root, str(base / "bridge/terminal-contract.js"), failures)
    bridge_js = read(root, str(base / "bridge/terminal-bridge.js"), failures)
    renderer_js = read(root, str(base / "bridge/terminal-renderer.js"), failures)
    codec_js = read(root, str(base / "bridge/terminal-codec.js"), failures)
    bridge_css = read(root, str(base / "bridge/bridge.css"), failures)
    platform_js = read(root, str(base / "bridge/terminal-platform.js"), failures)
    ligatures_loader = read(root, str(base / "bridge/terminal-ligatures.js"), failures)
    customization_js = read(root, str(base / "customization/customization.js"), failures)
    customization_css = read(root, str(base / "customization/customization.css"), failures)
    customization_kt = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalCustomization.kt",
        failures,
    )
    contract_kt = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt",
        failures,
    )
    host_appearance = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalHostAppearance.kt",
        failures,
    )
    shared_storage = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSharedStorage.kt",
        failures,
    )
    controller = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalController.kt",
        failures,
    )
    platform_adapter = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalPlatformAdapter.kt",
        failures,
    )
    platform_policy = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalPlatformPolicy.kt",
        failures,
    )
    platform_state = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalPlatformState.kt",
        failures,
    )
    document_policy = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalDocumentPolicy.kt",
        failures,
    )
    document_transport = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalDocumentTransport.kt",
        failures,
    )
    service = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSessionService.kt",
        failures,
    )
    session_title = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSessionTitle.kt",
        failures,
    )
    strings_default = read(root, "app/src/main/res/values/strings.xml", failures)
    strings_ko = read(root, "app/src/main/res/values-ko/strings.xml", failures)
    replay = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/SessionReplayBuffer.kt",
        failures,
    )
    geometry = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalGeometry.kt",
        failures,
    )
    activity = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/MainActivity.kt",
        failures,
    )
    web_client = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/LocalAssetWebViewClient.kt",
        failures,
    )
    frontend_recovery = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalFrontendRecoveryState.kt",
        failures,
    )
    session = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSession.kt",
        failures,
    )
    native = read(root, "app/src/main/c/shell_bridge.c", failures)
    session_environment = read(root, "app/src/main/c/session_environment.c", failures)
    session_directories = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSessionDirectories.kt",
        failures,
    )
    manifest = read(root, "app/src/main/AndroidManifest.xml", failures)
    architecture = read(root, "docs/architecture.md", failures)

    for heading in (
        "Layer 1: unmodified upstream",
        "Layer 2: complete Android adaptation",
        "Layer 3: optional customization scaffold",
        "Upgrade and change boundary",
    ):
        if heading not in architecture:
            fail(f"architecture document lacks heading: {heading}", failures)

    expected_order = (
        "/terminal/vendor/xterm.js",
        "/terminal/vendor/addon-fit.js",
        "/terminal/vendor/addon-serialize.js",
        "/terminal/vendor/addon-clipboard.js",
        "/terminal/vendor/addon-image.js",
        "/terminal/vendor/addon-progress.js",
        "/terminal/vendor/addon-search.js",
        "/terminal/vendor/addon-unicode11.js",
        "/terminal/vendor/addon-web-fonts.js",
        "/terminal/vendor/addon-web-links.js",
        "/terminal/vendor/addon-webgl.js",
        "/terminal/bridge/terminal-ligatures.js",
        "/terminal/bridge/terminal-contract.js",
        "/terminal/bridge/terminal-renderer.js",
        "/terminal/bridge/terminal-codec.js",
        "/terminal/bridge/terminal-platform.js",
        "/terminal/bridge/terminal-bridge.js",
        "/terminal/customization/customization.js",
    )
    positions = [html.find(value) for value in expected_order]
    if any(position < 0 for position in positions):
        fail("HTML does not load every declared Layer 1/2/3 script", failures)
    elif positions != sorted(positions):
        fail("HTML script order must be Layer 1, Layer 2, then optional Layer 3", failures)
    if "/terminal/customization/customization.css" not in html:
        fail("HTML does not load the Layer 3 stylesheet scaffold", failures)
    for asset_path in (
        "/terminal/vendor/addon-clipboard.js",
        "/terminal/vendor/addon-image.js",
        "/terminal/vendor/addon-progress.js",
        "/terminal/vendor/addon-search.js",
        "/terminal/vendor/addon-unicode11.js",
        "/terminal/vendor/addon-web-fonts.js",
        "/terminal/vendor/addon-web-links.js",
        "/terminal/vendor/addon-webgl.js",
        "/terminal/bridge/terminal-ligatures.js",
        "/terminal/customization/customization.css",
        "/terminal/customization/customization.js",
    ):
        if asset_path not in web_client:
            fail(f"local asset allowlist lacks required path: {asset_path}", failures)
    if 'id="custom-ui-root"' in html:
        fail("Layer 3 must not reserve product UI before an explicit feature decision", failures)
    if "window.AndroidTerminalLayer2" not in bridge_js:
        fail("Layer 2 must expose the stable optional-customization capability", failures)
    if "AndroidTerminalCustomization" in bridge_js or "/terminal/customization/" in bridge_js:
        fail("Layer 2 must not depend on the Layer 3 implementation", failures)
    if "contractVersion: 2" not in customization_js or "window.AndroidTerminalCustomization" not in customization_js:
        fail("Layer 3 JavaScript scaffold contract is incomplete", failures)
    if "CONTRACT_VERSION = 2" not in customization_kt:
        fail("Layer 3 native scaffold contract is incomplete", failures)

    if "protocolVersion: 6" not in contract_js or "PROTOCOL_VERSION = 6" not in contract_kt:
        fail("JavaScript and Kotlin protocol version 6 must match", failures)
    if "channelMarker: 'native-shell'" not in contract_js or 'CHANNEL_MARKER = "native-shell"' not in contract_kt:
        fail("JavaScript and Kotlin channel marker must match", failures)
    message_types = {
        "ready": "ready",
        "input": "input",
        "resize": "resize",
        "ack": "ack",
        "platformRequest": "platform-request",
        "sessionTitle": "session-title",
        "snapshot": "snapshot",
        "restoreAck": "restore-ack",
        "attached": "attached",
        "output": "output",
        "state": "state",
        "geometry": "geometry",
        "platformState": "platform-state",
        "platformResult": "platform-result",
        "error": "error",
    }
    for key, wire in message_types.items():
        if f"{key}: '{wire}'" not in contract_js:
            fail(f"JavaScript contract lacks message type: {wire}", failures)
        if f'= "{wire}"' not in contract_kt:
            fail(f"Kotlin contract lacks message type: {wire}", failures)

    for token in (
        "new window.Terminal({allowProposedApi: true})",
        "new window.FitAddon.FitAddon()",
        "new window.SerializeAddon.SerializeAddon()",
        "new window.ClipboardAddon.ClipboardAddon(undefined, clipboardProvider)",
        "new window.ImageAddon.ImageAddon()",
        "new window.ProgressAddon.ProgressAddon()",
        "new window.SearchAddon.SearchAddon()",
        "new window.Unicode11Addon.Unicode11Addon()",
        "new window.WebFontsAddon.WebFontsAddon()",
        "new module.LigaturesAddon(options)",
        "resolveLigaturesModule()",
        "rendererController.reactivate()",
        "terminal.onData(",
        "terminal.onBinary(",
        "terminal.write(",
        "contract.protocolVersion",
        "contract.pageCapabilities",
        "measureGeometry(type)",
        "geometryKey(geometry)",
        "window.visualViewport.addEventListener('resize'",
        "contract.messages.geometry",
        "window.AndroidTerminalPlatform = platform",
        "terminal.hasSelection()",
        "terminal.getSelection()",
        "terminal.paste(text)",
        "terminal.options.linkHandler",
        "new window.WebLinksAddon.WebLinksAddon(",
        "platform.openExternalUri(uri)",
        "terminal.onBell(",
        "terminal.onTitleChange(",
        "contract.messages.sessionTitle",
        "onTitleState",
        "getTitleState()",
        "getWindowReportState()",
        "contract.messages.platformRequest",
        "contract.messages.platformState",
        "contract.messages.platformResult",
        "importDocument(options = {})",
        "exportDocument(path, options = {})",
        "contract.platformOperations.documentImport",
        "contract.platformOperations.documentExport",
        "platformIntegration.applyPlatformState",
        "window.AndroidTerminalLayer2 = Object.freeze",
        "onPlatformState",
        "requestGeometrySync()",
        "contractVersion: 4",
    ):
        if token not in bridge_js:
            fail(f"Layer 2 bridge lacks required public integration token: {token}", failures)

    if bridge_js.count("allowProposedApi") != 1:
        fail("proposed API opt-in must be isolated to official Unicode 11 registration", failures)
    if "new window.ImageAddon.ImageAddon({" in bridge_js:
        fail("Layer 2 must instantiate ImageAddon with upstream defaults", failures)
    if "unicode.activeVersion =" in bridge_js.split("setActiveVersion(version)")[0]:
        fail("Layer 2 must not select a Unicode version before Layer 3 requests one", failures)

    for token in (
        "cursorBlink",
        "cursorStyle",
        "fontFamily",
        "letterSpacing",
        "lineHeight",
        "scrollback",
    ):
        if token in bridge_js or token in bridge_css or token in platform_js:
            fail(f"unnecessary product option leaked into Layer 2: {token}", failures)
    if "fontSize" in bridge_js or "fontSize" in bridge_css:
        fail("font size adaptation must remain isolated in the Android platform mapping", failures)

    for token in (
        "contractVersion: 4",
        "isExternalUriAllowed",
        "applyPlatformState",
        "terminal.options.screenReaderMode",
        "const upstreamFontSizes = new WeakMap()",
        "Number(terminal.options.fontSize)",
        "upstreamFontSizes.get(terminal) * boundedFontScale(value)",
        "applyFontScale(terminal, state.fontScale)",
        "applyLocalizedStrings(terminal, state)",
        "terminal.strings.promptLabel",
        "terminal.strings.tooMuchOutput",
        "configureWindowOperations",
        "getWinSizePixels: true",
        "getCellSizePixels: true",
        "getWinSizeChars: true",
        "pushTitle: true",
        "popTitle: true",
        "registerCsiHandler({final: 't'}",
        "terminal.refresh(",
        "terminal.input(",
    ):
        if token not in platform_js:
            fail(f"Layer 2 platform mapping lacks token: {token}", failures)
    for forbidden_window_option in (
        "fullscreenWin: true",
        "setWinPosition: true",
        "getScreenSizePixels: true",
        "getScreenSizeChars: true",
        "setWinSizePixels: true",
        "setWinSizeChars: true",
    ):
        if forbidden_window_option in platform_js:
            fail(f"unsafe or desktop-only window operation enabled: {forbidden_window_option}", failures)
    for token in (
        "MAX_CODE_POINTS = 1024",
        "codePointAt(index)",
        "codePoint == 0x7f",
    ):
        if token not in session_title:
            fail(f"service title sanitizer lacks token: {token}", failures)
    for token in (
        'name="xterm_prompt_label"',
        'name="xterm_too_much_output"',
    ):
        if token not in strings_default or token not in strings_ko:
            fail(f"Android xterm localization resources lack token: {token}", failures)
    for capability in (
        "session-title-state-v1",
        "localized-xterm-strings-v1",
        "safe-window-reports-v1",
    ):
        if capability not in contract_js or capability not in contract_kt:
            fail(f"page capability must match across JavaScript and Kotlin: {capability}", failures)
    if "android-localized-xterm-strings" not in contract_js or "android-localized-xterm-strings" not in contract_kt:
        fail("native localized-string capability must match", failures)

    if "terminal.options.theme" in platform_js or "darkTheme" in platform_js or "lightTheme" in platform_js:
        fail("project terminal palettes belong to Layer 3, not Layer 2", failures)
    for token in (
        "const darkTheme = Object.freeze",
        "const lightTheme = Object.freeze",
        "layer2.onPlatformState",
        "layer2.terminal.options.theme",
        "layer2.requestGeometrySync()",
    ):
        if token not in customization_js:
            fail(f"Layer 3 palette scaffold lacks token: {token}", failures)

    for token in (
        "nativePort",
        "postMessage",
        "WebMessagePort",
        "NativeShellCodec",
        "createWebMessageChannel",
        "NativePty",
        "forkpty",
        "execve",
        "TIOCSWINSZ",
    ):
        if token in platform_js:
            fail(f"public Layer 2 platform mapping bypasses bridge internals: {token}", failures)

    for private_api in ("._core", "._renderService", "._inputHandler", "._bufferService"):
        if private_api in bridge_js or private_api in renderer_js or private_api in platform_js or private_api in customization_js:
            fail(f"xterm.js private API is forbidden: {private_api}", failures)

    for forbidden in (
        "nativePort",
        "WebMessagePort",
        "NativePty",
        "forkpty",
        "execve",
        "TIOCSWINSZ",
        "AndroidTerminalBridge",
        "AndroidTerminalPlatform",
    ):
        if forbidden in customization_js or forbidden in customization_kt:
            fail(f"Layer 3 bypasses the stable Layer 2 capability: {forbidden}", failures)

    for token in ("documentImport: 'document-import'", "documentExport: 'document-export'", "android-document-transport"):
        if token not in contract_js:
            fail(f"document transport contract lacks token: {token}", failures)
    for token in ("DOCUMENT_IMPORT", "DOCUMENT_EXPORT", "android-document-transport"):
        if token not in contract_kt:
            fail(f"native document transport contract lacks token: {token}", failures)
    for token in (
        "Intent.ACTION_OPEN_DOCUMENT",
        "Intent.ACTION_CREATE_DOCUMENT",
        "OpenableColumns.DISPLAY_NAME",
        "openInputStream",
        "openOutputStream",
        "activity.filesDir",
    ):
        if token not in document_transport:
            fail(f"SAF private-file transport lacks token: {token}", failures)
    for token in (
        "validatedRelativeHomePath",
        "resolvePrivateExportSource",
        "MAX_DOCUMENT_BYTES",
        "uniqueImportTarget",
    ):
        if token not in document_policy:
            fail(f"document transport policy lacks token: {token}", failures)
    for forbidden in ("ACTION_OPEN_DOCUMENT_TREE", "takePersistableUriPermission", "DocumentsContract", "FUSE"):
        if forbidden in document_transport or forbidden in document_policy or forbidden in activity:
            fail(f"SAF virtual-mount behavior is forbidden: {forbidden}", failures)

    if "createWebMessageChannel()" not in controller or "TerminalContract" not in controller:
        fail("Kotlin platform bridge must use WebMessagePort through TerminalContract", failures)
    if "TerminalHostAppearance.backgroundColor" not in controller or "Color.BLACK" not in host_appearance:
        fail("Android host appearance mapping must remain in Layer 2", failures)
    if "NativeShellCodec" not in codec_js:
        fail("byte codec must remain in Layer 2", failures)

    if "TerminalSessionService.LocalBinder" not in controller or "TerminalSession(" in controller:
        fail("WebView controller must attach to, not own, the PTY session", failures)
    if "class TerminalSessionService : Service()" not in service or "TerminalSession(" not in service:
        fail("Android service must own the PTY session", failures)
    if "SessionReplayBuffer(REPLAY_LIMIT_BYTES)" not in service:
        fail("service must own the bounded raw replay journal", failures)
    if "connectionGeneration" not in service or "sessionId" not in service:
        fail("service attachment identity is incomplete", failures)
    if "snapshotAfter" not in replay or "removeFirst()" not in replay or "bytes.copyOf()" not in replay:
        fail("raw replay tail must be rolling, bounded, and byte preserving", failures)
    snapshot_store = read(root, "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSerializedSnapshot.kt", failures)
    if "class TerminalSerializedSnapshotStore" not in snapshot_store or "bytes.copyOf()" not in snapshot_store:
        fail("opaque serialized xterm snapshot storage is missing", failures)
    if "TerminalSerializedSnapshotStore(TerminalContract.MAX_SERIALIZED_SNAPSHOT_BYTES)" not in service:
        fail("service must own the bounded opaque xterm snapshot", failures)
    if "new window.SerializeAddon.SerializeAddon()" not in bridge_js or "serializeAddon.serialize()" not in bridge_js:
        fail("Layer 2 must use the official xterm serialize addon", failures)
    if "serialize-state-v1" not in contract_js or "xterm-serialized-state" not in contract_kt:
        fail("serialized state capabilities must match", failures)
    if "new WebglAddon.WebglAddon(false)" not in renderer_js or "candidate.onContextLoss" not in renderer_js:
        fail("Layer 2 must use the official WebGL addon and public context-loss event", failures)
    if "fallback('context-loss')" not in renderer_js or "permanentlyFellBack" not in renderer_js:
        fail("WebGL context loss must permanently fall back for the current frontend", failures)
    if "webgl-renderer-fallback-v1" not in contract_js or "webgl-renderer-fallback-v1" not in contract_kt:
        fail("WebGL fallback page capability is not mirrored", failures)
    if "function activate()" not in renderer_js or "rendererController.activate()" not in bridge_js:
        fail("Layer 2 must automatically attempt the official WebGL renderer", failures)
    if "policy-disabled" in renderer_js or "preferWebgl" in renderer_js or "preferWebgl" in bridge_js:
        fail("WebGL must not depend on a Layer 3 policy gate", failures)
    if "class TerminalGeometryState" not in geometry or "if (!candidate.isUsable()) return null" not in geometry:
        fail("terminal geometry must reject transient zero layouts", failures)
    if "if (sanitized == current) return null" not in geometry:
        fail("terminal geometry must deduplicate unchanged sizes", failures)
    if "bindService(serviceIntent, serviceConnection" not in activity or "TerminalSession(" in activity:
        fail("Activity must remain a replaceable service-bound frontend", failures)
    if "override fun onActivityResult" not in activity or "controller?.handleActivityResult" not in activity:
        fail("Activity must return SAF results to the current Layer 2 frontend", failures)
    if "override fun onRenderProcessGone" not in web_client or "onRendererGone(detail.didCrash())" not in web_client:
        fail("Layer 2 must handle WebView renderer termination through the host callback", failures)
    if "shutdown(rendererProcessGone = true)" not in controller or "sessionHost.detach" not in controller:
        fail("renderer recovery must detach only the stale frontend attachment", failures)
    if "installFrontend(binder)" not in activity or "recoverRenderer(" not in activity:
        fail("Activity must install a replacement WebView against the same service binder", failures)
    if "class TerminalFrontendRecoveryState" not in frontend_recovery:
        fail("renderer recovery state must be isolated in Layer 2", failures)
    for token in ("registerFrontend", "beginRecovery", "completeRecovery", "invalidate"):
        if token not in frontend_recovery:
            fail(f"renderer recovery state lacks token: {token}", failures)
    for token in (
        "setOnApplyWindowInsetsListener",
        "addOnLayoutChangeListener",
        "onConfigurationChanged",
        "requestApplyInsets()",
        "requestGeometrySync()",
    ):
        if token not in activity:
            fail(f"Android window geometry connection lacks token: {token}", failures)
    if "session-attach-v2" not in contract_js or "session-attach-v2" not in contract_kt:
        fail("session attachment capability is not mirrored", failures)
    if "geometry-dedup-v1" not in contract_js or "geometry-dedup-v1" not in contract_kt:
        fail("geometry deduplication capability is not mirrored", failures)
    if "android-window-geometry" not in contract_kt:
        fail("native Android window geometry capability is missing", failures)
    if "webview-renderer-recovery" not in contract_kt:
        fail("native WebView renderer recovery capability is missing", failures)
    if "platform-bridge-v2" not in contract_js or "platform-bridge-v2" not in contract_kt:
        fail("platform bridge capability is not mirrored", failures)
    if "android-font-scale-v1" not in contract_js or "android-font-scale-v1" not in contract_kt:
        fail("font-scale page capability is not mirrored", failures)
    if "android-font-scale-state" not in contract_js or "android-font-scale-state" not in contract_kt:
        fail("native font-scale capability is not mirrored", failures)
    if "web-links-v1" not in contract_js or "web-links-v1" not in contract_kt:
        fail("official Web Links page capability is not mirrored", failures)
    if "new window.WebLinksAddon.WebLinksAddon(" not in bridge_js or "platform.openExternalUri(uri)" not in bridge_js:
        fail("official Web Links addon must route through the bounded Android URI operation", failures)
    if "window.open(" in bridge_js:
        fail("terminal link activation must not navigate directly from the WebView", failures)
    if 'android:configChanges="fontScale|' not in manifest:
        fail("Activity does not own font-scale configuration changes", failures)
    if "configuration.fontScale.toDouble().coerceIn(0.5, 3.0)" not in platform_adapter:
        fail("Android font-scale state is not bounded at the native boundary", failures)
    for capability in (
        "android-clipboard",
        "android-external-uri",
        "android-haptic-bell",
        "android-system-theme",
        "android-accessibility-state",
        "android-hardware-keyboard-state",
        "android-document-transport",
        "android-shared-storage-direct-path",
        "android-native-account-session",
    ):
        if capability not in contract_kt:
            fail(f"native platform capability is missing: {capability}", failures)
    if "TerminalPlatformAdapter(activity, view)" not in controller:
        fail("WebView controller must delegate Android capabilities to TerminalPlatformAdapter", failures)
    if "TerminalContract.MessageType.PLATFORM_REQUEST" not in controller:
        fail("Kotlin controller does not accept bounded platform requests", failures)
    for token in (
        "ClipboardManager",
        "ClipData.newPlainText",
        "Intent.ACTION_VIEW",
        "performHapticFeedback",
        "AccessibilityStateChangeListener",
        "TouchExplorationStateChangeListener",
    ):
        if token not in platform_adapter:
            fail(f"Android platform adapter lacks token: {token}", failures)
    for token in (
        "MAX_CLIPBOARD_CHARACTERS",
        "validatedExternalUri",
        "scheme !in allowedSchemes",
        "parsed.userInfo != null",
        "parsed.host.isNullOrBlank()",
    ):
        if token not in platform_policy:
            fail(f"platform policy lacks bounded validation token: {token}", failures)
    if "data class TerminalPlatformState" not in platform_state or "sharedStorageAccessGranted" not in platform_state or "sharedStoragePath" not in platform_state:
        fail("Android platform state contract is incomplete", failures)
    if "TerminalPlatformPolicy.ALLOWED_EXTERNAL_URI_SCHEMES" not in platform_adapter:
        fail("external URI allowlist must remain in Layer 2 policy", failures)
    if "hapticBellEnabled" in platform_adapter:
        fail("Layer 2 bell integration must not depend on an optional Layer 3 preference", failures)

    for token in (
        "android.permission.MANAGE_EXTERNAL_STORAGE",
        "android.permission.READ_EXTERNAL_STORAGE",
        "android.permission.WRITE_EXTERNAL_STORAGE",
        'android:requestLegacyExternalStorage="true"',
    ):
        if token not in manifest:
            fail(f"manifest lacks Layer 2 shared-storage adaptation: {token}", failures)
    for token in (
        "Environment.isExternalStorageManager()",
        "Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION",
        "Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION",
        "Environment.getExternalStorageDirectory()",
    ):
        if token not in shared_storage:
            fail(f"shared-storage adapter lacks token: {token}", failures)
    if "TerminalSharedStorage.requestAccess(this)" not in activity:
        fail("Activity must initiate the Android system storage grant flow at startup", failures)
    if "prepareHomeLink" in shared_storage + session or "Os.symlink" in shared_storage + session:
        fail("shared-storage adaptation must not populate HOME", failures)
    if "sharedStorageDirectory" in session or "shared_storage_directory" in native:
        fail("shared storage must not enter the PTY spawn contract", failures)
    if "session_environment_merge(" not in native:
        fail("native shell must merge the inherited Android environment", failures)
    for forbidden in ("PATH=/system/bin", "SHELL=/system/bin/sh", "LANG=C.UTF-8", "ANDROID_STORAGE=/storage", "EXTERNAL_STORAGE="):
        if forbidden in native or forbidden in session_environment:
            fail(f"native shell must not synthesize {forbidden}", failures)
    for override in ('"HOME"', '"TMPDIR"', '"TERM"'):
        if override not in session_environment:
            fail(f"native session override missing: {override}", failures)
    if "TerminalSessionDirectories.prepareTemporaryDirectory(temporaryDirectory)" not in session:
        fail("session must prepare its distinct TMPDIR", failures)
    if "directory.mkdirs()" not in session_directories or "directory.canWrite()" not in session_directories:
        fail("TMPDIR lifecycle validation is incomplete", failures)
    if 'char *const arguments[] = {"-sh", NULL};' not in native:
        fail("native shell must use leading-hyphen argv[0] login semantics", failures)
    if '"-l"' in native or "system(" in native or "popen(" in native:
        fail("login shell must remain a direct execve adaptation", failures)
    if "native-account-session-v1" not in contract_js or "native-account-session-v1" not in contract_kt:
        fail("native account/session page capability must match", failures)
    if "layer3-scaffold-v1" not in contract_js or "layer3-scaffold-v1" not in contract_kt:
        fail("Layer 3 scaffold capability must match", failures)

    if "import {LigaturesAddon} from '/terminal/vendor/addon-ligatures.mjs'" not in ligatures_loader:
        fail("Layer 2 ligatures module adapter must import the unmodified Layer 1 ESM entry", failures)
    if "AndroidTerminalLigaturesLoader" not in ligatures_loader:
        fail("Layer 2 ligatures module adapter is incomplete", failures)

    semantic_parser_pattern = re.compile(r"\b(?:CSI|OSC|DCS|SGR)\b|escape sequence|terminal cell", re.IGNORECASE)
    for name, text in (("Kotlin controller", controller), ("native PTY bridge", native)):
        if semantic_parser_pattern.search(text):
            fail(f"{name} appears to implement terminal semantics", failures)

    vendor = root / base / "vendor"
    if not vendor.is_dir():
        fail("Layer 1 vendor directory is missing", failures)
    else:
        allowed = {
            "README.md",
            "ASSET_RECEIPT.json",
            "xterm.js",
            "xterm.css",
            "addon-fit.js",
            "addon-serialize.js",
            "addon-clipboard.js",
            "addon-image.js",
            "addon-progress.js",
            "addon-search.js",
            "addon-unicode11.js",
            "addon-web-fonts.js",
            "addon-ligatures.mjs",
            "addon-web-links.js",
            "addon-webgl.js",
            "LICENSE.xterm.txt",
            "LICENSE.addon-fit.txt",
            "PACKAGE.addon-serialize.json",
            "PACKAGE.addon-clipboard.json",
            "PACKAGE.addon-image.json",
            "PACKAGE.addon-progress.json",
            "PACKAGE.addon-search.json",
            "PACKAGE.addon-unicode11.json",
            "PACKAGE.addon-web-fonts.json",
            "PACKAGE.addon-ligatures.json",
            "PACKAGE.addon-web-links.json",
            "PACKAGE.addon-webgl.json",
        }
        for path in vendor.iterdir():
            if not path.is_file() or path.name not in allowed:
                fail(f"unexpected Layer 1 vendor entry: {path.relative_to(root)}", failures)

    return failures


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    failures = verify(root)
    if failures:
        for message in failures:
            print(f"FAIL layer-boundary: {message}", file=sys.stderr)
        return 1
    print("PASS layer-boundary")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
