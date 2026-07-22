(() => {
  'use strict';

  const messages = Object.freeze({
    ready: 'ready',
    input: 'input',
    resize: 'resize',
    ack: 'ack',
    output: 'output',
    exit: 'exit',
    error: 'error'
  });

  window.AndroidTerminalContract = Object.freeze({
    protocolVersion: 1,
    channelMarker: 'native-shell',
    messages,
    pageCapabilities: Object.freeze([
      'xterm-core',
      'binary-input',
      'fit',
      'output-ack'
    ])
  });
})();
