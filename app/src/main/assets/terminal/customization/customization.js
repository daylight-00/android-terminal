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

  function install(layer2) {
    if (!layer2 || layer2.contractVersion !== 1 ||
        !layer2.terminal || typeof layer2.onPlatformState !== 'function') {
      throw new Error('Layer 2 customization capability is unavailable.');
    }

    return layer2.onPlatformState((state) => {
      layer2.terminal.options.theme = state.colorScheme === 'light' ? lightTheme : darkTheme;
      layer2.requestGeometrySync();
    });
  }

  const installation = install(window.AndroidTerminalLayer2);
  window.AndroidTerminalCustomization = Object.freeze({
    contractVersion: 1,
    installation
  });
})();
