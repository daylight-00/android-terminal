#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BRIDGE="$ROOT/app/src/main/assets/terminal/bridge/terminal-bridge.js"
CUSTOMIZATION="$ROOT/app/src/main/assets/terminal/customization/customization.js"

if grep -Fq 'AndroidTerminalCustomization' "$BRIDGE" || grep -Fq '/terminal/customization/' "$BRIDGE"; then
  printf 'FAIL layer3-scaffold Layer 2 depends on Layer 3\n' >&2
  exit 1
fi
grep -Fq 'window.AndroidTerminalLayer2 = Object.freeze' "$BRIDGE"

if command -v node >/dev/null 2>&1; then
  node --check "$CUSTOMIZATION"
  node - "$CUSTOMIZATION" <<'JS'
'use strict';
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync(process.argv[2], 'utf8');
const listeners = [];
let geometryRequests = 0;
let disposed = false;
const terminal = {options: {theme: {background: 'upstream-default'}}};
const layer2 = Object.freeze({
  contractVersion: 1,
  terminal,
  onPlatformState(listener) {
    listeners.push(listener);
    return Object.freeze({dispose() { disposed = true; }});
  },
  requestGeometrySync() { geometryRequests += 1; }
});
const context = vm.createContext({window: {AndroidTerminalLayer2: layer2}, Error, Object});
vm.runInContext(source, context, {filename: 'customization.js'});
const customization = context.window.AndroidTerminalCustomization;
if (!customization || customization.contractVersion !== 1) {
  throw new Error('Layer 3 JavaScript contract is unavailable');
}
if (listeners.length !== 1) throw new Error('Layer 3 did not use the public Layer 2 state capability');
listeners[0]({colorScheme: 'light'});
if (terminal.options.theme.background !== '#fafafa') throw new Error('light palette was not applied');
listeners[0]({colorScheme: 'dark'});
if (terminal.options.theme.background !== '#000000') throw new Error('dark palette was not applied');
if (geometryRequests !== 2) throw new Error('Layer 3 did not request public geometry refresh');
customization.installation.dispose();
if (!disposed) throw new Error('Layer 3 subscription is not disposable');
console.log('PASS layer3-scaffold direction=layer2-to-layer3 palette=layer3 ui=empty');
JS
else
  python3 - "$CUSTOMIZATION" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding='utf-8')
for token in (
    'window.AndroidTerminalCustomization',
    'layer2.onPlatformState',
    'layer2.terminal.options.theme',
    'layer2.requestGeometrySync()',
):
    if token not in source:
        raise SystemExit(f'missing Layer 3 scaffold token: {token}')
for forbidden in ('nativePort', 'WebMessagePort', 'NativePty', '._core'):
    if forbidden in source:
        raise SystemExit(f'Layer 3 bypass token: {forbidden}')
print('PASS layer3-scaffold static-python node=unavailable')
PY
fi
