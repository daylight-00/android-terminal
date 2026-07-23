#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/app/src/main/assets/terminal/bridge/terminal-renderer.js"
NODE_COMMAND=${NODE_COMMAND:-node}

if ! command -v "$NODE_COMMAND" >/dev/null 2>&1; then
  printf 'SKIP webgl-renderer runtime=node-unavailable\n'
  exit 0
fi

"$NODE_COMMAND" --check "$SCRIPT"
"$NODE_COMMAND" - "$SCRIPT" <<'JS'
'use strict';
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync(process.argv[2], 'utf8');
const context = {window: null, Error, Object};
context.window = context;
vm.createContext(context);
vm.runInContext(source, context, {filename: process.argv[2]});
const renderer = context.AndroidTerminalRenderer;
if (!renderer || typeof renderer.create !== 'function') throw new Error('renderer export missing');

function fakeEnvironment({throwOnLoad = false} = {}) {
  const loaded = [];
  const states = [];
  let lossCallback = null;
  let subscriptionDisposed = 0;
  let addonDisposed = 0;
  class WebglAddon {
    constructor(preserveDrawingBuffer) {
      if (preserveDrawingBuffer !== false) throw new Error('preserveDrawingBuffer must remain false');
    }
    onContextLoss(callback) {
      lossCallback = callback;
      return {dispose() { subscriptionDisposed += 1; }};
    }
    dispose() { addonDisposed += 1; }
  }
  const terminal = {
    loadAddon(addon) {
      loaded.push(addon);
      if (throwOnLoad) throw new Error('activation failed');
    }
  };
  const controller = renderer.create({
    terminal,
    WebglAddon: {WebglAddon},
    onStateChange(state) { states.push({...state}); }
  });
  return {
    controller,
    loaded,
    states,
    loseContext() { if (!lossCallback) throw new Error('context loss callback missing'); lossCallback(); },
    counts() { return {subscriptionDisposed, addonDisposed}; }
  };
}

{
  const env = fakeEnvironment();
  const state = env.controller.activate();
  if (state.mode !== 'webgl' || state.reason !== 'active') throw new Error('WebGL activation state mismatch');
  if (env.loaded.length !== 1) throw new Error('WebGL addon was not loaded exactly once');
  env.loseContext();
  const fallback = env.controller.getState();
  if (fallback.mode !== 'dom' || fallback.reason !== 'context-loss') throw new Error('context-loss fallback mismatch');
  const counts = env.counts();
  if (counts.subscriptionDisposed !== 1 || counts.addonDisposed !== 1) throw new Error('context-loss cleanup mismatch');
  env.controller.activate();
  if (env.loaded.length !== 1) throw new Error('context-loss frontend retried WebGL');
  env.loseContext();
  const repeated = env.counts();
  if (repeated.subscriptionDisposed !== 1 || repeated.addonDisposed !== 1) throw new Error('duplicate context loss changed cleanup');
}

{
  const env = fakeEnvironment({throwOnLoad: true});
  const state = env.controller.activate();
  if (state.mode !== 'dom' || state.reason !== 'activation-failed') throw new Error('activation failure fallback mismatch');
  const counts = env.counts();
  if (counts.subscriptionDisposed !== 1 || counts.addonDisposed !== 1) throw new Error('activation failure cleanup mismatch');
  env.controller.activate();
  if (env.loaded.length !== 1) throw new Error('activation failure retried WebGL');
}

{
  const terminal = {loadAddon() { throw new Error('must not load'); }};
  const states = [];
  const controller = renderer.create({terminal, WebglAddon: {}, onStateChange(s) { states.push(s); }});
  const state = controller.activate();
  if (state.mode !== 'dom' || state.reason !== 'webgl-unavailable') throw new Error('unavailable fallback mismatch');
}


{
  let lossCallback = null;
  let disposed = 0;
  class SynchronousLossAddon {
    onContextLoss(callback) { lossCallback = callback; return {dispose() {}}; }
    dispose() { disposed += 1; }
  }
  const terminal = {loadAddon() { lossCallback(); }};
  const controller = renderer.create({
    terminal,
    WebglAddon: {WebglAddon: SynchronousLossAddon}
  });
  const state = controller.activate();
  if (state.mode !== 'dom' || state.reason !== 'context-loss') throw new Error('synchronous context loss resurrected WebGL');
  if (disposed !== 1) throw new Error('synchronous context loss cleanup mismatch');
}

console.log('PASS webgl-renderer runtime=node');
JS
