#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BRIDGE="$ROOT/app/src/main/assets/terminal/bridge/terminal-bridge.js"
CUSTOMIZATION="$ROOT/app/src/main/assets/terminal/customization/customization.js"
CUSTOMIZATION_CSS="$ROOT/app/src/main/assets/terminal/customization/customization.css"
INDEX="$ROOT/app/src/main/assets/terminal/bridge/index.html"

if grep -Fq 'AndroidTerminalCustomization' "$BRIDGE" || grep -Fq '/terminal/customization/' "$BRIDGE"; then
  printf 'FAIL layer3-scaffold Layer 2 depends on Layer 3\n' >&2
  exit 1
fi
grep -Fq 'window.AndroidTerminalLayer2 = Object.freeze' "$BRIDGE"
grep -Fq 'touch-action: none' "$CUSTOMIZATION_CSS"
grep -Fq '#terminal .xterm-screen canvas' "$CUSTOMIZATION_CSS"
! grep -Fq 'terminal-selection-toolbar' "$INDEX"
grep -Fq 'layer2.platform.showSelectionActions({x, y})' "$CUSTOMIZATION"
grep -Fq 'layer2.platform.hideSelectionActions()' "$CUSTOMIZATION"
grep -Fq 'layer2.onSelectionAction(runToolbarAction)' "$CUSTOMIZATION"
grep -Fq "selectionToolbarAuthority: 'layer2-android-floating-actionmode-copy-paste-select-all'" "$CUSTOMIZATION"

if command -v node >/dev/null 2>&1; then
  node --check "$CUSTOMIZATION"
  node - "$CUSTOMIZATION" <<'JS'
'use strict';
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync(process.argv[2], 'utf8');

class FakeTarget {
  constructor() { this.events = []; }
  closest() { return null; }
  dispatchEvent(event) { this.events.push(event); return true; }
}
class FakeMouseEvent {
  constructor(type, init = {}) { this.type = type; Object.assign(this, init); }
}
class FakeScreen {
  getBoundingClientRect() { return {left: 0, top: 0, width: 1200, height: 240}; }
}
class FakeElement {
  constructor() { this.listeners = new Map(); this.screen = new FakeScreen(); }
  addEventListener(type, listener) {
    const list = this.listeners.get(type) || [];
    list.push(listener);
    this.listeners.set(type, list);
  }
  removeEventListener(type, listener) {
    this.listeners.set(type, (this.listeners.get(type) || []).filter((item) => item !== listener));
  }
  dispatch(type, event) {
    for (const listener of [...(this.listeners.get(type) || [])]) listener(event);
  }
  querySelector(selector) { return selector === '.xterm-screen' ? this.screen : null; }
  listenerCount() { return [...this.listeners.values()].reduce((sum, list) => sum + list.length, 0); }
}
function touch(identifier, x, y) { return {identifier, clientX: x, clientY: y}; }
function touchEvent(touches, timeStamp, target = new FakeTarget()) {
  return {
    touches,
    timeStamp,
    target,
    preventDefault() { this.prevented = true; },
    stopPropagation() { this.stopped = true; },
    stopImmediatePropagation() { this.immediate = true; }
  };
}

const terminalElement = new FakeElement();
const platformStateListeners = [];
const selectionActionListeners = [];
const timers = new Map();
let nextTimer = 1;
const frames = new Map();
let nextFrame = 1;
let selectionActive = false;
let focusCalls = 0;
let blurCalls = 0;
let softInputCalls = 0;
let copyCalls = 0;
let pasteCalls = 0;
let selectAllCalls = 0;
let geometryCalls = 0;
let showCalls = [];
let hideCalls = 0;
let stateDisposed = false;
let actionDisposed = false;
const scrollCalls = [];
const selectCalls = [];
const lineText = 'hello world';
const activeBuffer = {
  type: 'normal',
  viewportY: 0,
  getLine() {
    return {
      getCell(column) {
        const value = lineText[column] || '';
        return {getChars() { return value; }, getWidth() { return 1; }};
      }
    };
  }
};
const terminal = {
  cols: 120,
  rows: 12,
  options: {theme: {}, fontSize: 15, lineHeight: 1, wordSeparator: ' ()[]{}\'"'},
  buffer: {active: activeBuffer},
  modes: {mouseTrackingMode: 'none'},
  scrollLines(rows) { scrollCalls.push(rows); },
  select(column, row, length) { selectCalls.push([column, row, length]); selectionActive = true; },
  selectAll() { selectAllCalls += 1; selectionActive = true; },
  hasSelection() { return selectionActive; },
  clearSelection() { selectionActive = false; },
  focus() { focusCalls += 1; },
  blur() { blurCalls += 1; }
};
const layer2 = Object.freeze({
  contractVersion: 4,
  terminal,
  completion: Object.freeze({manifest: Object.freeze({schemaVersion: 1})}),
  platform: Object.freeze({
    showSoftInput() { softInputCalls += 1; return {catch() {}}; },
    copySelection() { copyCalls += 1; return {catch() {}}; },
    pasteClipboard() {
      pasteCalls += 1;
      return {then(callback) { callback({text: 'clipboard'}); return {catch() {}}; }};
    },
    showSelectionActions(position) { showCalls.push({...position}); return {catch() {}}; },
    hideSelectionActions() { hideCalls += 1; return {catch() {}}; }
  }),
  getPlatformState() { return {colorScheme: 'dark', fontScale: 1, softInputVisible: false}; },
  onPlatformState(listener) {
    platformStateListeners.push(listener);
    return Object.freeze({dispose() { stateDisposed = true; }});
  },
  onSelectionAction(listener) {
    selectionActionListeners.push(listener);
    return Object.freeze({dispose() { actionDisposed = true; }});
  },
  requestGeometrySync() { geometryCalls += 1; }
});
const windowObject = {
  AndroidTerminalLayer2: layer2,
  MouseEvent: FakeMouseEvent,
  requestAnimationFrame(callback) { const id = nextFrame++; frames.set(id, callback); return id; },
  cancelAnimationFrame(id) { frames.delete(id); },
  setTimeout(callback) { const id = nextTimer++; timers.set(id, callback); return id; },
  clearTimeout(id) { timers.delete(id); }
};
const context = vm.createContext({
  window: windowObject,
  document: {getElementById(id) { return id === 'terminal' ? terminalElement : null; }},
  console,
  Error,
  TypeError,
  Object,
  Number,
  Math,
  Date,
  setTimeout: windowObject.setTimeout,
  clearTimeout: windowObject.clearTimeout
});
vm.runInContext(source, context, {filename: 'customization.js'});
const customization = context.window.AndroidTerminalCustomization;
if (!customization || customization.contractVersion !== 2) throw new Error('customization missing');
if (terminalElement.listenerCount() !== 4) throw new Error('touch listeners incomplete');
if (platformStateListeners.length !== 1 || selectionActionListeners.length !== 1) {
  throw new Error('Layer 2 subscriptions incomplete');
}
function runTimers() {
  const pending = [...timers.values()];
  timers.clear();
  for (const callback of pending) callback();
}

const longPressTarget = new FakeTarget();
const focusBaseline = focusCalls;
const softBaseline = softInputCalls;
const blurBaseline = blurCalls;
terminalElement.dispatch('touchstart', touchEvent([touch(1, 30, 80)], 10, longPressTarget));
runTimers();
terminalElement.dispatch('touchmove', touchEvent([touch(1, 80, 80)], 20, longPressTarget));
terminalElement.dispatch('touchend', touchEvent([], 30, longPressTarget));
if (!selectionActive || selectCalls.length < 2) throw new Error('long press selection failed');
if (showCalls.length !== 1 || showCalls[0].x !== 80 || showCalls[0].y !== 80) {
  throw new Error('native action anchor was not requested');
}
if (focusCalls !== focusBaseline || softInputCalls !== softBaseline || blurCalls !== blurBaseline + 1) {
  throw new Error('hidden-IME selection focus policy regressed');
}
if (customization.getInteractionState().selectionToolbarAuthority !==
    'layer2-android-floating-actionmode-copy-paste-select-all') {
  throw new Error('native ActionMode authority missing');
}

selectionActionListeners[0]('copy');
if (copyCalls !== 1 || !selectionActive) throw new Error('copy action failed or cleared selection');
if (customization.getInteractionState().selectionToolbarVisible) {
  throw new Error('copy did not close the toolbar state');
}

// Re-open actions around the existing selection, then paste.
terminalElement.dispatch('touchstart', touchEvent([touch(2, 40, 80)], 40));
runTimers();
terminalElement.dispatch('touchend', touchEvent([], 50));
selectionActionListeners[0]('paste');
if (pasteCalls !== 1 || selectionActive) throw new Error('paste did not clear selection');
if (focusCalls !== focusBaseline || softInputCalls !== softBaseline) {
  throw new Error('native toolbar action reactivated input');
}

// Select all stays active and refreshes the native anchor.
selectionActive = true;
selectionActionListeners[0]('select-all');
if (selectAllCalls !== 1 || !selectionActive || showCalls.length < 3) {
  throw new Error('select all did not refresh native actions');
}

// Hidden-IME scroll must never activate input.
const scrollFocus = focusCalls;
const scrollSoft = softInputCalls;
const scrollBlur = blurCalls;
terminalElement.dispatch('touchstart', touchEvent([touch(3, 0, 100)], 60));
terminalElement.dispatch('touchmove', touchEvent([touch(3, 0, 150)], 80));
terminalElement.dispatch('touchend', touchEvent([], 90));
if (scrollCalls.length === 0) throw new Error('scrollLines was not used');
if (focusCalls !== scrollFocus || softInputCalls !== scrollSoft || blurCalls !== scrollBlur + 1) {
  throw new Error('hidden-IME scroll focus policy regressed');
}

// Hidden-IME short tap remains the only path that opens input.
const tapFocus = focusCalls;
const tapSoft = softInputCalls;
terminalElement.dispatch('touchstart', touchEvent([touch(4, 20, 60)], 100));
terminalElement.dispatch('touchend', touchEvent([], 110));
if (focusCalls !== tapFocus + 1 || softInputCalls !== tapSoft + 1) {
  throw new Error('tap-only input activation regressed');
}

// Visible IME gestures do not blur.
platformStateListeners[0]({colorScheme: 'dark', fontScale: 1, softInputVisible: true});
const visibleBlur = blurCalls;
const visibleFocus = focusCalls;
const visibleSoft = softInputCalls;
terminalElement.dispatch('touchstart', touchEvent([touch(5, 0, 100)], 120));
terminalElement.dispatch('touchmove', touchEvent([touch(5, 0, 150)], 130));
terminalElement.dispatch('touchend', touchEvent([], 140));
if (blurCalls !== visibleBlur || focusCalls !== visibleFocus || softInputCalls !== visibleSoft) {
  throw new Error('visible-IME gesture policy regressed');
}

// Pinch uses public font size and geometry synchronization.
platformStateListeners[0]({colorScheme: 'dark', fontScale: 1, softInputVisible: false});
const sizeBefore = terminal.options.fontSize;
terminalElement.dispatch('touchstart', touchEvent([touch(6, 0, 0)], 150));
terminalElement.dispatch('touchstart', touchEvent([touch(6, 0, 0), touch(7, 100, 0)], 160));
terminalElement.dispatch('touchmove', touchEvent([touch(6, 0, 0), touch(7, 120, 0)], 170));
terminalElement.dispatch('touchend', touchEvent([], 180));
if (!(terminal.options.fontSize > sizeBefore) || geometryCalls === 0) throw new Error('pinch failed');

customization.installation.dispose();
if (!stateDisposed || !actionDisposed) throw new Error('subscriptions were not disposed');
if (terminalElement.listenerCount() !== 0) throw new Error('touch listeners were not removed');
console.log('PASS layer3-scaffold selection=xterm-buffer native-toolbar=android-floating-actionmode copy-close=true ime=r15-preserved');
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
    'layer2.onSelectionAction',
    'layer2.platform.showSelectionActions({x, y})',
    'layer2.platform.hideSelectionActions()',
    'layer2.platform.copySelection()',
    'layer2.platform.pasteClipboard()',
    'layer2.terminal.selectAll()',
    "selectionToolbarAuthority: 'layer2-android-floating-actionmode-copy-paste-select-all'",
    "touchActivationAuthority: 'layer3-deferred-tap-only-native-ime'",
    'releaseHiddenInputFocusAtGestureStart',
    'layer2.terminal.scrollLines(rows)',
    'layer2.terminal.select(first.column, first.row, length)',
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
