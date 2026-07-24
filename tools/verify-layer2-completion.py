#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

EXPECTED_PINS = {
    "@xterm/xterm": "6.0.0",
    "@xterm/addon-clipboard": "0.2.0",
    "@xterm/addon-fit": "0.11.0",
    "@xterm/addon-image": "0.9.0",
    "@xterm/addon-ligatures": "0.10.0",
    "@xterm/addon-progress": "0.2.0",
    "@xterm/addon-search": "0.16.0",
    "@xterm/addon-serialize": "0.13.0",
    "@xterm/addon-unicode11": "0.9.0",
    "@xterm/addon-web-fonts": "0.1.0",
    "@xterm/addon-web-links": "0.12.0",
    "@xterm/addon-webgl": "0.19.0",
}
AUTOMATIC = {
    "@xterm/addon-clipboard@0.2.0",
    "@xterm/addon-fit@0.11.0",
    "@xterm/addon-image@0.9.0",
    "@xterm/addon-progress@0.2.0",
    "@xterm/addon-serialize@0.13.0",
    "@xterm/addon-web-links@0.12.0",
    "@xterm/addon-webgl@0.19.0",
}
REGISTERED = {
    "@xterm/addon-ligatures@0.10.0",
    "@xterm/addon-search@0.16.0",
    "@xterm/addon-unicode11@0.9.0",
    "@xterm/addon-web-fonts@0.1.0",
}
EXCLUDED = {"@xterm/addon-attach", "@xterm/addon-unicode-graphemes"}


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as error:
        raise ValueError(f"cannot read {path}: {error}") from error


def load_json(path: Path) -> object:
    try:
        return json.loads(read(path))
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid JSON {path}: {error}") from error


def verify(root: Path) -> list[str]:
    failures: list[str] = []
    try:
        completion = load_json(root / "docs/layer2-completion.json")
        receipt = load_json(root / "app/src/main/assets/terminal/vendor/ASSET_RECEIPT.json")
        inventory = load_json(root / "docs/upstream-capabilities.json")
        bridge = read(root / "app/src/main/assets/terminal/bridge/terminal-bridge.js")
        contract_js = read(root / "app/src/main/assets/terminal/bridge/terminal-contract.js")
        contract_kt = read(root / "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt")
        customization_js = read(root / "app/src/main/assets/terminal/customization/customization.js")
        customization_kt = read(root / "app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalCustomization.kt")
        web_client = read(root / "app/src/main/kotlin/io/github/daylight00/androidterminal/LocalAssetWebViewClient.kt")
        main_activity = read(root / "app/src/main/kotlin/io/github/daylight00/androidterminal/MainActivity.kt")
        image_addon = read(root / "app/src/main/assets/terminal/vendor/addon-image.js")
        gradle = read(root / "app/build.gradle")
        device_doc = read(root / "docs/device-validation.md")
    except ValueError as error:
        return [str(error)]

    if not isinstance(completion, dict) or completion.get("schema_version") != 1:
        failures.append("completion authority schema_version must be 1")
        completion = {}
    if completion.get("status") != "repository-complete-device-validation-pending":
        failures.append("completion status must preserve the real-device gate")
    if completion.get("repository_gate") != "complete" or completion.get("device_gate") != "pending":
        failures.append("repository/device completion gates are invalid")
    runtime = completion.get("runtime_contract") if isinstance(completion.get("runtime_contract"), dict) else {}
    if runtime != {
        "wire_protocol": 6,
        "layer2_extension": 4,
        "layer3_scaffold": 2,
        "page_capability": "layer2-completion-v1",
    }:
        failures.append("runtime contract authority mismatch")

    account = completion.get("account_session") if isinstance(completion.get("account_session"), dict) else {}
    if account.get("status") != "repository-complete-device-validation-pending":
        failures.append("native account/session completion gate is invalid")
    if account.get("shell") != "/system/bin/sh" or account.get("argv0") != "-sh":
        failures.append("native login-shell contract mismatch")
    if account.get("working_directory") != "HOME":
        failures.append("native account working directory must be HOME")
    if account.get("home") != "Context.getFilesDir()" or account.get("tmpdir") != "Context.getCacheDir()/tmp":
        failures.append("native account directory mapping mismatch")
    environment = account.get("environment") if isinstance(account.get("environment"), dict) else {}
    if environment.get("inherited") != "Android application process environment":
        failures.append("native account environment authority mismatch")
    if environment.get("overrides") != ["HOME", "TMPDIR", "TERM"] or environment.get("synthesized") != []:
        failures.append("native account environment override set mismatch")
    if account.get("home_initialization") != "none":
        failures.append("native account HOME must remain unpopulated")
    storage = account.get("shared_storage") if isinstance(account.get("shared_storage"), dict) else {}
    if storage.get("permission_request") != "startup Android system flow":
        failures.append("shared-storage startup permission policy mismatch")
    if storage.get("home_link") != "none" or storage.get("child_environment_synthesis") != "none":
        failures.append("shared storage must not alter HOME or child environment")
    saf = account.get("saf") if isinstance(account.get("saf"), dict) else {}
    if saf != {
        "mode": "explicit Android document import/export",
        "import_destination": "caller-selected HOME-relative directory; empty means HOME root",
        "fixed_home_inbox": "none",
        "collision_policy": "preserve existing files with a unique provider-derived name",
        "virtual_mount": "none",
    }:
        failures.append("SAF destination policy mismatch")

    upstream = completion.get("upstream") if isinstance(completion.get("upstream"), dict) else {}
    if upstream.get("core") != "@xterm/xterm@6.0.0":
        failures.append("completion authority core pin mismatch")
    if set(upstream.get("automatic_addons", [])) != AUTOMATIC:
        failures.append("completion automatic addon set mismatch")
    if set(upstream.get("registered_addons", [])) != REGISTERED:
        failures.append("completion registered addon set mismatch")
    excluded = upstream.get("excluded_addons")
    if not isinstance(excluded, dict) or set(excluded) != EXCLUDED:
        failures.append("completion excluded addon set mismatch")

    packages = receipt.get("packages") if isinstance(receipt, dict) else None
    actual_pins: dict[str, str] = {}
    if not isinstance(packages, list):
        failures.append("asset receipt packages must be a list")
    else:
        for row in packages:
            if not isinstance(row, dict):
                failures.append("asset receipt package row must be an object")
                continue
            name, version = row.get("name"), row.get("version")
            if not isinstance(name, str) or not isinstance(version, str):
                failures.append("asset receipt package identity is incomplete")
                continue
            if name in actual_pins:
                failures.append(f"duplicate asset receipt package: {name}")
            actual_pins[name] = version
            integrity = row.get("npm_integrity")
            if not isinstance(integrity, str) or not re.fullmatch(r"sha512-[A-Za-z0-9+/]+={0,2}", integrity):
                failures.append(f"invalid asset receipt integrity: {name}")
    if actual_pins != EXPECTED_PINS:
        failures.append(f"asset receipt pin set mismatch: {actual_pins!r}")

    addon_rows = inventory.get("official_addons") if isinstance(inventory, dict) else None
    classifications: dict[str, str] = {}
    if isinstance(addon_rows, list):
        for row in addon_rows:
            if isinstance(row, dict) and isinstance(row.get("package"), str):
                classifications[row["package"]] = str(row.get("classification"))
    else:
        failures.append("upstream addon inventory is unavailable")
    for name in EXPECTED_PINS:
        if name == "@xterm/xterm":
            continue
        if name not in classifications:
            failures.append(f"provisioned addon missing from inventory: {name}")
    for name in EXCLUDED:
        if name not in classifications:
            failures.append(f"excluded addon missing from inventory: {name}")

    required_bridge_tokens = (
        "status: 'repository-complete-device-validation-pending'",
        "core: '@xterm/xterm@6.0.0'",
        "automaticAddons: Object.freeze([",
        "registeredAddons: Object.freeze([",
        "excludedAddons: Object.freeze([",
        "webassembly-compilation-for-image-addon",
        "const completion = Object.freeze({",
        "snapshot() {",
        "completion,",
        "contractVersion: 4",
    )
    for token in required_bridge_tokens:
        if token not in bridge:
            failures.append(f"Layer 2 completion surface lacks token: {token}")
    for coordinate in sorted(AUTOMATIC | REGISTERED):
        if f"'{coordinate}'" not in bridge:
            failures.append(f"runtime completion manifest lacks coordinate: {coordinate}")
    for name in sorted(EXCLUDED):
        if f"'{name}'" not in bridge:
            failures.append(f"runtime completion manifest lacks exclusion: {name}")

    if "'layer2-completion-v1'" not in contract_js or '"layer2-completion-v1"' not in contract_kt:
        failures.append("Layer 2 completion page capability must match JavaScript and Kotlin")
    if "'native-account-session-v1'" not in contract_js or '"native-account-session-v1"' not in contract_kt:
        failures.append("native account/session page capability must match JavaScript and Kotlin")
    if "'android-native-account-session'" not in contract_js or '"android-native-account-session"' not in contract_kt:
        failures.append("native account/session host capability must match JavaScript and Kotlin")
    if "layer2.contractVersion !== 4" not in customization_js:
        failures.append("Layer 3 does not bind Layer 2 extension contract 4")
    if "layer2.completion.manifest.schemaVersion !== 1" not in customization_js:
        failures.append("Layer 3 does not bind the completion manifest schema")
    if "contractVersion: 2" not in customization_js or "CONTRACT_VERSION = 2" not in customization_kt:
        failures.append("Layer 3 scaffold contract 2 is incomplete")

    expected_csp = "script-src 'self' 'wasm-unsafe-eval';"
    if expected_csp not in web_client:
        failures.append("WebView CSP does not permit official ImageAddon WebAssembly")
    if "script-src 'self' 'unsafe-eval';" in web_client:
        failures.append("WebView CSP must not permit JavaScript unsafe-eval")
    if "WebAssembly" not in image_addon or "WebAssembly.instantiate" not in image_addon:
        failures.append("pinned ImageAddon no longer contains the expected WebAssembly runtime")
    if "BuildConfig.DEBUG" not in main_activity or "WebView.setWebContentsDebuggingEnabled(true)" not in main_activity:
        failures.append("debug-only WebView device evidence surface is missing")

    for token in ("versionCode 24", "versionName '0.23.3'", "minSdk 29", "targetSdk 28"):
        if token not in gradle:
            failures.append(f"closure version/policy mismatch: {token}")
    for token in (
        "AndroidTerminalLayer2.completion.manifest",
        "AndroidTerminalLayer2.completion.snapshot()",
        "OSC 52",
        "inline image",
        "wasm-unsafe-eval",
        'argv0=<%s>',
        "destinationDirectory: 'incoming'",
        'must never create `HOME/imports`',
    ):
        if token not in device_doc:
            failures.append(f"device validation document lacks token: {token}")

    return failures


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    failures = verify(root)
    if failures:
        for failure in failures:
            print(f"FAIL layer2-completion: {failure}", file=sys.stderr)
        return 1
    print(
        "PASS layer2-completion "
        "status=repository-complete-device-validation-pending "
        f"pins={len(EXPECTED_PINS)} automatic={len(AUTOMATIC)} registered={len(REGISTERED)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
