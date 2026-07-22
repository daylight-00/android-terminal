#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

node --check "$ROOT/app/src/main/assets/terminal/terminal-codec.js"
node --check "$ROOT/app/src/main/assets/terminal/terminal.js"

node - "$ROOT/app/src/main/assets/terminal/terminal-codec.js" <<'JS'
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
console.log('PASS web-terminal-codec');
JS
