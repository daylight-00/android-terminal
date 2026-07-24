#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

PACKAGE_DEFINITIONS = {
    "@xterm/xterm": {
        "version": "6.0.0",
        "url": "https://registry.npmjs.org/@xterm/xterm/-/xterm-6.0.0.tgz",
        "npm_integrity": "sha512-TQwDdQGtwwDt+2cgKDLn0IRaSxYu1tSUjgKarSDkUM0ZNiSRXFpjxEsvc/Zgc5kq5omJ+V0a8/kIM2WD3sMOYg==",
        "files": {"xterm.js", "xterm.css", "LICENSE.xterm.txt"},
    },
    "@xterm/addon-fit": {
        "version": "0.11.0",
        "url": "https://registry.npmjs.org/@xterm/addon-fit/-/addon-fit-0.11.0.tgz",
        "npm_integrity": "sha512-jYcgT6xtVYhnhgxh3QgYDnnNMYTcf8ElbxxFzX0IZo+vabQqSPAjC3c1wJrKB5E19VwQei89QCiZZP86DCPF7g==",
        "files": {"addon-fit.js", "LICENSE.addon-fit.txt"},
    },
    "@xterm/addon-serialize": {
        "version": "0.13.0",
        "url": "https://registry.npmjs.org/@xterm/addon-serialize/-/addon-serialize-0.13.0.tgz",
        "npm_integrity": "sha512-kGs8o6LWAmN1l2NpMp01/YkpxbmO4UrfWybeGu79Khw5K9+Krp7XhXbBTOTc3GJRRhd6EmILjpR8k5+odY39YQ==",
        "files": {"addon-serialize.js", "PACKAGE.addon-serialize.json"},
        "metadata": {
            "path": "PACKAGE.addon-serialize.json",
            "name": "@xterm/addon-serialize",
            "version": "0.13.0",
            "main": "lib/addon-serialize.js",
            "license": "MIT",
        },
    },
    "@xterm/addon-webgl": {
        "version": "0.19.0",
        "url": "https://registry.npmjs.org/@xterm/addon-webgl/-/addon-webgl-0.19.0.tgz",
        "npm_integrity": "sha512-b3fMOsyLVuCeNJWxolACEUED0vm7qC0cy4wRvf3oURSzDTYVQiGPhTnhWZwIHdvC48Y+oLhvYXnY4XDXPoJo6A==",
        "files": {"addon-webgl.js", "PACKAGE.addon-webgl.json"},
        "metadata": {
            "path": "PACKAGE.addon-webgl.json",
            "name": "@xterm/addon-webgl",
            "version": "0.19.0",
            "main": "lib/addon-webgl.js",
            "license": "MIT",
        },
    },
    "@xterm/addon-web-links": {
        "version": "0.12.0",
        "url": "https://registry.npmjs.org/@xterm/addon-web-links/-/addon-web-links-0.12.0.tgz",
        "npm_integrity": "sha512-4Smom3RPyVp7ZMYOYDoC/9eGJJJqYhnPLGGqJ6wOBfB8VxPViJNSKdgRYb8NpaM6YSelEKbA2SStD7lGyqaobw==",
        "files": {"addon-web-links.js", "PACKAGE.addon-web-links.json"},
        "metadata": {
            "path": "PACKAGE.addon-web-links.json",
            "name": "@xterm/addon-web-links",
            "version": "0.12.0",
            "main": "lib/addon-web-links.js",
            "license": "MIT",
        },
    },
    "@xterm/addon-clipboard": {
        "version": "0.2.0",
        "url": "https://registry.npmjs.org/@xterm/addon-clipboard/-/addon-clipboard-0.2.0.tgz",
        "npm_integrity": None,
        "files": {"addon-clipboard.js", "PACKAGE.addon-clipboard.json"},
        "metadata": {"path": "PACKAGE.addon-clipboard.json", "name": "@xterm/addon-clipboard", "version": "0.2.0", "main": "lib/addon-clipboard.js", "license": "MIT"},
    },
    "@xterm/addon-image": {
        "version": "0.9.0",
        "url": "https://registry.npmjs.org/@xterm/addon-image/-/addon-image-0.9.0.tgz",
        "npm_integrity": None,
        "files": {"addon-image.js", "PACKAGE.addon-image.json"},
        "metadata": {"path": "PACKAGE.addon-image.json", "name": "@xterm/addon-image", "version": "0.9.0", "main": "lib/addon-image.js", "license": "MIT"},
    },
    "@xterm/addon-progress": {
        "version": "0.2.0",
        "url": "https://registry.npmjs.org/@xterm/addon-progress/-/addon-progress-0.2.0.tgz",
        "npm_integrity": None,
        "files": {"addon-progress.js", "PACKAGE.addon-progress.json"},
        "metadata": {"path": "PACKAGE.addon-progress.json", "name": "@xterm/addon-progress", "version": "0.2.0", "main": "lib/addon-progress.js", "license": "MIT"},
    },
    "@xterm/addon-search": {
        "version": "0.16.0",
        "url": "https://registry.npmjs.org/@xterm/addon-search/-/addon-search-0.16.0.tgz",
        "npm_integrity": None,
        "files": {"addon-search.js", "PACKAGE.addon-search.json"},
        "metadata": {"path": "PACKAGE.addon-search.json", "name": "@xterm/addon-search", "version": "0.16.0", "main": "lib/addon-search.js", "license": "MIT"},
    },
    "@xterm/addon-unicode11": {
        "version": "0.9.0",
        "url": "https://registry.npmjs.org/@xterm/addon-unicode11/-/addon-unicode11-0.9.0.tgz",
        "npm_integrity": None,
        "files": {"addon-unicode11.js", "PACKAGE.addon-unicode11.json"},
        "metadata": {"path": "PACKAGE.addon-unicode11.json", "name": "@xterm/addon-unicode11", "version": "0.9.0", "main": "lib/addon-unicode11.js", "license": "MIT"},
    },
    "@xterm/addon-web-fonts": {
        "version": "0.1.0",
        "url": "https://registry.npmjs.org/@xterm/addon-web-fonts/-/addon-web-fonts-0.1.0.tgz",
        "npm_integrity": None,
        "files": {"addon-web-fonts.js", "PACKAGE.addon-web-fonts.json"},
        "metadata": {"path": "PACKAGE.addon-web-fonts.json", "name": "@xterm/addon-web-fonts", "version": "0.1.0", "main": "lib/addon-web-fonts.js", "license": "MIT"},
    },
    "@xterm/addon-ligatures": {
        "version": "0.10.0",
        "url": "https://registry.npmjs.org/@xterm/addon-ligatures/-/addon-ligatures-0.10.0.tgz",
        "npm_integrity": None,
        "files": {"addon-ligatures.mjs", "PACKAGE.addon-ligatures.json"},
        "metadata": {"path": "PACKAGE.addon-ligatures.json", "name": "@xterm/addon-ligatures", "version": "0.10.0", "module": "lib/addon-ligatures.mjs", "license": "MIT"},
    },

}

RECOGNIZED_GENERATIONS = (
    ("provisioned", frozenset(PACKAGE_DEFINITIONS)),
    ("stale-provisioned", frozenset({"@xterm/xterm", "@xterm/addon-fit", "@xterm/addon-serialize", "@xterm/addon-webgl", "@xterm/addon-web-links"})),
    ("stale-provisioned", frozenset({"@xterm/xterm", "@xterm/addon-fit", "@xterm/addon-serialize", "@xterm/addon-webgl"})),
    ("stale-provisioned", frozenset({"@xterm/xterm", "@xterm/addon-fit", "@xterm/addon-serialize"})),
    ("stale-provisioned", frozenset({"@xterm/xterm", "@xterm/addon-fit"})),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def expected_files(package_names: frozenset[str]) -> set[str]:
    files: set[str] = set()
    for name in package_names:
        files.update(PACKAGE_DEFINITIONS[name]["files"])
    return files


def generation_for(package_names: set[str]) -> tuple[str, frozenset[str]] | None:
    frozen = frozenset(package_names)
    for state, recognized in RECOGNIZED_GENERATIONS:
        if frozen == recognized:
            return state, recognized
    return None


def verify_metadata(vendor: Path, package_names: frozenset[str], failures: list[str]) -> None:
    for package_name in package_names:
        metadata_definition = PACKAGE_DEFINITIONS[package_name].get("metadata")
        if not isinstance(metadata_definition, dict):
            continue
        metadata_path = vendor / str(metadata_definition["path"])
        try:
            metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            failures.append(f"invalid {package_name} package metadata: {error}")
            continue
        if not isinstance(metadata, dict):
            failures.append(f"{package_name} package metadata must be an object")
            continue
        for field, expected_value in metadata_definition.items():
            if field == "path":
                continue
            if metadata.get(field) != expected_value:
                failures.append(f"{package_name} package metadata mismatch: {field}")


def verify(root: Path) -> tuple[str, list[str]]:
    failures: list[str] = []
    vendor = root / "app/src/main/assets/terminal/vendor"
    if not vendor.is_dir():
        return "missing", ["missing terminal vendor directory"]

    present = {path.name for path in vendor.iterdir() if path.is_file()}
    receipt_path = vendor / "ASSET_RECEIPT.json"
    if not receipt_path.is_file():
        unexpected = present - {"README.md"}
        if unexpected:
            failures.append(f"unexpected unprovisioned vendor files: {sorted(unexpected)}")
        return "unprovisioned", failures

    try:
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        return "invalid", [f"invalid asset receipt: {error}"]

    package_entries = receipt.get("packages")
    if not isinstance(package_entries, list):
        return "invalid", ["asset receipt packages must be a list"]
    actual_packages: dict[str, dict[str, object]] = {}
    for entry in package_entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("name"), str):
            failures.append("invalid package receipt entry")
            continue
        name = str(entry["name"])
        if name in actual_packages:
            failures.append(f"duplicate package receipt entry: {name}")
            continue
        actual_packages[name] = entry

    generation = generation_for(set(actual_packages))
    if generation is None:
        return "invalid", ["asset receipt package set does not match a recognized pinned package generation"]
    state, package_names = generation
    files = expected_files(package_names)
    allowed_files = files | {"README.md", "ASSET_RECEIPT.json"}
    missing = (files | {"ASSET_RECEIPT.json"}) - present
    unexpected = present - allowed_files
    if missing:
        failures.append(f"partially provisioned vendor assets; missing: {sorted(missing)}")
    if unexpected:
        failures.append(f"unexpected vendor files: {sorted(unexpected)}")
    if receipt.get("schema_version") != 1:
        failures.append("asset receipt schema_version must be 1")

    for name in package_names:
        expected = PACKAGE_DEFINITIONS[name]
        actual = actual_packages.get(name, {})
        for field in ("version", "url"):
            if actual.get(field) != expected[field]:
                failures.append(f"asset receipt mismatch for {name} {field}")
        expected_integrity = expected["npm_integrity"]
        actual_integrity = actual.get("npm_integrity")
        if expected_integrity is None:
            if not isinstance(actual_integrity, str) or not actual_integrity.startswith("sha512-"):
                failures.append(f"asset receipt lacks registry SHA-512 integrity for {name}")
        elif actual_integrity != expected_integrity:
            failures.append(f"asset receipt mismatch for {name} npm_integrity")
        if not isinstance(actual.get("archive_sha256"), str) or len(str(actual.get("archive_sha256", ""))) != 64:
            failures.append(f"asset receipt lacks archive SHA-256 for {name}")
        if not isinstance(actual.get("archive_size"), int) or int(actual.get("archive_size", 0)) <= 0:
            failures.append(f"asset receipt lacks archive size for {name}")

    file_entries = receipt.get("files")
    if not isinstance(file_entries, list):
        failures.append("asset receipt files must be a list")
        file_entries = []
    actual_files: dict[str, dict[str, object]] = {}
    for entry in file_entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
            failures.append("invalid file receipt entry")
            continue
        path_name = str(entry["path"])
        if path_name in actual_files:
            failures.append(f"duplicate file receipt entry: {path_name}")
            continue
        actual_files[path_name] = entry
    if set(actual_files) != files:
        failures.append("asset receipt file set does not match installed production files")
    valid_source_packages = {
        f"{name}@{PACKAGE_DEFINITIONS[name]['version']}" for name in package_names
    }
    for name in files:
        path = vendor / name
        entry = actual_files.get(name, {})
        if not path.is_file():
            continue
        if entry.get("size") != path.stat().st_size:
            failures.append(f"asset size mismatch: {name}")
        if entry.get("sha256") != sha256(path):
            failures.append(f"asset SHA-256 mismatch: {name}")
        if entry.get("package") not in valid_source_packages:
            failures.append(f"invalid source package in receipt: {name}")
        source_member = entry.get("source_member")
        if not isinstance(source_member, str) or not source_member.startswith("package/"):
            failures.append(f"invalid source member in receipt: {name}")

    verify_metadata(vendor, package_names, failures)
    return (state if not failures else "invalid"), failures


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
