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

class FakeTarget {
  constructor() {
    this.events = [];
  }
  closest() { return null; }
  dispatchEvent(event) {
    this.events.push(event);
    return !event.defaultPrevented;
  }
}

class FakeMouseEvent {
  constructor(type, init = {}) {
    this.type = type;
    Object.assign(this, init);
    this.defaultPrevented = false;
  }
  preventDefault() { this.defaultPrevented = true; }
}

class FakeScreen {
  getBoundingClientRect() { return {height: 240}; }
}

class FakeElement {
  constructor() {
    this.listeners = new Map();
    this.screen = new FakeScreen();
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
  querySelector(selector) {
    return selector === '.xterm-screen' ? this.screen : null;
  }
  listenerCount() {
    let total = 0;
    for (const listeners of this.listeners.values()) total += listeners.length;
    return total;
  }
}

function touchEvent(touches, timeStamp, target = new FakeTarget()) {
  return {
    touches,
    timeStamp,
    target,
    prevented: false,
    stopped: false,
    immediate: false,
    preventDefault() { this.prevented = true; },
    stopPropagation() { this.stopped = true; },
    stopImmediatePropagation() { this.immediate = true; }
  };
}

function point(identifier, x, y) {
  return {identifier, clientX: x, clientY: y};
}

const terminalElement = new FakeElement();
const listeners = [];
const scrollCalls = [];
const frames = new Map();
let nextFrameId = 1;
let geometryRequests = 0;
let disposed = false;
let focusCalls = 0;
let blurCalls = 0;
let softInputCalls = 0;
const terminal = {
  rows: 12,
  options: {theme: {background: 'upstream-default'}, fontSize: 15, lineHeight: 1},
  buffer: {active: {type: 'normal'}},
  modes: {mouseTrackingMode: 'none'},
  scrollLines(rows) { scrollCalls.push(rows); },
  focus() { focusCalls += 1; },
  blur() { blurCalls += 1; }
};
const layer2 = Object.freeze({
  contractVersion: 4,
  terminal,
  platform: Object.freeze({
    showSoftInput() { softInputCalls += 1; return {catch() {}}; }
  }),
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
const windowObject = {
  AndroidTerminalLayer2: layer2,
  MouseEvent: FakeMouseEvent,
  requestAnimationFrame(callback) {
    const id = nextFrameId++;
    frames.set(id, callback);
    return id;
  },
  cancelAnimationFrame(id) { frames.delete(id); },
  setTimeout,
  clearTimeout
};
const context = vm.createContext({
  window: windowObject,
  document,
  console,
  Error,
  TypeError,
  Object,
  Number,
  Math,
  Date,
  setTimeout,
  clearTimeout
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

const tapTarget = new FakeTarget();
const tapStart = touchEvent([point(1, 40, 100)], 0, tapTarget);
terminalElement.dispatch('touchstart', tapStart);
if (!tapStart.prevented || !tapStart.stopped || !tapStart.immediate) {
  throw new Error('tap candidate was not owned from touchstart');
}
if (blurCalls !== 1) throw new Error('tap candidate did not suspend retained xterm input focus');
const tapEnd = touchEvent([], 10, tapTarget);
terminalElement.dispatch('touchend', tapEnd);
if (!tapEnd.prevented || !tapEnd.stopped || !tapEnd.immediate) {
  throw new Error('tap release was not isolated from WebView compatibility activation');
}
if (focusCalls !== 1) throw new Error('ordinary tap did not explicitly focus the terminal');
if (softInputCalls !== 1) throw new Error('ordinary tap did not request Android soft input');
if (tapTarget.events.map((event) => event.type).join(',') !== 'mousedown,mouseup,click') {
  throw new Error('ordinary tap compatibility sequence was not replayed');
}

const dragTarget = new FakeTarget();
const dragStart = touchEvent([point(2, 0, 100)], 20, dragTarget);
terminalElement.dispatch('touchstart', dragStart);
if (!dragStart.prevented) throw new Error('scroll candidate touchstart was not consumed');
const dragDown = touchEvent([point(2, 0, 140)], 40, dragTarget);
terminalElement.dispatch('touchmove', dragDown);
if (!dragDown.prevented || !dragDown.stopped || !dragDown.immediate) {
  throw new Error('one-finger drag was not isolated from WebView page handling');
}
if (scrollCalls.length !== 1 || scrollCalls[0] !== -2) {
  throw new Error(`drag-down row translation failed: ${JSON.stringify(scrollCalls)}`);
}
const dragUp = touchEvent([point(2, 0, 120)], 60, dragTarget);
terminalElement.dispatch('touchmove', dragUp);
if (scrollCalls.length !== 2 || scrollCalls[1] !== 1) {
  throw new Error(`drag-up row translation failed: ${JSON.stringify(scrollCalls)}`);
}
const dragEnd = touchEvent([], 70, dragTarget);
terminalElement.dispatch('touchend', dragEnd);
if (!dragEnd.prevented || frames.size !== 1) throw new Error('scroll fling was not scheduled');
if (focusCalls !== 1 || softInputCalls !== 1 || dragTarget.events.length !== 0) {
  throw new Error('committed scroll replayed tap focus activation');
}
if (blurCalls !== 2) throw new Error('committed scroll did not suspend retained xterm input focus');

const pinchTarget = new FakeTarget();
const firstPinchFinger = touchEvent([point(3, 0, 0)], 75, pinchTarget);
terminalElement.dispatch('touchstart', firstPinchFinger);
if (!firstPinchFinger.prevented) throw new Error('first pinch finger was not owned');
const pinchStart = touchEvent([point(3, 0, 0), point(4, 100, 0)], 80, pinchTarget);
terminalElement.dispatch('touchstart', pinchStart);
if (!pinchStart.prevented || !pinchStart.stopped || !pinchStart.immediate) {
  throw new Error('pinch gesture was not isolated from one-finger scrolling');
}
if (frames.size !== 0) throw new Error('pinch did not cancel prior scroll inertia');
const pinchGrow = touchEvent([point(3, 0, 0), point(4, 111, 0)], 90, pinchTarget);
terminalElement.dispatch('touchmove', pinchGrow);
if (Math.abs(terminal.options.fontSize - 19) > 1e-9) throw new Error('pinch-out did not increase font size');
if (geometryRequests !== 2) throw new Error('pinch-out did not request geometry refresh');
const pinchEnd = touchEvent([], 100, pinchTarget);
terminalElement.dispatch('touchend', pinchEnd);
if (focusCalls !== 1 || softInputCalls !== 1 || pinchTarget.events.length !== 0) {
  throw new Error('pinch replayed tap focus activation');
}
if (blurCalls < 4) throw new Error('pinch did not keep retained xterm input focus suspended');
if (customization.getInteractionState().pinchConsumesGesture) throw new Error('pinch ownership did not reset');
if (customization.getInteractionState().scrollAuthority !== 'layer3-public-scroll-lines') {
  throw new Error('scroll authority is not reported correctly');
}
if (customization.getInteractionState().touchActivationAuthority !== 'layer3-blur-then-deferred-tap-native-ime') {
  throw new Error('touch activation authority is not reported correctly');
}

terminal.buffer.active.type = 'alternate';
const altTarget = new FakeTarget();
const altStart = touchEvent([point(5, 0, 100)], 110, altTarget);
terminalElement.dispatch('touchstart', altStart);
const altMove = touchEvent([point(5, 0, 140)], 130, altTarget);
terminalElement.dispatch('touchmove', altMove);
if (altStart.prevented || altMove.prevented || scrollCalls.length !== 2) {
  throw new Error('alternate-buffer touch was incorrectly captured as normal scrollback');
}
terminalElement.dispatch('touchend', touchEvent([], 140, altTarget));
terminal.buffer.active.type = 'normal';

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
console.log('PASS layer3-scaffold direction=layer2-to-layer3 scroll=public-scroll-lines pinch=font-size focus=blur-then-deferred-tap-native-ime');
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
    'consumeTouch(event);',
    'replayTap(tapTarget, tapX, tapY)',
    'layer2.terminal.blur()',
    'layer2.platform.showSoftInput()',
    "touchActivationAuthority: 'layer3-blur-then-deferred-tap-native-ime'",
    'layer2.terminal.scrollLines(rows)',
    'layer2.requestGeometrySync()',
    "scrollAuthority: 'layer3-public-scroll-lines'",
):
    if token not in source:
        raise SystemExit(f'missing Layer 3 interaction token: {token}')
for token in ('touch-action: none', '#terminal .xterm-screen canvas'):
    if token not in css:
        raise SystemExit(f'missing Layer 3 touch CSS token: {token}')
for forbidden in ('nativePort', 'WebMessagePort', 'NativePty', '._core'):
    if forbidden in source:
        raise SystemExit(f'Layer 3 bypass token: {forbidden}')
print('PASS layer3-scaffold static-python node=unavailable')
PY
fi
