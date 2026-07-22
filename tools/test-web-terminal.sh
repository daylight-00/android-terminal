#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CONTRACT="$ROOT/app/src/main/assets/terminal/bridge/terminal-contract.js"
CODEC="$ROOT/app/src/main/assets/terminal/bridge/terminal-codec.js"
CUSTOMIZATION="$ROOT/app/src/main/assets/terminal/customization/customization.js"
BRIDGE="$ROOT/app/src/main/assets/terminal/bridge/terminal-bridge.js"
NODE_COMMAND=${NODE_COMMAND:-node}

if command -v "$NODE_COMMAND" >/dev/null 2>&1; then
  for script in "$CONTRACT" "$CODEC" "$CUSTOMIZATION" "$BRIDGE"; do
    "$NODE_COMMAND" --check "$script"
  done

  "$NODE_COMMAND" - "$CODEC" <<'JS'
'use strict';
const fs = require('fs');
const vm = require('vm');
const path = process.argv[2];
const source = fs.readFileSync(path, 'utf8');
const context = {
  Uint8Array,
  TextEncoder,
  btoa(value) { return Buffer.from(value, 'binary').toString('base64'); },
  atob(value) { return Buffer.from(value, 'base64').toString('binary'); }
};
context.window = context;
vm.createContext(context);
vm.runInContext(source, context, {filename: path});
const codec = context.NativeShellCodec;
if (!codec) throw new Error('codec export missing');

function equalBytes(actual, expected, label) {
  if (actual.length !== expected.length) throw new Error(`${label}: length mismatch`);
  for (let i = 0; i < actual.length; i += 1) {
    if (actual[i] !== expected[i]) throw new Error(`${label}: byte mismatch at ${i}`);
  }
}

for (const length of [0, 1, 2, 3, 255, 32768, 65537]) {
  const input = new Uint8Array(length);
  for (let index = 0; index < length; index += 1) input[index] = (index * 131 + 17) & 0xff;
  equalBytes(codec.base64ToBytes(codec.bytesToBase64(input)), input, `roundtrip-${length}`);
}
const utf8 = new TextEncoder().encode('ASCII 한글 😀 \\u0000');
equalBytes(codec.base64ToBytes(codec.stringToUtf8Base64('ASCII 한글 😀 \\u0000')), utf8, 'utf8');
console.log('PASS web-terminal-codec runtime=node');
JS

  "$NODE_COMMAND" - "$CONTRACT" "$CODEC" "$CUSTOMIZATION" "$BRIDGE" <<'JS'
'use strict';
const fs = require('fs');
const vm = require('vm');
const paths = process.argv.slice(2);

const listeners = new Map();
const documentListeners = new Map();
const viewportListeners = new Map();
const frames = [];
const statusClasses = new Set();
const status = {
  textContent: '',
  classList: {
    add(value) { statusClasses.add(value); },
    remove(value) { statusClasses.delete(value); }
  }
};
const container = {clientWidth: 0, clientHeight: 0};
const customRoot = {replaceChildren() { this.cleared = true; }};
const posted = [];
let portStarted = false;
let resizeObserverCallback = null;
let terminalInstance = null;
const writes = [];
const port = {
  onmessage: null,
  postMessage(value) { posted.push(JSON.parse(value)); },
  start() { portStarted = true; }
};
class Terminal {
  constructor(options) {
    this.rows = 0;
    this.cols = 0;
    this.options = options;
    terminalInstance = this;
  }
  loadAddon() {}
  open() {}
  onData(callback) { this.dataCallback = callback; }
  onBinary(callback) { this.binaryCallback = callback; }
  focus() {}
  write(data, callback) { writes.push(data); if (callback) callback(); }
}
class FitAddon {
  fit() {
    if (!terminalInstance || container.clientWidth <= 0 || container.clientHeight <= 0) return;
    terminalInstance.cols = Math.max(1, Math.floor(container.clientWidth / 10));
    terminalInstance.rows = Math.max(1, Math.floor(container.clientHeight / 20));
  }
}
function flushFrames() {
  while (frames.length) frames.shift()();
}
const documentObject = {
  hidden: false,
  getElementById(id) {
    if (id === 'status') return status;
    if (id === 'custom-ui-root') return customRoot;
    return container;
  },
  addEventListener(type, callback) { documentListeners.set(type, callback); }
};
const context = {
  console,
  Error,
  Number,
  String,
  Uint8Array,
  TextEncoder,
  document: documentObject,
  Terminal,
  FitAddon: {FitAddon},
  ResizeObserver: class {
    constructor(callback) { resizeObserverCallback = callback; }
    observe() {}
  },
  btoa(value) { return Buffer.from(value, 'binary').toString('base64'); },
  atob(value) { return Buffer.from(value, 'base64').toString('binary'); }
};
context.window = context;
context.visualViewport = {
  addEventListener(type, callback) { viewportListeners.set(type, callback); }
};
context.requestAnimationFrame = (callback) => {
  frames.push(callback);
  return frames.length;
};
context.setTimeout = () => 7;
context.clearTimeout = () => {};
context.addEventListener = (type, callback) => listeners.set(type, callback);
context.removeEventListener = (type, callback) => {
  if (listeners.get(type) === callback) listeners.delete(type);
};
vm.createContext(context);
for (const path of paths) {
  vm.runInContext(fs.readFileSync(path, 'utf8'), context, {filename: path});
}
if (!context.AndroidTerminalContract) throw new Error('contract export missing');
if (context.AndroidTerminalContract.protocolVersion !== 3) throw new Error('protocol v3 missing');
if (!context.TerminalCustomization) throw new Error('customization export missing');
if (!customRoot.cleared) throw new Error('custom UI root was not initialized');
const handler = listeners.get('message');
if (typeof handler !== 'function') throw new Error('message handler missing');
handler({origin: '', data: 'native-shell', ports: [port]});
if (!portStarted) throw new Error('native port was rejected when MessageEvent.origin was empty');
flushFrames();
if (posted.length !== 0) throw new Error('zero-sized geometry produced a ready message');

container.clientWidth = 1080;
container.clientHeight = 1920;
resizeObserverCallback();
flushFrames();
if (posted.length !== 1 || posted[0].type !== 'ready') throw new Error('ready message missing');
if (posted[0].contractVersion !== 3) throw new Error('ready contract version missing');
if (posted[0].pixelWidth !== 1080 || posted[0].pixelHeight !== 1920) {
  throw new Error('ready pixel geometry missing');
}
if (!Array.isArray(posted[0].capabilities) ||
    !posted[0].capabilities.includes('geometry-dedup-v1')) {
  throw new Error('ready capabilities missing geometry dedupe');
}

port.onmessage({data: JSON.stringify({
  contractVersion: 3,
  type: 'attached',
  connectionGeneration: 3,
  sessionId: 'session-a',
  state: 'running',
  replayAvailable: true,
  replayTruncated: false,
  nativeCapabilities: ['frontend-reconnect', 'android-window-geometry']
})});
flushFrames();
if (!statusClasses.has('hidden')) throw new Error('loading overlay remained after attachment');
if (posted.length !== 1) throw new Error('attachment emitted duplicate geometry');

port.onmessage({data: JSON.stringify({
  contractVersion: 3,
  type: 'geometry',
  connectionGeneration: 3,
  sessionId: 'session-a'
})});
flushFrames();
if (posted.length !== 1) throw new Error('unchanged native geometry signal emitted resize');

container.clientHeight = 1200;
viewportListeners.get('resize')();
flushFrames();
if (posted.length !== 2 || posted[1].type !== 'resize') throw new Error('changed viewport did not resize');
if (posted[1].rows !== 60 || posted[1].columns !== 108 || posted[1].pixelHeight !== 1200) {
  throw new Error('changed geometry values are incorrect');
}
viewportListeners.get('resize')();
flushFrames();
if (posted.length !== 2) throw new Error('duplicate viewport geometry emitted resize');
container.clientHeight = 0;
listeners.get('resize')();
flushFrames();
if (posted.length !== 2) throw new Error('transient zero geometry emitted resize');

port.onmessage({data: JSON.stringify({
  contractVersion: 3,
  type: 'output',
  connectionGeneration: 2,
  sessionId: 'stale-session',
  seq: 40,
  data: ''
})});
if (posted.length !== 2) throw new Error('stale output produced an acknowledgement');

port.onmessage({data: JSON.stringify({
  contractVersion: 3,
  type: 'output',
  connectionGeneration: 3,
  sessionId: 'session-a',
  seq: 41,
  data: ''
})});
if (posted.length !== 3 || posted[2].type !== 'ack' || posted[2].seq !== 41) {
  throw new Error('output acknowledgement missing');
}
if (posted[2].contractVersion !== 3 ||
    posted[2].connectionGeneration !== 3 ||
    posted[2].sessionId !== 'session-a') {
  throw new Error('ack attachment identity missing');
}
console.log('PASS web-terminal-channel contract=3 zero=rejected geometry=deduplicated stale=rejected');
JS
else
  python3 - "$CONTRACT" "$CODEC" "$CUSTOMIZATION" "$BRIDGE" <<'PY'
from __future__ import annotations

import base64
import pathlib
import sys

contract_path, codec_path, customization_path, bridge_path = map(pathlib.Path, sys.argv[1:])
required = {
    contract_path: (
        "protocolVersion: 3",
        "channelMarker: 'native-shell'",
        "session-attach-v2",
        "geometry-dedup-v1",
        "geometry: 'geometry'",
    ),
    codec_path: ("window.NativeShellCodec = Object.freeze", "new TextEncoder().encode(value)"),
    customization_path: ("window.TerminalCustomization = Object.freeze", "cursorBlink", "replayUnavailable"),
    bridge_path: (
        "new window.Terminal(customization.terminalOptions)",
        "terminal.onData(",
        "terminal.onBinary(",
        "terminal.write(",
        "measureGeometry(type)",
        "geometryKey(geometry)",
        "window.visualViewport.addEventListener('resize'",
        "contract.messages.geometry",
        "matchesAttachment(nativeMessage)",
    ),
}
for path, tokens in required.items():
    text = path.read_text(encoding="utf-8")
    if "\x00" in text:
        raise SystemExit(f"NUL byte in {path}")
    for token in tokens:
        if token not in text:
            raise SystemExit(f"missing required token in {path}: {token}")

for length in (0, 1, 2, 3, 255, 32768, 65537):
    payload = bytes((index * 131 + 17) & 0xFF for index in range(length))
    if base64.b64decode(base64.b64encode(payload), validate=True) != payload:
        raise SystemExit(f"base64 reference roundtrip failed: {length}")

print("PASS web-terminal static-python node=unavailable contract=3 geometry=deduplicated")
PY
fi
