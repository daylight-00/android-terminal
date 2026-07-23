#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PLATFORM="$ROOT/app/src/main/assets/terminal/bridge/terminal-platform.js"

if command -v node >/dev/null 2>&1; then
  node - "$PLATFORM" <<'JS'
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync(process.argv[2], 'utf8');
const context = vm.createContext({URL, window: {}});
vm.runInContext(source, context, {filename: 'terminal-platform.js'});
const integration = context.window.AndroidTerminalPlatformIntegration;
if (!integration || integration.contractVersion !== 2) {
  throw new Error('font-scale platform contract is unavailable');
}

function terminalWithUpstreamDefault(fontSize) {
  return {options: {fontSize, theme: null, screenReaderMode: false}};
}

const terminal = terminalWithUpstreamDefault(15);
integration.applyPlatformState(terminal, {
  colorScheme: 'dark',
  accessibilityEnabled: false,
  touchExplorationEnabled: false,
  fontScale: 1.5
});
if (terminal.options.fontSize !== 22.5) throw new Error('Android font scale was not applied');

integration.applyPlatformState(terminal, {
  colorScheme: 'light',
  accessibilityEnabled: true,
  touchExplorationEnabled: true,
  fontScale: 2
});
if (terminal.options.fontSize !== 30) throw new Error('font scale compounded instead of using the upstream baseline');
if (!terminal.options.screenReaderMode) throw new Error('accessibility mapping regressed');
if (terminal.options.theme.background !== '#fafafa') throw new Error('theme mapping regressed');

integration.applyPlatformState(terminal, {fontScale: 0.1});
if (terminal.options.fontSize !== 7.5) throw new Error('minimum Android font scale bound failed');
integration.applyPlatformState(terminal, {fontScale: 9});
if (terminal.options.fontSize !== 45) throw new Error('maximum Android font scale bound failed');
integration.applyPlatformState(terminal, {fontScale: Number.NaN});
if (terminal.options.fontSize !== 15) throw new Error('invalid Android font scale did not restore the upstream baseline');

const upgradedUpstream = terminalWithUpstreamDefault(17);
integration.applyPlatformState(upgradedUpstream, {fontScale: 2});
if (upgradedUpstream.options.fontSize !== 34) {
  throw new Error('mapping hard-coded an xterm.js font size instead of consuming the upstream default');
}

console.log('PASS terminal-font-scale upstream-default=preserved android-scale=bounded geometry=public-option');
JS
else
  python3 - "$PLATFORM" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding='utf-8')
for token in (
    'const upstreamFontSizes = new WeakMap()',
    'const MIN_ANDROID_FONT_SCALE = 0.5',
    'const MAX_ANDROID_FONT_SCALE = 3.0',
    'Number(terminal.options.fontSize)',
    'upstreamFontSizes.get(terminal) * boundedFontScale(value)',
    'applyFontScale(terminal, state.fontScale)',
    'contractVersion: 2',
):
    if token not in source:
        raise SystemExit(f'missing font-scale mapping token: {token}')
print('PASS terminal-font-scale static-python node=unavailable upstream-default=preserved')
PY
fi
