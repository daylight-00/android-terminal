#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/android-terminal-provisioner.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT

python3 - "$TMP" <<'PY'
from __future__ import annotations
import base64
import hashlib
import io
import pathlib
import tarfile
import sys

root = pathlib.Path(sys.argv[1])

def make(path: pathlib.Path, files: dict[str, bytes], extra=None):
    with tarfile.open(path, "w:gz") as archive:
        for name, data in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(data))
        if extra is not None:
            archive.addfile(extra)

def integrity(path: pathlib.Path) -> str:
    return "sha512-" + base64.b64encode(hashlib.sha512(path.read_bytes()).digest()).decode()

archives = {
    "xterm": {
        "package/lib/xterm.js": b"xterm-js",
        "package/css/xterm.css": b"xterm-css",
        "package/LICENSE": b"MIT xterm",
    },
    "fit": {
        "package/lib/addon-fit.js": b"fit-js",
        "package/LICENSE": b"MIT fit",
    },
    "serialize": {
        "package/lib/addon-serialize.js": b"serialize-js",
        "package/package.json": (
            b'{"name":"@xterm/addon-serialize","version":"0.13.0",'
            b'"main":"lib/addon-serialize.js","license":"MIT"}'
        ),
    },
    "webgl": {
        "package/lib/addon-webgl.js": b"webgl-js",
        "package/package.json": (
            b'{"name":"@xterm/addon-webgl","version":"0.19.0",'
            b'"main":"lib/addon-webgl.js","license":"MIT"}'
        ),
    },
    "web-links": {
        "package/lib/addon-web-links.js": b"web-links-js",
        "package/package.json": (
            b'{"name":"@xterm/addon-web-links","version":"0.12.0",'
            b'"main":"lib/addon-web-links.js","license":"MIT"}'
        ),
    },
}
values = []
for name, files in archives.items():
    path = root / f"{name}.tgz"
    make(path, files)
    values.append(integrity(path))
(root / "integrities").write_text("\n".join(values) + "\n")

unsafe = root / "unsafe.tgz"
link = tarfile.TarInfo("package/lib/xterm.js")
link.type = tarfile.SYMTYPE
link.linkname = "/etc/passwd"
make(unsafe, {
    "package/css/xterm.css": b"xterm-css",
    "package/LICENSE": b"MIT xterm",
}, extra=link)
(root / "unsafe-integrity").write_text(integrity(unsafe) + "\n")
PY

mapfile -t INTEGRITIES < "$TMP/integrities"
provision() {
  local xterm_archive=$1
  local xterm_integrity=$2
  local destination=$3
  python3 "$ROOT/tools/provision-web-terminal-assets.py" \
    --xterm-archive "$xterm_archive" \
    --xterm-url 'https://example.invalid/xterm.tgz' \
    --xterm-integrity "$xterm_integrity" \
    --fit-archive "$TMP/fit.tgz" \
    --fit-url 'https://example.invalid/fit.tgz' \
    --fit-integrity "${INTEGRITIES[1]}" \
    --serialize-archive "$TMP/serialize.tgz" \
    --serialize-url 'https://example.invalid/serialize.tgz' \
    --serialize-integrity "${INTEGRITIES[2]}" \
    --webgl-archive "$TMP/webgl.tgz" \
    --webgl-url 'https://example.invalid/webgl.tgz' \
    --webgl-integrity "${INTEGRITIES[3]}" \
    --web-links-archive "$TMP/web-links.tgz" \
    --web-links-url 'https://example.invalid/web-links.tgz' \
    --web-links-integrity "${INTEGRITIES[4]}" \
    --destination "$destination"
}

provision "$TMP/xterm.tgz" "${INTEGRITIES[0]}" "$TMP/output"
for file in \
  xterm.js xterm.css addon-fit.js addon-serialize.js addon-webgl.js addon-web-links.js \
  LICENSE.xterm.txt LICENSE.addon-fit.txt \
  PACKAGE.addon-serialize.json PACKAGE.addon-webgl.json PACKAGE.addon-web-links.json ASSET_RECEIPT.json; do
  test -s "$TMP/output/$file"
done
test ! -e "$TMP/output/LICENSE.addon-serialize.txt"
test ! -e "$TMP/output/LICENSE.addon-webgl.txt"
printf 'PASS asset-provisioner-success\n'

# Convert a current receipt into the immediate previous generation (all current assets except web-links).
PREVIOUS_ROOT="$TMP/previous-root"
mkdir -p "$PREVIOUS_ROOT/app/src/main/assets/terminal"
cp -a "$TMP/output" "$PREVIOUS_ROOT/app/src/main/assets/terminal/vendor"
rm -f \
  "$PREVIOUS_ROOT/app/src/main/assets/terminal/vendor/addon-web-links.js" \
  "$PREVIOUS_ROOT/app/src/main/assets/terminal/vendor/PACKAGE.addon-web-links.json"
python3 - "$PREVIOUS_ROOT/app/src/main/assets/terminal/vendor/ASSET_RECEIPT.json" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
receipt = json.loads(path.read_text())
expected = {
    "@xterm/xterm": (
        "https://registry.npmjs.org/@xterm/xterm/-/xterm-6.0.0.tgz",
        "sha512-TQwDdQGtwwDt+2cgKDLn0IRaSxYu1tSUjgKarSDkUM0ZNiSRXFpjxEsvc/Zgc5kq5omJ+V0a8/kIM2WD3sMOYg==",
    ),
    "@xterm/addon-fit": (
        "https://registry.npmjs.org/@xterm/addon-fit/-/addon-fit-0.11.0.tgz",
        "sha512-jYcgT6xtVYhnhgxh3QgYDnnNMYTcf8ElbxxFzX0IZo+vabQqSPAjC3c1wJrKB5E19VwQei89QCiZZP86DCPF7g==",
    ),
    "@xterm/addon-serialize": (
        "https://registry.npmjs.org/@xterm/addon-serialize/-/addon-serialize-0.13.0.tgz",
        "sha512-kGs8o6LWAmN1l2NpMp01/YkpxbmO4UrfWybeGu79Khw5K9+Krp7XhXbBTOTc3GJRRhd6EmILjpR8k5+odY39YQ==",
    ),
    "@xterm/addon-webgl": (
        "https://registry.npmjs.org/@xterm/addon-webgl/-/addon-webgl-0.19.0.tgz",
        "sha512-b3fMOsyLVuCeNJWxolACEUED0vm7qC0cy4wRvf3oURSzDTYVQiGPhTnhWZwIHdvC48Y+oLhvYXnY4XDXPoJo6A==",
    ),
}
receipt["packages"] = [entry for entry in receipt["packages"] if entry["name"] in expected]
for entry in receipt["packages"]:
    entry["url"], entry["npm_integrity"] = expected[entry["name"]]
receipt["files"] = [entry for entry in receipt["files"] if entry["package"] != "@xterm/addon-web-links@0.12.0"]
path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
PY
python3 "$ROOT/tools/verify-web-assets.py" "$PREVIOUS_ROOT" | grep -Fq 'state=stale-provisioned'
printf 'PASS asset-provisioner-previous-generation\n'

UNSAFE_INTEGRITY=$(cat "$TMP/unsafe-integrity")
if provision "$TMP/unsafe.tgz" "$UNSAFE_INTEGRITY" "$TMP/unsafe-output" >/dev/null 2>&1; then
  printf 'FAIL asset-provisioner-unsafe unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS asset-provisioner-unsafe\n'
