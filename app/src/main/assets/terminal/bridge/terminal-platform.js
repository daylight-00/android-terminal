(() => {
  'use strict';

  const allowedExternalUriSchemes = Object.freeze(['http:', 'https:']);
  const upstreamFontSizes = new WeakMap();
  const MIN_ANDROID_FONT_SCALE = 0.5;
  const MAX_ANDROID_FONT_SCALE = 3.0;
  const MAX_LOCALIZED_STRING_CHARACTERS = 512;

  function isExternalUriAllowed(value) {
    try {
      const parsed = new URL(String(value));
      return allowedExternalUriSchemes.includes(parsed.protocol) &&
        parsed.username === '' && parsed.password === '' && parsed.hostname !== '';
    } catch (_) {
      return false;
    }
  }

  function boundedFontScale(value) {
    const scale = Number(value);
    if (!Number.isFinite(scale)) return 1;
    return Math.min(MAX_ANDROID_FONT_SCALE, Math.max(MIN_ANDROID_FONT_SCALE, scale));
  }

  function applyFontScale(terminal, value) {
    if (!upstreamFontSizes.has(terminal)) {
      const upstreamDefault = Number(terminal.options.fontSize);
      if (!Number.isFinite(upstreamDefault) || upstreamDefault <= 0) return;
      upstreamFontSizes.set(terminal, upstreamDefault);
    }
    terminal.options.fontSize = upstreamFontSizes.get(terminal) * boundedFontScale(value);
  }

  function boundedLocalizedString(value) {
    if (typeof value !== 'string' || value === '') return null;
    return Array.from(value).slice(0, MAX_LOCALIZED_STRING_CHARACTERS).join('');
  }

  function applyLocalizedStrings(terminal, state) {
    if (!terminal.strings) return;
    const promptLabel = boundedLocalizedString(state.promptLabel);
    const tooMuchOutput = boundedLocalizedString(state.tooMuchOutput);
    if (promptLabel !== null) terminal.strings.promptLabel = promptLabel;
    if (tooMuchOutput !== null) terminal.strings.tooMuchOutput = tooMuchOutput;
  }

  function applyPlatformState(terminal, state) {
    if (!terminal || !state) return;
    terminal.options.screenReaderMode = Boolean(
      state.accessibilityEnabled && state.touchExplorationEnabled
    );
    applyFontScale(terminal, state.fontScale);
    applyLocalizedStrings(terminal, state);
  }

  function firstParameter(params) {
    if (!params) return -1;
    if (typeof params.get === 'function') return Number(params.get(0));
    if (Array.isArray(params) || typeof params.length === 'number') return Number(params[0]);
    return -1;
  }

  function configureWindowOperations(terminal, host) {
    if (!terminal || !terminal.options || !terminal.parser ||
        typeof terminal.parser.registerCsiHandler !== 'function' ||
        typeof terminal.input !== 'function' || typeof terminal.refresh !== 'function') {
      throw new Error('xterm public window-operation APIs are unavailable.');
    }

    terminal.options.windowOptions = {
      getWinSizePixels: true,
      getCellSizePixels: true,
      getWinSizeChars: true,
      pushTitle: true,
      popTitle: true
    };

    return terminal.parser.registerCsiHandler({final: 't'}, (params) => {
      const operation = firstParameter(params);
      if (operation === 7) {
        terminal.refresh(0, Math.max(0, terminal.rows - 1));
        return true;
      }
      if (operation === 21) {
        const title = host && typeof host.getTitle === 'function' ? host.getTitle() : '';
        terminal.input(`\x1b]l${String(title)}\x1b\\`, false);
        return true;
      }
      return false;
    });
  }

  window.AndroidTerminalPlatformIntegration = Object.freeze({
    contractVersion: 4,
    isExternalUriAllowed,
    applyPlatformState,
    configureWindowOperations
  });
})();
