(() => {
  'use strict';

  const container = document.getElementById('terminal');
  const status = document.getElementById('status');
  const contract = window.AndroidTerminalContract;
  const platformIntegration = window.AndroidTerminalPlatformIntegration;
  const codec = window.NativeShellCodec;
  const renderer = window.AndroidTerminalRenderer;
  const messages = Object.freeze({
    loading: 'Loading terminal…',
    missingUpstream: 'Pinned xterm.js assets are not provisioned.\nRun tools/acquire-web-terminal-assets.sh before building.',
    missingCodec: 'Terminal codec is unavailable.',
    missingContract: 'Terminal bridge contract is unavailable.',
    channelTimeout: 'Native terminal channel did not connect.',
    invalidNativeMessage: 'Invalid native terminal message.',
    incompatibleNativeMessage: 'Native terminal protocol version is incompatible.',
    invalidAttachment: 'Native terminal attachment is invalid.',
    replayUnavailable: '[earlier terminal output is unavailable after frontend reconnection]'
  });

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

  if (!contract || contract.protocolVersion !== 6 || !contract.messages || !contract.platformOperations) {
    fail(message('missingContract', 'Terminal bridge contract is unavailable.'));
    return;
  }
  if (!platformIntegration || platformIntegration.contractVersion !== 4) {
    fail('Android terminal platform integration is unavailable.');
    return;
  }
  if (!codec) {
    fail(message('missingCodec', 'Terminal codec is unavailable.'));
    return;
  }
  if (!renderer || typeof renderer.create !== 'function') {
    fail('Terminal renderer controller is unavailable.');
    return;
  }
  if (typeof window.Terminal !== 'function' ||
      !window.FitAddon || typeof window.FitAddon.FitAddon !== 'function' ||
      !window.SerializeAddon || typeof window.SerializeAddon.SerializeAddon !== 'function' ||
      !window.ClipboardAddon || typeof window.ClipboardAddon.ClipboardAddon !== 'function' ||
      !window.ImageAddon || typeof window.ImageAddon.ImageAddon !== 'function' ||
      !window.ProgressAddon || typeof window.ProgressAddon.ProgressAddon !== 'function' ||
      !window.SearchAddon || typeof window.SearchAddon.SearchAddon !== 'function' ||
      !window.Unicode11Addon || typeof window.Unicode11Addon.Unicode11Addon !== 'function' ||
      !window.WebFontsAddon || typeof window.WebFontsAddon.WebFontsAddon !== 'function' ||
      !window.WebLinksAddon || typeof window.WebLinksAddon.WebLinksAddon !== 'function' ||
      !window.WebglAddon || typeof window.WebglAddon.WebglAddon !== 'function') {
    fail(message('missingUpstream', 'Pinned xterm.js assets are not provisioned.'));
    return;
  }

  const terminal = new window.Terminal({allowProposedApi: true});
  const fitAddon = new window.FitAddon.FitAddon();
  const serializeAddon = new window.SerializeAddon.SerializeAddon();
  const imageAddon = new window.ImageAddon.ImageAddon();
  const progressAddon = new window.ProgressAddon.ProgressAddon();
  const searchAddon = new window.SearchAddon.SearchAddon();
  const unicode11Addon = new window.Unicode11Addon.Unicode11Addon();
  const webFontsAddon = new window.WebFontsAddon.WebFontsAddon();
  terminal.loadAddon(fitAddon);
  terminal.loadAddon(serializeAddon);
  terminal.loadAddon(imageAddon);
  terminal.loadAddon(progressAddon);
  terminal.loadAddon(searchAddon);
  terminal.loadAddon(unicode11Addon);
  terminal.loadAddon(webFontsAddon);
  terminal.open(container);

  const rendererController = renderer.create({
    terminal,
    WebglAddon: window.WebglAddon,
    onStateChange(state) {
      if (state.reason === 'context-loss' || state.reason === 'activation-failed') {
        scheduleGeometry();
      }
    }
  });
  rendererController.activate();

  let nativePort = null;
  let geometryFrame = 0;
  let readySent = false;
  let lastPostedGeometry = '';
  let connectionGeneration = 0;
  let sessionId = '';
  let nextPlatformRequestId = 1;
  let lastPlatformState = null;
  let snapshotTimer = 0;
  let lastAppliedSequence = 0;
  let lastSnapshotSequence = -1;
  let restoringSnapshot = false;
  const pendingPlatformRequests = new Map();
  const platformStateListeners = new Set();
  const titleStateListeners = new Set();
  const progressStateListeners = new Set();
  let lastTitleState = '';
  let lastProgressState = Object.freeze({state: 0, value: 0});
  let ligaturesAddon = null;
  let ligaturesActivation = null;
  const MAX_PENDING_PLATFORM_REQUESTS = 16;
  const MAX_SNAPSHOT_BASE64_CHARACTERS = Math.ceil(contract.serializedSnapshotMaxBytes / 3) * 4;
  const SNAPSHOT_DELAY_MILLIS = 200;
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

  function flushSnapshot() {
    if (snapshotTimer) {
      window.clearTimeout(snapshotTimer);
      snapshotTimer = 0;
    }
    if (!isAttached() || restoringSnapshot || lastAppliedSequence === lastSnapshotSequence) {
      return false;
    }
    const serialized = serializeAddon.serialize();
    const data = codec.stringToUtf8Base64(serialized);
    if (data.length > MAX_SNAPSHOT_BASE64_CHARACTERS) {
      console.warn('Serialized terminal state exceeds the bounded Layer 2 snapshot limit.');
      return false;
    }
    const sent = post({
      type: contract.messages.snapshot,
      throughSequence: lastAppliedSequence,
      data
    });
    if (sent) lastSnapshotSequence = lastAppliedSequence;
    return sent;
  }

  function scheduleSnapshot() {
    if (snapshotTimer || !isAttached() || restoringSnapshot) return;
    snapshotTimer = window.setTimeout(() => {
      snapshotTimer = 0;
      flushSnapshot();
    }, SNAPSHOT_DELAY_MILLIS);
  }

  window.AndroidTerminalBridge = Object.freeze({
    flushSnapshot,
    getRendererState() { return rendererController.getState(); },
    getWindowOperations() { return windowOperations; }
  });

  function requestPlatform(operation, payload = {}, timeoutMillis = 5000) {
    if (!isAttached()) return Promise.reject(new Error('Native terminal platform is not attached.'));
    if (pendingPlatformRequests.size >= MAX_PENDING_PLATFORM_REQUESTS) {
      return Promise.reject(new Error('Too many pending Android platform requests.'));
    }
    const requestId = `platform-${nextPlatformRequestId++}`;
    return new Promise((resolve, reject) => {
      const timeout = window.setTimeout(() => {
        pendingPlatformRequests.delete(requestId);
        reject(new Error(`Android platform request timed out: ${operation}`));
      }, timeoutMillis);
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
      if (!platformIntegration.isExternalUriAllowed(uri)) {
        return Promise.reject(new Error('External URI is blocked by terminal policy.'));
      }
      return requestPlatform(contract.platformOperations.openExternalUri, {uri: String(uri)});
    },
    bell() {
      return requestPlatform(contract.platformOperations.bell);
    },
    showSoftInput() {
      return requestPlatform(contract.platformOperations.softInputShow);
    },
    importDocument(options = {}) {
      const mimeType = options && typeof options.mimeType === 'string' ? options.mimeType : '*/*';
      const destinationDirectory = options && typeof options.destinationDirectory === 'string'
        ? options.destinationDirectory : '';
      return requestPlatform(
        contract.platformOperations.documentImport,
        {mimeType, destinationDirectory},
        10 * 60 * 1000
      );
    },
    exportDocument(path, options = {}) {
      if (typeof path !== 'string' || path === '') {
        return Promise.reject(new Error('A HOME-relative export path is required.'));
      }
      const payload = {path};
      if (options && typeof options.suggestedName === 'string') {
        payload.suggestedName = options.suggestedName;
      }
      if (options && typeof options.mimeType === 'string') {
        payload.mimeType = options.mimeType;
      }
      return requestPlatform(
        contract.platformOperations.documentExport,
        payload,
        10 * 60 * 1000
      );
    },
    getState() {
      return lastPlatformState ? {...lastPlatformState} : null;
    }
  });
  window.AndroidTerminalPlatform = platform;

  function onPlatformState(listener) {
    if (typeof listener !== 'function') {
      throw new TypeError('A Layer 3 platform-state listener must be a function.');
    }
    platformStateListeners.add(listener);
    if (lastPlatformState) listener({...lastPlatformState});
    let active = true;
    return Object.freeze({
      dispose() {
        if (!active) return;
        active = false;
        platformStateListeners.delete(listener);
      }
    });
  }

  function boundedTitle(value) {
    return Array.from(String(value || ''))
      .filter((character) => {
        const codePoint = character.codePointAt(0);
        return codePoint >= 0x20 && codePoint !== 0x7f;
      })
      .slice(0, 1024)
      .join('');
  }

  function updateTitleState(value, publishToNative) {
    const title = boundedTitle(value);
    if (title === lastTitleState) return false;
    lastTitleState = title;
    if (publishToNative) {
      post({type: contract.messages.sessionTitle, title});
    }
    for (const listener of [...titleStateListeners]) {
      try {
        listener(title);
      } catch (error) {
        console.error('Layer 3 title-state listener failed.', error);
      }
    }
    return true;
  }

  function onTitleState(listener) {
    if (typeof listener !== 'function') {
      throw new TypeError('A Layer 3 title-state listener must be a function.');
    }
    titleStateListeners.add(listener);
    listener(lastTitleState);
    let active = true;
    return Object.freeze({
      dispose() {
        if (!active) return;
        active = false;
        titleStateListeners.delete(listener);
      }
    });
  }

  const clipboardProvider = Object.freeze({
    readText(_selection) {
      return requestPlatform(contract.platformOperations.clipboardRead).then((result) => (
        result && typeof result.text === 'string' ? result.text : ''
      ));
    },
    writeText(_selection, text) {
      if (typeof text !== 'string') {
        return Promise.reject(new TypeError('OSC 52 clipboard text must be a string.'));
      }
      return requestPlatform(contract.platformOperations.clipboardWrite, {text}).then(() => undefined);
    }
  });
  terminal.loadAddon(new window.ClipboardAddon.ClipboardAddon(undefined, clipboardProvider));

  progressAddon.onChange((value) => {
    const state = Number.isInteger(value && value.state) ? Math.max(0, Math.min(4, value.state)) : 0;
    const progress = Number.isFinite(value && value.value) ? Math.max(0, Math.min(100, Math.trunc(value.value))) : 0;
    lastProgressState = Object.freeze({state, value: progress});
    for (const listener of [...progressStateListeners]) {
      try { listener(lastProgressState); } catch (error) { console.error('Layer 3 progress listener failed.', error); }
    }
  });

  function onProgressState(listener) {
    if (typeof listener !== 'function') throw new TypeError('A progress listener must be a function.');
    progressStateListeners.add(listener);
    listener(lastProgressState);
    let active = true;
    return Object.freeze({dispose() { if (!active) return; active = false; progressStateListeners.delete(listener); }});
  }

  const search = Object.freeze({
    findNext(term, options) { return searchAddon.findNext(String(term), options); },
    findPrevious(term, options) { return searchAddon.findPrevious(String(term), options); },
    clearDecorations() { if (typeof searchAddon.clearDecorations === 'function') searchAddon.clearDecorations(); },
    clearActiveDecoration() { if (typeof searchAddon.clearActiveDecoration === 'function') searchAddon.clearActiveDecoration(); },
    onResult(listener) {
      if (typeof searchAddon.onDidChangeResults !== 'function') {
        return Object.freeze({dispose() {}});
      }
      return searchAddon.onDidChangeResults(listener);
    }
  });

  const unicode = Object.freeze({
    get activeVersion() { return terminal.unicode.activeVersion; },
    get versions() { return Object.freeze([...terminal.unicode.versions]); },
    setActiveVersion(version) {
      const requested = String(version);
      if (!terminal.unicode.versions.includes(requested)) throw new RangeError('Unsupported Unicode provider.');
      terminal.unicode.activeVersion = requested;
      scheduleGeometry();
    }
  });

  const webFonts = Object.freeze({
    loadFonts(fonts) {
      if (fonts !== undefined && !Array.isArray(fonts)) {
        return Promise.reject(new TypeError('Web font selection must be an array when provided.'));
      }
      return webFontsAddon.loadFonts(fonts).then(() => { scheduleGeometry(); });
    },
    relayout() { return webFontsAddon.relayout().then(() => { scheduleGeometry(); }); }
  });

  function resolveLigaturesModule(timeoutMillis = 5000) {
    const current = window.AndroidTerminalLigaturesLoader;
    if (current && current.ready && typeof current.ready.then === 'function') {
      return current.ready;
    }
    return new Promise((resolve, reject) => {
      let settled = false;
      const finish = () => {
        if (settled) return;
        const loader = window.AndroidTerminalLigaturesLoader;
        if (!loader || !loader.ready || typeof loader.ready.then !== 'function') return;
        settled = true;
        window.clearTimeout(timeout);
        window.removeEventListener('android-terminal-ligatures-loader-ready', finish);
        loader.ready.then(resolve, reject);
      };
      const timeout = window.setTimeout(() => {
        if (settled) return;
        settled = true;
        window.removeEventListener('android-terminal-ligatures-loader-ready', finish);
        reject(new Error('Official LigaturesAddon module did not load.'));
      }, timeoutMillis);
      window.addEventListener('android-terminal-ligatures-loader-ready', finish);
      finish();
    });
  }

  const ligatures = Object.freeze({
    enable(options) {
      if (ligaturesAddon !== null) return Promise.resolve(false);
      if (ligaturesActivation !== null) return ligaturesActivation;
      ligaturesActivation = resolveLigaturesModule().then((module) => {
        if (!module || typeof module.LigaturesAddon !== 'function') {
          throw new Error('Official LigaturesAddon export is unavailable.');
        }
        if (ligaturesAddon !== null) return false;
        ligaturesAddon = new module.LigaturesAddon(options);
        terminal.loadAddon(ligaturesAddon);
        rendererController.reactivate();
        scheduleGeometry();
        return true;
      }).finally(() => {
        ligaturesActivation = null;
      });
      return ligaturesActivation;
    },
    get enabled() { return ligaturesAddon !== null; }
  });

  const images = Object.freeze({
    get storageLimit() { return imageAddon.storageLimit; },
    get storageUsage() { return imageAddon.storageUsage; },
    getImageAtBufferCell(x, y) { return imageAddon.getImageAtBufferCell(x, y); },
    extractTileAtBufferCell(x, y) { return imageAddon.extractTileAtBufferCell(x, y); }
  });

  const windowOperations = platformIntegration.configureWindowOperations(terminal, {
    getTitle() { return lastTitleState; }
  });

  const completionManifest = Object.freeze({
    schemaVersion: 1,
    status: 'repository-complete-device-validation-pending',
    core: '@xterm/xterm@6.0.0',
    automaticAddons: Object.freeze([
      '@xterm/addon-clipboard@0.2.0',
      '@xterm/addon-fit@0.11.0',
      '@xterm/addon-image@0.9.0',
      '@xterm/addon-progress@0.2.0',
      '@xterm/addon-serialize@0.13.0',
      '@xterm/addon-web-links@0.12.0',
      '@xterm/addon-webgl@0.19.0'
    ]),
    registeredAddons: Object.freeze([
      '@xterm/addon-ligatures@0.10.0',
      '@xterm/addon-search@0.16.0',
      '@xterm/addon-unicode11@0.9.0',
      '@xterm/addon-web-fonts@0.1.0'
    ]),
    excludedAddons: Object.freeze([
      '@xterm/addon-attach',
      '@xterm/addon-unicode-graphemes'
    ]),
    webViewRequirements: Object.freeze([
      'local-origin-only',
      'webassembly-compilation-for-image-addon',
      'webgl2-with-dom-fallback',
      'webmessageport'
    ])
  });

  const completion = Object.freeze({
    manifest: completionManifest,
    snapshot() {
      return Object.freeze({
        attached: isAttached(),
        renderer: rendererController.getState(),
        rows: terminal.rows,
        columns: terminal.cols,
        title: lastTitleState,
        progress: lastProgressState,
        unicodeVersion: terminal.unicode.activeVersion,
        unicodeVersions: Object.freeze([...terminal.unicode.versions]),
        ligaturesEnabled: ligaturesAddon !== null,
        imageStorageLimit: imageAddon.storageLimit,
        imageStorageUsage: imageAddon.storageUsage,
        platformStateAvailable: lastPlatformState !== null
      });
    }
  });

  window.AndroidTerminalLayer2 = Object.freeze({
    contractVersion: 4,
    terminal,
    platform,
    search,
    unicode,
    webFonts,
    ligatures,
    images,
    completion,
    onPlatformState,
    onTitleState,
    onProgressState,
    getTitleState() {
      return lastTitleState;
    },
    getProgressState() {
      return lastProgressState;
    },
    getPlatformState() {
      return lastPlatformState ? {...lastPlatformState} : null;
    },
    requestGeometrySync() {
      scheduleGeometry();
    },
    getWindowReportState() {
      return Object.freeze({
        title: lastTitleState,
        rows: terminal.rows,
        columns: terminal.cols,
        windowOptions: {...terminal.options.windowOptions}
      });
    }
  });

  const webLinksAddon = new window.WebLinksAddon.WebLinksAddon((_event, uri) => {
    platform.openExternalUri(uri).catch(() => {});
  });
  terminal.loadAddon(webLinksAddon);

  terminal.options.linkHandler = {
    allowNonHttpProtocols: false,
    activate(_event, uri) {
      platform.openExternalUri(uri).catch(() => {});
    }
  };
  terminal.onBell(() => {
    platform.bell().catch(() => {});
  });
  terminal.onTitleChange((value) => {
    updateTitleState(value, true);
  });

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
    if (document.hidden) {
      flushSnapshot();
    } else {
      scheduleGeometry();
    }
  });
  window.addEventListener('pagehide', flushSnapshot, {passive: true});
  window.addEventListener('beforeunload', flushSnapshot, {passive: true});
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
      localeTag: typeof nativeMessage.localeTag === 'string' ? nativeMessage.localeTag : '',
      promptLabel: typeof nativeMessage.promptLabel === 'string' ? nativeMessage.promptLabel : '',
      tooMuchOutput: typeof nativeMessage.tooMuchOutput === 'string' ? nativeMessage.tooMuchOutput : '',
      hardwareKeyboardPresent: Boolean(nativeMessage.hardwareKeyboardPresent),
      fontScale: Number(nativeMessage.fontScale) || 1,
      sharedStorageAccessGranted: Boolean(nativeMessage.sharedStorageAccessGranted),
      sharedStoragePath: typeof nativeMessage.sharedStoragePath === 'string'
        ? nativeMessage.sharedStoragePath : ''
    });
    platformIntegration.applyPlatformState(terminal, lastPlatformState);
    for (const listener of [...platformStateListeners]) {
      try {
        listener({...lastPlatformState});
      } catch (error) {
        console.error('Layer 3 platform-state listener failed.', error);
      }
    }
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
        updateTitleState(nativeMessage.title, false);
        const finishAttachment = () => {
          status.classList.add('hidden');
          terminal.focus();
          scheduleGeometry();
          scheduleSnapshot();
        };
        if (nativeMessage.serializedSnapshotAvailable) {
          const throughSequence = Number(nativeMessage.serializedThroughSequence) || 0;
          const encodedSnapshot = typeof nativeMessage.serializedSnapshotData === 'string'
            ? nativeMessage.serializedSnapshotData : '';
          restoringSnapshot = true;
          terminal.write(codec.base64ToBytes(encodedSnapshot), () => {
            lastAppliedSequence = throughSequence;
            lastSnapshotSequence = throughSequence;
            restoringSnapshot = false;
            post({type: contract.messages.restoreAck, throughSequence});
            finishAttachment();
          });
          return;
        }
        lastAppliedSequence = (!nativeMessage.replayAvailable && nativeMessage.replayTruncated)
          ? Math.max(0, (Number(nativeMessage.nextSequence) || 1) - 1)
          : 0;
        lastSnapshotSequence = -1;
        if (!nativeMessage.replayAvailable && nativeMessage.replayTruncated) {
          terminal.write(`\r\n${message(
            'replayUnavailable',
            '[earlier terminal output is unavailable after frontend reconnection]'
          )}\r\n`);
        }
        finishAttachment();
        return;
      }
      if (!matchesAttachment(nativeMessage)) return;
      switch (nativeMessage.type) {
        case contract.messages.output: {
          const sequence = Number(nativeMessage.seq) || 0;
          if (sequence <= 0) break;
          if (sequence <= lastAppliedSequence) {
            post({type: contract.messages.ack, seq: sequence});
            break;
          }
          if (sequence !== lastAppliedSequence + 1) {
            fail('Native terminal output sequence is discontinuous.');
            break;
          }
          terminal.write(codec.base64ToBytes(nativeMessage.data), () => {
            lastAppliedSequence = sequence;
            post({type: contract.messages.ack, seq: sequence});
            scheduleSnapshot();
          });
          break;
        }
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
