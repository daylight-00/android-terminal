# Architecture

Android Terminal is a thin Android host for unmodified upstream xterm.js and Android's native shell. The project completes Layer 2 before introducing Layer 3 product features.

## Layer authority

```text
Layer 1  unmodified upstream xterm.js/addons and Android-provided runtime
   ↓ public upstream APIs
Layer 2  complete Android adaptation and native integration
   ↓ stable optional capability
Layer 3  product customization scaffold
```

The classification test is responsibility, not file language or feature size:

1. exact upstream bytes and behavior are Layer 1;
2. work required to make an upstream capability fully usable under Android is Layer 2;
3. a feature that is not required for Android adaptation and changes the product beyond the upstream host is Layer 3.

A bundled userland is Layer 3. Android storage permissions, WebView lifecycle recovery, PTY integration, and Android mappings for xterm.js public APIs are Layer 2.

## Layer 1: unmodified upstream

### Vendored xterm.js frontend

`app/src/main/assets/terminal/vendor/` contains exact production files from pinned official npm releases of `@xterm/xterm`, `@xterm/addon-fit`, `@xterm/addon-serialize`, `@xterm/addon-web-links`, and `@xterm/addon-webgl`. `tools/acquire-web-terminal-assets.sh` verifies the fixed npm integrity values, validates archive shape, installs only selected production files, and records exact installed identities in `ASSET_RECEIPT.json`.

The vendored files are never edited. xterm.js owns terminal parsing, screen state, Unicode layout, cursor behavior, selection, scrollback, keyboard/IME semantics, and rendering. Official addons continue to own their feature semantics. A routine upstream update changes only `vendor/**`, package coordinates, and the receipt.

### Android-provided runtime

Android supplies System WebView, Bionic, the dynamic linker, `/system/bin/sh`, and `/system/bin` executables. None are copied into the APK.

## Layer 2: complete Android adaptation

```text
Android Activity / Service / WebView / platform APIs
                         ↓
                 stable terminal contract
                         ↕
                public xterm.js APIs

/system/bin/sh ↔ PTY/JNI ↔ TerminalSessionService ↔ WebMessagePort ↔ xterm.js
```

Layer 2 is the active product scope. It must expose upstream functionality through public xterm.js or WebView APIs and add only the Android connection that functionality needs.

Current Layer 2 responsibilities include:

- replaceable Activity/WebView frontend and service-owned PTY lifetime;
- secure synthetic local origin, exact asset allowlist, CSP, and no runtime network access;
- versioned WebMessagePort contract, attachment generations, capability handshake, bounded byte transport, ACK/backpressure, and explicit failures;
- Android window, inset, rotation, focus, IME viewport, `ResizeObserver`, and `visualViewport` geometry reduced through `addon-fit` to deduplicated `TIOCSWINSZ` updates;
- xterm input callbacks connected to PTY writes without reinterpreting keyboard or terminal semantics;
- clipboard, OSC 8 URI activation, official plain-text web-link activation, bell, Android color-scheme state, accessibility, touch exploration, hardware-keyboard state, and font scale mapped to Android native APIs;
- official WebGL renderer activation with one-way fallback to xterm core DOM rendering after activation failure or public `onContextLoss` notification;
- official serialize-addon snapshots plus a bounded raw PTY tail for replacement frontends;
- SAF import/export for explicit document transactions;
- direct shared-storage adaptation: Android 10 runtime storage permissions, Android 11+ all-files special access, API 28 compatibility targeting, `EXTERNAL_STORAGE`, and a non-destructive `HOME/storage` symlink;
- API 28 compatibility targeting so owner-provided executables under writable app-private HOME remain launchable without a custom linker or loader shim;
- PTY creation, `/system/bin/sh` execution, signals, reads, writes, resize, wait, and cleanup through the minimum JNI/C syscall bridge.

Layer 2 may contain fixed safety limits and neutral host mappings required to make a feature operational. It must not contain a custom VT parser, screen model, renderer, shell-command semantics, bundled userland, package manager, or distribution filesystem.

### Executable HOME compatibility boundary

The app keeps `minSdk 29` and the native bridge API floor at 29, but declares `targetSdk 28`. This is a Layer 2 compatibility decision: Android 10 applies the writable-app-home `execve()` prohibition to apps targeting API 29 or later. The project does not absorb that platform transition through a custom dynamic linker, executable relocation service, copied loader, or bundled userland. Owner-provided Android executables remain ordinary files launched by `/system/bin/sh`; actual device execution is still a target gate.

### Shared storage boundary

Direct POSIX shared-storage access is Layer 2 because Android's permission model otherwise prevents the native shell from using ordinary paths such as `/storage/emulated/0/Download`. The app declares `MANAGE_EXTERNAL_STORAGE`, uses the API 28 compatibility target with API 29 read/write runtime permissions, and directs API 30+ users to the app-specific all-files settings screen. Grant status remains a device/user decision.

Layer 2 creates `HOME/storage` only when that path is absent and never replaces an existing owner-created entry. The symlink does not bypass Android permissions. SAF remains available for explicit document import/export and does not become a virtual mount.

### Plain-text web-link mapping

The official `@xterm/addon-web-links` package owns URL recognition, wrapped-line handling, hover
decorations, and terminal-buffer link semantics. Layer 2 supplies only the addon activation callback.
That callback reuses the same bounded Android `open-external-uri` operation as OSC 8 links, so only
validated HTTP/HTTPS URIs without embedded credentials reach `ACTION_VIEW`.

Layer 2 does not copy the upstream regular expression, register a private xterm link provider, call
`window.open`, navigate the local WebView, or add runtime network permission. Upstream package bytes
remain unmodified in Layer 1; Android owns only external intent activation.

### Android font-scale mapping

Android configuration owns the user-selected `fontScale`; xterm.js owns the terminal's default
font size and rendering behavior. Layer 2 reads the public `terminal.options.fontSize` value from
each newly created upstream terminal instance, freezes that value as the instance baseline, and
multiplies it by the bounded Android scale. Repeated configuration updates always recompute from
the captured upstream baseline, so scaling does not compound.

The adapter does not encode xterm.js's current numeric default, define a terminal font preference,
or use WebView text zoom as a second scaling authority. A font-scale change is delivered through
`onConfigurationChanged`, mapped through the public xterm option, and followed by the existing
`addon-fit`/geometry path before any changed dimensions reach `TIOCSWINSZ`. This is Layer 2 because
it connects Android's accessibility/display configuration to an upstream public capability; the
font size and rendering semantics remain upstream-owned.

### Upstream update delegation

Layer 2 never copies upstream feature logic merely to expose it on Android. For each capability it must, in order:

1. use xterm.js core when core owns the capability;
2. use an official addon when an addon owns it;
3. connect that public surface to Android native APIs when an Android connection is required;
4. retain an explicit pending or exclusion state instead of implementing a private substitute.

This keeps feature-update responsibility with xterm.js while this repository owns only Android integration.

## Layer 3: optional customization scaffold

Layer 3 exists physically and loads after Layer 2. Its presence does not define Layer 2 completion: the PTY, WebMessagePort, lifecycle recovery, renderer fallback, explicit clipboard actions, link activation, accessibility, font-scale adaptation, storage, and document transport must remain complete when Layer 3 is empty or omitted.

The dependency direction is fixed:

```text
Layer 1 public API
        ↓
Layer 2 stable capability (`AndroidTerminalLayer2`)
        ↓
Layer 3 customization
```

Layer 2 never imports or names the Layer 3 implementation. Layer 3 may use only the stable Layer 2 capability and public xterm.js APIs exposed through it; it may not access WebMessagePort, JNI, PTY/session internals, or xterm.js private objects.

The current scaffold contains no custom UI. It owns the project light/dark terminal palettes because palette choice is product policy, while Layer 2 owns only the Android `uiMode` state and neutral notification. Future special keys, modifier bars, user themes, font selection, search UI, progress presentation, userland, and workspace features also belong here and require separate owner decisions.

## Upgrade and change boundary

```text
upstream update       vendor/** and exact receipt only
Android adaptation    bridge/**, Kotlin platform host, JNI/C, manifest, verifier
product customization customization/** and TerminalCustomization.kt only
```

`tools/verify-layer-boundaries.py` rejects modified or unexpected Layer 1 assets, Layer 2 dependencies on Layer 3, Layer 3 access to transport/native internals, xterm.js private API use, custom terminal semantics, and Android adaptation that bypasses the stable contract. The machine authority is [`upstream-capabilities.json`](upstream-capabilities.json), verified by `tools/verify-upstream-capabilities.py`; [`capability-matrix.md`](capability-matrix.md) is its human-readable view.
