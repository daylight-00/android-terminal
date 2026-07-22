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
    geometry: 'geometry',
    error: 'error'
  });

  window.AndroidTerminalContract = Object.freeze({
    protocolVersion: 3,
    channelMarker: 'native-shell',
    messages,
    pageCapabilities: Object.freeze([
      'xterm-core',
      'binary-input',
      'fit',
      'output-ack',
      'session-attach-v2',
      'geometry-dedup-v1'
    ])
  });
})();
