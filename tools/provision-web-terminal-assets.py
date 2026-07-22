#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import pathlib
import sys
import tarfile
from dataclasses import dataclass

MAX_ARCHIVE_BYTES = 16 * 1024 * 1024
MAX_MEMBER_BYTES = 12 * 1024 * 1024
MAX_TOTAL_BYTES = 32 * 1024 * 1024


@dataclass(frozen=True)
class Package:
    name: str
    version: str
    archive: pathlib.Path
    url: str
    integrity: str
    members: dict[str, str]


def digest_file(path: pathlib.Path, algorithm: str) -> str:
    digest = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_integrity(path: pathlib.Path, integrity: str) -> None:
    algorithm, separator, encoded = integrity.partition("-")
    if separator != "-" or algorithm != "sha512":
        raise ValueError(f"unsupported integrity value: {integrity}")
    expected = base64.b64decode(encoded, validate=True)
    digest = hashlib.sha512()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.digest() != expected:
        raise ValueError(f"integrity mismatch: {path}")


def safe_members(archive: tarfile.TarFile) -> dict[str, tarfile.TarInfo]:
    selected: dict[str, tarfile.TarInfo] = {}
    total = 0
    for member in archive.getmembers():
        name = member.name
        pure = pathlib.PurePosixPath(name)
        if name in selected:
            raise ValueError(f"duplicate archive member: {name}")
        if pure.is_absolute() or ".." in pure.parts or not pure.parts or pure.parts[0] != "package":
            raise ValueError(f"unsafe archive member: {name}")
        if not (member.isdir() or member.isfile()):
            raise ValueError(f"unsupported archive member type: {name}")
        if member.isfile():
            if member.size < 0 or member.size > MAX_MEMBER_BYTES:
                raise ValueError(f"invalid archive member size: {name}: {member.size}")
            total += member.size
            if total > MAX_TOTAL_BYTES:
                raise ValueError("archive expands beyond the bounded total size")
        selected[name] = member
    return selected


def provision(packages: list[Package], destination: pathlib.Path) -> None:
    if destination.exists():
        raise ValueError(f"destination already exists: {destination}")
    destination.mkdir(parents=True, exist_ok=False)
    receipt_packages: list[dict[str, object]] = []
    receipt_files: list[dict[str, object]] = []

    for package in packages:
        if not package.archive.is_file():
            raise ValueError(f"missing downloaded archive: {package.archive}")
        archive_size = package.archive.stat().st_size
        if archive_size <= 0 or archive_size > MAX_ARCHIVE_BYTES:
            raise ValueError(f"invalid archive size: {package.archive}: {archive_size}")
        verify_integrity(package.archive, package.integrity)

        with tarfile.open(package.archive, mode="r:gz") as archive:
            members = safe_members(archive)
            for source_member, output_name in package.members.items():
                member = members.get(source_member)
                if member is None or not member.isfile():
                    raise ValueError(
                        f"required member missing from {package.name}@{package.version}: {source_member}"
                    )
                source = archive.extractfile(member)
                if source is None:
                    raise ValueError(f"cannot read archive member: {source_member}")
                data = source.read(MAX_MEMBER_BYTES + 1)
                if len(data) != member.size or len(data) > MAX_MEMBER_BYTES:
                    raise ValueError(f"archive member size mismatch: {source_member}")
                output = destination / output_name
                output.write_bytes(data)
                receipt_files.append(
                    {
                        "path": output_name,
                        "package": f"{package.name}@{package.version}",
                        "source_member": source_member,
                        "sha256": hashlib.sha256(data).hexdigest(),
                        "size": len(data),
                    }
                )

        receipt_packages.append(
            {
                "name": package.name,
                "version": package.version,
                "url": package.url,
                "npm_integrity": package.integrity,
                "archive_sha256": digest_file(package.archive, "sha256"),
                "archive_size": archive_size,
            }
        )

    readme = """# Provisioned upstream assets

These files were acquired by `tools/acquire-web-terminal-assets.sh` from the pinned
official npm package URLs. `ASSET_RECEIPT.json` records the package coordinates,
fixed npm SHA-512 integrity, acquired tarball SHA-256/size, and every installed file
SHA-256/size. The application loads these files only from its APK assets.
"""
    (destination / "README.md").write_text(readme, encoding="utf-8")
    receipt = {
        "schema_version": 1,
        "packages": receipt_packages,
        "files": sorted(receipt_files, key=lambda item: str(item["path"])),
    }
    (destination / "ASSET_RECEIPT.json").write_text(
        json.dumps(receipt, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    for path in destination.iterdir():
        if path.is_file():
            os.chmod(path, 0o644)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--xterm-archive", required=True, type=pathlib.Path)
    parser.add_argument("--xterm-url", required=True)
    parser.add_argument("--xterm-integrity", required=True)
    parser.add_argument("--fit-archive", required=True, type=pathlib.Path)
    parser.add_argument("--fit-url", required=True)
    parser.add_argument("--fit-integrity", required=True)
    parser.add_argument("--serialize-archive", required=True, type=pathlib.Path)
    parser.add_argument("--serialize-url", required=True)
    parser.add_argument("--serialize-integrity", required=True)
    parser.add_argument("--destination", required=True, type=pathlib.Path)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    packages = [
        Package(
            name="@xterm/xterm",
            version="6.0.0",
            archive=arguments.xterm_archive,
            url=arguments.xterm_url,
            integrity=arguments.xterm_integrity,
            members={
                "package/lib/xterm.js": "xterm.js",
                "package/css/xterm.css": "xterm.css",
                "package/LICENSE": "LICENSE.xterm.txt",
            },
        ),
        Package(
            name="@xterm/addon-fit",
            version="0.11.0",
            archive=arguments.fit_archive,
            url=arguments.fit_url,
            integrity=arguments.fit_integrity,
            members={
                "package/lib/addon-fit.js": "addon-fit.js",
                "package/LICENSE": "LICENSE.addon-fit.txt",
            },
        ),
        Package(
            name="@xterm/addon-serialize",
            version="0.13.0",
            archive=arguments.serialize_archive,
            url=arguments.serialize_url,
            integrity=arguments.serialize_integrity,
            members={
                "package/lib/addon-serialize.js": "addon-serialize.js",
                "package/LICENSE": "LICENSE.addon-serialize.txt",
            },
        ),
    ]
    try:
        provision(packages, arguments.destination)
    except (OSError, ValueError, tarfile.TarError) as error:
        print(f"asset provisioning failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
