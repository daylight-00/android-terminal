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
  const SCROLL_START_THRESHOLD_PIXELS = 6;
  const SCROLL_SAMPLE_WINDOW_MILLIS = 120;
  const SCROLL_MAX_FRAME_MILLIS = 32;
  const SCROLL_FRICTION_PER_MILLISECOND = 0.006;
  const SCROLL_STOP_VELOCITY = 0.02;

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

  function findTouch(touches, identifier) {
    if (!touches) return null;
    for (let index = 0; index < touches.length; index += 1) {
      const touch = touches[index];
      if (touch && touch.identifier === identifier) return touch;
    }
    return null;
  }

  function consumeTouch(event) {
    event.preventDefault();
    event.stopPropagation();
    if (typeof event.stopImmediatePropagation === 'function') {
      event.stopImmediatePropagation();
    }
  }

  function eventTime(event) {
    const timestamp = Number(event && event.timeStamp);
    return Number.isFinite(timestamp) && timestamp >= 0 ? timestamp : Date.now();
  }

  function isScrollbarTarget(target) {
    return Boolean(
      target && typeof target.closest === 'function' &&
      target.closest('.xterm-scrollable-element > .scrollbar')
    );
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

    // Native WebView selection requires real DOM rows. The Layer 2 renderer
    // switch disposes the official WebGL addon and leaves xterm's built-in DOM
    // renderer as authority; no alternate renderer is introduced here.
    layer2.useDomRenderer('native-touch-selection');
    xtermElement.classList.add('xterm-native-touch-selection');

    const helperTextarea = layer2.terminal.textarea || null;
    const helperTextareaStyle = helperTextarea ? Object.freeze({
      opacity: helperTextarea.style.opacity,
      background: helperTextarea.style.background,
      color: helperTextarea.style.color,
      webkitTextFillColor: helperTextarea.style.webkitTextFillColor,
      caretColor: helperTextarea.style.caretColor,
      outline: helperTextarea.style.outline,
      textShadow: helperTextarea.style.textShadow,
      webkitAppearance: helperTextarea.style.webkitAppearance,
      appearance: helperTextarea.style.appearance,
      webkitUserSelect: helperTextarea.style.webkitUserSelect,
      userSelect: helperTextarea.style.userSelect,
      webkitTouchCallout: helperTextarea.style.webkitTouchCallout,
      pointerEvents: helperTextarea.style.pointerEvents,
      left: helperTextarea.style.left,
      top: helperTextarea.style.top,
      width: helperTextarea.style.width,
      height: helperTextarea.style.height,
      lineHeight: helperTextarea.style.lineHeight,
      zIndex: helperTextarea.style.zIndex
    }) : null;
    let lastNativeTouchMillis = Number.NEGATIVE_INFINITY;

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
    let scrollTouchIdentifier = null;
    let scrollStartX = 0;
    let scrollStartY = 0;
    let scrollLastY = 0;
    let scrollPixelRemainder = 0;
    let scrollConsumesGesture = false;
    let scrollSamples = [];
    let scrollAnimationFrame = 0;
    let disposed = false;

    const requestFrame = typeof window.requestAnimationFrame === 'function'
      ? (callback) => window.requestAnimationFrame(callback)
      : (callback) => window.setTimeout(() => callback(Date.now()), 16);
    const cancelFrame = typeof window.cancelAnimationFrame === 'function'
      ? (handle) => window.cancelAnimationFrame(handle)
      : (handle) => window.clearTimeout(handle);

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
      // Keep the browser default action intact while preventing xterm's own
      // bubbling selection mousedown from creating a second selection model.
      event.stopPropagation();
      if (typeof event.stopImmediatePropagation === 'function') {
        event.stopImmediatePropagation();
      }
    }

    function syncNativePasteTarget() {
      if (!helperTextarea) return false;
      const screen = terminalElement.querySelector('.xterm-screen');
      const activeBuffer = layer2.terminal.buffer && layer2.terminal.buffer.active;
      const columns = Number(layer2.terminal.cols);
      const rows = Number(layer2.terminal.rows);
      if (!screen || typeof screen.getBoundingClientRect !== 'function' ||
          !activeBuffer || !(columns > 0) || !(rows > 0)) return false;
      const rect = screen.getBoundingClientRect();
      const cellWidth = Number(rect.width) / columns;
      const cellHeight = Number(rect.height) / rows;
      const cursorX = Math.max(0, Math.min(columns - 1, Number(activeBuffer.cursorX) || 0));
      const cursorY = Math.max(0, Math.min(rows - 1, Number(activeBuffer.cursorY) || 0));
      if (!(cellWidth > 0) || !(cellHeight > 0)) return false;
      helperTextarea.style.left = `${cursorX * cellWidth}px`;
      helperTextarea.style.top = `${cursorY * cellHeight}px`;
      helperTextarea.style.width = `${Math.max(cellWidth, 80)}px`;
      helperTextarea.style.height = `${Math.max(cellHeight, 32)}px`;
      helperTextarea.style.lineHeight = `${cellHeight}px`;
      helperTextarea.style.zIndex = '10';
      return true;
    }

    function enableNativePasteTarget() {
      if (!helperTextarea) return;
      helperTextarea.style.opacity = '1';
      helperTextarea.style.background = 'transparent';
      helperTextarea.style.color = 'transparent';
      helperTextarea.style.webkitTextFillColor = 'transparent';
      helperTextarea.style.caretColor = 'transparent';
      helperTextarea.style.outline = 'none';
      helperTextarea.style.textShadow = 'none';
      helperTextarea.style.webkitAppearance = 'none';
      helperTextarea.style.appearance = 'none';
      helperTextarea.style.webkitUserSelect = 'text';
      helperTextarea.style.userSelect = 'text';
      helperTextarea.style.webkitTouchCallout = 'default';
      helperTextarea.style.pointerEvents = 'auto';
      syncNativePasteTarget();
    }

    function restoreNativePasteTarget() {
      if (!helperTextarea || !helperTextareaStyle) return;
      for (const [name, value] of Object.entries(helperTextareaStyle)) {
        helperTextarea.style[name] = value;
      }
    }

    function handleNativePaste(event) {
      if (!event || !event.clipboardData || typeof layer2.terminal.paste !== 'function') return;
      event.preventDefault();
      event.stopPropagation();
      if (typeof event.stopImmediatePropagation === 'function') {
        event.stopImmediatePropagation();
      }
      layer2.terminal.paste(event.clipboardData.getData('text/plain'));
    }

    function applyAppearance(state) {
      layer2.terminal.options.theme = state.colorScheme === 'light' ? lightTheme : darkTheme;
      androidFontScale = boundedScale(
        state.fontScale,
        MIN_ANDROID_FONT_SCALE,
        MAX_ANDROID_FONT_SCALE
      );
      layer2.terminal.options.fontSize = upstreamFontSize * androidFontScale * userFontScale;
      layer2.requestGeometrySync();
      requestFrame(syncNativePasteTarget);
    }

    function changeUserFontSize(direction) {
      const platformBase = upstreamFontSize * androidFontScale;
      const current = platformBase * userFontScale;
      const minimum = platformBase * MIN_USER_FONT_SCALE;
      const maximum = platformBase * MAX_USER_FONT_SCALE;
      const next = Math.min(maximum, Math.max(minimum, current + direction * FONT_SIZE_STEP_PIXELS));
      if (next === current) return false;
      userFontScale = next / platformBase;
      layer2.terminal.options.fontSize = next;
      layer2.requestGeometrySync();
      requestFrame(syncNativePasteTarget);
      return true;
    }

    function measureCellHeight() {
      const rows = Number(layer2.terminal.rows);
      const screen = terminalElement.querySelector('.xterm-screen');
      if (screen && typeof screen.getBoundingClientRect === 'function' && rows > 0) {
        const height = Number(screen.getBoundingClientRect().height);
        if (Number.isFinite(height) && height > 0) return height / rows;
      }
      const fontSize = Number(layer2.terminal.options.fontSize);
      const lineHeight = Number(layer2.terminal.options.lineHeight);
      return Number.isFinite(fontSize) && fontSize > 0
        ? fontSize * (Number.isFinite(lineHeight) && lineHeight > 0 ? lineHeight : 1.2)
        : 18;
    }

    function canScrollNormalBuffer() {
      if (typeof layer2.terminal.scrollLines !== 'function') return false;
      const activeBuffer = layer2.terminal.buffer && layer2.terminal.buffer.active;
      if (activeBuffer && activeBuffer.type && activeBuffer.type !== 'normal') return false;
      const modes = layer2.terminal.modes;
      return !modes || !modes.mouseTrackingMode || modes.mouseTrackingMode === 'none';
    }

    function scrollByPixels(deltaPixels) {
      if (!canScrollNormalBuffer()) return false;
      const cellHeight = measureCellHeight();
      if (!Number.isFinite(cellHeight) || cellHeight <= 0) return false;
      scrollPixelRemainder += deltaPixels;
      const rows = Math.trunc(scrollPixelRemainder / cellHeight);
      if (rows === 0) return false;
      scrollPixelRemainder -= rows * cellHeight;
      layer2.terminal.scrollLines(rows);
      return true;
    }

    function cancelScrollInertia() {
      if (!scrollAnimationFrame) return;
      cancelFrame(scrollAnimationFrame);
      scrollAnimationFrame = 0;
    }

    function recordScrollSample(time, y) {
      scrollSamples.push({time, y});
      const minimumTime = time - SCROLL_SAMPLE_WINDOW_MILLIS;
      while (scrollSamples.length > 2 && scrollSamples[0].time < minimumTime) {
        scrollSamples.shift();
      }
    }

    function resetScrollGesture(resetRemainder) {
      scrollTouchIdentifier = null;
      scrollStartX = 0;
      scrollStartY = 0;
      scrollLastY = 0;
      scrollConsumesGesture = false;
      scrollSamples = [];
      if (resetRemainder) scrollPixelRemainder = 0;
    }

    function startScrollInertia() {
      if (scrollSamples.length < 2 || !canScrollNormalBuffer()) return;
      const first = scrollSamples[0];
      const last = scrollSamples[scrollSamples.length - 1];
      const duration = last.time - first.time;
      if (!(duration > 0)) return;
      let velocity = (first.y - last.y) / duration;
      if (!Number.isFinite(velocity) || Math.abs(velocity) < SCROLL_STOP_VELOCITY) return;
      let previousTime = last.time;

      function animate(timestamp) {
        scrollAnimationFrame = 0;
        if (disposed || !canScrollNormalBuffer()) return;
        const now = Number.isFinite(Number(timestamp)) ? Number(timestamp) : Date.now();
        const elapsed = Math.min(SCROLL_MAX_FRAME_MILLIS, Math.max(1, now - previousTime));
        previousTime = now;
        scrollByPixels(velocity * elapsed);
        velocity *= Math.exp(-SCROLL_FRICTION_PER_MILLISECOND * elapsed);
        if (Math.abs(velocity) >= SCROLL_STOP_VELOCITY) {
          scrollAnimationFrame = requestFrame(animate);
        }
      }

      scrollAnimationFrame = requestFrame(animate);
    }

    function beginOneFingerGesture(event) {
      if (event.touches.length !== 1 || isScrollbarTarget(event.target) ||
          !canScrollNormalBuffer()) {
        resetScrollGesture(true);
        return;
      }
      const touch = event.touches[0];
      cancelScrollInertia();
      scrollTouchIdentifier = touch.identifier;
      scrollStartX = Number(touch.clientX);
      scrollStartY = Number(touch.clientY);
      scrollLastY = scrollStartY;
      scrollPixelRemainder = 0;
      scrollConsumesGesture = false;
      scrollSamples = [];
      recordScrollSample(eventTime(event), scrollStartY);
      // Do not prevent the initial touch. A stationary gesture remains wholly
      // browser-owned so WebView can start native long-press selection/callout.
    }

    function beginPinch(event) {
      cancelScrollInertia();
      resetScrollGesture(true);
      pinchConsumesGesture = true;
      pinchDistance = touchDistance(event.touches);
      consumeTouch(event);
    }

    function onTouchStart(event) {
      markNativeTouch();
      if (event.touches.length >= 2 || pinchConsumesGesture) {
        beginPinch(event);
        return;
      }
      beginOneFingerGesture(event);
    }

    function onTouchMove(event) {
      if (pinchConsumesGesture || event.touches.length >= 2) {
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
        return;
      }

      if (event.touches.length !== 1 || scrollTouchIdentifier === null) return;
      const touch = findTouch(event.touches, scrollTouchIdentifier);
      if (!touch) return;
      const currentX = Number(touch.clientX);
      const currentY = Number(touch.clientY);
      if (!Number.isFinite(currentX) || !Number.isFinite(currentY)) return;
      const deltaPixels = scrollLastY - currentY;
      scrollLastY = currentY;
      recordScrollSample(eventTime(event), currentY);
      if (!scrollConsumesGesture &&
          Math.hypot(currentX - scrollStartX, currentY - scrollStartY) <
            SCROLL_START_THRESHOLD_PIXELS) {
        return;
      }
      scrollConsumesGesture = true;
      scrollByPixels(deltaPixels);
      consumeTouch(event);
    }

    function onTouchEnd(event) {
      if (pinchConsumesGesture) {
        consumeTouch(event);
        if (event.touches.length >= 2) {
          pinchDistance = touchDistance(event.touches);
        } else if (event.touches.length === 0) {
          pinchDistance = 0;
          pinchConsumesGesture = false;
        }
        return;
      }
      if (scrollTouchIdentifier === null || findTouch(event.touches, scrollTouchIdentifier)) return;
      const consumed = scrollConsumesGesture;
      if (consumed) startScrollInertia();
      resetScrollGesture(false);
      if (consumed) consumeTouch(event);
      // An unconsumed tap or long press is left to xterm/WebView unchanged.
    }

    function onTouchCancel(event) {
      const owned = pinchConsumesGesture || scrollConsumesGesture;
      pinchDistance = 0;
      pinchConsumesGesture = false;
      cancelScrollInertia();
      resetScrollGesture(true);
      if (owned) consumeTouch(event);
    }

    const touchOptions = Object.freeze({capture: true, passive: false});
    const mouseCaptureOptions = true;
    xtermElement.addEventListener('mousedown', suppressXtermTouchSelection, mouseCaptureOptions);
    if (helperTextarea) helperTextarea.addEventListener('paste', handleNativePaste, mouseCaptureOptions);
    enableNativePasteTarget();
    terminalElement.addEventListener('touchstart', onTouchStart, touchOptions);
    terminalElement.addEventListener('touchmove', onTouchMove, touchOptions);
    terminalElement.addEventListener('touchend', onTouchEnd, touchOptions);
    terminalElement.addEventListener('touchcancel', onTouchCancel, touchOptions);

    const platformSubscription = layer2.onPlatformState(applyAppearance);
    const cursorSubscription = typeof layer2.terminal.onCursorMove === 'function'
      ? layer2.terminal.onCursorMove(() => requestFrame(syncNativePasteTarget))
      : null;
    const resizeSubscription = typeof layer2.terminal.onResize === 'function'
      ? layer2.terminal.onResize(() => requestFrame(syncNativePasteTarget))
      : null;

    return Object.freeze({
      dispose() {
        if (disposed) return;
        disposed = true;
        cancelScrollInertia();
        platformSubscription.dispose();
        if (cursorSubscription && typeof cursorSubscription.dispose === 'function') cursorSubscription.dispose();
        if (resizeSubscription && typeof resizeSubscription.dispose === 'function') resizeSubscription.dispose();
        xtermElement.removeEventListener('mousedown', suppressXtermTouchSelection, mouseCaptureOptions);
        if (helperTextarea) helperTextarea.removeEventListener('paste', handleNativePaste, mouseCaptureOptions);
        restoreNativePasteTarget();
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
          scrollConsumesGesture,
          selectionAuthority: 'webview-native-dom-selection-poc',
          selectionHandles: 'webview-native',
          copyAuthority: 'webview-native-action-mode',
          pasteAuthority: 'xterm-helper-textarea-native-paste',
          rendererAuthority: 'xterm-dom-renderer',
          scrollAuthority: 'layer3-public-scroll-lines-after-move-threshold',
          touchActivationAuthority: 'webview-default-unconsumed-tap',
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
