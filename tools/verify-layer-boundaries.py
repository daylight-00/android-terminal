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
    codec_js = read(root, str(base / "bridge/terminal-codec.js"), failures)
    bridge_css = read(root, str(base / "bridge/bridge.css"), failures)
    custom_js = read(root, str(base / "customization/customization.js"), failures)
    custom_css = read(root, str(base / "customization/customization.css"), failures)
    contract_kt = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt",
        failures,
    )
    native_customization = read(
        root,
        "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalCustomization.kt",
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
    native = read(root, "app/src/main/c/shell_bridge.c", failures)
    architecture = read(root, "docs/architecture.md", failures)

    for heading in (
        "Layer 1: upstream runtime",
        "Layer 2: required Android integration",
        "Layer 3: explicit customization",
        "Upgrade boundary",
    ):
        if heading not in architecture:
            fail(f"architecture document lacks heading: {heading}", failures)

    expected_order = (
        "/terminal/vendor/xterm.js",
        "/terminal/vendor/addon-fit.js",
        "/terminal/vendor/addon-serialize.js",
        "/terminal/bridge/terminal-contract.js",
        "/terminal/bridge/terminal-codec.js",
        "/terminal/customization/customization.js",
        "/terminal/bridge/terminal-bridge.js",
    )
    positions = [html.find(value) for value in expected_order]
    if any(position < 0 for position in positions):
        fail("HTML does not load every declared layer script", failures)
    elif positions != sorted(positions):
        fail("HTML layer script order is not upstream -> contract -> customization -> bridge", failures)
    if 'id="custom-ui-root"' not in html:
        fail("custom UI root is missing", failures)

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
        "new window.Terminal(customization.terminalOptions)",
        "new window.FitAddon.FitAddon()",
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
        "terminal.onBell(",
        "contract.messages.platformRequest",
        "contract.messages.platformState",
        "contract.messages.platformResult",
        "importDocument(options = {})",
        "exportDocument(path, options = {})",
        "contract.platformOperations.documentImport",
        "contract.platformOperations.documentExport",
    ):
        if token not in bridge_js:
            fail(f"Layer 2 bridge lacks required public integration token: {token}", failures)

    for token in (
        "cursorBlink",
        "cursorStyle",
        "fontFamily",
        "fontSize",
        "letterSpacing",
        "lineHeight",
        "scrollback",
        "cursorAccent",
        "#000000",
        "#e6e6e6",
    ):
        if token in bridge_js or token in bridge_css:
            fail(f"Layer 3 policy leaked into Layer 2 bridge: {token}", failures)

    for token in (
        "cursorBlink",
        "fontSize",
        "scrollback",
        "theme",
        "contractVersion: 2",
        "platformPolicy",
        "isExternalUriAllowed",
        "applyPlatformState",
        "function mount(context)",
    ):
        if token not in custom_js:
            fail(f"Layer 3 customization lacks explicit policy token: {token}", failures)

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
        if token in custom_js or token in custom_css or token in native_customization:
            fail(f"Layer 3 accesses Layer 2 internals: {token}", failures)

    for private_api in ("._core", "._renderService", "._inputHandler", "._bufferService"):
        if private_api in bridge_js or private_api in custom_js:
            fail(f"xterm.js private API is forbidden: {private_api}", failures)

    for unselected_upstream in ("ClipboardAddon", "WebLinksAddon", "osc52-clipboard", "'web-links'"):
        if unselected_upstream in bridge_js or unselected_upstream in contract_js:
            fail(f"unselected upstream addon leaked into Layer 2: {unselected_upstream}", failures)

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
    if "TerminalCustomization.backgroundColor" not in controller:
        fail("native appearance policy must come from TerminalCustomization", failures)
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
    for capability in (
        "android-clipboard",
        "android-external-uri",
        "android-haptic-bell",
        "android-system-theme",
        "android-accessibility-state",
        "android-hardware-keyboard-state",
        "android-document-transport",
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
    if "data class TerminalPlatformState" not in platform_state:
        fail("Android platform state contract is missing", failures)
    if "allowedExternalUriSchemes" not in native_customization or "hapticBellEnabled" not in native_customization:
        fail("native Layer 3 platform policy is incomplete", failures)

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
            "LICENSE.xterm.txt",
            "LICENSE.addon-fit.txt",
            "PACKAGE.addon-serialize.json",
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
