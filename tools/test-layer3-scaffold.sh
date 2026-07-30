#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BRIDGE="$ROOT/app/src/main/assets/terminal/bridge/terminal-bridge.js"
RENDERER="$ROOT/app/src/main/assets/terminal/bridge/terminal-renderer.js"
CUSTOMIZATION="$ROOT/app/src/main/assets/terminal/customization/customization.js"
CUSTOMIZATION_CSS="$ROOT/app/src/main/assets/terminal/customization/customization.css"

if grep -Fq 'AndroidTerminalCustomization' "$BRIDGE" || grep -Fq '/terminal/customization/' "$BRIDGE"; then
  printf 'FAIL layer3-scaffold Layer 2 depends on Layer 3\n' >&2
  exit 1
fi
for token in \
  'useDom(reason' \
  'useDom,'; do
  grep -Fq "$token" "$RENDERER"
done
for token in \
  'useDomRenderer(reason' \
  'rendererController.useDom(reason)'; do
  grep -Fq "$token" "$BRIDGE"
done
for token in \
  'xterm-native-touch-selection' \
  'user-select: text !important' \
  'pointer-events: auto !important' \
  'xterm-helper-textarea'; do
  grep -Fq "$token" "$CUSTOMIZATION_CSS"
done
if grep -Fq 'showSelectionActionMode' "$CUSTOMIZATION" || \
   grep -Fq 'onSelectionAction' "$CUSTOMIZATION" || \
   grep -Fq 'dispatchMouseEvent' "$CUSTOMIZATION"; then
  printf 'FAIL layer3-scaffold custom selection path remains active\n' >&2
  exit 1
fi

if command -v node >/dev/null 2>&1; then
  node --check "$CUSTOMIZATION"
  node - "$CUSTOMIZATION" <<'JS'
'use strict';
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync(process.argv[2], 'utf8');

class ClassList {
  constructor() { this.values = new Set(); }
  add(value) { this.values.add(value); }
  remove(value) { this.values.delete(value); }
  contains(value) { return this.values.has(value); }
}
class EventTarget {
  constructor() { this.listeners = new Map(); }
  addEventListener(type, listener) { const a=this.listeners.get(type)||[]; a.push(listener); this.listeners.set(type,a); }
  removeEventListener(type, listener) { const a=this.listeners.get(type)||[]; this.listeners.set(type,a.filter(v=>v!==listener)); }
  dispatch(type, event) { for (const listener of [...(this.listeners.get(type)||[])]) listener(event); }
}
class Screen {
  getBoundingClientRect() { return {width: 800, height: 240}; }
}
class Element extends EventTarget {
  constructor() { super(); this.screen = new Screen(); }
  querySelector(selector) { return selector === '.xterm-screen' ? this.screen : null; }
}
function event(touches, timeStamp=0) {
  return {
    touches, timeStamp, target: {closest(){return null;}},
    prevented:false, stopped:false, immediate:false,
    preventDefault(){this.prevented=true;},
    stopPropagation(){this.stopped=true;},
    stopImmediatePropagation(){this.immediate=true;}
  };
}
function point(identifier,x,y){return {identifier,clientX:x,clientY:y};}

const terminalElement = new Element();
const xtermElement = new EventTarget();
xtermElement.classList = new ClassList();
const helperTextarea = new EventTarget();
helperTextarea.style = {};
const pasteCalls = [];
const scrollCalls=[];
const frames=[];
const platformListeners=[];
let geometry=0;
let domReason='';
const terminal={
  element:xtermElement,
  textarea:helperTextarea,
  rows:12,
  cols:80,
  options:{fontSize:15,lineHeight:1,theme:{}},
  buffer:{active:{type:'normal',cursorX:3,cursorY:4}},
  modes:{mouseTrackingMode:'none'},
  scrollLines(value){scrollCalls.push(value);},
  paste(value){pasteCalls.push(value);}
};
const layer2={
  contractVersion:4,
  terminal,
  completion:{manifest:{schemaVersion:1}},
  getPlatformState(){return {fontScale:1};},
  onPlatformState(listener){platformListeners.push(listener); return {dispose(){}};},
  requestGeometrySync(){geometry+=1;},
  useDomRenderer(reason){domReason=reason; return {mode:'dom',reason};}
};
const windowObject={
  AndroidTerminalLayer2:layer2,
  requestAnimationFrame(cb){frames.push(cb); return frames.length;},
  cancelAnimationFrame(){},
  setTimeout,
  clearTimeout
};
const context=vm.createContext({window:windowObject,document:{getElementById(id){return id==='terminal'?terminalElement:null;}},console,Object,Number,Math,Date,Error,TypeError,setTimeout,clearTimeout});
vm.runInContext(source,context,{filename:'customization.js'});
const customization=context.window.AndroidTerminalCustomization;
if(!customization || customization.contractVersion!==3) throw new Error('Layer 3 contract missing');
if(domReason!=='native-touch-selection') throw new Error('DOM renderer was not selected');
if(!xtermElement.classList.contains('xterm-native-touch-selection')) throw new Error('native selection class missing');
if(terminalElement.listeners.size!==4) throw new Error('touch listeners incomplete');
if(helperTextarea.style.zIndex!=='10' || helperTextarea.style.width!=='80px' || helperTextarea.style.height!=='32px') throw new Error('native paste target not positioned');
let pasteEvent={clipboardData:{getData(){return 'native paste';}},prevented:false,stopped:false,immediate:false,preventDefault(){this.prevented=true;},stopPropagation(){this.stopped=true;},stopImmediatePropagation(){this.immediate=true;}};
helperTextarea.dispatch('paste',pasteEvent);
if(pasteCalls.join(',')!=='native paste' || !pasteEvent.prevented || !pasteEvent.immediate) throw new Error('native paste bridge failed');
let mouseEvent={sourceCapabilities:{firesTouchEvents:true},stopped:false,immediate:false,stopPropagation(){this.stopped=true;},stopImmediatePropagation(){this.immediate=true;}};
xtermElement.dispatch('mousedown',mouseEvent);
if(!mouseEvent.stopped || !mouseEvent.immediate) throw new Error('xterm touch selection was not suppressed without preventDefault');

platformListeners[0]({colorScheme:'light',fontScale:1.2});
if(terminal.options.theme.background!=='#fafafa' || terminal.options.fontSize!==18 || geometry!==1) throw new Error('appearance mapping failed');
frames.length = 0;

const stationaryStart=event([point(1,20,20)],0);
terminalElement.dispatch('touchstart',stationaryStart);
if(stationaryStart.prevented || stationaryStart.stopped) throw new Error('stationary touch was not left to WebView');
const stationaryEnd=event([],600);
terminalElement.dispatch('touchend',stationaryEnd);
if(stationaryEnd.prevented || scrollCalls.length!==0) throw new Error('native long press/tap path was consumed');

const dragStart=event([point(2,20,100)],700);
terminalElement.dispatch('touchstart',dragStart);
const dragMove=event([point(2,20,140)],730);
terminalElement.dispatch('touchmove',dragMove);
if(!dragMove.prevented || !dragMove.stopped || scrollCalls.length!==1 || scrollCalls[0]!==-2) throw new Error('scroll threshold path failed');
const dragEnd=event([],750);
terminalElement.dispatch('touchend',dragEnd);
if(!dragEnd.prevented || frames.length!==1) throw new Error('scroll completion/inertia failed');

const pinchStart=event([point(3,0,0),point(4,100,0)],800);
terminalElement.dispatch('touchstart',pinchStart);
if(!pinchStart.prevented) throw new Error('pinch start not owned');
const pinchMove=event([point(3,0,0),point(4,120,0)],820);
terminalElement.dispatch('touchmove',pinchMove);
if(!pinchMove.prevented || terminal.options.fontSize!==19) throw new Error('pinch font resize failed');

const state=customization.getInteractionState();
if(state.selectionAuthority!=='webview-native-dom-selection-poc' ||
   state.selectionHandles!=='webview-native' ||
   state.rendererAuthority!=='xterm-dom-renderer') throw new Error('native authority state missing');
customization.installation.dispose();
if(xtermElement.classList.contains('xterm-native-touch-selection')) throw new Error('native selection class not removed');
console.log('PASS layer3-scaffold runtime=node authority=webview-native-dom-selection-poc');
JS
else
  python3 - "$CUSTOMIZATION" "$CUSTOMIZATION_CSS" "$RENDERER" "$BRIDGE" <<'PY'
from pathlib import Path
import sys
customization, css, renderer, bridge = map(lambda p: Path(p).read_text(), sys.argv[1:])
required = {
    'customization': ['useDomRenderer', 'xterm-native-touch-selection', 'webview-native-dom-selection-poc', 'syncNativePasteTarget', 'suppressXtermTouchSelection', "layer2.terminal.paste(event.clipboardData.getData('text/plain'))"],
    'css': ['user-select: text !important', 'pointer-events: auto !important', 'xterm-helper-textarea'],
    'renderer': ['function useDom(', 'useDom,'],
    'bridge': ['useDomRenderer(reason', 'rendererController.useDom(reason)'],
}
for label, tokens in required.items():
    text = locals()[label]
    for token in tokens:
        if token not in text:
            raise SystemExit(f'FAIL layer3-scaffold missing {label} token: {token}')
for forbidden in ('showSelectionActionMode', 'onSelectionAction', 'dispatchMouseEvent'):
    if forbidden in customization:
        raise SystemExit(f'FAIL layer3-scaffold custom selection token remains: {forbidden}')
print('PASS layer3-scaffold static-python authority=webview-native-dom-selection-poc')
PY
fi
