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
const statusClasses = new Set();
const status = {
  textContent: '',
  classList: {
    add(value) { statusClasses.add(value); },
    remove(value) { statusClasses.delete(value); }
  }
};
const container = {clientWidth: 1080, clientHeight: 1920};
const customRoot = {replaceChildren() { this.cleared = true; }};
const posted = [];
let portStarted = false;
const writes = [];
const port = {
  onmessage: null,
  postMessage(value) { posted.push(JSON.parse(value)); },
  start() { portStarted = true; }
};
class Terminal {
  constructor(options) { this.rows = 24; this.cols = 80; this.options = options; }
  loadAddon() {}
  open() {}
  onData(callback) { this.dataCallback = callback; }
  onBinary(callback) { this.binaryCallback = callback; }
  focus() {}
  write(data, callback) { writes.push(data); if (callback) callback(); }
}
class FitAddon { fit() {} }
const context = {
  console,
  Error,
  String,
  Uint8Array,
  TextEncoder,
  document: {getElementById(id) {
    if (id === 'status') return status;
    if (id === 'custom-ui-root') return customRoot;
    return container;
  }},
  Terminal,
  FitAddon: {FitAddon},
  ResizeObserver: class { observe() {} },
  requestAnimationFrame() { return 1; },
  btoa(value) { return Buffer.from(value, 'binary').toString('base64'); },
  atob(value) { return Buffer.from(value, 'base64').toString('binary'); }
};
context.window = context;
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
if (!context.TerminalCustomization) throw new Error('customization export missing');
if (!customRoot.cleared) throw new Error('custom UI root was not initialized');
const handler = listeners.get('message');
if (typeof handler !== 'function') throw new Error('message handler missing');
handler({origin: '', data: 'native-shell', ports: [port]});
if (!portStarted) throw new Error('native port was rejected when MessageEvent.origin was empty');
if (!statusClasses.has('hidden')) throw new Error('loading overlay was not hidden');
if (listeners.has('message')) throw new Error('message handler was not removed after valid handshake');
if (posted.length !== 1 || posted[0].type !== 'ready') throw new Error('ready message missing');
if (posted[0].contractVersion !== 1) throw new Error('ready contract version missing');
if (!Array.isArray(posted[0].capabilities) || !posted[0].capabilities.includes('output-ack')) {
  throw new Error('ready capabilities missing');
}
port.onmessage({data: JSON.stringify({
  contractVersion: 1,
  type: 'output',
  seq: 41,
  data: ''
})});
if (posted.length !== 2 || posted[1].type !== 'ack' || posted[1].seq !== 41) {
  throw new Error('output acknowledgement missing');
}
if (posted[1].contractVersion !== 1) throw new Error('ack contract version missing');
console.log('PASS web-terminal-channel origin=empty contract=1 capabilities=present');
JS
else
  python3 - "$CONTRACT" "$CODEC" "$CUSTOMIZATION" "$BRIDGE" <<'PY'
from __future__ import annotations

import base64
import pathlib
import sys

contract_path, codec_path, customization_path, bridge_path = map(pathlib.Path, sys.argv[1:])
contract = contract_path.read_text(encoding="utf-8")
codec = codec_path.read_text(encoding="utf-8")
customization = customization_path.read_text(encoding="utf-8")
bridge = bridge_path.read_text(encoding="utf-8")

required = {
    contract_path: ("protocolVersion: 1", "channelMarker: 'native-shell'", "pageCapabilities"),
    codec_path: ("window.NativeShellCodec = Object.freeze", "new TextEncoder().encode(value)"),
    customization_path: ("window.TerminalCustomization = Object.freeze", "cursorBlink", "scrollback"),
    bridge_path: (
        "new window.Terminal(customization.terminalOptions)",
        "terminal.onData(",
        "terminal.onBinary(",
        "terminal.write(",
        "contractVersion: contract.protocolVersion",
        "capabilities: contract.pageCapabilities",
        "window.removeEventListener('message', handleNativeChannel)",
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

print("PASS web-terminal static-python node=unavailable")
PY
fi
