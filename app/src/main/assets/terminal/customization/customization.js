(() => {
  'use strict';

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
    scrollback: 5000,
    theme: Object.freeze({
      background: '#000000',
      foreground: '#e6e6e6',
      cursor: '#e6e6e6',
      cursorAccent: '#000000'
    })
  });

  const messages = Object.freeze({
    loading: 'Loading terminal…',
    missingUpstream: 'Pinned xterm.js assets are not provisioned.\nRun tools/acquire-web-terminal-assets.sh before building.',
    missingCodec: 'Terminal codec is unavailable.',
    missingContract: 'Terminal bridge contract is unavailable.',
    channelTimeout: 'Native terminal channel did not connect.',
    invalidNativeMessage: 'Invalid native terminal message.',
    incompatibleNativeMessage: 'Native terminal protocol version is incompatible.'
  });

  function mount(context) {
    const root = context && context.root;
    if (!root) throw new Error('The custom UI root is missing');
    root.replaceChildren();
  }

  window.TerminalCustomization = Object.freeze({
    contractVersion: 1,
    terminalOptions,
    messages,
    mount
  });
})();
