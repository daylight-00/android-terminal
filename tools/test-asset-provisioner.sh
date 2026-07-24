#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/android-terminal-provisioner.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT

python3 - "$TMP" <<'PY'
from __future__ import annotations
import base64, hashlib, io, json, pathlib, tarfile, sys
root=pathlib.Path(sys.argv[1])
packages={
'xterm':('@xterm/xterm','6.0.0','lib/xterm.js', {'package/lib/xterm.js':b'xterm-js','package/css/xterm.css':b'xterm-css','package/LICENSE':b'MIT xterm'}),
'fit':('@xterm/addon-fit','0.11.0','lib/addon-fit.js', {'package/lib/addon-fit.js':b'fit-js','package/LICENSE':b'MIT fit'}),
'serialize':('@xterm/addon-serialize','0.13.0','lib/addon-serialize.js', {}),
'webgl':('@xterm/addon-webgl','0.19.0','lib/addon-webgl.js', {}),
'web-links':('@xterm/addon-web-links','0.12.0','lib/addon-web-links.js', {}),
'clipboard':('@xterm/addon-clipboard','0.2.0','lib/addon-clipboard.js', {}),
'image':('@xterm/addon-image','0.9.0','lib/addon-image.js', {}),
'progress':('@xterm/addon-progress','0.2.0','lib/addon-progress.js', {}),
'search':('@xterm/addon-search','0.16.0','lib/addon-search.js', {}),
'unicode11':('@xterm/addon-unicode11','0.9.0','lib/addon-unicode11.js', {}),
'web-fonts':('@xterm/addon-web-fonts','0.1.0','lib/addon-web-fonts.js', {}),
'ligatures':('@xterm/addon-ligatures','0.10.0','lib/addon-ligatures.mjs', {}),
}
values={}
for key,(name,version,main,files) in packages.items():
    if key not in ('xterm','fit'):
        entry_field = 'module' if key == 'ligatures' else 'main'
        files={f'package/{main}': f'{key}-js'.encode(), 'package/package.json': json.dumps({'name':name,'version':version,entry_field:main,'license':'MIT'}).encode()}
    path=root/f'{key}.tgz'
    with tarfile.open(path,'w:gz') as t:
        for member,data in files.items():
            info=tarfile.TarInfo(member); info.size=len(data); info.mode=0o644; t.addfile(info,io.BytesIO(data))
    values[key]='sha512-'+base64.b64encode(hashlib.sha512(path.read_bytes()).digest()).decode()
# Old CommonJS ligatures layout must be rejected; 0.10.0 is ESM-only.
old_path=root/'ligatures-old.tgz'
old_main='lib/addon-ligatures.js'
old_files={f'package/{old_main}': b'old-ligatures-js', 'package/package.json': json.dumps({'name':'@xterm/addon-ligatures','version':'0.10.0','main':old_main,'license':'MIT'}).encode()}
with tarfile.open(old_path,'w:gz') as t:
    for member,data in old_files.items():
        info=tarfile.TarInfo(member); info.size=len(data); info.mode=0o644; t.addfile(info,io.BytesIO(data))
values['ligatures-old']='sha512-'+base64.b64encode(hashlib.sha512(old_path.read_bytes()).digest()).decode()
(root/'integrities.json').write_text(json.dumps(values))
# Unsafe symlink archive for xterm.
path=root/'unsafe.tgz'
with tarfile.open(path,'w:gz') as t:
    link=tarfile.TarInfo('package/lib/xterm.js'); link.type=tarfile.SYMTYPE; link.linkname='/etc/passwd'; t.addfile(link)
    for member,data in {'package/css/xterm.css':b'css','package/LICENSE':b'MIT'}.items():
        info=tarfile.TarInfo(member); info.size=len(data); t.addfile(info,io.BytesIO(data))
(root/'unsafe-integrity').write_text('sha512-'+base64.b64encode(hashlib.sha512(path.read_bytes()).digest()).decode())
PY

integrity() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$TMP/integrities.json" "$1"; }
provision() {
  local xterm_archive=$1 xterm_integrity=$2 destination=$3
  local ligatures_archive=${4:-"$TMP/ligatures.tgz"}
  local ligatures_integrity=${5:-"$(integrity ligatures)"}
  python3 "$ROOT/tools/provision-web-terminal-assets.py" \
    --xterm-archive "$xterm_archive" --xterm-url 'https://example.invalid/xterm.tgz' --xterm-integrity "$xterm_integrity" \
    --fit-archive "$TMP/fit.tgz" --fit-url 'https://example.invalid/fit.tgz' --fit-integrity "$(integrity fit)" \
    --serialize-archive "$TMP/serialize.tgz" --serialize-url 'https://example.invalid/serialize.tgz' --serialize-integrity "$(integrity serialize)" \
    --webgl-archive "$TMP/webgl.tgz" --webgl-url 'https://example.invalid/webgl.tgz' --webgl-integrity "$(integrity webgl)" \
    --web-links-archive "$TMP/web-links.tgz" --web-links-url 'https://example.invalid/web-links.tgz' --web-links-integrity "$(integrity web-links)" \
    --clipboard-archive "$TMP/clipboard.tgz" --clipboard-url 'https://example.invalid/clipboard.tgz' --clipboard-integrity "$(integrity clipboard)" \
    --image-archive "$TMP/image.tgz" --image-url 'https://example.invalid/image.tgz' --image-integrity "$(integrity image)" \
    --progress-archive "$TMP/progress.tgz" --progress-url 'https://example.invalid/progress.tgz' --progress-integrity "$(integrity progress)" \
    --search-archive "$TMP/search.tgz" --search-url 'https://example.invalid/search.tgz' --search-integrity "$(integrity search)" \
    --unicode11-archive "$TMP/unicode11.tgz" --unicode11-url 'https://example.invalid/unicode11.tgz' --unicode11-integrity "$(integrity unicode11)" \
    --web-fonts-archive "$TMP/web-fonts.tgz" --web-fonts-url 'https://example.invalid/web-fonts.tgz' --web-fonts-integrity "$(integrity web-fonts)" \
    --ligatures-archive "$ligatures_archive" --ligatures-url 'https://example.invalid/ligatures.tgz' --ligatures-integrity "$ligatures_integrity" \
    --destination "$destination"
}

provision "$TMP/xterm.tgz" "$(integrity xterm)" "$TMP/output"
for file in xterm.js xterm.css LICENSE.xterm.txt LICENSE.addon-fit.txt \
  addon-fit.js addon-serialize.js addon-webgl.js addon-web-links.js addon-clipboard.js addon-image.js \
  addon-progress.js addon-search.js addon-unicode11.js addon-web-fonts.js addon-ligatures.mjs \
  PACKAGE.addon-serialize.json PACKAGE.addon-webgl.json PACKAGE.addon-web-links.json \
  PACKAGE.addon-clipboard.json PACKAGE.addon-image.json PACKAGE.addon-progress.json PACKAGE.addon-search.json \
  PACKAGE.addon-unicode11.json PACKAGE.addon-web-fonts.json PACKAGE.addon-ligatures.json ASSET_RECEIPT.json; do
  test -s "$TMP/output/$file"
done
printf 'PASS asset-provisioner-success\n'


if provision "$TMP/xterm.tgz" "$(integrity xterm)" "$TMP/old-ligatures-output" "$TMP/ligatures-old.tgz" "$(integrity ligatures-old)" >/dev/null 2>&1; then
  printf 'FAIL asset-provisioner-old-ligatures-layout unexpectedly passed\n' >&2; exit 1
fi
printf 'PASS asset-provisioner-old-ligatures-layout-rejected\n'

UNSAFE_INTEGRITY=$(cat "$TMP/unsafe-integrity")
if provision "$TMP/unsafe.tgz" "$UNSAFE_INTEGRITY" "$TMP/unsafe-output" >/dev/null 2>&1; then
  printf 'FAIL asset-provisioner-unsafe unexpectedly passed\n' >&2; exit 1
fi
printf 'PASS asset-provisioner-unsafe\n'
