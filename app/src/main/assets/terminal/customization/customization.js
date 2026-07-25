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
  const LONG_PRESS_DELAY_MILLIS = 500;
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
        typeof layer2.onSelectionAction !== 'function' ||
        typeof layer2.requestGeometrySync !== 'function' ||
        !layer2.platform || typeof layer2.platform.showSoftInput !== 'function' ||
        typeof layer2.platform.copySelection !== 'function' ||
        typeof layer2.platform.pasteClipboard !== 'function' ||
        typeof layer2.platform.showSelectionActionMode !== 'function' ||
        typeof layer2.platform.hideSelectionActionMode !== 'function') {
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
    let softInputVisible = Boolean(initialState && initialState.softInputVisible);
    let ownedTouchFocusActive = false;
    let ownedTouchStartedWithSoftInput = false;
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
    let longPressTimer = 0;
    let selectionConsumesGesture = false;
    let selectionMouseTarget = null;
    let selectionActionModeVisible = false;
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

    function dispatchMouseEvent(target, type, clientX, clientY, buttons, detail) {
      if (!target || typeof target.dispatchEvent !== 'function' ||
          typeof window.MouseEvent !== 'function') {
        return false;
      }
      return target.dispatchEvent(new window.MouseEvent(type, {
        bubbles: true,
        cancelable: true,
        composed: true,
        view: window,
        clientX,
        clientY,
        screenX: clientX,
        screenY: clientY,
        button: 0,
        buttons,
        detail
      }));
    }

    function applyAppearance(state) {
      layer2.terminal.options.theme = state.colorScheme === 'light' ? lightTheme : darkTheme;
      softInputVisible = Boolean(state.softInputVisible);
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

    function cancelLongPress() {
      if (!longPressTimer) return;
      window.clearTimeout(longPressTimer);
      longPressTimer = 0;
    }

    function resetScrollGesture(resetRemainder) {
      cancelLongPress();
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

    function beginOwnedTouchFocusPolicy() {
      if (ownedTouchFocusActive) return;
      ownedTouchFocusActive = true;
      ownedTouchStartedWithSoftInput = softInputVisible;

      // Android owns IME visibility. Preserve xterm focus when the IME is already
      // visible so scroll, pinch, and future selection gestures do not collapse
      // the keyboard. When the IME is hidden, blur the retained hidden textarea
      // before WebView can reinterpret the owned touch as an editor activation.
      if (!ownedTouchStartedWithSoftInput &&
          typeof layer2.terminal.blur === 'function') {
        layer2.terminal.blur();
      }
    }

    function finishOwnedTouchFocusPolicy() {
      const startedWithSoftInput = ownedTouchStartedWithSoftInput;
      ownedTouchFocusActive = false;
      ownedTouchStartedWithSoftInput = false;
      return startedWithSoftInput;
    }

    function replayTap(target, clientX, clientY, requestSoftInput) {
      dispatchMouseEvent(target, 'mousedown', clientX, clientY, 1, 1);
      dispatchMouseEvent(target, 'mouseup', clientX, clientY, 0, 1);
      dispatchMouseEvent(target, 'click', clientX, clientY, 0, 1);
      if (typeof layer2.terminal.focus === 'function') {
        layer2.terminal.focus();
      }
      if (requestSoftInput) {
        const request = layer2.platform.showSoftInput();
        if (request && typeof request.catch === 'function') {
          request.catch((error) => console.warn('Android soft-input request failed.', error));
        }
      }
    }

    function selectionContentRect(fallbackX = scrollLastX, fallbackY = scrollLastY) {
      const position = typeof layer2.terminal.getSelectionPosition === 'function'
        ? layer2.terminal.getSelectionPosition()
        : null;
      const screen = typeof terminalElement.querySelector === 'function'
        ? terminalElement.querySelector('.xterm-screen')
        : null;
      if (!screen || typeof screen.getBoundingClientRect !== 'function') return null;
      const rect = screen.getBoundingClientRect();
      const columns = Number(layer2.terminal.cols);
      const rows = Number(layer2.terminal.rows);
      const activeBuffer = layer2.terminal.buffer && layer2.terminal.buffer.active;
      const viewportRow = Number(activeBuffer && activeBuffer.viewportY);
      if (!Number.isFinite(columns) || columns <= 0 ||
          !Number.isFinite(rows) || rows <= 0 ||
          !Number.isFinite(rect.width) || rect.width <= 0 ||
          !Number.isFinite(rect.height) || rect.height <= 0) {
        return null;
      }
      const ydisp = Number.isFinite(viewportRow) ? viewportRow : 0;
      const cellWidth = rect.width / columns;
      const cellHeight = rect.height / rows;
      if (!position || !position.start || !position.end) {
        const anchorX = Number.isFinite(Number(fallbackX)) ? Number(fallbackX) : rect.left;
        const anchorY = Number.isFinite(Number(fallbackY)) ? Number(fallbackY) : rect.top;
        const left = Math.max(rect.left, Math.min(rect.right - 1, anchorX));
        const top = Math.max(rect.top, Math.min(rect.bottom - 1, anchorY));
        return Object.freeze({
          left: Math.floor(left),
          top: Math.floor(top),
          right: Math.max(Math.floor(left) + 1, Math.ceil(Math.min(rect.right, left + cellWidth))),
          bottom: Math.max(Math.floor(top) + 1, Math.ceil(Math.min(rect.bottom, top + cellHeight)))
        });
      }
      let startRow = Number(position.start.y);
      let endRow = Number(position.end.y);
      let startColumn = Number(position.start.x);
      let endColumn = Number(position.end.x);
      if (![startRow, endRow, startColumn, endColumn].every(Number.isFinite)) return null;
      if (endColumn === 0 && endRow > startRow) {
        endRow -= 1;
        endColumn = columns;
      }
      const visibleStartRow = Math.max(0, Math.min(rows - 1, startRow - ydisp));
      const visibleEndRow = Math.max(visibleStartRow, Math.min(rows - 1, endRow - ydisp));
      const singleRow = startRow === endRow;
      const left = singleRow
        ? rect.left + Math.max(0, Math.min(columns - 1, startColumn)) * cellWidth
        : rect.left;
      const right = singleRow
        ? rect.left + Math.max(startColumn + 1, Math.min(columns, endColumn)) * cellWidth
        : rect.right;
      const top = rect.top + visibleStartRow * cellHeight;
      const bottom = rect.top + (visibleEndRow + 1) * cellHeight;
      return Object.freeze({
        left: Math.floor(left),
        top: Math.floor(top),
        right: Math.max(Math.floor(left) + 1, Math.ceil(right)),
        bottom: Math.max(Math.floor(top) + 1, Math.ceil(bottom))
      });
    }

    function showSelectionActionMode() {
      const hasSelection = typeof layer2.terminal.hasSelection === 'function' &&
        layer2.terminal.hasSelection();
      const contentRect = selectionContentRect();
      if (!contentRect) return;
      selectionActionModeVisible = true;
      const request = layer2.platform.showSelectionActionMode(Object.freeze({
        ...contentRect,
        hasSelection
      }));
      if (request && typeof request.catch === 'function') {
        request.catch((error) => {
          selectionActionModeVisible = false;
          console.warn('Android selection action mode failed.', error);
        });
      }
    }

    function dismissSelectionActionMode(clearSelection) {
      if (clearSelection && typeof layer2.terminal.clearSelection === 'function' &&
          typeof layer2.terminal.hasSelection === 'function' && layer2.terminal.hasSelection()) {
        layer2.terminal.clearSelection();
      }
      if (!selectionActionModeVisible) return;
      selectionActionModeVisible = false;
      const request = layer2.platform.hideSelectionActionMode();
      if (request && typeof request.catch === 'function') {
        request.catch((error) => console.warn('Android selection action mode dismissal failed.', error));
      }
    }

    function handleSelectionAction(action) {
      if (action === 'copy') {
        const request = layer2.platform.copySelection();
        if (request && typeof request.catch === 'function') {
          request.catch((error) => console.warn('Terminal selection copy failed.', error));
        }
        return;
      }
      if (action === 'paste') {
        const request = layer2.platform.pasteClipboard();
        if (request && typeof request.catch === 'function') {
          request.catch((error) => console.warn('Terminal clipboard paste failed.', error));
        }
        return;
      }
      if (action === 'select-all') {
        if (typeof layer2.terminal.selectAll === 'function') layer2.terminal.selectAll();
        requestFrame(showSelectionActionMode);
        return;
      }
      if (action === 'clear') {
        selectionActionModeVisible = false;
        if (typeof layer2.terminal.clearSelection === 'function') {
          layer2.terminal.clearSelection();
        }
      }
    }

    function beginLongPressSelection() {
      longPressTimer = 0;
      if (disposed || pinchConsumesGesture || scrollConsumesGesture ||
          scrollTouchIdentifier === null || selectionConsumesGesture || !scrollTapTarget) {
        return;
      }
      selectionConsumesGesture = true;
      selectionMouseTarget = scrollTapTarget;
      // A double-click mousedown delegates word selection and subsequent drag
      // expansion to xterm's own selection service without reading private APIs.
      dispatchMouseEvent(selectionMouseTarget, 'mousedown', scrollLastX, scrollLastY, 1, 2);
      requestFrame(showSelectionActionMode);
    }

    function armLongPressSelection() {
      cancelLongPress();
      longPressTimer = window.setTimeout(beginLongPressSelection, LONG_PRESS_DELAY_MILLIS);
    }

    function finishSelectionGesture(showActionMode) {
      if (!selectionConsumesGesture) return false;
      dispatchMouseEvent(selectionMouseTarget, 'mouseup', scrollLastX, scrollLastY, 0, 2);
      selectionConsumesGesture = false;
      selectionMouseTarget = null;
      if (showActionMode) showSelectionActionMode();
      return true;
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
      armLongPressSelection();
      return true;
    }

    function beginPinch(event) {
      beginOwnedTouchFocusPolicy();
      cancelScrollInertia();
      cancelLongPress();
      finishSelectionGesture(false);
      dismissSelectionActionMode(true);
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
      dismissSelectionActionMode(true);
      if (beginOneFingerScroll(event)) {
        beginOwnedTouchFocusPolicy();
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
      if (selectionConsumesGesture) {
        dispatchMouseEvent(selectionMouseTarget, 'mousemove', currentX, currentY, 1, 0);
        consumeTouch(event);
        return;
      }
      if (!scrollConsumesGesture &&
          Math.hypot(currentX - scrollStartX, currentY - scrollStartY) <
            SCROLL_START_THRESHOLD_PIXELS) {
        consumeTouch(event);
        return;
      }
      cancelLongPress();
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
          finishOwnedTouchFocusPolicy();
        }
        return;
      }

      if (scrollTouchIdentifier === null) return;
      if (findTouch(event.touches, scrollTouchIdentifier)) return;
      if (selectionConsumesGesture) {
        finishOwnedTouchFocusPolicy();
        finishSelectionGesture(true);
        resetScrollGesture(false);
        consumeTouch(event);
        return;
      }
      cancelLongPress();
      const consumed = scrollConsumesGesture;
      const tapTarget = scrollTapTarget;
      const tapX = scrollLastX;
      const tapY = scrollLastY;
      const startedWithSoftInput = finishOwnedTouchFocusPolicy();
      if (consumed) startScrollInertia();
      resetScrollGesture(false);
      consumeTouch(event);
      if (!consumed) replayTap(tapTarget, tapX, tapY, !startedWithSoftInput);
    }

    function onTouchCancel(event) {
      const owned = pinchConsumesGesture || scrollTouchIdentifier !== null;
      pinchDistance = 0;
      pinchConsumesGesture = false;
      cancelScrollInertia();
      cancelLongPress();
      finishSelectionGesture(false);
      dismissSelectionActionMode(true);
      resetScrollGesture(true);
      if (owned) {
        finishOwnedTouchFocusPolicy();
        consumeTouch(event);
      }
    }

    const touchOptions = Object.freeze({capture: true, passive: false});
    if (touchSurfaceAvailable) {
      terminalElement.addEventListener('touchstart', onTouchStart, touchOptions);
      terminalElement.addEventListener('touchmove', onTouchMove, touchOptions);
      terminalElement.addEventListener('touchend', onTouchEnd, touchOptions);
      terminalElement.addEventListener('touchcancel', onTouchCancel, touchOptions);
    }

    const platformSubscription = layer2.onPlatformState(applyAppearance);
    const selectionActionSubscription = layer2.onSelectionAction(handleSelectionAction);

    return Object.freeze({
      dispose() {
        if (disposed) return;
        disposed = true;
        cancelScrollInertia();
        cancelLongPress();
        finishSelectionGesture(false);
        dismissSelectionActionMode(true);
        platformSubscription.dispose();
        selectionActionSubscription.dispose();
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
          selectionConsumesGesture,
          selectionActionModeVisible,
          selectionAuthority: 'xterm-public-selection-via-native-floating-action-mode',
          scrollAuthority: 'layer3-public-scroll-lines',
          touchActivationAuthority: 'layer3-ime-visibility-aware-deferred-tap-native-ime',
          gestureFocusPolicy: 'blur-only-when-platform-reports-ime-hidden',
          softInputVisible,
          ownedTouchFocusActive,
          touchSurfaceAvailable
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
