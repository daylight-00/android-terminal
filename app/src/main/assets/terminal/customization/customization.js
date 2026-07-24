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
        !layer2.platform || typeof layer2.platform.showSoftInput !== 'function') {
      throw new Error('Layer 2 customization capability is unavailable.');
    }

    const terminalElement = document.getElementById('terminal');
    if (!terminalElement) {
      throw new Error('Terminal interaction surface is unavailable.');
    }

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
    let scrollLastX = 0;
    let scrollLastY = 0;
    let scrollTapTarget = null;
    let scrollPixelRemainder = 0;
    let scrollConsumesGesture = false;
    let scrollSamples = [];
    let scrollAnimationFrame = 0;
    let disposed = false;
    const touchSurfaceAvailable =
      typeof terminalElement.addEventListener === 'function' &&
      typeof terminalElement.removeEventListener === 'function';
    const requestFrame = typeof window.requestAnimationFrame === 'function'
      ? (callback) => window.requestAnimationFrame(callback)
      : (callback) => window.setTimeout(() => callback(Date.now()), 16);
    const cancelFrame = typeof window.cancelAnimationFrame === 'function'
      ? (handle) => window.cancelAnimationFrame(handle)
      : (handle) => window.clearTimeout(handle);

    function applyAppearance(state) {
      layer2.terminal.options.theme = state.colorScheme === 'light' ? lightTheme : darkTheme;
      androidFontScale = boundedScale(
        state.fontScale,
        MIN_ANDROID_FONT_SCALE,
        MAX_ANDROID_FONT_SCALE
      );
      layer2.terminal.options.fontSize = upstreamFontSize * androidFontScale * userFontScale;
      layer2.requestGeometrySync();
    }

    function changeUserFontSize(direction) {
      const platformBase = upstreamFontSize * androidFontScale;
      const current = platformBase * userFontScale;
      const minimum = platformBase * MIN_USER_FONT_SCALE;
      const maximum = platformBase * MAX_USER_FONT_SCALE;
      const next = Math.min(
        maximum,
        Math.max(minimum, current + direction * FONT_SIZE_STEP_PIXELS)
      );
      if (next === current) return false;
      userFontScale = next / platformBase;
      layer2.terminal.options.fontSize = next;
      layer2.requestGeometrySync();
      return true;
    }

    function measureCellHeight() {
      const rows = Number(layer2.terminal.rows);
      const screen = typeof terminalElement.querySelector === 'function'
        ? terminalElement.querySelector('.xterm-screen')
        : null;
      if (screen && typeof screen.getBoundingClientRect === 'function' &&
          Number.isFinite(rows) && rows > 0) {
        const height = Number(screen.getBoundingClientRect().height);
        if (Number.isFinite(height) && height > 0) return height / rows;
      }
      const fontSize = Number(layer2.terminal.options.fontSize);
      const lineHeight = Number(layer2.terminal.options.lineHeight);
      if (Number.isFinite(fontSize) && fontSize > 0) {
        return fontSize * (Number.isFinite(lineHeight) && lineHeight > 0 ? lineHeight : 1.2);
      }
      return 18;
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

    function resetScrollGesture(resetRemainder) {
      scrollTouchIdentifier = null;
      scrollStartX = 0;
      scrollStartY = 0;
      scrollLastX = 0;
      scrollLastY = 0;
      scrollTapTarget = null;
      scrollConsumesGesture = false;
      scrollSamples = [];
      if (resetRemainder) scrollPixelRemainder = 0;
    }

    function recordScrollSample(time, y) {
      scrollSamples.push({time, y});
      const minimumTime = time - SCROLL_SAMPLE_WINDOW_MILLIS;
      while (scrollSamples.length > 2 && scrollSamples[0].time < minimumTime) {
        scrollSamples.shift();
      }
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
        const elapsed = Math.min(
          SCROLL_MAX_FRAME_MILLIS,
          Math.max(1, now - previousTime)
        );
        previousTime = now;
        scrollByPixels(velocity * elapsed);
        velocity *= Math.exp(-SCROLL_FRICTION_PER_MILLISECOND * elapsed);
        if (Math.abs(velocity) >= SCROLL_STOP_VELOCITY) {
          scrollAnimationFrame = requestFrame(animate);
        }
      }

      scrollAnimationFrame = requestFrame(animate);
    }

    function replayTap(target, clientX, clientY) {
      if (target && typeof target.dispatchEvent === 'function' &&
          typeof window.MouseEvent === 'function') {
        const common = {
          bubbles: true,
          cancelable: true,
          composed: true,
          view: window,
          clientX,
          clientY,
          screenX: clientX,
          screenY: clientY,
          button: 0,
          detail: 1
        };
        target.dispatchEvent(new window.MouseEvent('mousedown', {...common, buttons: 1}));
        target.dispatchEvent(new window.MouseEvent('mouseup', {...common, buttons: 0}));
        target.dispatchEvent(new window.MouseEvent('click', {...common, buttons: 0}));
      }
      if (typeof layer2.terminal.focus === 'function') {
        layer2.terminal.focus();
      }
      const request = layer2.platform.showSoftInput();
      if (request && typeof request.catch === 'function') {
        request.catch((error) => console.warn('Android soft-input request failed.', error));
      }
    }

    function beginOneFingerScroll(event) {
      if (event.touches.length !== 1 || isScrollbarTarget(event.target) ||
          !canScrollNormalBuffer()) {
        resetScrollGesture(true);
        return false;
      }
      const touch = event.touches[0];
      cancelScrollInertia();
      scrollTouchIdentifier = touch.identifier;
      scrollStartX = Number(touch.clientX);
      scrollStartY = Number(touch.clientY);
      scrollLastX = scrollStartX;
      scrollLastY = scrollStartY;
      scrollTapTarget = event.target;
      scrollPixelRemainder = 0;
      scrollConsumesGesture = false;
      scrollSamples = [];
      recordScrollSample(eventTime(event), scrollStartY);
      return true;
    }

    function beginPinch(event) {
      cancelScrollInertia();
      resetScrollGesture(true);
      pinchConsumesGesture = true;
      pinchDistance = touchDistance(event.touches);
      consumeTouch(event);
    }

    function onTouchStart(event) {
      if (event.touches.length >= 2 || pinchConsumesGesture) {
        beginPinch(event);
        return;
      }
      if (beginOneFingerScroll(event)) {
        // Own the gesture from its first touch. Waiting until touchmove is too
        // late on Android WebView because the initial touch can already arm
        // xterm's focus/IME activation for release.
        consumeTouch(event);
      }
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
      scrollLastX = currentX;
      scrollLastY = currentY;
      recordScrollSample(eventTime(event), currentY);
      if (!scrollConsumesGesture &&
          Math.hypot(currentX - scrollStartX, currentY - scrollStartY) <
            SCROLL_START_THRESHOLD_PIXELS) {
        consumeTouch(event);
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

      if (scrollTouchIdentifier === null) return;
      if (findTouch(event.touches, scrollTouchIdentifier)) return;
      const consumed = scrollConsumesGesture;
      const tapTarget = scrollTapTarget;
      const tapX = scrollLastX;
      const tapY = scrollLastY;
      if (consumed) startScrollInertia();
      resetScrollGesture(false);
      consumeTouch(event);
      if (!consumed) replayTap(tapTarget, tapX, tapY);
    }

    function onTouchCancel(event) {
      const owned = pinchConsumesGesture || scrollTouchIdentifier !== null;
      pinchDistance = 0;
      pinchConsumesGesture = false;
      cancelScrollInertia();
      resetScrollGesture(true);
      if (owned) consumeTouch(event);
    }

    const touchOptions = Object.freeze({capture: true, passive: false});
    if (touchSurfaceAvailable) {
      terminalElement.addEventListener('touchstart', onTouchStart, touchOptions);
      terminalElement.addEventListener('touchmove', onTouchMove, touchOptions);
      terminalElement.addEventListener('touchend', onTouchEnd, touchOptions);
      terminalElement.addEventListener('touchcancel', onTouchCancel, touchOptions);
    }

    const platformSubscription = layer2.onPlatformState(applyAppearance);

    return Object.freeze({
      dispose() {
        if (disposed) return;
        disposed = true;
        cancelScrollInertia();
        platformSubscription.dispose();
        if (touchSurfaceAvailable) {
          terminalElement.removeEventListener('touchstart', onTouchStart, touchOptions);
          terminalElement.removeEventListener('touchmove', onTouchMove, touchOptions);
          terminalElement.removeEventListener('touchend', onTouchEnd, touchOptions);
          terminalElement.removeEventListener('touchcancel', onTouchCancel, touchOptions);
        }
      },
      getState() {
        return Object.freeze({
          androidFontScale,
          userFontScale,
          effectiveFontSize: Number(layer2.terminal.options.fontSize),
          pinchConsumesGesture,
          scrollConsumesGesture,
          scrollAuthority: 'layer3-public-scroll-lines',
          touchActivationAuthority: 'layer3-deferred-tap-native-ime',
          touchSurfaceAvailable
        });
      }
    });
  }

  const installation = install(window.AndroidTerminalLayer2);
  window.AndroidTerminalCustomization = Object.freeze({
    contractVersion: 2,
    installation,
    getInteractionState() {
      return installation.getState();
    }
  });
})();
