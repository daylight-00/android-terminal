(() => {
  'use strict';

  function create(context) {
    const terminal = context && context.terminal;
    const WebglAddon = context && context.WebglAddon;
    const onStateChange = context && typeof context.onStateChange === 'function'
      ? context.onStateChange : () => {};

    if (!terminal || typeof terminal.loadAddon !== 'function') {
      throw new Error('A terminal with loadAddon() is required.');
    }

    let activeAddon = null;
    let contextLossSubscription = null;
    let disposed = false;
    let permanentlyFellBack = false;
    let state = Object.freeze({mode: 'dom', reason: 'not-activated'});

    function publish(mode, reason) {
      state = Object.freeze({mode, reason});
      onStateChange(state);
      return state;
    }

    function releaseActiveAddon() {
      const subscription = contextLossSubscription;
      const addon = activeAddon;
      contextLossSubscription = null;
      activeAddon = null;
      try {
        if (subscription && typeof subscription.dispose === 'function') subscription.dispose();
      } finally {
        if (addon && typeof addon.dispose === 'function') addon.dispose();
      }
    }

    function fallback(reason) {
      if (disposed || permanentlyFellBack) return state;
      permanentlyFellBack = true;
      releaseActiveAddon();
      return publish('dom', reason);
    }

    function activate() {
      if (disposed) return publish('dom', 'disposed');
      if (permanentlyFellBack) return state;
      if (!WebglAddon || typeof WebglAddon.WebglAddon !== 'function') {
        return fallback('webgl-unavailable');
      }

      let candidate = null;
      try {
        candidate = new WebglAddon.WebglAddon(false);
        activeAddon = candidate;
        contextLossSubscription = candidate.onContextLoss(() => {
          if (activeAddon !== candidate) return;
          fallback('context-loss');
        });
        terminal.loadAddon(candidate);
        if (permanentlyFellBack || activeAddon !== candidate) return state;
        return publish('webgl', 'active');
      } catch (error) {
        if (activeAddon !== candidate && candidate && typeof candidate.dispose === 'function') {
          candidate.dispose();
        }
        return fallback('activation-failed');
      }
    }

    function reactivate() {
      if (disposed) return publish('dom', 'disposed');
      if (permanentlyFellBack) return state;
      if (activeAddon === null) return activate();
      releaseActiveAddon();
      return activate();
    }

    function dispose() {
      if (disposed) return;
      disposed = true;
      releaseActiveAddon();
      publish('dom', 'disposed');
    }

    return Object.freeze({
      activate,
      reactivate,
      dispose,
      getState() { return state; }
    });
  }

  window.AndroidTerminalRenderer = Object.freeze({create});
})();
