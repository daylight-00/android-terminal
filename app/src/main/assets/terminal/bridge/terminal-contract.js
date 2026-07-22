(() => {
  'use strict';

  const messages = Object.freeze({
    ready: 'ready',
    input: 'input',
    resize: 'resize',
    ack: 'ack',
    attached: 'attached',
    output: 'output',
    state: 'state',
    error: 'error'
  });

  window.AndroidTerminalContract = Object.freeze({
    protocolVersion: 2,
    channelMarker: 'native-shell',
    messages,
    pageCapabilities: Object.freeze([
      'xterm-core',
      'binary-input',
      'fit',
      'output-ack',
      'session-attach-v2'
    ])
  });
})();
