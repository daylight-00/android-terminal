# Architecture

Android Terminal is a thin Android host for unmodified upstream xterm.js and Android's native shell. The project completes Layer 2 before introducing Layer 3 product features.

## Project-level scope

At the largest scale, the project consists of the terminal mechanism and the minimum native account/session baseline. Actual user configuration and use are outside the repository. The repository Layer 1/2/3 design is orthogonal: it is the implementation philosophy used mainly to connect upstream xterm.js and Android-native behavior with minimal intervention.

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

`app/src/main/assets/terminal/vendor/` contains exact production files from pinned official npm releases of `@xterm/xterm` and the stable Layer 2 addon set: fit, serialize, clipboard, image, progress, search, unicode11, web-fonts, ligatures, web-links, and webgl. `tools/acquire-web-terminal-assets.sh` verifies the fixed npm integrity values, validates archive shape, installs only selected production files, and records exact installed identities in `ASSET_RECEIPT.json`.

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
- secure synthetic local origin, exact asset allowlist, CSP, and no WebView runtime network access even though the app UID grants native child processes `INTERNET`; the CSP grants only `'wasm-unsafe-eval'` beyond same-origin scripts because the official ImageAddon compiles embedded WebAssembly, while JavaScript string compilation remains disabled;
- versioned WebMessagePort contract, attachment generations, capability handshake, bounded byte transport, ACK/backpressure, and explicit failures;
- Android window, inset, rotation, focus, IME viewport, `ResizeObserver`, and `visualViewport` geometry reduced through `addon-fit` to deduplicated `TIOCSWINSZ` updates;
- xterm input callbacks connected to PTY writes without reinterpreting keyboard or terminal semantics;
- explicit clipboard actions plus official OSC 52 clipboard handling, official image/progress/search/Unicode 11/web-font/ligature capabilities, OSC 8 URI activation, official plain-text web-link activation, bell, Android color-scheme state, accessibility, touch exploration, hardware-keyboard state, font scale, Android-localized upstream strings, and neutral service-owned title state mapped through public APIs;
- truthful xterm window reports for cell pixels, terminal pixels, rows/columns, title stack, refresh, and current title, while desktop position/stacking/screen/fullscreen/terminal-driven host resize operations remain disabled;
- official WebGL renderer activation with one-way fallback to xterm core DOM rendering after activation failure or public `onContextLoss` notification;
- official serialize-addon snapshots plus a bounded raw PTY tail for replacement frontends;
- SAF import/export for explicit document transactions;
- direct shared-storage adaptation: Android 10 runtime permissions, Android 11+ all-files special access, startup entry into the official Android grant flow, and neutral reporting of the actual platform path and grant state;
- API 28 compatibility targeting so owner-provided executables under writable app-private HOME remain launchable without a custom linker or loader shim;
- PTY creation, login-shell `/system/bin/sh` execution via the standard leading-hyphen `argv[0]` convention, signals, reads, writes, resize, wait, and cleanup through the minimum JNI/C syscall bridge.

Layer 2 may contain fixed safety limits and neutral host mappings required to make a feature operational. It must not contain a custom VT parser, screen model, renderer, shell-command semantics, bundled userland, package manager, or distribution filesystem.

### Executable HOME compatibility boundary

The app keeps `minSdk 29` and the native bridge API floor at 29, but declares `targetSdk 28`. This is a Layer 2 compatibility decision: Android 10 applies the writable-app-home `execve()` prohibition to apps targeting API 29 or later. The project does not absorb that platform transition through a custom dynamic linker, executable relocation service, copied loader, or bundled userland. Owner-provided Android executables remain ordinary files launched by `/system/bin/sh`; actual device execution is still a target gate.

### Native account/session and shared-storage boundary

The child inherits the Android application environment and Layer 2 replaces only `HOME`, `TMPDIR`, and `TERM`. `HOME` is `filesDir`, `TMPDIR` is the distinct `cacheDir/tmp` namespace, and session startup does not create any entry under `HOME`.

Direct POSIX shared-storage access is Layer 2 because Android permission is required before the app UID can use ordinary paths such as `/storage/emulated/0/Download`. The app declares `MANAGE_EXTERNAL_STORAGE`, uses the API 28 compatibility target with API 29 read/write runtime permissions, and immediately enters the official Android system grant flow when needed. Grant status remains a device/user decision; denial does not block the private shell or SAF.

Layer 2 does not create `HOME/storage`, pass a shared-storage coordinate through JNI, or synthesize `EXTERNAL_STORAGE`. The shell uses real Android paths under the app UID's actual grant. SAF remains available for explicit document import/export, imposes no fixed HOME inbox, accepts a caller-selected HOME-relative import destination, and does not become a virtual mount. See `docs/native-account-session.md`.

### Native process network boundary

`android.permission.INTERNET` is declared as a normal app-UID permission so `/system/bin/sh` children and owner-provided Android-native tools can open network sockets without a private userland or proxy bridge. No environment variable, resolver replacement, certificate bundle, VPN policy, or command wrapper is synthesized. Tool behavior remains subject to Android DNS, routing, SELinux, VPN, proxy, certificate, and remote-server policy.

The permission does not convert the terminal page into a network client. `WebSettings.blockNetworkLoads` remains enabled, the synthetic-origin asset client serves an exact local allowlist, navigation remains rejected, and the page CSP keeps `connect-src 'none'`.

### Plain-text web-link mapping

The official `@xterm/addon-web-links` package owns URL recognition, wrapped-line handling, hover
decorations, and terminal-buffer link semantics. Layer 2 supplies only the addon activation callback.
That callback reuses the same bounded Android `open-external-uri` operation as OSC 8 links, so only
validated HTTP/HTTPS URIs without embedded credentials reach `ACTION_VIEW`.

Layer 2 does not copy the upstream regular expression, register a private xterm link provider, call
`window.open` or navigate the local WebView. The app UID network permission exists for native shell processes and does not become a WebView fetch path. Upstream package bytes
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

### Core host integration boundary

OSC 0/2 title changes remain upstream-parsed. Layer 2 listens through `Terminal.onTitleChange`, removes C0/DEL control characters, bounds the value to 1024 Unicode code points, stores it with the service-owned PTY session, and restores it to a replacement frontend. Layer 3 decides whether and where that neutral title is displayed.

Android resources supply only xterm's public `promptLabel` and `tooMuchOutput` strings. Layer 2 transports the current locale tag and applies those values through `Terminal.strings`, with a neutral 512-code-point bound. Product copy remains Layer 3.

The window-operation bridge enables only truthful reports that xterm can answer from its own geometry and title state. Upstream default handlers retain cell-pixel, terminal-pixel, row/column, and title-stack semantics; public parser/input/refresh APIs handle refresh and current-title reports. Android desktop-window approximations are forbidden.

### Stable addon integration wave

Layer 2 automatically loads ClipboardAddon, ImageAddon, ProgressAddon, SearchAddon, Unicode11Addon, and WebFontsAddon using their public APIs. ClipboardAddon retains the official default Base64 implementation and receives a bounded plain-text Android provider; ImageAddon retains upstream constructor defaults; ProgressAddon exposes neutral state; SearchAddon exposes its engine without UI; Unicode 11 is registered without changing the active provider; and Web Fonts exposes loading/relayout without selecting any font. `allowProposedApi` is enabled solely because the official Unicode namespace requires that opt-in. The official LigaturesAddon 0.10.0 ESM entry remains unmodified in Layer 1 and is exposed through a minimal Layer 2 module adapter. Ligatures remain a one-time Layer 2 capability and activate only after Layer 3 explicitly requests them; an active WebGL renderer is then reactivated through the Layer 2 renderer controller as required by the official ligatures contract.

### Login shell boundary

The native bridge still executes the Android-provided `/system/bin/sh` directly with the unchanged environment. It marks the shell as a login shell solely by passing `-sh` as `argv[0]`, the conventional shell interface. No shell wrapper, profile injection, userland, loader, or command string is added. Startup-file interpretation remains the responsibility of the Android-provided shell.

### Upstream update delegation

Layer 2 never copies upstream feature logic merely to expose it on Android. For each capability it must, in order:

1. use xterm.js core when core owns the capability;
2. use an official addon when an addon owns it;
3. connect that public surface to Android native APIs when an Android connection is required;
4. retain an explicit pending or exclusion state instead of implementing a private substitute.

This keeps feature-update responsibility with xterm.js while this repository owns only Android integration.

## Layer 3: optional customization scaffold

Layer 3 exists physically and loads after Layer 2. Its presence does not define Layer 2 completion: the PTY, WebMessagePort, lifecycle recovery, renderer fallback, explicit clipboard actions, link activation, accessibility, localized upstream strings, neutral title state, safe window reports, font-scale adaptation, storage, and document transport must remain complete when Layer 3 is empty or omitted.

The dependency direction is fixed:

```text
Layer 1 public API
        ↓
Layer 2 stable capability (`AndroidTerminalLayer2`)
        ↓
Layer 3 customization
```

Layer 2 never imports or names the Layer 3 implementation. Layer 3 may use only the stable Layer 2 capability and public xterm.js APIs exposed through it; it may not access WebMessagePort, JNI, PTY/session internals, or xterm.js private objects. Extension contract 4 adds an immutable completion manifest and a read-only runtime snapshot; Layer 3 scaffold contract 2 binds that schema without becoming required by Layer 2.

The current scaffold contains no custom UI. It owns the project light/dark terminal palettes because palette choice is product policy, while Layer 2 owns only the Android `uiMode` state and neutral notification. Future special keys, modifier bars, user themes, font selection, search UI, progress presentation, userland, and workspace features also belong here and require separate owner decisions.

## Upgrade and change boundary

```text
upstream update       vendor/** and exact receipt only
Android adaptation    bridge/**, Kotlin platform host, JNI/C, manifest, verifier
product customization customization/** and TerminalCustomization.kt only
```

`tools/verify-layer-boundaries.py` rejects modified or unexpected Layer 1 assets, Layer 2 dependencies on Layer 3, Layer 3 access to transport/native internals, xterm.js private API use, custom terminal semantics, and Android adaptation that bypasses the stable contract. The machine capability authority is [`upstream-capabilities.json`](upstream-capabilities.json), verified by `tools/verify-upstream-capabilities.py`; [`capability-matrix.md`](capability-matrix.md) is its human-readable view. Repository closure is separately bound by [`layer2-completion.json`](layer2-completion.json) and `tools/verify-layer2-completion.py`, which cross-check the exact asset receipt, runtime extension contract, CSP requirements, Layer 3 scaffold contract, version, and remaining device gates.
