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

  if (!contract || contract.protocolVersion !== 4 || !contract.messages || !contract.platformOperations) {
    fail(message('missingContract', 'Terminal bridge contract is unavailable.'));
    return;
  }
  if (!customization || customization.contractVersion !== 2) {
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

  let nativePort = null;
  let geometryFrame = 0;
  let readySent = false;
  let lastPostedGeometry = '';
  let connectionGeneration = 0;
  let sessionId = '';
  let nextPlatformRequestId = 1;
  let lastPlatformState = null;
  const pendingPlatformRequests = new Map();
  const MAX_PENDING_PLATFORM_REQUESTS = 16;
  const channelTimeout = window.setTimeout(() => {
    fail(message('channelTimeout', 'Native terminal channel did not connect.'));
  }, 5000);

  function isAttached() {
    return nativePort !== null && connectionGeneration !== 0 && sessionId !== '';
  }

  function post(payload, attachmentRequired = true) {
    if (!nativePort || (attachmentRequired && !isAttached())) return false;
    const envelope = {
      contractVersion: contract.protocolVersion,
      ...payload
    };
    if (isAttached()) {
      envelope.connectionGeneration = connectionGeneration;
      envelope.sessionId = sessionId;
    }
    nativePort.postMessage(JSON.stringify(envelope));
    return true;
  }

  function requestPlatform(operation, payload = {}) {
    if (!isAttached()) return Promise.reject(new Error('Native terminal platform is not attached.'));
    if (pendingPlatformRequests.size >= MAX_PENDING_PLATFORM_REQUESTS) {
      return Promise.reject(new Error('Too many pending Android platform requests.'));
    }
    const requestId = `platform-${nextPlatformRequestId++}`;
    return new Promise((resolve, reject) => {
      const timeout = window.setTimeout(() => {
        pendingPlatformRequests.delete(requestId);
        reject(new Error(`Android platform request timed out: ${operation}`));
      }, 5000);
      pendingPlatformRequests.set(requestId, {resolve, reject, timeout});
      if (!post({
        type: contract.messages.platformRequest,
        requestId,
        operation,
        payload
      })) {
        window.clearTimeout(timeout);
        pendingPlatformRequests.delete(requestId);
        reject(new Error('Native terminal platform is unavailable.'));
      }
    });
  }

  const platform = Object.freeze({
    copySelection() {
      if (!terminal.hasSelection()) return Promise.resolve({copied: false, reason: 'no-selection'});
      return requestPlatform(contract.platformOperations.clipboardWrite, {
        text: terminal.getSelection()
      });
    },
    pasteClipboard() {
      return requestPlatform(contract.platformOperations.clipboardRead).then((result) => {
        const text = result && typeof result.text === 'string' ? result.text : '';
        if (text !== '') terminal.paste(text);
        return result;
      });
    },
    openExternalUri(uri) {
      if (!customization.isExternalUriAllowed(uri)) {
        return Promise.reject(new Error('External URI is blocked by terminal policy.'));
      }
      return requestPlatform(contract.platformOperations.openExternalUri, {uri: String(uri)});
    },
    bell() {
      return requestPlatform(contract.platformOperations.bell);
    },
    getState() {
      return lastPlatformState ? {...lastPlatformState} : null;
    }
  });
  window.AndroidTerminalPlatform = platform;

  terminal.options.linkHandler = {
    allowNonHttpProtocols: false,
    activate(_event, uri) {
      platform.openExternalUri(uri).catch(() => {});
    }
  };
  terminal.onBell(() => {
    platform.bell().catch(() => {});
  });

  customization.mount({root: customRoot, terminal, fitAddon, platform});

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
    return post(payload, attachmentRequired);
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

  function handlePlatformState(nativeMessage) {
    lastPlatformState = Object.freeze({
      colorScheme: nativeMessage.colorScheme === 'light' ? 'light' : 'dark',
      accessibilityEnabled: Boolean(nativeMessage.accessibilityEnabled),
      touchExplorationEnabled: Boolean(nativeMessage.touchExplorationEnabled),
      hardwareKeyboardPresent: Boolean(nativeMessage.hardwareKeyboardPresent),
      fontScale: Number(nativeMessage.fontScale) || 1
    });
    customization.applyPlatformState({terminal, state: lastPlatformState, platform});
    scheduleGeometry();
  }

  function handlePlatformResult(nativeMessage) {
    const requestId = String(nativeMessage.requestId || '');
    const pending = pendingPlatformRequests.get(requestId);
    if (!pending) return;
    pendingPlatformRequests.delete(requestId);
    window.clearTimeout(pending.timeout);
    if (nativeMessage.ok) {
      pending.resolve(nativeMessage.data && typeof nativeMessage.data === 'object'
        ? nativeMessage.data : {});
    } else {
      pending.reject(new Error(String(nativeMessage.error || 'Android platform request failed.')));
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
        if (!contract.requiredNativeCapabilities.every((value) => nativeCapabilities.includes(value))) {
          fail(message('incompatibleNativeMessage', 'Native terminal platform capabilities are incomplete.'));
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
        case contract.messages.platformState:
          handlePlatformState(nativeMessage);
          break;
        case contract.messages.platformResult:
          handlePlatformResult(nativeMessage);
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
