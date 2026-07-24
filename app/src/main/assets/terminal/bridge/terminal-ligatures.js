import {LigaturesAddon} from '/terminal/vendor/addon-ligatures.mjs';

const exports = Object.freeze({LigaturesAddon});
window.AndroidTerminalLigaturesLoader = Object.freeze({
  ready: Promise.resolve(exports)
});
window.dispatchEvent(new Event('android-terminal-ligatures-loader-ready'));
