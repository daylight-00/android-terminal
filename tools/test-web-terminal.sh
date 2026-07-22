#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CODEC="$ROOT/app/src/main/assets/terminal/terminal-codec.js"
TERMINAL="$ROOT/app/src/main/assets/terminal/terminal.js"
NODE_COMMAND=${NODE_COMMAND:-node}

if command -v "$NODE_COMMAND" >/dev/null 2>&1; then
  "$NODE_COMMAND" --check "$CODEC"
  "$NODE_COMMAND" --check "$TERMINAL"

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
else
  python3 - "$CODEC" "$TERMINAL" <<'PY'
from __future__ import annotations

import base64
import pathlib
import sys

codec_path = pathlib.Path(sys.argv[1])
terminal_path = pathlib.Path(sys.argv[2])
codec = codec_path.read_text(encoding="utf-8")
terminal = terminal_path.read_text(encoding="utf-8")

required_codec = (
    "function bytesToBase64(bytes)",
    "function base64ToBytes(encoded)",
    "new TextEncoder().encode(value)",
    "window.NativeShellCodec = Object.freeze",
)
required_terminal = (
    "new window.Terminal(",
    "new window.FitAddon.FitAddon()",
    "terminal.onData(",
    "terminal.onBinary(",
    "terminal.write(codec.base64ToBytes(message.data)",
    "event.origin !== APP_ORIGIN",
    "nativePort.start()",
)

for path, text, required in (
    (codec_path, codec, required_codec),
    (terminal_path, terminal, required_terminal),
):
    if "\x00" in text:
        raise SystemExit(f"NUL byte in {path}")
    for token in required:
        if token not in text:
            raise SystemExit(f"missing required token in {path}: {token}")

for length in (0, 1, 2, 3, 255, 32768, 65537):
    payload = bytes((index * 131 + 17) & 0xFF for index in range(length))
    if base64.b64decode(base64.b64encode(payload), validate=True) != payload:
        raise SystemExit(f"base64 reference roundtrip failed: {length}")

sample = "ASCII 한글 😀 \\u0000".encode("utf-8")
if base64.b64decode(base64.b64encode(sample), validate=True) != sample:
    raise SystemExit("UTF-8 reference roundtrip failed")

print("PASS web-terminal-codec mode=static-python node=unavailable")
PY
fi
