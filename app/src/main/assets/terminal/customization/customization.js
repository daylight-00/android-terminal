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
        typeof layer2.requestGeometrySync !== 'function') {
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
    let disposed = false;
    const touchSurfaceAvailable =
      typeof terminalElement.addEventListener === 'function' &&
      typeof terminalElement.removeEventListener === 'function';

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

    function onTouchStart(event) {
      if (!pinchConsumesGesture && event.touches.length < 2) return;
      pinchConsumesGesture = true;
      if (event.touches.length >= 2) {
        pinchDistance = touchDistance(event.touches);
      }
      consumeTouch(event);
    }

    function onTouchMove(event) {
      if (!pinchConsumesGesture && event.touches.length < 2) return;
      pinchConsumesGesture = true;
      if (event.touches.length >= 2) {
        const currentDistance = touchDistance(event.touches);
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

    const touchOptions = Object.freeze({capture: true, passive: false});
    if (touchSurfaceAvailable) {
      terminalElement.addEventListener('touchstart', onTouchStart, touchOptions);
      terminalElement.addEventListener('touchmove', onTouchMove, touchOptions);
      terminalElement.addEventListener('touchend', onTouchEnd, touchOptions);
      terminalElement.addEventListener('touchcancel', onTouchEnd, touchOptions);
    }

    const platformSubscription = layer2.onPlatformState(applyAppearance);

    return Object.freeze({
      dispose() {
        if (disposed) return;
        disposed = true;
        platformSubscription.dispose();
        if (touchSurfaceAvailable) {
          terminalElement.removeEventListener('touchstart', onTouchStart, touchOptions);
          terminalElement.removeEventListener('touchmove', onTouchMove, touchOptions);
          terminalElement.removeEventListener('touchend', onTouchEnd, touchOptions);
          terminalElement.removeEventListener('touchcancel', onTouchEnd, touchOptions);
        }
      },
      getState() {
        return Object.freeze({
          androidFontScale,
          userFontScale,
          effectiveFontSize: Number(layer2.terminal.options.fontSize),
          pinchConsumesGesture,
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
