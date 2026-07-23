(() => {
  'use strict';

  const allowedExternalUriSchemes = Object.freeze(['http:', 'https:']);
  const upstreamFontSizes = new WeakMap();
  const MIN_ANDROID_FONT_SCALE = 0.5;
  const MAX_ANDROID_FONT_SCALE = 3.0;

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

  function applyPlatformState(terminal, state) {
    if (!terminal || !state) return;
    terminal.options.screenReaderMode = Boolean(
      state.accessibilityEnabled && state.touchExplorationEnabled
    );
    applyFontScale(terminal, state.fontScale);
  }

  window.AndroidTerminalPlatformIntegration = Object.freeze({
    contractVersion: 3,
    isExternalUriAllowed,
    applyPlatformState
  });
})();
