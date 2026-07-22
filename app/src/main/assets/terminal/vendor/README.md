# Provisioned upstream assets

This directory is intentionally incomplete in repository-only source.

`tools/acquire-web-terminal-assets.sh` installs the pinned production files:

- `xterm.js` and `xterm.css` from `@xterm/xterm@6.0.0`
- `addon-fit.js` from `@xterm/addon-fit@0.11.0`
- corresponding MIT license texts and an acquisition receipt

The Android app never loads these files from a network at runtime.
