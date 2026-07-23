#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CONTRACT="$ROOT/app/src/main/assets/terminal/bridge/terminal-contract.js"
CODEC="$ROOT/app/src/main/assets/terminal/bridge/terminal-codec.js"
PLATFORM="$ROOT/app/src/main/assets/terminal/bridge/terminal-platform.js"
BRIDGE="$ROOT/app/src/main/assets/terminal/bridge/terminal-bridge.js"
RENDERER="$ROOT/app/src/main/assets/terminal/bridge/terminal-renderer.js"
NODE_COMMAND=${NODE_COMMAND:-node}

if command -v "$NODE_COMMAND" >/dev/null 2>&1; then
  for script in "$CONTRACT" "$CODEC" "$RENDERER" "$PLATFORM" "$BRIDGE"; do
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

  "$NODE_COMMAND" - "$CONTRACT" "$CODEC" "$RENDERER" "$PLATFORM" "$BRIDGE" <<'JS'
'use strict';
const fs = require('fs');
const vm = require('vm');
const paths = process.argv.slice(2);

(async () => {
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
  const posted = [];
  let portStarted = false;
  let resizeObserverCallback = null;
  let terminalInstance = null;
  const writes = [];
  const pastes = [];
  const port = {
    onmessage: null,
    postMessage(value) { posted.push(JSON.parse(value)); },
    start() { portStarted = true; }
  };

  class Terminal {
    constructor(options) {
      this.rows = 0;
      this.cols = 0;
      this.options = {...options};
      this.selection = '';
      terminalInstance = this;
    }
    loadAddon() {}
    open() {}
    onData(callback) { this.dataCallback = callback; return {dispose() {}}; }
    onBinary(callback) { this.binaryCallback = callback; return {dispose() {}}; }
    onBell(callback) { this.bellCallback = callback; return {dispose() {}}; }
    focus() { this.focused = true; }
    write(data, callback) { writes.push(data); if (callback) callback(); }
    hasSelection() { return this.selection !== ''; }
    getSelection() { return this.selection; }
    paste(value) { pastes.push(value); }
  }

  class SerializeAddon {
    serialize() { return 'serialized-state'; }
  }

  class WebglAddon {
    onContextLoss() { return {dispose() {}}; }
    dispose() {}
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

  function sendNative(payload) {
    port.onmessage({data: JSON.stringify({
      contractVersion: 6,
      connectionGeneration: 3,
      sessionId: 'session-a',
      ...payload
    })});
  }

  function latestRequest(operation) {
    const value = posted[posted.length - 1];
    if (!value || value.type !== 'platform-request' || value.operation !== operation) {
      throw new Error(`platform request missing: ${operation}`);
    }
    if (!/^platform-[0-9]+$/.test(value.requestId)) throw new Error('invalid platform request id');
    return value;
  }

  function completeRequest(request, data = {}) {
    sendNative({
      type: 'platform-result',
      requestId: request.requestId,
      ok: true,
      data
    });
  }

  const documentObject = {
    hidden: false,
    getElementById(id) {
      if (id === 'status') return status;
      return container;
    },
    addEventListener(type, callback) { documentListeners.set(type, callback); }
  };
  const context = {
    console,
    Error,
    Number,
    String,
    URL,
    Uint8Array,
    TextEncoder,
    document: documentObject,
    Terminal,
    FitAddon: {FitAddon},
    SerializeAddon: {SerializeAddon},
    WebglAddon: {WebglAddon},
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
  let timeoutId = 0;
  const timers = new Map();
  context.setTimeout = (callback) => { const id = ++timeoutId; timers.set(id, callback); return id; };
  context.clearTimeout = (id) => { timers.delete(id); };
  function flushTimers() {
    const callbacks = Array.from(timers.values());
    timers.clear();
    for (const callback of callbacks) callback();
  }
  context.addEventListener = (type, callback) => listeners.set(type, callback);
  context.removeEventListener = (type, callback) => {
    if (listeners.get(type) === callback) listeners.delete(type);
  };
  vm.createContext(context);
  for (const path of paths) {
    vm.runInContext(fs.readFileSync(path, 'utf8'), context, {filename: path});
  }

  if (!context.AndroidTerminalContract) throw new Error('contract export missing');
  if (context.AndroidTerminalContract.protocolVersion !== 6) throw new Error('protocol v6 missing');
  if (!context.AndroidTerminalPlatformIntegration) throw new Error('platform integration export missing');
  if (!context.AndroidTerminalPlatform) throw new Error('platform facade missing');
  if (!context.AndroidTerminalBridge || typeof context.AndroidTerminalBridge.getRendererState !== 'function') {
    throw new Error('renderer state facade missing');
  }
  const rendererState = context.AndroidTerminalBridge.getRendererState();
  if (rendererState.mode !== 'webgl' || rendererState.reason !== 'active') {
    throw new Error('Layer 2 WebGL activation state mismatch');
  }
  if (context.ClipboardAddon || context.WebLinksAddon) throw new Error('unselected addons leaked into Layer 2');

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
  if (posted[0].contractVersion !== 6) throw new Error('ready contract version missing');
  if (posted[0].pixelWidth !== 1080 || posted[0].pixelHeight !== 1920) {
    throw new Error('ready pixel geometry missing');
  }
  for (const capability of ['geometry-dedup-v1', 'platform-bridge-v2', 'document-transport-v1', 'serialize-state-v1', 'webgl-renderer-fallback-v1']) {
    if (!posted[0].capabilities.includes(capability)) throw new Error(`ready capability missing: ${capability}`);
  }
  for (const forbidden of ['osc52-clipboard', 'web-links']) {
    if (posted[0].capabilities.includes(forbidden)) throw new Error(`unselected capability advertised: ${forbidden}`);
  }

  const requiredNative = context.AndroidTerminalContract.requiredNativeCapabilities;
  port.onmessage({data: JSON.stringify({
    contractVersion: 6,
    type: 'attached',
    connectionGeneration: 3,
    sessionId: 'session-a',
    state: 'running',
    replayAvailable: true,
    replayTruncated: false,
    nativeCapabilities: ['frontend-reconnect', ...requiredNative]
  })});
  flushFrames();
  if (!statusClasses.has('hidden')) throw new Error('loading overlay remained after attachment');
  if (posted.length !== 1) throw new Error('attachment emitted duplicate geometry');

  sendNative({
    type: 'platform-state',
    colorScheme: 'light',
    accessibilityEnabled: true,
    touchExplorationEnabled: true,
    hardwareKeyboardPresent: true,
    fontScale: 1.25,
    sharedStorageAccessGranted: true,
    sharedStoragePath: '/storage/emulated/0'
  });
  flushFrames();
  if (terminalInstance.options.theme.background !== '#fafafa') throw new Error('system theme was not applied');
  if (terminalInstance.options.screenReaderMode !== true) throw new Error('screen reader mode was not applied');
  const state = context.AndroidTerminalPlatform.getState();
  if (!state || !state.hardwareKeyboardPresent || state.fontScale !== 1.25 ||
      !state.sharedStorageAccessGranted || state.sharedStoragePath !== '/storage/emulated/0') {
    throw new Error('platform state facade is incomplete');
  }

  sendNative({type: 'geometry'});
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
    contractVersion: 6,
    type: 'output',
    connectionGeneration: 2,
    sessionId: 'stale-session',
    seq: 40,
    data: ''
  })});
  if (posted.length !== 2) throw new Error('stale output produced an acknowledgement');

  sendNative({type: 'output', seq: 1, data: ''});
  if (posted.length !== 3 || posted[2].type !== 'ack' || posted[2].seq !== 1) {
    throw new Error('output acknowledgement missing');
  }
  flushTimers();
  const snapshot = posted[posted.length - 1];
  if (!snapshot || snapshot.type !== 'snapshot' || snapshot.throughSequence !== 1) {
    throw new Error('serialized snapshot message missing');
  }
  if (Buffer.from(snapshot.data, 'base64').toString('utf8') !== 'serialized-state') {
    throw new Error('serialized snapshot bytes are incorrect');
  }

  terminalInstance.selection = 'selected text';
  const copyPromise = context.AndroidTerminalPlatform.copySelection();
  const copyRequest = latestRequest('clipboard-write');
  if (copyRequest.payload.text !== 'selected text') throw new Error('selection was not transported');
  completeRequest(copyRequest, {characters: 13});
  await copyPromise;

  terminalInstance.selection = '';
  const countBeforeEmptyCopy = posted.length;
  const emptyCopy = await context.AndroidTerminalPlatform.copySelection();
  if (emptyCopy.copied !== false || posted.length !== countBeforeEmptyCopy) {
    throw new Error('empty selection reached Android clipboard');
  }

  const pastePromise = context.AndroidTerminalPlatform.pasteClipboard();
  const pasteRequest = latestRequest('clipboard-read');
  completeRequest(pasteRequest, {text: 'paste value'});
  await pastePromise;
  if (pastes[pastes.length - 1] !== 'paste value') throw new Error('clipboard text did not use xterm paste');

  const countBeforeBlockedUri = posted.length;
  let blocked = false;
  try {
    await context.AndroidTerminalPlatform.openExternalUri('file:///data/local/tmp/value');
  } catch (_) {
    blocked = true;
  }
  if (!blocked || posted.length !== countBeforeBlockedUri) throw new Error('blocked URI reached Android');

  const directLinkPromise = context.AndroidTerminalPlatform.openExternalUri('https://example.com/path');
  const directLinkRequest = latestRequest('open-external-uri');
  completeRequest(directLinkRequest);
  await directLinkPromise;

  const countBeforeOsc = posted.length;
  terminalInstance.options.linkHandler.activate(null, 'https://example.com/osc8', null);
  if (posted.length !== countBeforeOsc + 1) throw new Error('OSC 8 link handler did not reach Android');
  const oscRequest = latestRequest('open-external-uri');
  completeRequest(oscRequest);
  await Promise.resolve();

  const countBeforeBell = posted.length;
  terminalInstance.bellCallback();
  if (posted.length !== countBeforeBell + 1) throw new Error('bell event did not reach Android');
  const bellRequest = latestRequest('bell');
  completeRequest(bellRequest, {performed: false});
  await Promise.resolve();

  const importPromise = context.AndroidTerminalPlatform.importDocument({mimeType: 'text/plain'});
  const importRequest = latestRequest('document-import');
  if (importRequest.payload.mimeType !== 'text/plain') throw new Error('document import MIME type missing');
  completeRequest(importRequest, {
    path: '/data/user/0/app/files/imports/input.txt',
    relativePath: 'imports/input.txt',
    name: 'input.txt',
    mimeType: 'text/plain',
    bytes: 12
  });
  const imported = await importPromise;
  if (imported.relativePath !== 'imports/input.txt') throw new Error('document import result missing');

  const exportPromise = context.AndroidTerminalPlatform.exportDocument('imports/input.txt', {
    suggestedName: 'output.txt',
    mimeType: 'text/plain'
  });
  const exportRequest = latestRequest('document-export');
  if (exportRequest.payload.path !== 'imports/input.txt' ||
      exportRequest.payload.suggestedName !== 'output.txt' ||
      exportRequest.payload.mimeType !== 'text/plain') {
    throw new Error('document export payload is incomplete');
  }
  completeRequest(exportRequest, {relativePath: 'imports/input.txt', bytes: 12});
  await exportPromise;

  port.onmessage({data: JSON.stringify({
    contractVersion: 6,
    type: 'attached',
    connectionGeneration: 4,
    sessionId: 'session-gap',
    state: 'running',
    replayAvailable: false,
    replayTruncated: true,
    nextSequence: 51,
    serializedSnapshotAvailable: false,
    serializedThroughSequence: 0,
    nativeCapabilities: ['frontend-reconnect', ...requiredNative]
  })});
  const gapCount = posted.length;
  port.onmessage({data: JSON.stringify({
    contractVersion: 6,
    type: 'output',
    connectionGeneration: 4,
    sessionId: 'session-gap',
    seq: 51,
    data: ''
  })});
  const gapAck = posted[posted.length - 1];
  if (posted.length !== gapCount + 1 || gapAck.type !== 'ack' || gapAck.seq !== 51) {
    throw new Error('truncated replay did not resume at the live sequence watermark');
  }

  const countBeforeRestore = posted.length;
  port.onmessage({data: JSON.stringify({
    contractVersion: 6,
    type: 'attached',
    connectionGeneration: 5,
    sessionId: 'session-b',
    state: 'running',
    replayAvailable: true,
    replayTruncated: false,
    serializedSnapshotAvailable: true,
    serializedSnapshotData: Buffer.from('restored-state', 'utf8').toString('base64'),
    serializedThroughSequence: 7,
    nativeCapabilities: ['frontend-reconnect', ...requiredNative]
  })});
  const restoreAck = posted[posted.length - 1];
  if (posted.length !== countBeforeRestore + 1 || restoreAck.type !== 'restore-ack' || restoreAck.throughSequence !== 7) {
    throw new Error('serialized state restore acknowledgement missing');
  }
  const restoredBytes = writes[writes.length - 1];
  if (!(restoredBytes instanceof Uint8Array) || Buffer.from(restoredBytes).toString('utf8') !== 'restored-state') {
    throw new Error('serialized state was not restored through xterm write');
  }

  console.log('PASS web-terminal-channel contract=6 serialize=official-addon platform=clipboard,theme,accessibility,links,bell,documents geometry=deduplicated');
})().catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
JS
else
  python3 - "$CONTRACT" "$CODEC" "$PLATFORM" "$BRIDGE" <<'PY'
from __future__ import annotations

import base64
import pathlib
import sys

contract_path, codec_path, platform_path, bridge_path = map(pathlib.Path, sys.argv[1:])
required = {
    contract_path: (
        "protocolVersion: 6",
        "channelMarker: 'native-shell'",
        "session-attach-v2",
        "geometry-dedup-v1",
        "platform-bridge-v2",
        "document-transport-v1",
        "serialize-state-v1",
        "platformRequest: 'platform-request'",
        "platformState: 'platform-state'",
        "platformResult: 'platform-result'",
    ),
    codec_path: ("window.NativeShellCodec = Object.freeze", "new TextEncoder().encode(value)"),
    platform_path: (
        "window.AndroidTerminalPlatformIntegration = Object.freeze",
        "contractVersion: 1",
        "isExternalUriAllowed",
        "applyPlatformState",
    ),
    bridge_path: (
        "new window.Terminal()",
        "new window.SerializeAddon.SerializeAddon()",
        "serializeAddon.serialize()",
        "terminal.onData(",
        "terminal.onBinary(",
        "terminal.write(",
        "terminal.hasSelection()",
        "terminal.getSelection()",
        "terminal.paste(text)",
        "terminal.options.linkHandler",
        "terminal.onBell(",
        "window.AndroidTerminalPlatform = platform",
        "importDocument(options = {})",
        "exportDocument(path, options = {})",
        "window.visualViewport.addEventListener('resize'",
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

bridge = bridge_path.read_text(encoding="utf-8")
contract = contract_path.read_text(encoding="utf-8")
for forbidden in ("ClipboardAddon", "WebLinksAddon", "osc52-clipboard", "'web-links'"):
    if forbidden in bridge or forbidden in contract:
        raise SystemExit(f"unselected upstream addon leaked into platform bridge: {forbidden}")

for length in (0, 1, 2, 3, 255, 32768, 65537):
    payload = bytes((index * 131 + 17) & 0xFF for index in range(length))
    if base64.b64decode(base64.b64encode(payload), validate=True) != payload:
        raise SystemExit(f"base64 reference roundtrip failed: {length}")

print("PASS web-terminal static-python node=unavailable contract=6 serialize=official-addon platform=bounded-documents geometry=deduplicated")
PY
fi
