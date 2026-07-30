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
for token in 'useDom(reason' 'useDom,'; do grep -Fq "$token" "$RENDERER"; done
for token in 'useDomRenderer(reason' 'rendererController.useDom(reason)'; do grep -Fq "$token" "$BRIDGE"; done
for token in \
  'xterm-native-touch-selection' \
  'user-select: text !important' \
  'touch-action: auto !important' \
  'pointer-events: auto !important'; do
  grep -Fq "$token" "$CUSTOMIZATION_CSS"
done
for forbidden in \
  'xterm-helper-textarea' \
  'touch-action: none' \
  'scrollLines(' \
  'syncNativePasteTarget' \
  'handleNativePaste' \
  'showSelectionActionMode' \
  'onSelectionAction' \
  'dispatchMouseEvent'; do
  if grep -Fq "$forbidden" "$CUSTOMIZATION" "$CUSTOMIZATION_CSS"; then
    printf 'FAIL layer3-scaffold isolation contains forbidden token: %s\n' "$forbidden" >&2
    exit 1
  fi
done

if command -v node >/dev/null 2>&1; then
  node --check "$CUSTOMIZATION"
  node - "$CUSTOMIZATION" <<'JS'
'use strict';
const fs=require('fs');
const vm=require('vm');
const source=fs.readFileSync(process.argv[2],'utf8');
class ClassList{constructor(){this.values=new Set();}add(v){this.values.add(v);}remove(v){this.values.delete(v);}contains(v){return this.values.has(v);}}
class EventTarget{constructor(){this.listeners=new Map();}addEventListener(t,l){const a=this.listeners.get(t)||[];a.push(l);this.listeners.set(t,a);}removeEventListener(t,l){const a=this.listeners.get(t)||[];this.listeners.set(t,a.filter(v=>v!==l));}dispatch(t,e){for(const l of [...(this.listeners.get(t)||[])])l(e);}}
function event(touches){return{touches,prevented:false,stopped:false,immediate:false,preventDefault(){this.prevented=true;},stopPropagation(){this.stopped=true;},stopImmediatePropagation(){this.immediate=true;}};}
function point(identifier,x,y){return{identifier,clientX:x,clientY:y};}
const terminalElement=new EventTarget();
const xtermElement=new EventTarget();xtermElement.classList=new ClassList();
const platformListeners=[];let geometry=0;let domReason='';
const terminal={element:xtermElement,options:{fontSize:15,theme:{}},modes:{mouseTrackingMode:'none'}};
const layer2={contractVersion:4,terminal,completion:{manifest:{schemaVersion:1}},getPlatformState(){return{fontScale:1};},onPlatformState(l){platformListeners.push(l);return{dispose(){}};},requestGeometrySync(){geometry+=1;},useDomRenderer(reason){domReason=reason;return{mode:'dom',reason};}};
const windowObject={AndroidTerminalLayer2:layer2};
const context=vm.createContext({window:windowObject,document:{getElementById(id){return id==='terminal'?terminalElement:null;}},console,Object,Number,Math,Date,Error,TypeError});
vm.runInContext(source,context,{filename:'customization.js'});
const customization=context.window.AndroidTerminalCustomization;
if(!customization||customization.contractVersion!==3)throw new Error('Layer 3 contract missing');
if(domReason!=='native-touch-selection-isolation')throw new Error('isolation DOM renderer reason missing');
if(!xtermElement.classList.contains('xterm-native-touch-selection'))throw new Error('native class missing');
if(terminalElement.listeners.size!==4)throw new Error('touch listeners incomplete');
platformListeners[0]({colorScheme:'light',fontScale:1.2});
if(terminal.options.theme.background!=='#fafafa'||terminal.options.fontSize!==18||geometry!==1)throw new Error('appearance mapping failed');

const start=event([point(1,20,20)]);terminalElement.dispatch('touchstart',start);
const move=event([point(1,20,160)]);terminalElement.dispatch('touchmove',move);
const end=event([]);terminalElement.dispatch('touchend',end);
if(start.prevented||move.prevented||end.prevented||start.stopped||move.stopped||end.stopped)throw new Error('one-finger ownership leaked from WebView');

const mouse={sourceCapabilities:{firesTouchEvents:true},stopped:false,immediate:false,stopPropagation(){this.stopped=true;},stopImmediatePropagation(){this.immediate=true;}};
xtermElement.dispatch('mousedown',mouse);
if(!mouse.stopped||!mouse.immediate)throw new Error('xterm touch mouse selection not suppressed');

const pinchStart=event([point(2,0,0),point(3,100,0)]);terminalElement.dispatch('touchstart',pinchStart);
if(!pinchStart.prevented)throw new Error('pinch start not owned');
const pinchMove=event([point(2,0,0),point(3,120,0)]);terminalElement.dispatch('touchmove',pinchMove);
if(!pinchMove.prevented||terminal.options.fontSize!==19)throw new Error('pinch resize failed');
const pinchEnd=event([]);terminalElement.dispatch('touchend',pinchEnd);
if(!pinchEnd.prevented)throw new Error('pinch end not owned');

const state=customization.getInteractionState();
if(state.selectionAuthority!=='webview-native-dom-row-selection-isolation-poc'||
   state.scrollAuthority!=='webview-native-overflow-isolation'||
   state.pasteAuthority!=='none-in-row-selection-isolation'||
   state.touchActivationAuthority!=='webview-default-one-finger-complete-ownership')throw new Error('isolation authority state missing');
customization.installation.dispose();
if(xtermElement.classList.contains('xterm-native-touch-selection'))throw new Error('native class not removed');
console.log('PASS layer3-scaffold runtime=node authority=webview-native-dom-row-selection-isolation-poc');
JS
else
  python3 - "$CUSTOMIZATION" "$CUSTOMIZATION_CSS" "$RENDERER" "$BRIDGE" <<'PY'
from pathlib import Path
import sys
customization, css, renderer, bridge = map(lambda p: Path(p).read_text(), sys.argv[1:])
required = {
    'customization': ["useDomRenderer('native-touch-selection-isolation')", 'suppressXtermTouchSelection', 'webview-native-dom-row-selection-isolation-poc', 'webview-native-overflow-isolation', 'none-in-row-selection-isolation'],
    'css': ['user-select: text !important', 'touch-action: auto !important', 'pointer-events: auto !important'],
    'renderer': ['function useDom(', 'useDom,'],
    'bridge': ['useDomRenderer(reason', 'rendererController.useDom(reason)'],
}
for label, tokens in required.items():
    text = locals()[label]
    for token in tokens:
        if token not in text:
            raise SystemExit(f'FAIL layer3-scaffold missing {label} token: {token}')
for forbidden in ('scrollLines(', 'syncNativePasteTarget', 'handleNativePaste', 'showSelectionActionMode', 'onSelectionAction', 'dispatchMouseEvent', 'xterm-helper-textarea', 'touch-action: none'):
    if forbidden in customization or forbidden in css:
        raise SystemExit(f'FAIL layer3-scaffold isolation contains forbidden token: {forbidden}')
print('PASS layer3-scaffold static-python authority=webview-native-dom-row-selection-isolation-poc')
PY
fi
