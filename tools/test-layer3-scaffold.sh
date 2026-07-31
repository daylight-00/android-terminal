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
  getBoundingClientRect() { return {left: 0, top: 0, width: 1200, height: 240}; }
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
const selectCalls = [];
const frames = new Map();
let nextFrameId = 1;
const timers = new Map();
let nextTimerId = 1;
function scheduleTimeout(callback) {
  const id = nextTimerId++;
  timers.set(id, callback);
  return id;
}
function cancelTimeout(id) { timers.delete(id); }
function runTimers() {
  const pending = [...timers.entries()];
  timers.clear();
  for (const [, callback] of pending) callback();
}
let geometryRequests = 0;
let disposed = false;
let focusCalls = 0;
let blurCalls = 0;
let softInputCalls = 0;
const lineText = 'hello world';
const fakeLine = {
  getCell(column) {
    const character = lineText[column] || '';
    return {
      getChars() { return character; },
      getWidth() { return character ? 1 : 1; }
    };
  }
};
const activeBuffer = {
  type: 'normal',
  viewportY: 0,
  getLine() { return fakeLine; }
};
const terminal = {
  cols: 120,
  rows: 12,
  options: {
    theme: {background: 'upstream-default'},
    fontSize: 15,
    lineHeight: 1,
    wordSeparator: ' ()[]{}\'"'
  },
  buffer: {active: activeBuffer},
  modes: {mouseTrackingMode: 'none'},
  scrollLines(rows) { scrollCalls.push(rows); },
  select(column, row, length) { selectCalls.push([column, row, length]); },
  focus() { focusCalls += 1; },
  blur() { blurCalls += 1; },
  clearSelection() {},
  hasSelection() { return selectCalls.length > 0; }
};
const layer2 = Object.freeze({
  contractVersion: 4,
  terminal,
  platform: Object.freeze({
    showSoftInput() { softInputCalls += 1; return {catch() {}}; }
  }),
  completion: Object.freeze({manifest: Object.freeze({schemaVersion: 1})}),
  getPlatformState() { return {softInputVisible: false}; },
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
  setTimeout: scheduleTimeout,
  clearTimeout: cancelTimeout
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
  setTimeout: scheduleTimeout,
  clearTimeout: cancelTimeout
});
vm.runInContext(source, context, {filename: 'customization.js'});
const customization = context.window.AndroidTerminalCustomization;
if (!customization || customization.contractVersion !== 2) {
  throw new Error('Layer 3 JavaScript contract is unavailable');
}
if (listeners.length !== 1) throw new Error('Layer 3 did not use the public Layer 2 state capability');
if (terminalElement.listenerCount() !== 4) throw new Error('Layer 3 touch listeners are incomplete');

listeners[0]({colorScheme: 'light', fontScale: 1.2, softInputVisible: false});
if (terminal.options.theme.background !== '#fafafa') throw new Error('light palette was not applied');
if (Math.abs(terminal.options.fontSize - 18) > 1e-9) throw new Error('Android font scale was not composed');
if (geometryRequests !== 1) throw new Error('Layer 3 did not request geometry refresh');

const tapTarget = new FakeTarget();
const tapStart = touchEvent([point(1, 40, 100)], 0, tapTarget);
terminalElement.dispatch('touchstart', tapStart);
if (!tapStart.prevented || !tapStart.stopped || !tapStart.immediate) {
  throw new Error('tap candidate was not owned from touchstart');
}
if (blurCalls !== 0) throw new Error('tap candidate changed xterm focus on touchstart');
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
if (blurCalls !== 0) throw new Error('committed scroll changed xterm focus');

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
if (blurCalls !== 0) throw new Error('pinch changed xterm focus');
if (customization.getInteractionState().pinchConsumesGesture) throw new Error('pinch ownership did not reset');
if (customization.getInteractionState().scrollAuthority !== 'layer3-public-scroll-lines') {
  throw new Error('scroll authority is not reported correctly');
}
if (customization.getInteractionState().touchActivationAuthority !== 'layer3-deferred-tap-only-native-ime') {
  throw new Error('touch activation authority is not reported correctly');
}

listeners[0]({colorScheme: 'dark', fontScale: 1.2, softInputVisible: true});
const selectionBlurBaseline = blurCalls;
const selectionFocusBaseline = focusCalls;
const selectionSoftInputBaseline = softInputCalls;
const selectionTarget = new FakeTarget();
terminalElement.dispatch('touchstart', touchEvent([point(10, 30, 80)], 105, selectionTarget));
runTimers();
if (!customization.getInteractionState().selectionConsumesGesture) {
  throw new Error('long press did not enter xterm selection mode');
}
if (selectionTarget.events.length !== 0) {
  throw new Error('long press used focus-bearing synthetic mouse selection');
}
if (JSON.stringify(selectCalls[0]) !== JSON.stringify([0, 4, 5])) {
  throw new Error(`long press did not select the xterm buffer word: ${JSON.stringify(selectCalls)}`);
}
terminalElement.dispatch('touchmove', touchEvent([point(10, 70, 80)], 110, selectionTarget));
if (JSON.stringify(selectCalls[1]) !== JSON.stringify([0, 4, 8])) {
  throw new Error(`selection drag did not extend through public terminal.select: ${JSON.stringify(selectCalls)}`);
}
terminalElement.dispatch('touchend', touchEvent([], 120, selectionTarget));
if (selectCalls.length !== 2) {
  throw new Error('selection release unexpectedly changed the selected range');
}
if (customization.getInteractionState().selectionConsumesGesture) {
  throw new Error('selection ownership did not reset');
}
if (blurCalls !== selectionBlurBaseline || focusCalls !== selectionFocusBaseline ||
    softInputCalls !== selectionSoftInputBaseline) {
  throw new Error('visible-IME long press changed xterm focus or Android soft input');
}
if (customization.getInteractionState().selectionAuthority !== 'xterm-public-buffer-select-long-press') {
  throw new Error('selection authority is not reported correctly');
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

listeners[0]({colorScheme: 'dark', fontScale: 2, softInputVisible: true});
if (terminal.options.theme.background !== '#000000') throw new Error('dark palette was not applied');
const expectedScaledSize = 15 * 2 * (19 / 18);
if (Math.abs(terminal.options.fontSize - expectedScaledSize) > 1e-9) {
  throw new Error('user font scale was not preserved across Android font-scale updates');
}
if (geometryRequests !== 4) throw new Error('second platform update did not request geometry refresh');
if (!customization.getInteractionState().softInputVisible) {
  throw new Error('Layer 3 did not retain Android IME visibility state');
}
if (customization.getInteractionState().gestureFocusPolicy !== 'ime-hide-blur-tap-only-focus-ime') {
  throw new Error('gesture focus policy is not reported correctly');
}

const visibleTapBlurBaseline = blurCalls;
const visibleTapSoftInputBaseline = softInputCalls;
const visibleTapFocusBaseline = focusCalls;
const visibleTapTarget = new FakeTarget();
terminalElement.dispatch('touchstart', touchEvent([point(6, 20, 60)], 150, visibleTapTarget));
terminalElement.dispatch('touchend', touchEvent([], 160, visibleTapTarget));
if (blurCalls !== visibleTapBlurBaseline) {
  throw new Error('visible-IME tap incorrectly blurred xterm input focus');
}
if (softInputCalls !== visibleTapSoftInputBaseline) {
  throw new Error('visible-IME tap redundantly requested Android soft input');
}
if (focusCalls !== visibleTapFocusBaseline + 1) {
  throw new Error('visible-IME tap did not preserve ordinary terminal focus activation');
}

const visibleDragBlurBaseline = blurCalls;
const visibleDragFocusBaseline = focusCalls;
const visibleDragSoftInputBaseline = softInputCalls;
const visibleDragTarget = new FakeTarget();
terminalElement.dispatch('touchstart', touchEvent([point(7, 0, 100)], 170, visibleDragTarget));
terminalElement.dispatch('touchmove', touchEvent([point(7, 0, 140)], 190, visibleDragTarget));
terminalElement.dispatch('touchend', touchEvent([], 200, visibleDragTarget));
if (blurCalls !== visibleDragBlurBaseline || focusCalls !== visibleDragFocusBaseline ||
    softInputCalls !== visibleDragSoftInputBaseline) {
  throw new Error('visible-IME scroll changed xterm focus or Android soft input');
}

const visiblePinchBlurBaseline = blurCalls;
const visiblePinchFocusBaseline = focusCalls;
const visiblePinchSoftInputBaseline = softInputCalls;
const visiblePinchTarget = new FakeTarget();
terminalElement.dispatch('touchstart', touchEvent([point(8, 0, 0)], 210, visiblePinchTarget));
terminalElement.dispatch('touchstart', touchEvent([point(8, 0, 0), point(9, 100, 0)], 220, visiblePinchTarget));
terminalElement.dispatch('touchmove', touchEvent([point(8, 0, 0), point(9, 111, 0)], 230, visiblePinchTarget));
terminalElement.dispatch('touchend', touchEvent([], 240, visiblePinchTarget));
if (blurCalls !== visiblePinchBlurBaseline || focusCalls !== visiblePinchFocusBaseline ||
    softInputCalls !== visiblePinchSoftInputBaseline) {
  throw new Error('visible-IME pinch changed xterm focus or Android soft input');
}

const imeHideBlurBaseline = blurCalls;
const imeHideFocusBaseline = focusCalls;
const imeHideSoftInputBaseline = softInputCalls;
listeners[0]({colorScheme: 'dark', fontScale: 2, softInputVisible: false});
if (blurCalls !== imeHideBlurBaseline + 1) {
  throw new Error('visible-to-hidden IME transition did not release retained xterm focus exactly once');
}
if (focusCalls !== imeHideFocusBaseline || softInputCalls !== imeHideSoftInputBaseline) {
  throw new Error('IME hide transition unexpectedly focused xterm or requested Android soft input');
}
listeners[0]({colorScheme: 'dark', fontScale: 2, softInputVisible: false});
if (blurCalls !== imeHideBlurBaseline + 1) {
  throw new Error('repeated hidden-IME state redundantly blurred xterm');
}
if (customization.getInteractionState().softInputVisible) {
  throw new Error('Layer 3 did not retain the hidden Android IME state');
}

const hiddenSelectionBlurBaseline = blurCalls;
const hiddenSelectionFocusBaseline = focusCalls;
const hiddenSelectionSoftInputBaseline = softInputCalls;
const hiddenSelectionTarget = new FakeTarget();
terminalElement.dispatch('touchstart', touchEvent([point(11, 30, 80)], 250, hiddenSelectionTarget));
runTimers();
terminalElement.dispatch('touchmove', touchEvent([point(11, 70, 80)], 260, hiddenSelectionTarget));
terminalElement.dispatch('touchend', touchEvent([], 270, hiddenSelectionTarget));
if (blurCalls !== hiddenSelectionBlurBaseline || focusCalls !== hiddenSelectionFocusBaseline ||
    softInputCalls !== hiddenSelectionSoftInputBaseline) {
  throw new Error('hidden-IME long press reactivated or redundantly blurred terminal input');
}

const hiddenDragBlurBaseline = blurCalls;
const hiddenDragFocusBaseline = focusCalls;
const hiddenDragSoftInputBaseline = softInputCalls;
const hiddenDragTarget = new FakeTarget();
terminalElement.dispatch('touchstart', touchEvent([point(12, 0, 100)], 280, hiddenDragTarget));
terminalElement.dispatch('touchmove', touchEvent([point(12, 0, 140)], 300, hiddenDragTarget));
terminalElement.dispatch('touchend', touchEvent([], 310, hiddenDragTarget));
if (blurCalls !== hiddenDragBlurBaseline || focusCalls !== hiddenDragFocusBaseline ||
    softInputCalls !== hiddenDragSoftInputBaseline) {
  throw new Error('hidden-IME scroll reactivated or redundantly blurred terminal input');
}

customization.installation.dispose();
if (!disposed) throw new Error('Layer 3 subscription is not disposable');
if (terminalElement.listenerCount() !== 0) throw new Error('Layer 3 touch listeners were not removed');
console.log('PASS layer3-scaffold direction=layer2-to-layer3 scroll=public-scroll-lines pinch=font-size focus=ime-hide-blur-tap-only-ime selection=xterm-buffer-select-long-press');
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
    'replayTap(tapTarget, tapX, tapY, !softInputVisible)',
    'layer2.terminal.select(first.column, first.row, length)',
    'layer2.platform.showSoftInput()',
    "touchActivationAuthority: 'layer3-deferred-tap-only-native-ime'",
    "gestureFocusPolicy: 'ime-hide-blur-tap-only-focus-ime'",
    'const wasSoftInputVisible = softInputVisible',
    'softInputVisible = Boolean(state.softInputVisible)',
    'wasSoftInputVisible && !softInputVisible',
    'layer2.terminal.blur()',
    'layer2.terminal.scrollLines(rows)',
    'layer2.requestGeometrySync()',
    "scrollAuthority: 'layer3-public-scroll-lines'",
    'LONG_PRESS_DELAY_MILLIS',
    'beginLongPressSelection',
    "selectionAuthority: 'xterm-public-buffer-select-long-press'",
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
