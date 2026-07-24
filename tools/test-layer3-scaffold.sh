#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BRIDGE="$ROOT/app/src/main/assets/terminal/bridge/terminal-bridge.js"
CUSTOMIZATION="$ROOT/app/src/main/assets/terminal/customization/customization.js"
CUSTOMIZATION_CSS="$ROOT/app/src/main/assets/terminal/customization/customization.css"

if grep -Fq 'AndroidTerminalCustomization' "$BRIDGE" || grep -Fq '/terminal/customization/' "$BRIDGE"; then
  printf 'FAIL layer3-scaffold Layer 2 depends on Layer 3\n' >&2
  exit 1
fi
grep -Fq 'window.AndroidTerminalLayer2 = Object.freeze' "$BRIDGE"
grep -Fq 'touch-action: none' "$CUSTOMIZATION_CSS"
grep -Fq '#terminal .xterm-screen canvas' "$CUSTOMIZATION_CSS"

if command -v node >/dev/null 2>&1; then
  node --check "$CUSTOMIZATION"
  node - "$CUSTOMIZATION" <<'JS'
'use strict';
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync(process.argv[2], 'utf8');

class FakeElement {
  constructor() {
    this.listeners = new Map();
  }
  addEventListener(type, listener) {
    const current = this.listeners.get(type) || [];
    current.push(listener);
    this.listeners.set(type, current);
  }
  removeEventListener(type, listener) {
    const current = this.listeners.get(type) || [];
    this.listeners.set(type, current.filter((candidate) => candidate !== listener));
  }
  dispatch(type, event) {
    for (const listener of [...(this.listeners.get(type) || [])]) listener(event);
  }
  listenerCount() {
    let total = 0;
    for (const listeners of this.listeners.values()) total += listeners.length;
    return total;
  }
}

function touchEvent(touches) {
  return {
    touches,
    prevented: false,
    stopped: false,
    immediate: false,
    preventDefault() { this.prevented = true; },
    stopPropagation() { this.stopped = true; },
    stopImmediatePropagation() { this.immediate = true; }
  };
}

function point(x, y) {
  return {clientX: x, clientY: y};
}

const terminalElement = new FakeElement();
const listeners = [];
let geometryRequests = 0;
let disposed = false;
const terminal = {options: {theme: {background: 'upstream-default'}, fontSize: 15}};
const layer2 = Object.freeze({
  contractVersion: 4,
  terminal,
  completion: Object.freeze({manifest: Object.freeze({schemaVersion: 1})}),
  getPlatformState() { return null; },
  onPlatformState(listener) {
    listeners.push(listener);
    return Object.freeze({dispose() { disposed = true; }});
  },
  requestGeometrySync() { geometryRequests += 1; }
});
const document = Object.freeze({
  getElementById(id) { return id === 'terminal' ? terminalElement : null; }
});
const context = vm.createContext({
  window: {AndroidTerminalLayer2: layer2},
  document,
  console,
  Error,
  TypeError,
  Object,
  Number,
  Math
});
vm.runInContext(source, context, {filename: 'customization.js'});
const customization = context.window.AndroidTerminalCustomization;
if (!customization || customization.contractVersion !== 2) {
  throw new Error('Layer 3 JavaScript contract is unavailable');
}
if (listeners.length !== 1) throw new Error('Layer 3 did not use the public Layer 2 state capability');
if (terminalElement.listenerCount() !== 4) throw new Error('Layer 3 touch listeners are incomplete');

listeners[0]({colorScheme: 'light', fontScale: 1.2});
if (terminal.options.theme.background !== '#fafafa') throw new Error('light palette was not applied');
if (Math.abs(terminal.options.fontSize - 18) > 1e-9) throw new Error('Android font scale was not composed');
if (geometryRequests !== 1) throw new Error('Layer 3 did not request geometry refresh');

const oneFinger = touchEvent([point(0, 0)]);
terminalElement.dispatch('touchstart', oneFinger);
if (oneFinger.prevented || oneFinger.stopped) throw new Error('one-finger scroll was stolen from upstream xterm');

const pinchStart = touchEvent([point(0, 0), point(100, 0)]);
terminalElement.dispatch('touchstart', pinchStart);
if (!pinchStart.prevented || !pinchStart.stopped || !pinchStart.immediate) {
  throw new Error('pinch gesture was not isolated from upstream scrolling');
}
const pinchGrow = touchEvent([point(0, 0), point(111, 0)]);
terminalElement.dispatch('touchmove', pinchGrow);
if (Math.abs(terminal.options.fontSize - 19) > 1e-9) throw new Error('pinch-out did not increase font size');
if (geometryRequests !== 2) throw new Error('pinch-out did not request geometry refresh');
const pinchEnd = touchEvent([]);
terminalElement.dispatch('touchend', pinchEnd);
if (customization.getInteractionState().pinchConsumesGesture) throw new Error('pinch ownership did not reset');

listeners[0]({colorScheme: 'dark', fontScale: 2});
if (terminal.options.theme.background !== '#000000') throw new Error('dark palette was not applied');
const expectedScaledSize = 15 * 2 * (19 / 18);
if (Math.abs(terminal.options.fontSize - expectedScaledSize) > 1e-9) {
  throw new Error('user font scale was not preserved across Android font-scale updates');
}
if (geometryRequests !== 3) throw new Error('second platform update did not request geometry refresh');

customization.installation.dispose();
if (!disposed) throw new Error('Layer 3 subscription is not disposable');
if (terminalElement.listenerCount() !== 0) throw new Error('Layer 3 touch listeners were not removed');
console.log('PASS layer3-scaffold direction=layer2-to-layer3 scroll=upstream pinch=font-size');
JS
else
  python3 - "$CUSTOMIZATION" "$CUSTOMIZATION_CSS" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding='utf-8')
css = Path(sys.argv[2]).read_text(encoding='utf-8')
for token in (
    'window.AndroidTerminalCustomization',
    'layer2.onPlatformState',
    'layer2.terminal.options.theme',
    'layer2.terminal.options.fontSize',
    "addEventListener('touchstart'",
    "addEventListener('touchmove'",
    'layer2.requestGeometrySync()',
):
    if token not in source:
        raise SystemExit(f'missing Layer 3 interaction token: {token}')
for token in ('touch-action: none', '#terminal .xterm-screen canvas'):
    if token not in css:
        raise SystemExit(f'missing Layer 3 touch CSS token: {token}')
for forbidden in ('nativePort', 'WebMessagePort', 'NativePty', '._core', 'terminal.scrollLines('):
    if forbidden in source:
        raise SystemExit(f'Layer 3 bypass or duplicate scroll token: {forbidden}')
print('PASS layer3-scaffold static-python node=unavailable')
PY
fi
