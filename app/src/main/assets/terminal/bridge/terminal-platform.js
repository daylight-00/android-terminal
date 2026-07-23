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

  const allowedExternalUriSchemes = Object.freeze(['http:', 'https:']);

  function isExternalUriAllowed(value) {
    try {
      const parsed = new URL(String(value));
      return allowedExternalUriSchemes.includes(parsed.protocol) &&
        parsed.username === '' && parsed.password === '' && parsed.hostname !== '';
    } catch (_) {
      return false;
    }
  }

  function applyPlatformState(terminal, state) {
    if (!terminal || !state) return;
    terminal.options.theme = state.colorScheme === 'light' ? lightTheme : darkTheme;
    terminal.options.screenReaderMode = Boolean(
      state.accessibilityEnabled && state.touchExplorationEnabled
    );
  }

  window.AndroidTerminalPlatformIntegration = Object.freeze({
    contractVersion: 1,
    isExternalUriAllowed,
    applyPlatformState
  });
})();
