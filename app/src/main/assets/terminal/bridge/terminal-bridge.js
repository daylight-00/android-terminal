(() => {
  'use strict';

  const container = document.getElementById('terminal');
  const status = document.getElementById('status');
  const customRoot = document.getElementById('custom-ui-root');
  const contract = window.AndroidTerminalContract;
  const customization = window.TerminalCustomization;
  const codec = window.NativeShellCodec;
  const messages = customization && customization.messages ? customization.messages : {};

  function message(name, fallback) {
    return typeof messages[name] === 'string' ? messages[name] : fallback;
  }

  function fail(text) {
    status.textContent = text;
    status.classList.remove('hidden');
  }

  window.addEventListener('error', (event) => {
    fail(`Terminal script error: ${event.message || 'unknown error'}`);
  });
  window.addEventListener('unhandledrejection', (event) => {
    const reason = event.reason instanceof Error ? event.reason.message : String(event.reason);
    fail(`Terminal promise error: ${reason}`);
  });

  status.textContent = message('loading', 'Loading terminal…');

  if (!contract || contract.protocolVersion !== 3 || !contract.messages) {
    fail(message('missingContract', 'Terminal bridge contract is unavailable.'));
    return;
  }
  if (!customization || customization.contractVersion !== 1) {
    fail('Terminal customization contract is unavailable.');
    return;
  }
  if (!codec) {
    fail(message('missingCodec', 'Terminal codec is unavailable.'));
    return;
  }
  if (typeof window.Terminal !== 'function' ||
      !window.FitAddon || typeof window.FitAddon.FitAddon !== 'function') {
    fail(message('missingUpstream', 'Pinned xterm.js assets are not provisioned.'));
    return;
  }

  const terminal = new window.Terminal(customization.terminalOptions);
  const fitAddon = new window.FitAddon.FitAddon();
  terminal.loadAddon(fitAddon);
  terminal.open(container);
  customization.mount({root: customRoot, terminal, fitAddon});

  let nativePort = null;
  let geometryFrame = 0;
  let readySent = false;
  let lastPostedGeometry = '';
  let connectionGeneration = 0;
  let sessionId = '';
  const channelTimeout = window.setTimeout(() => {
    fail(message('channelTimeout', 'Native terminal channel did not connect.'));
  }, 5000);

  function isAttached() {
    return nativePort !== null && connectionGeneration !== 0 && sessionId !== '';
  }

  function post(payload, attachmentRequired = true) {
    if (!nativePort || (attachmentRequired && !isAttached())) return;
    const envelope = {
      contractVersion: contract.protocolVersion,
      ...payload
    };
    if (isAttached()) {
      envelope.connectionGeneration = connectionGeneration;
      envelope.sessionId = sessionId;
    }
    nativePort.postMessage(JSON.stringify(envelope));
  }

  function measureGeometry(type) {
    const pixelWidth = Math.floor(container.clientWidth);
    const pixelHeight = Math.floor(container.clientHeight);
    if (pixelWidth <= 0 || pixelHeight <= 0) return null;

    fitAddon.fit();
    const rows = Number(terminal.rows) || 0;
    const columns = Number(terminal.cols) || 0;
    if (rows <= 0 || columns <= 0) return null;

    return {type, rows, columns, pixelWidth, pixelHeight};
  }

  function geometryKey(geometry) {
    return `${geometry.rows}:${geometry.columns}:${geometry.pixelWidth}:${geometry.pixelHeight}`;
  }

  function postMeasuredGeometry(type, attachmentRequired) {
    const geometry = measureGeometry(type);
    if (!geometry) return false;
    const key = geometryKey(geometry);
    if (type === contract.messages.resize && key === lastPostedGeometry) return false;
    lastPostedGeometry = key;
    const payload = type === contract.messages.ready
      ? {...geometry, capabilities: contract.pageCapabilities}
      : geometry;
    post(payload, attachmentRequired);
    return true;
  }

  function flushGeometry() {
    if (!nativePort) return;
    if (!readySent) {
      readySent = postMeasuredGeometry(contract.messages.ready, false);
      return;
    }
    if (isAttached()) postMeasuredGeometry(contract.messages.resize, true);
  }

  function scheduleGeometry() {
    if (geometryFrame) return;
    geometryFrame = window.requestAnimationFrame(() => {
      geometryFrame = 0;
      flushGeometry();
    });
  }

  terminal.onData((data) => {
    post({type: contract.messages.input, data: codec.stringToUtf8Base64(data)});
  });

  terminal.onBinary((data) => {
    const bytes = new Uint8Array(data.length);
    for (let index = 0; index < data.length; index += 1) {
      bytes[index] = data.charCodeAt(index) & 0xff;
    }
    post({type: contract.messages.input, data: codec.bytesToBase64(bytes)});
  });

  new ResizeObserver(scheduleGeometry).observe(container);
  window.addEventListener('resize', scheduleGeometry, {passive: true});
  window.addEventListener('pageshow', scheduleGeometry, {passive: true});
  window.addEventListener('focus', scheduleGeometry, {passive: true});
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) scheduleGeometry();
  });
  if (window.visualViewport && typeof window.visualViewport.addEventListener === 'function') {
    window.visualViewport.addEventListener('resize', scheduleGeometry, {passive: true});
  }

  function matchesAttachment(nativeMessage) {
    return nativeMessage.connectionGeneration === connectionGeneration &&
      nativeMessage.sessionId === sessionId;
  }

  function renderState(nativeMessage) {
    switch (nativeMessage.state) {
      case 'exited':
        terminal.write(`\r\n[process exited ${nativeMessage.exitCode}]\r\n`);
        break;
      case 'failed':
        terminal.write(`\r\n[native error: ${nativeMessage.failure || 'session failed'}]\r\n`);
        break;
      case 'closed':
        terminal.write('\r\n[session closed]\r\n');
        break;
    }
  }

  function handleNativeChannel(event) {
    if (event.data !== contract.channelMarker || !event.ports || !event.ports[0]) return;
    window.removeEventListener('message', handleNativeChannel);
    window.clearTimeout(channelTimeout);
    nativePort = event.ports[0];
    nativePort.onmessage = (nativeEvent) => {
      let nativeMessage;
      try {
        nativeMessage = JSON.parse(nativeEvent.data);
      } catch (_) {
        fail(message('invalidNativeMessage', 'Invalid native terminal message.'));
        return;
      }
      if (nativeMessage.contractVersion !== contract.protocolVersion) {
        fail(message('incompatibleNativeMessage', 'Native terminal protocol version is incompatible.'));
        return;
      }
      if (nativeMessage.type === contract.messages.attached) {
        connectionGeneration = Number(nativeMessage.connectionGeneration) || 0;
        sessionId = String(nativeMessage.sessionId || '');
        if (!isAttached()) {
          fail(message('invalidAttachment', 'Native terminal attachment is invalid.'));
          return;
        }
        const nativeCapabilities = Array.isArray(nativeMessage.nativeCapabilities)
          ? nativeMessage.nativeCapabilities : [];
        if (!nativeCapabilities.includes('android-window-geometry')) {
          fail(message('incompatibleNativeMessage', 'Native terminal geometry capability is unavailable.'));
          return;
        }
        if (!nativeMessage.replayAvailable && nativeMessage.replayTruncated) {
          terminal.write(`\r\n${message(
            'replayUnavailable',
            '[earlier terminal output is unavailable after frontend reconnection]'
          )}\r\n`);
        }
        status.classList.add('hidden');
        terminal.focus();
        scheduleGeometry();
        return;
      }
      if (!matchesAttachment(nativeMessage)) return;
      switch (nativeMessage.type) {
        case contract.messages.output:
          terminal.write(codec.base64ToBytes(nativeMessage.data), () => {
            post({type: contract.messages.ack, seq: nativeMessage.seq});
          });
          break;
        case contract.messages.state:
          renderState(nativeMessage);
          break;
        case contract.messages.geometry:
          scheduleGeometry();
          break;
        case contract.messages.error:
          terminal.write(`\r\n[native error: ${nativeMessage.message}]\r\n`);
          break;
      }
    };
    nativePort.start();
    scheduleGeometry();
  }

  window.addEventListener('message', handleNativeChannel);
})();
