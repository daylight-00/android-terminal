# Architecture

Android Terminal is a thin Android host for unmodified upstream xterm.js and Android's native shell. The project completes Layer 2 before introducing Layer 3 product features.

## Layer authority

```text
Layer 3  reserved product customization; absent from the active runtime
   ↓
Layer 2  complete Android adaptation and native integration
   ↓
Layer 1  unmodified upstream xterm.js/addons and Android-provided runtime
```

The classification test is responsibility, not file language or feature size:

1. exact upstream bytes and behavior are Layer 1;
2. work required to make an upstream capability fully usable under Android is Layer 2;
3. a feature that is not required for Android adaptation and changes the product beyond the upstream host is Layer 3.

A bundled userland is Layer 3. Android storage permissions, WebView lifecycle recovery, PTY integration, and Android mappings for xterm.js public APIs are Layer 2.

## Layer 1: unmodified upstream

### Vendored xterm.js frontend

`app/src/main/assets/terminal/vendor/` contains exact production files from pinned official npm releases of `@xterm/xterm`, `@xterm/addon-fit`, `@xterm/addon-serialize`, and `@xterm/addon-webgl`. `tools/acquire-web-terminal-assets.sh` verifies the fixed npm integrity values, validates archive shape, installs only selected production files, and records exact installed identities in `ASSET_RECEIPT.json`.

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
- clipboard, OSC 8 URI activation, bell, system theme, accessibility, touch exploration, hardware-keyboard state, and font-scale signals mapped to Android native APIs;
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

### Upstream update delegation

Layer 2 never copies upstream feature logic merely to expose it on Android. For each capability it must, in order:

1. use xterm.js core when core owns the capability;
2. use an official addon when an addon owns it;
3. connect that public surface to Android native APIs when an Android connection is required;
4. retain an explicit pending or exclusion state instead of implementing a private substitute.

This keeps feature-update responsibility with xterm.js while this repository owns only Android integration.

## Layer 3: reserved and inactive

Layer 3 is not part of the current runtime, asset graph, or build authority. No `customization/**` script, native customization object, userland, package manager, command profile, modifier bar, workspace manager, or product-specific feature is loaded.

A future Layer 3 change requires an explicit owner decision and must consume only public Layer 2 capabilities. It may not access WebMessagePort, JNI, PTY internals, or xterm.js private APIs. Ambiguous behavior remains in Layer 2 only when it is necessary to make an upstream capability operable on Android; otherwise it stays unimplemented.

## Upgrade and change boundary

```text
upstream update       vendor/** and exact receipt only
Android adaptation    bridge/**, Kotlin platform host, JNI/C, manifest, verifier
product customization reserved; no active runtime path
```

`tools/verify-layer-boundaries.py` rejects modified or unexpected Layer 1 assets, active Layer 3 runtime files, xterm.js private API use, custom terminal semantics, and Android adaptation that bypasses the stable contract. Current and pending integrations are tracked in [`capability-matrix.md`](capability-matrix.md).
