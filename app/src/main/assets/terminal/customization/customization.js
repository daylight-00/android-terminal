(() => {
  'use strict';

  const darkTheme = Object.freeze({
    background: '#000000',
    foreground: '#e6e6e6',
    cursor: '#e6e6e6',
    cursorAccent: '#000000',
    selectionBackground: '#5c5c5c'
  });

  const lightTheme = Object.freeze({
    background: '#fafafa',
    foreground: '#161616',
    cursor: '#161616',
    cursorAccent: '#fafafa',
    selectionBackground: '#b7c9e2'
  });

  const terminalOptions = Object.freeze({
    allowProposedApi: false,
    convertEol: false,
    cursorBlink: true,
    cursorStyle: 'block',
    disableStdin: false,
    fontFamily: 'monospace',
    fontSize: 15,
    letterSpacing: 0,
    lineHeight: 1.05,
    screenReaderMode: false,
    scrollback: 5000,
    theme: darkTheme
  });

  const platformPolicy = Object.freeze({
    followSystemTheme: true,
    followAccessibilityState: true,
    allowedExternalUriSchemes: Object.freeze(['http:', 'https:'])
  });

  const messages = Object.freeze({
    loading: 'Loading terminal…',
    missingUpstream: 'Pinned xterm.js assets are not provisioned.\nRun tools/acquire-web-terminal-assets.sh before building.',
    missingCodec: 'Terminal codec is unavailable.',
    missingContract: 'Terminal bridge contract is unavailable.',
    channelTimeout: 'Native terminal channel did not connect.',
    invalidNativeMessage: 'Invalid native terminal message.',
    incompatibleNativeMessage: 'Native terminal protocol version is incompatible.',
    invalidAttachment: 'Native terminal attachment is invalid.',
    replayUnavailable: '[earlier terminal output is unavailable after frontend reconnection]'
  });

  function isExternalUriAllowed(value) {
    try {
      const parsed = new URL(String(value));
      return platformPolicy.allowedExternalUriSchemes.includes(parsed.protocol) &&
        parsed.username === '' && parsed.password === '' && parsed.hostname !== '';
    } catch (_) {
      return false;
    }
  }

  function applyPlatformState(context) {
    const terminal = context && context.terminal;
    const state = context && context.state;
    if (!terminal || !state) return;

    if (platformPolicy.followSystemTheme) {
      terminal.options.theme = state.colorScheme === 'light' ? lightTheme : darkTheme;
    }
    if (platformPolicy.followAccessibilityState) {
      terminal.options.screenReaderMode = Boolean(
        state.accessibilityEnabled && state.touchExplorationEnabled
      );
    }
  }

  function mount(context) {
    const root = context && context.root;
    if (!root) throw new Error('The custom UI root is missing');
    root.replaceChildren();
  }

  window.TerminalCustomization = Object.freeze({
    contractVersion: 2,
    terminalOptions,
    platformPolicy,
    messages,
    isExternalUriAllowed,
    applyPlatformState,
    mount
  });
})();
