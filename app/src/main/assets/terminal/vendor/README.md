# Provisioned upstream assets

This directory is intentionally incomplete in repository-only source.

`tools/acquire-web-terminal-assets.sh` installs the pinned production files:

- `xterm.js` and `xterm.css` from `@xterm/xterm@6.0.0`
- `addon-fit.js` from `@xterm/addon-fit@0.11.0`
- `addon-serialize.js` and its exact `package.json` from `@xterm/addon-serialize@0.13.0`
- upstream MIT license texts and an acquisition receipt

The serialize package publishes no standalone `LICENSE` member. Its retained package metadata
declares `MIT`; `LICENSE.xterm.txt` is the project-wide xterm.js license.

The Android app never loads these files from a network at runtime.
