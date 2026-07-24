#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
HTML="$ROOT/app/src/main/assets/terminal/bridge/index.html"
BRIDGE="$ROOT/app/src/main/assets/terminal/bridge/terminal-bridge.js"
CODEC="$ROOT/app/src/main/assets/terminal/bridge/terminal-codec.js"
CLIENT="$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal/LocalAssetWebViewClient.kt"
CAPS="$ROOT/docs/upstream-capabilities.json"

for addon in clipboard image progress search unicode11 web-fonts; do
  grep -Fq "/terminal/vendor/addon-$addon.js" "$HTML"
  grep -Fq "/terminal/vendor/addon-$addon.js" "$CLIENT"
done
grep -Fq "/terminal/bridge/terminal-ligatures.js" "$HTML"
grep -Fq "/terminal/bridge/terminal-ligatures.js" "$CLIENT"
grep -Fq "/terminal/vendor/addon-ligatures.mjs" "$CLIENT"

grep -Fq "new window.Terminal({allowProposedApi: true})" "$BRIDGE"
grep -Fq 'new window.ClipboardAddon.ClipboardAddon(undefined, clipboardProvider)' "$BRIDGE"
grep -Fq 'new window.ImageAddon.ImageAddon()' "$BRIDGE"
grep -Fq 'new window.ProgressAddon.ProgressAddon()' "$BRIDGE"
grep -Fq 'new window.SearchAddon.SearchAddon()' "$BRIDGE"
grep -Fq 'new window.Unicode11Addon.Unicode11Addon()' "$BRIDGE"
grep -Fq 'new window.WebFontsAddon.WebFontsAddon()' "$BRIDGE"
grep -Fq 'new module.LigaturesAddon(options)' "$BRIDGE"
grep -Fq 'resolveLigaturesModule()' "$BRIDGE"
grep -Fq "import {LigaturesAddon} from '/terminal/vendor/addon-ligatures.mjs'" "$ROOT/app/src/main/assets/terminal/bridge/terminal-ligatures.js"
grep -Fq 'rendererController.reactivate()' "$BRIDGE"
grep -Fq "typeof text !== 'string'" "$BRIDGE"
grep -Fq 'onProgressState' "$BRIDGE"
grep -Fq 'findNext(term, options)' "$BRIDGE"
grep -Fq 'setActiveVersion(version)' "$BRIDGE"
grep -Fq 'loadFonts(fonts)' "$BRIDGE"
grep -Fq 'contractVersion: 3' "$BRIDGE"
grep -Fq 'stable-addon-wave-v1' "$ROOT/app/src/main/assets/terminal/bridge/terminal-contract.js"
python3 - "$CAPS" <<'PY'
import json,sys
p=json.load(open(sys.argv[1]))
expected={
'@xterm/addon-clipboard':'connected-with-bounds',
'@xterm/addon-image':'connected-with-upstream-defaults',
'@xterm/addon-progress':'connected',
'@xterm/addon-search':'available',
'@xterm/addon-unicode11':'available',
'@xterm/addon-web-fonts':'available',
'@xterm/addon-ligatures':'available',
}
actual={r['package']:r['status'] for r in p['official_addons']}
assert all(actual.get(k)==v for k,v in expected.items()), (expected,actual)
PY
printf 'PASS stable-addon-wave\n'
