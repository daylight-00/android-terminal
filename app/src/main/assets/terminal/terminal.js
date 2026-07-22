(() => {
  'use strict';

  const status = document.getElementById('status');
  const container = document.getElementById('terminal');

  window.addEventListener('error', (event) => {
    fail(`Terminal script error: ${event.message || 'unknown error'}`);
  });
  window.addEventListener('unhandledrejection', (event) => {
    const reason = event.reason instanceof Error ? event.reason.message : String(event.reason);
    fail(`Terminal promise error: ${reason}`);
  });

  function fail(message) {
    status.textContent = message;
    status.classList.remove('hidden');
  }

  if (typeof window.Terminal !== 'function' ||
      !window.FitAddon || typeof window.FitAddon.FitAddon !== 'function') {
    fail('Pinned xterm.js assets are not provisioned.\nRun tools/acquire-web-terminal-assets.sh before building.');
    return;
  }

  const terminal = new window.Terminal({
    allowProposedApi: false,
    convertEol: false,
    cursorBlink: true,
    cursorStyle: 'block',
    disableStdin: false,
    fontFamily: 'monospace',
    fontSize: 15,
    letterSpacing: 0,
    lineHeight: 1.05,
    scrollback: 5000,
    theme: {
      background: '#000000',
      foreground: '#e6e6e6',
      cursor: '#e6e6e6',
      cursorAccent: '#000000'
    }
  });
  const fitAddon = new window.FitAddon.FitAddon();
  terminal.loadAddon(fitAddon);
  terminal.open(container);
  fitAddon.fit();

  let nativePort = null;
  let resizeFrame = 0;
  const channelTimeout = window.setTimeout(() => {
    fail('Native terminal channel did not connect.');
  }, 5000);

  const codec = window.NativeShellCodec;
  if (!codec) {
    fail('Terminal codec is unavailable.');
    return;
  }

  function post(message) {
    if (nativePort) nativePort.postMessage(JSON.stringify(message));
  }

  function dimensions(type) {
    return {
      type,
      rows: terminal.rows,
      columns: terminal.cols,
      pixelWidth: Math.max(0, Math.floor(container.clientWidth)),
      pixelHeight: Math.max(0, Math.floor(container.clientHeight))
    };
  }

  function scheduleResize() {
    if (!nativePort || resizeFrame) return;
    resizeFrame = requestAnimationFrame(() => {
      resizeFrame = 0;
      fitAddon.fit();
      post(dimensions('resize'));
    });
  }

  terminal.onData((data) => {
    post({type: 'input', data: codec.stringToUtf8Base64(data)});
  });

  terminal.onBinary((data) => {
    const bytes = new Uint8Array(data.length);
    for (let index = 0; index < data.length; index += 1) {
      bytes[index] = data.charCodeAt(index) & 0xff;
    }
    post({type: 'input', data: codec.bytesToBase64(bytes)});
  });

  new ResizeObserver(scheduleResize).observe(container);
  window.addEventListener('resize', scheduleResize, {passive: true});

  function handleNativeChannel(event) {
    if (event.data !== 'native-shell' || !event.ports || !event.ports[0]) return;
    window.removeEventListener('message', handleNativeChannel);
    window.clearTimeout(channelTimeout);
    nativePort = event.ports[0];
    nativePort.onmessage = (nativeEvent) => {
      let message;
      try {
        message = JSON.parse(nativeEvent.data);
      } catch (_) {
        fail('Invalid native terminal message.');
        return;
      }
      switch (message.type) {
        case 'output':
          terminal.write(codec.base64ToBytes(message.data), () => {
            post({type: 'ack', seq: message.seq});
          });
          break;
        case 'exit':
          terminal.write(`\r\n[process exited ${message.code}]\r\n`);
          break;
        case 'error':
          terminal.write(`\r\n[native error: ${message.message}]\r\n`);
          break;
      }
    };
    nativePort.start();
    status.classList.add('hidden');
    terminal.focus();
    fitAddon.fit();
    post(dimensions('ready'));
  }

  window.addEventListener('message', handleNativeChannel);
})();
