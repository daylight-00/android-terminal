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

    if "protocolVersion: 3" not in contract_js or "PROTOCOL_VERSION = 3" not in contract_kt:
        fail("JavaScript and Kotlin protocol version 3 must match", failures)
    if "channelMarker: 'native-shell'" not in contract_js or 'CHANNEL_MARKER = "native-shell"' not in contract_kt:
        fail("JavaScript and Kotlin channel marker must match", failures)
    for message_type in ("ready", "input", "resize", "ack", "attached", "output", "state", "geometry", "error"):
        if f"{message_type}: '{message_type}'" not in contract_js:
            fail(f"JavaScript contract lacks message type: {message_type}", failures)
        if f'= "{message_type}"' not in contract_kt:
            fail(f"Kotlin contract lacks message type: {message_type}", failures)

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
        "contractVersion: 1",
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
    if "replayAvailable = false" not in replay or "bytes.copyOf()" not in replay:
        fail("raw replay must be bounded and byte preserving", failures)
    if "class TerminalGeometryState" not in geometry or "if (!candidate.isUsable()) return null" not in geometry:
        fail("terminal geometry must reject transient zero layouts", failures)
    if "if (sanitized == current) return null" not in geometry:
        fail("terminal geometry must deduplicate unchanged sizes", failures)
    if "bindService(serviceIntent, serviceConnection" not in activity or "TerminalSession(" in activity:
        fail("Activity must remain a replaceable service-bound frontend", failures)
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
            "LICENSE.xterm.txt",
            "LICENSE.addon-fit.txt",
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
