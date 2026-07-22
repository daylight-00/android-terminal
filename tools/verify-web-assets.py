#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

EXPECTED_PACKAGES = {
    "@xterm/xterm": {
        "version": "6.0.0",
        "url": "https://registry.npmjs.org/@xterm/xterm/-/xterm-6.0.0.tgz",
        "npm_integrity": "sha512-TQwDdQGtwwDt+2cgKDLn0IRaSxYu1tSUjgKarSDkUM0ZNiSRXFpjxEsvc/Zgc5kq5omJ+V0a8/kIM2WD3sMOYg==",
    },
    "@xterm/addon-fit": {
        "version": "0.11.0",
        "url": "https://registry.npmjs.org/@xterm/addon-fit/-/addon-fit-0.11.0.tgz",
        "npm_integrity": "sha512-jYcgT6xtVYhnhgxh3QgYDnnNMYTcf8ElbxxFzX0IZo+vabQqSPAjC3c1wJrKB5E19VwQei89QCiZZP86DCPF7g==",
    },
}
EXPECTED_FILES = {
    "xterm.js",
    "xterm.css",
    "addon-fit.js",
    "LICENSE.xterm.txt",
    "LICENSE.addon-fit.txt",
}
ALLOWED_FILES = EXPECTED_FILES | {"README.md", "ASSET_RECEIPT.json"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify(root: Path) -> tuple[str, list[str]]:
    failures: list[str] = []
    vendor = root / "app/src/main/assets/terminal/vendor"
    if not vendor.is_dir():
        return "missing", ["missing terminal vendor directory"]

    present = {path.name for path in vendor.iterdir() if path.is_file()}
    provisioned_present = present & (EXPECTED_FILES | {"ASSET_RECEIPT.json"})
    if not provisioned_present:
        unexpected = present - {"README.md"}
        if unexpected:
            failures.append(f"unexpected unprovisioned vendor files: {sorted(unexpected)}")
        return "unprovisioned", failures

    missing = (EXPECTED_FILES | {"ASSET_RECEIPT.json"}) - present
    unexpected = present - ALLOWED_FILES
    if missing:
        failures.append(f"partially provisioned vendor assets; missing: {sorted(missing)}")
    if unexpected:
        failures.append(f"unexpected vendor files: {sorted(unexpected)}")
    if failures:
        return "invalid", failures

    receipt_path = vendor / "ASSET_RECEIPT.json"
    try:
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        return "invalid", [f"invalid asset receipt: {error}"]

    if receipt.get("schema_version") != 1:
        failures.append("asset receipt schema_version must be 1")

    package_entries = receipt.get("packages")
    if not isinstance(package_entries, list):
        failures.append("asset receipt packages must be a list")
        package_entries = []
    actual_packages = {}
    for entry in package_entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("name"), str):
            failures.append("invalid package receipt entry")
            continue
        actual_packages[entry["name"]] = entry
    if set(actual_packages) != set(EXPECTED_PACKAGES):
        failures.append("asset receipt package set does not match pinned packages")
    for name, expected in EXPECTED_PACKAGES.items():
        actual = actual_packages.get(name, {})
        for field, value in expected.items():
            if actual.get(field) != value:
                failures.append(f"asset receipt mismatch for {name} {field}")
        if not isinstance(actual.get("archive_sha256"), str) or len(actual.get("archive_sha256", "")) != 64:
            failures.append(f"asset receipt lacks archive SHA-256 for {name}")
        if not isinstance(actual.get("archive_size"), int) or actual.get("archive_size", 0) <= 0:
            failures.append(f"asset receipt lacks archive size for {name}")

    file_entries = receipt.get("files")
    if not isinstance(file_entries, list):
        failures.append("asset receipt files must be a list")
        file_entries = []
    actual_files = {}
    for entry in file_entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
            failures.append("invalid file receipt entry")
            continue
        actual_files[entry["path"]] = entry
    if set(actual_files) != EXPECTED_FILES:
        failures.append("asset receipt file set does not match installed production files")
    for name in EXPECTED_FILES:
        path = vendor / name
        entry = actual_files.get(name, {})
        if not path.is_file():
            continue
        if entry.get("size") != path.stat().st_size:
            failures.append(f"asset size mismatch: {name}")
        if entry.get("sha256") != sha256(path):
            failures.append(f"asset SHA-256 mismatch: {name}")
        package = entry.get("package")
        if package not in {"@xterm/xterm@6.0.0", "@xterm/addon-fit@0.11.0"}:
            failures.append(f"invalid source package in receipt: {name}")
        source_member = entry.get("source_member")
        if not isinstance(source_member, str) or not source_member.startswith("package/"):
            failures.append(f"invalid source member in receipt: {name}")

    return ("provisioned" if not failures else "invalid"), failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", default=".")
    arguments = parser.parse_args()
    state, failures = verify(Path(arguments.root).resolve())
    if failures:
        for failure in failures:
            print(f"FAIL web-assets: {failure}", file=sys.stderr)
        return 1
    print(f"PASS web-assets state={state}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
