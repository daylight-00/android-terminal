# Layer 2 device validation

Repository verification and APK construction establish the implementation gate. The remaining claims require the built debug APK on a real Android device.

## Inspect the neutral completion surface

Debug builds enable WebView inspection only when `BuildConfig.DEBUG` is true. Attach Chrome DevTools to the app WebView and evaluate:

```js
AndroidTerminalLayer2.completion.manifest
AndroidTerminalLayer2.completion.snapshot()
```

The manifest status is `repository-complete-device-validation-pending`. The image path requires CSP `wasm-unsafe-eval` and does not enable JavaScript `unsafe-eval`. The snapshot reports attachment state, renderer state, geometry, title, progress, Unicode providers, ligature activation, image storage, and Android platform-state availability without adding product UI.


## SAF destination probes

From the inspected WebView, exercise the neutral document facade without adding product UI:

```js
AndroidTerminalPlatform.importDocument({mimeType: 'text/plain'})
AndroidTerminalPlatform.importDocument({
  mimeType: 'text/plain',
  destinationDirectory: 'incoming'
})
```

The first explicit import must create a provider-named file directly under HOME. The second may create `HOME/incoming` only as the result of that explicit operation. Layer 2 must never create `HOME/imports`, must reject absolute or parent-traversing destinations, must preserve existing files through collision renaming, and must expose no `content://` URI as a shell path.

## Shell and terminal probes

Run these inside the app terminal:

```sh
printf 'argv0=<%s>\nSHELL=<%s>\nPATH=<%s>\nHOME=<%s>\nTMPDIR=<%s>\nTERM=<%s>\n' \
  "$0" "${SHELL-<unset>}" "${PATH-<unset>}" "$HOME" "$TMPDIR" "$TERM"
printf 'ANDROID_ROOT=<%s>\nANDROID_DATA=<%s>\nANDROID_STORAGE=<%s>\nEXTERNAL_STORAGE=<%s>\n' \
  "${ANDROID_ROOT-<unset>}" "${ANDROID_DATA-<unset>}" \
  "${ANDROID_STORAGE-<unset>}" "${EXTERNAL_STORAGE-<unset>}"
find "$HOME" -mindepth 1 -maxdepth 1 -print
ls -ld "$TMPDIR"
ls -ld /storage/emulated/0 2>&1 || true

printf '\033]0;android-terminal-layer2-probe\007'
printf '\033]9;4;1;42\007'
printf '\033]52;c;YW5kcm9pZC10ZXJtaW5hbC1vc2M1Mg==\007'
printf '\033]8;;https://xtermjs.org\033\\xterm.js OSC 8 link\033]8;;\033\\\n'
printf 'https://xtermjs.org\n'
printf '\033]1337;File=inline=1;width=1;height=1;preserveAspectRatio=1:iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=\007\n'
printf '\033[14t\033[16t\033[18t\033[21t'
printf '\033]9;4;0;0\007'
```

Expected evidence:

- `$0` begins with `-`, while the executable remains `/system/bin/sh`.
- `HOME` is the app files directory, `TMPDIR` is the app cache `tmp` child, and a fresh HOME has no session-created entry.
- Parent Android variables are inherited as the device supplied them; the app does not force `PATH`, `SHELL`, `LANG`, `ANDROID_*`, `EXTERNAL_STORAGE`, or XDG values.
- Shared-storage access uses `/storage/emulated/0` directly after the Android system grant and no `HOME/storage` link appears.
- The title and progress values appear in `completion.snapshot()`.
- OSC 52 writes the decoded text to the Android clipboard, subject to Android clipboard behavior.
- OSC 8 and plain-text links route through Android `ACTION_VIEW` rather than WebView navigation.
- The inline image renders; this specifically exercises the official ImageAddon embedded WebAssembly under the narrow CSP permission.
- Window-report queries return truthful terminal/cell geometry and current title through the PTY.

Search, Unicode 11 selection, web-font relayout, and ligatures are neutral Layer 2 capabilities with no default Layer 3 UI or preference. Exercise them from the inspected WebView:

```js
AndroidTerminalLayer2.search.findNext('probe')
AndroidTerminalLayer2.unicode.versions
AndroidTerminalLayer2.unicode.setActiveVersion('11')
AndroidTerminalLayer2.webFonts.relayout()
AndroidTerminalLayer2.ligatures.enable()
```

A failed device probe does not authorize a Layer 3 workaround. It must be classified as an upstream, WebView, Android bridge, or device-specific limitation first.
