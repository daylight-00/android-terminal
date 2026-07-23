#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

EXPECTED_ADDONS = {
    "@xterm/addon-attach": ("not-applicable", "excluded", "none"),
    "@xterm/addon-clipboard": ("layer2-runtime", "pending", "automatic"),
    "@xterm/addon-fit": ("layer2-runtime", "connected", "automatic"),
    "@xterm/addon-image": ("layer2-runtime", "pending", "automatic"),
    "@xterm/addon-ligatures": ("layer2-capability", "pending", "registered"),
    "@xterm/addon-progress": ("layer2-runtime", "pending", "automatic"),
    "@xterm/addon-search": ("layer2-capability", "pending", "registered"),
    "@xterm/addon-serialize": ("layer2-runtime", "connected-with-bounds", "automatic"),
    "@xterm/addon-unicode-graphemes": (
        "experimental",
        "excluded-from-completion-gate",
        "none",
    ),
    "@xterm/addon-unicode11": ("layer2-capability", "pending", "registered"),
    "@xterm/addon-web-fonts": ("layer2-capability", "pending", "registered"),
    "@xterm/addon-web-links": ("layer2-runtime", "connected", "automatic"),
    "@xterm/addon-webgl": (
        "layer2-runtime",
        "connected-with-bounds",
        "automatic-attempt",
    ),
}

REQUIRED_CORE_IDS = {
    "terminal-emulation",
    "pty-input",
    "pty-output-flow-control",
    "geometry",
    "focus-ime-hardware-keyboard",
    "clipboard-selection-paste",
    "osc52-clipboard",
    "osc8-links",
    "bell",
    "title",
    "platform-color-scheme",
    "accessibility",
    "localizable-strings",
    "font-scale",
    "window-metric-reports",
    "public-extension-apis",
    "frontend-lifecycle",
}

ALLOWED_CLASSIFICATIONS = {
    "layer2-runtime",
    "layer2-capability",
    "native-already",
    "not-applicable",
    "experimental",
}


def fail(message: str, failures: list[str]) -> None:
    failures.append(message)


def nonempty_string(value: object) -> bool:
    return isinstance(value, str) and value.strip() != ""


def verify(root: Path) -> list[str]:
    failures: list[str] = []
    inventory_path = root / "docs/upstream-capabilities.json"
    matrix_path = root / "docs/capability-matrix.md"
    if not inventory_path.is_file():
        return ["missing capability authority: docs/upstream-capabilities.json"]
    if not matrix_path.is_file():
        return ["missing capability view: docs/capability-matrix.md"]

    try:
        inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [f"invalid capability authority: {error}"]

    if inventory.get("schema_version") != 1:
        fail("capability authority schema_version must be 1", failures)
    upstream = inventory.get("upstream")
    if not isinstance(upstream, dict):
        fail("capability authority lacks upstream metadata", failures)
        upstream = {}
    if upstream.get("project") != "xtermjs/xterm.js":
        fail("capability authority must bind the official xtermjs/xterm.js project", failures)
    if upstream.get("pinned_core") != "@xterm/xterm@6.0.0":
        fail("capability authority must bind the pinned xterm.js core", failures)

    core = inventory.get("core_capabilities")
    if not isinstance(core, list):
        fail("core_capabilities must be a list", failures)
        core = []
    core_ids: list[str] = []
    for row in core:
        if not isinstance(row, dict):
            fail("core capability row must be an object", failures)
            continue
        identifier = row.get("id")
        if not nonempty_string(identifier):
            fail("core capability row lacks id", failures)
            continue
        core_ids.append(identifier)
        if row.get("classification") not in ALLOWED_CLASSIFICATIONS:
            fail(f"core capability has invalid classification: {identifier}", failures)
        for key in ("authority", "status", "android_boundary", "layer3_boundary"):
            if not nonempty_string(row.get(key)):
                fail(f"core capability lacks {key}: {identifier}", failures)
    if len(core_ids) != len(set(core_ids)):
        fail("core capability ids must be unique", failures)
    missing_core = sorted(REQUIRED_CORE_IDS - set(core_ids))
    extra_core = sorted(set(core_ids) - REQUIRED_CORE_IDS)
    if missing_core:
        fail(f"missing core capability rows: {', '.join(missing_core)}", failures)
    if extra_core:
        fail(f"unexpected core capability rows: {', '.join(extra_core)}", failures)

    addons = inventory.get("official_addons")
    if not isinstance(addons, list):
        fail("official_addons must be a list", failures)
        addons = []
    addon_rows: dict[str, dict[str, object]] = {}
    for row in addons:
        if not isinstance(row, dict):
            fail("official addon row must be an object", failures)
            continue
        package = row.get("package")
        if not nonempty_string(package):
            fail("official addon row lacks package", failures)
            continue
        if package in addon_rows:
            fail(f"duplicate official addon row: {package}", failures)
            continue
        addon_rows[package] = row
        for key in ("android_boundary", "layer3_boundary"):
            if not nonempty_string(row.get(key)):
                fail(f"official addon lacks {key}: {package}", failures)

    missing_addons = sorted(set(EXPECTED_ADDONS) - set(addon_rows))
    extra_addons = sorted(set(addon_rows) - set(EXPECTED_ADDONS))
    if missing_addons:
        fail(f"missing official addon rows: {', '.join(missing_addons)}", failures)
    if extra_addons:
        fail(f"unexpected official addon rows: {', '.join(extra_addons)}", failures)
    for package, expected in EXPECTED_ADDONS.items():
        row = addon_rows.get(package)
        if row is None:
            continue
        actual = (
            row.get("classification"),
            row.get("status"),
            row.get("default_activation"),
        )
        if actual != expected:
            fail(
                f"official addon classification mismatch for {package}: "
                f"expected={expected!r} actual={actual!r}",
                failures,
            )

    webview = inventory.get("webview_boundary")
    if not isinstance(webview, list) or len(webview) < 2:
        fail("WebView boundary must state both included and not-applicable surfaces", failures)

    matrix = matrix_path.read_text(encoding="utf-8")
    matrix_lines = matrix.splitlines()
    for package in EXPECTED_ADDONS:
        row_prefix = f"| `{package}` |"
        if sum(line.startswith(row_prefix) for line in matrix_lines) != 1:
            fail(f"human capability matrix must list {package} exactly once", failures)
    for token in (
        "unmodified upstream capability",
        "Android operation required to make it usable",
        "Layer 3 scaffold rule",
        "Layer 2 must operate when the scaffold is empty or omitted",
        "generic remote navigation",
        "@xterm/xterm@6.0.0",
    ):
        if token not in matrix:
            fail(f"human capability matrix lacks boundary token: {token}", failures)

    return failures


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    failures = verify(root)
    if failures:
        for failure in failures:
            print(f"FAIL upstream-capabilities: {failure}", file=sys.stderr)
        return 1
    print(
        "PASS upstream-capabilities "
        f"core={len(REQUIRED_CORE_IDS)} official-addons={len(EXPECTED_ADDONS)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
