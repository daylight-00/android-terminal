(() => {
  'use strict';

  const messages = Object.freeze({
    ready: 'ready',
    input: 'input',
    resize: 'resize',
    ack: 'ack',
    platformRequest: 'platform-request',
    sessionTitle: 'session-title',
    snapshot: 'snapshot',
    restoreAck: 'restore-ack',
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
    bell: 'bell',
    documentImport: 'document-import',
    documentExport: 'document-export'
  });

  window.AndroidTerminalContract = Object.freeze({
    protocolVersion: 6,
    channelMarker: 'native-shell',
    serializedSnapshotMaxBytes: 8 * 1024 * 1024,
    messages,
    platformOperations,
    requiredNativeCapabilities: Object.freeze([
      'android-window-geometry',
      'android-clipboard',
      'android-external-uri',
      'android-haptic-bell',
      'android-system-theme',
      'android-accessibility-state',
      'android-localized-xterm-strings',
      'android-hardware-keyboard-state',
      'android-font-scale-state',
      'android-document-transport',
      'android-shared-storage-direct-path',
      'xterm-serialized-state'
    ]),
    pageCapabilities: Object.freeze([
      'xterm-core',
      'binary-input',
      'fit',
      'output-ack',
      'session-attach-v2',
      'geometry-dedup-v1',
      'platform-bridge-v2',
      'android-font-scale-v1',
      'web-links-v1',
      'document-transport-v1',
      'serialize-state-v1',
      'webgl-renderer-fallback-v1',
      'layer3-scaffold-v1',
      'session-title-state-v1',
      'localized-xterm-strings-v1',
      'safe-window-reports-v1',
      'stable-addon-wave-v1',
      'login-shell-v1',
      'layer2-completion-v1'
    ])
  });
})();
