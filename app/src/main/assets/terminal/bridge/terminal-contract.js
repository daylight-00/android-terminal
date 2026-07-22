(() => {
  'use strict';

  const messages = Object.freeze({
    ready: 'ready',
    input: 'input',
    resize: 'resize',
    ack: 'ack',
    platformRequest: 'platform-request',
    attached: 'attached',
    output: 'output',
    state: 'state',
    geometry: 'geometry',
    platformState: 'platform-state',
    platformResult: 'platform-result',
    error: 'error'
  });

  const platformOperations = Object.freeze({
    clipboardRead: 'clipboard-read',
    clipboardWrite: 'clipboard-write',
    openExternalUri: 'open-external-uri',
    bell: 'bell'
  });

  window.AndroidTerminalContract = Object.freeze({
    protocolVersion: 4,
    channelMarker: 'native-shell',
    messages,
    platformOperations,
    requiredNativeCapabilities: Object.freeze([
      'android-window-geometry',
      'android-clipboard',
      'android-external-uri',
      'android-haptic-bell',
      'android-system-theme',
      'android-accessibility-state',
      'android-hardware-keyboard-state'
    ]),
    pageCapabilities: Object.freeze([
      'xterm-core',
      'binary-input',
      'fit',
      'output-ack',
      'session-attach-v2',
      'geometry-dedup-v1',
      'platform-bridge-v1'
    ])
  });
})();
