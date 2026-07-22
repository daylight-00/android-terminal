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

xterm = root / "xterm.tgz"
fit = root / "fit.tgz"
serialize = root / "serialize.tgz"
make(xterm, {
    "package/lib/xterm.js": b"xterm-js",
    "package/css/xterm.css": b"xterm-css",
    "package/LICENSE": b"MIT xterm",
})
make(fit, {
    "package/lib/addon-fit.js": b"fit-js",
    "package/LICENSE": b"MIT fit",
})
make(serialize, {
    "package/lib/addon-serialize.js": b"serialize-js",
    "package/LICENSE": b"MIT serialize",
})
(root / "integrities").write_text(
    integrity(xterm) + "\n" + integrity(fit) + "\n" + integrity(serialize) + "\n"
)

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
python3 "$ROOT/tools/provision-web-terminal-assets.py" \
  --xterm-archive "$TMP/xterm.tgz" \
  --xterm-url 'https://example.invalid/xterm.tgz' \
  --xterm-integrity "${INTEGRITIES[0]}" \
  --fit-archive "$TMP/fit.tgz" \
  --fit-url 'https://example.invalid/fit.tgz' \
  --fit-integrity "${INTEGRITIES[1]}" \
  --serialize-archive "$TMP/serialize.tgz" \
  --serialize-url 'https://example.invalid/serialize.tgz' \
  --serialize-integrity "${INTEGRITIES[2]}" \
  --destination "$TMP/output"

test -s "$TMP/output/xterm.js"
test -s "$TMP/output/xterm.css"
test -s "$TMP/output/addon-fit.js"
test -s "$TMP/output/addon-serialize.js"
test -s "$TMP/output/ASSET_RECEIPT.json"
printf 'PASS asset-provisioner-success\n'

cp -a "$TMP/output" "$TMP/legacy-output"
rm -f "$TMP/legacy-output/addon-serialize.js" "$TMP/legacy-output/LICENSE.addon-serialize.txt"
python3 - "$TMP/legacy-output/ASSET_RECEIPT.json" <<'PYLEGACY'
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
}
receipt["packages"] = [entry for entry in receipt["packages"] if entry["name"] in expected]
for entry in receipt["packages"]:
    entry["url"], entry["npm_integrity"] = expected[entry["name"]]
receipt["files"] = [entry for entry in receipt["files"] if entry["package"] != "@xterm/addon-serialize@0.13.0"]
path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
PYLEGACY
python3 "$ROOT/tools/verify-web-assets.py" "$(dirname -- "$TMP/legacy-output")" >/dev/null 2>&1 && {
  printf 'FAIL asset-generation fixture used wrong root\n' >&2
  exit 1
} || true
LEGACY_ROOT="$TMP/legacy-root"
mkdir -p "$LEGACY_ROOT/app/src/main/assets/terminal"
mv "$TMP/legacy-output" "$LEGACY_ROOT/app/src/main/assets/terminal/vendor"
python3 "$ROOT/tools/verify-web-assets.py" "$LEGACY_ROOT" | grep -Fq 'state=stale-provisioned'
printf 'PASS asset-provisioner-legacy-generation\n'

UNSAFE_INTEGRITY=$(cat "$TMP/unsafe-integrity")
if python3 "$ROOT/tools/provision-web-terminal-assets.py" \
  --xterm-archive "$TMP/unsafe.tgz" \
  --xterm-url 'https://example.invalid/unsafe.tgz' \
  --xterm-integrity "$UNSAFE_INTEGRITY" \
  --fit-archive "$TMP/fit.tgz" \
  --fit-url 'https://example.invalid/fit.tgz' \
  --fit-integrity "${INTEGRITIES[1]}" \
  --serialize-archive "$TMP/serialize.tgz" \
  --serialize-url 'https://example.invalid/serialize.tgz' \
  --serialize-integrity "${INTEGRITIES[2]}" \
  --destination "$TMP/unsafe-output" >/dev/null 2>&1; then
  printf 'FAIL asset-provisioner-unsafe unexpectedly passed\n' >&2
  exit 1
fi
printf 'PASS asset-provisioner-unsafe\n'
