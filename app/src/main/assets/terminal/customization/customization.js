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

  const MIN_ANDROID_FONT_SCALE = 0.5;
  const MAX_ANDROID_FONT_SCALE = 3.0;
  const MIN_USER_FONT_SCALE = 0.5;
  const MAX_USER_FONT_SCALE = 3.0;
  const PINCH_STEP_RATIO = 0.1;
  const FONT_SIZE_STEP_PIXELS = 1;

  function boundedScale(value, minimum, maximum) {
    const scale = Number(value);
    if (!Number.isFinite(scale) || scale <= 0) return 1;
    return Math.min(maximum, Math.max(minimum, scale));
  }

  function touchDistance(touches) {
    if (!touches || touches.length < 2) return 0;
    const first = touches[0];
    const second = touches[1];
    return Math.hypot(
      Number(second.clientX) - Number(first.clientX),
      Number(second.clientY) - Number(first.clientY)
    );
  }

  function consumeTouch(event) {
    event.preventDefault();
    event.stopPropagation();
    if (typeof event.stopImmediatePropagation === 'function') {
      event.stopImmediatePropagation();
    }
  }

  function install(layer2) {
    if (!layer2 || layer2.contractVersion !== 4 ||
        !layer2.terminal || !layer2.completion ||
        !layer2.completion.manifest || layer2.completion.manifest.schemaVersion !== 1 ||
        typeof layer2.onPlatformState !== 'function' ||
        typeof layer2.requestGeometrySync !== 'function' ||
        typeof layer2.useDomRenderer !== 'function') {
      throw new Error('Layer 2 native-selection capability is unavailable.');
    }

    const terminalElement = document.getElementById('terminal');
    const xtermElement = layer2.terminal.element;
    if (!terminalElement || !xtermElement || !xtermElement.classList) {
      throw new Error('Terminal native-selection surface is unavailable.');
    }

    layer2.useDomRenderer('native-touch-selection-isolation');
    xtermElement.classList.add('xterm-native-touch-selection');

    const initialState = typeof layer2.getPlatformState === 'function'
      ? layer2.getPlatformState()
      : null;
    let androidFontScale = boundedScale(
      initialState && initialState.fontScale,
      MIN_ANDROID_FONT_SCALE,
      MAX_ANDROID_FONT_SCALE
    );
    const currentFontSize = Number(layer2.terminal.options.fontSize);
    const upstreamFontSize = Number.isFinite(currentFontSize) && currentFontSize > 0
      ? currentFontSize / androidFontScale
      : 15;
    let userFontScale = 1;
    let pinchDistance = 0;
    let pinchConsumesGesture = false;
    let lastNativeTouchMillis = Number.NEGATIVE_INFINITY;
    let disposed = false;

    function isMouseTrackingActive() {
      const modes = layer2.terminal.modes;
      return Boolean(modes && modes.mouseTrackingMode && modes.mouseTrackingMode !== 'none');
    }

    function markNativeTouch() {
      lastNativeTouchMillis = Date.now();
    }

    function suppressXtermTouchSelection(event) {
      const sourceCapabilities = event && event.sourceCapabilities;
      const touchGenerated = Boolean(sourceCapabilities && sourceCapabilities.firesTouchEvents) ||
        Date.now() - lastNativeTouchMillis < 1500;
      if (!touchGenerated || isMouseTrackingActive()) return;
      // Browser default selection remains intact because preventDefault is not
      // called. Only xterm's separate mouse-selection model is suppressed.
      event.stopPropagation();
      if (typeof event.stopImmediatePropagation === 'function') {
        event.stopImmediatePropagation();
      }
    }

    function effectiveFontSize() {
      return upstreamFontSize * androidFontScale * userFontScale;
    }

    function applyAppearance(state) {
      androidFontScale = boundedScale(
        state && state.fontScale,
        MIN_ANDROID_FONT_SCALE,
        MAX_ANDROID_FONT_SCALE
      );
      layer2.terminal.options.theme = state && state.colorScheme === 'light'
        ? lightTheme
        : darkTheme;
      layer2.terminal.options.fontSize = effectiveFontSize();
      layer2.requestGeometrySync();
    }

    function changeUserFontSize(direction) {
      const current = effectiveFontSize();
      const minimum = upstreamFontSize * androidFontScale * MIN_USER_FONT_SCALE;
      const maximum = upstreamFontSize * androidFontScale * MAX_USER_FONT_SCALE;
      const next = Math.min(
        maximum,
        Math.max(minimum, current + direction * FONT_SIZE_STEP_PIXELS)
      );
      userFontScale = next / (upstreamFontSize * androidFontScale);
      layer2.terminal.options.fontSize = next;
      layer2.requestGeometrySync();
    }

    function beginPinch(event) {
      pinchConsumesGesture = true;
      pinchDistance = touchDistance(event.touches);
      consumeTouch(event);
    }

    function onTouchStart(event) {
      markNativeTouch();
      if (event.touches.length >= 2 || pinchConsumesGesture) {
        beginPinch(event);
      }
      // Every one-finger touch remains entirely WebView-owned. There is no
      // threshold handoff to JavaScript scrolling in this isolation POC.
    }

    function onTouchMove(event) {
      if (!pinchConsumesGesture && event.touches.length < 2) return;
      if (!pinchConsumesGesture) beginPinch(event);
      const currentDistance = touchDistance(event.touches);
      if (currentDistance > 0) {
        if (pinchDistance <= 0) {
          pinchDistance = currentDistance;
        } else if (currentDistance >= pinchDistance * (1 + PINCH_STEP_RATIO)) {
          changeUserFontSize(1);
          pinchDistance = currentDistance;
        } else if (currentDistance <= pinchDistance * (1 - PINCH_STEP_RATIO)) {
          changeUserFontSize(-1);
          pinchDistance = currentDistance;
        }
      }
      consumeTouch(event);
    }

    function onTouchEnd(event) {
      if (!pinchConsumesGesture) return;
      consumeTouch(event);
      if (event.touches.length >= 2) {
        pinchDistance = touchDistance(event.touches);
      } else if (event.touches.length === 0) {
        pinchDistance = 0;
        pinchConsumesGesture = false;
      }
    }

    function onTouchCancel(event) {
      if (!pinchConsumesGesture) return;
      pinchDistance = 0;
      pinchConsumesGesture = false;
      consumeTouch(event);
    }

    const touchOptions = Object.freeze({capture: true, passive: false});
    const mouseCaptureOptions = true;
    xtermElement.addEventListener('mousedown', suppressXtermTouchSelection, mouseCaptureOptions);
    terminalElement.addEventListener('touchstart', onTouchStart, touchOptions);
    terminalElement.addEventListener('touchmove', onTouchMove, touchOptions);
    terminalElement.addEventListener('touchend', onTouchEnd, touchOptions);
    terminalElement.addEventListener('touchcancel', onTouchCancel, touchOptions);

    const platformSubscription = layer2.onPlatformState(applyAppearance);

    return Object.freeze({
      dispose() {
        if (disposed) return;
        disposed = true;
        platformSubscription.dispose();
        xtermElement.removeEventListener('mousedown', suppressXtermTouchSelection, mouseCaptureOptions);
        terminalElement.removeEventListener('touchstart', onTouchStart, touchOptions);
        terminalElement.removeEventListener('touchmove', onTouchMove, touchOptions);
        terminalElement.removeEventListener('touchend', onTouchEnd, touchOptions);
        terminalElement.removeEventListener('touchcancel', onTouchCancel, touchOptions);
        xtermElement.classList.remove('xterm-native-touch-selection');
      },
      getState() {
        return Object.freeze({
          androidFontScale,
          userFontScale,
          effectiveFontSize: Number(layer2.terminal.options.fontSize),
          pinchConsumesGesture,
          selectionAuthority: 'webview-native-dom-row-selection-isolation-poc',
          selectionHandles: 'webview-native-if-supported',
          copyAuthority: 'webview-native-if-row-selection-succeeds',
          pasteAuthority: 'none-in-row-selection-isolation',
          rendererAuthority: 'xterm-dom-renderer',
          scrollAuthority: 'webview-native-overflow-isolation',
          touchActivationAuthority: 'webview-default-one-finger-complete-ownership',
          touchSurfaceAvailable: true
        });
      }
    });
  }

  const installation = install(window.AndroidTerminalLayer2);
  window.AndroidTerminalCustomization = Object.freeze({
    contractVersion: 3,
    installation,
    getInteractionState() {
      return installation.getState();
    }
  });
})();
