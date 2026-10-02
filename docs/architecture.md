# Architecture

Android Terminal is a thin Android host for unmodified upstream xterm.js and Android's native shell. Layer 2 is completed before Layer 3 product features are introduced.

## Project-level scope

- **In the repository** — the terminal mechanism and the minimum native account/session baseline
- **Outside the repository** — user configuration and use
- **Layer 1/2/3** — orthogonal to that scope; the implementation approach for connecting upstream xterm.js and Android-native behavior with minimal intervention

## Layer authority

```text
Layer 1  unmodified upstream xterm.js/addons and Android-provided runtime
   ↓ public upstream APIs
Layer 2  complete Android adaptation and native integration
   ↓ stable optional capability
Layer 3  product customization scaffold
```

Classification is by responsibility, not file language or feature size:

1. exact upstream bytes and behavior are Layer 1
2. work required to make an upstream capability fully usable under Android is Layer 2
3. a feature that is not required for Android adaptation and changes the product beyond the upstream host is Layer 3

Examples:

- **Layer 3** — a bundled userland
- **Layer 2** — Android storage permissions, WebView lifecycle recovery, PTY integration, Android mappings for xterm.js public APIs

## Layer 1: unmodified upstream

### Vendored xterm.js frontend

- **Location** — `app/src/main/assets/terminal/vendor/`
- **Contents** — exact production files from pinned official npm releases of `@xterm/xterm` and the stable Layer 2 addon set: fit, serialize, clipboard, image, progress, search, unicode11, web-fonts, ligatures, web-links, webgl
- **Acquisition** — `tools/acquire-web-terminal-assets.sh` verifies fixed npm integrity values, validates archive shape, installs only selected production files, and records exact installed identities in `ASSET_RECEIPT.json`
- **Never edited** — files are used as published
- **xterm.js owns** — terminal parsing, screen state, Unicode layout, cursor behavior, selection, scrollback, keyboard/IME semantics, rendering
- **Official addons own** — their own feature semantics
- **Routine upstream update** — changes only `vendor/**`, package coordinates, and the receipt

### Android-provided runtime

- Android supplies System WebView, Bionic, the dynamic linker, `/system/bin/sh`, and `/system/bin` executables
- None are copied into the APK

## Layer 2: complete Android adaptation

```text
Android Activity / Service / WebView / platform APIs
                         ↓
                 stable terminal contract
                         ↕
                public xterm.js APIs

/system/bin/sh ↔ PTY/JNI ↔ TerminalSessionService ↔ WebMessagePort ↔ xterm.js
```

Layer 2 is the active product scope. It exposes upstream functionality through public xterm.js or WebView APIs and adds only the Android connection that functionality needs.

Current responsibilities:

- **Frontend lifetime** — replaceable Activity/WebView frontend; service-owned PTY
- **WebView security**
  - synthetic local origin, exact asset allowlist, CSP
  - no WebView runtime network access, even though the app UID grants native child processes `INTERNET`
  - the CSP adds only `'wasm-unsafe-eval'` beyond same-origin scripts (the official ImageAddon compiles embedded WebAssembly); JavaScript string compilation stays disabled
- **Contract** — versioned WebMessagePort contract, attachment generations, capability handshake, bounded byte transport, ACK/backpressure, explicit failures
- **Geometry** — Android window, inset, rotation, focus, IME viewport, `ResizeObserver`, and `visualViewport` changes reduced through `addon-fit` to deduplicated `TIOCSWINSZ` updates
- **Input** — xterm input callbacks connected to PTY writes without reinterpreting keyboard or terminal semantics
- **Platform capabilities**
  - explicit clipboard actions and official OSC 52 clipboard handling
  - official image, progress, search, Unicode 11, web-font, and ligature capabilities
  - OSC 8 URI activation and official plain-text web-link activation
  - bell, Android color-scheme state, accessibility, touch exploration, hardware-keyboard state, font scale
  - Android-localized upstream strings
  - neutral service-owned title state, mapped through public APIs
- **Window reports** — truthful xterm reports for cell pixels, terminal pixels, rows/columns, title stack, refresh, and current title; desktop position, stacking, screen, fullscreen, and terminal-driven host resize stay disabled
- **Renderer** — official WebGL activation, with one-way fallback to xterm core DOM rendering after activation failure or public `onContextLoss`
- **Replacement frontends** — official serialize-addon snapshots plus a bounded raw PTY tail
- **Documents** — SAF import/export for explicit document transactions
- **Shared storage** — Android 10 runtime permissions, Android 11+ all-files special access, startup entry into the official grant flow, neutral reporting of the actual platform path and grant state
- **Executable `HOME`** — API 28 compatibility targeting, so user-provided executables under writable app-private `HOME` stay launchable without a custom linker or loader shim
- **PTY** — creation, login-shell `/system/bin/sh` execution via the standard leading-hyphen `argv[0]`, signals, reads, writes, resize, wait, and cleanup through the minimum JNI/C syscall bridge

Layer 2 may contain fixed safety limits and neutral host mappings needed to make a feature operational. It must not contain a custom VT parser, screen model, renderer, shell-command semantics, bundled userland, package manager, or distribution filesystem.

### Executable HOME compatibility boundary

- **Versions** — `minSdk 29` and native bridge API floor 29, with `targetSdk 28`
- **Reason** — Android 10 applies the writable-app-home `execve()` prohibition to apps targeting API 29 or later; this is a Layer 2 compatibility decision
- **Not used** — custom dynamic linker, executable relocation service, copied loader, bundled userland
- **Result** — user-provided Android executables stay ordinary files launched by `/system/bin/sh`
- **Device gate** — actual execution on a device

### Native account/session and shared-storage boundary

- **Environment** — the child inherits the Android application environment; Layer 2 replaces only `HOME`, `TMPDIR`, and `TERM`
- **Paths** — `HOME` is `filesDir`; `TMPDIR` is the distinct `cacheDir/tmp`; session startup creates no entry under `HOME`
- **Why shared storage is Layer 2** — Android permission is required before the app UID can use ordinary paths such as `/storage/emulated/0/Download`
- **Permissions** — the app declares `MANAGE_EXTERNAL_STORAGE`, uses the API 28 compatibility target with API 29 read/write runtime permissions, and enters the official Android system grant flow immediately when needed
- **Denial** — grant status is a user/device decision; denial blocks neither the private shell nor SAF
- **Layer 2 does not** — create `HOME/storage`, pass a shared-storage coordinate through JNI, or synthesize `EXTERNAL_STORAGE`
- **Shell** — uses real Android paths under the app UID's actual grant
- **SAF** — stays available for explicit import/export; no fixed `HOME` inbox; caller-selected `HOME`-relative import destination; never a virtual mount

See [`native-account-session.md`](native-account-session.md).

### Native process network boundary

- **Permission** — `android.permission.INTERNET` is a normal app-UID permission, so `/system/bin/sh` children and user-provided Android-native tools can open sockets without a private userland or proxy bridge
- **Not synthesized** — environment variables, resolver replacement, certificate bundle, VPN policy, command wrapper
- **Tool behavior** — subject to Android DNS, routing, SELinux, VPN, proxy, certificate, and remote-server policy
- **WebView stays local** — `WebSettings.blockNetworkLoads` enabled, exact local asset allowlist, navigation rejected, page CSP `connect-src 'none'`

### Plain-text web-link mapping

- **Upstream owns** — `@xterm/addon-web-links`: URL recognition, wrapped-line handling, hover decorations, terminal-buffer link semantics
- **Layer 2 supplies** — only the addon activation callback
- **Shared operation** — the callback reuses the bounded Android `open-external-uri` operation used for OSC 8 links, so only validated HTTP/HTTPS URIs without embedded credentials reach `ACTION_VIEW`
- **Layer 2 does not** — copy the upstream regular expression, register a private xterm link provider, call `window.open`, or navigate the local WebView
- **Network permission** — exists for native shell processes; it is not a WebView fetch path
- **Bytes** — upstream package unmodified in Layer 1; Android owns only external intent activation

### Android font-scale mapping

- **Android owns** — the user-selected `fontScale`
- **xterm.js owns** — the default font size and rendering
- **Mapping** — Layer 2 reads public `terminal.options.fontSize` from each new upstream terminal, freezes it as that instance's baseline, and multiplies it by the bounded Android scale
- **No compounding** — repeated configuration updates recompute from the captured baseline
- **Not encoded** — xterm.js's numeric default, a terminal font preference, or WebView text zoom as a second scaling authority
- **Delivery** — `onConfigurationChanged`, then the public xterm option, then the existing `addon-fit`/geometry path before any changed dimensions reach `TIOCSWINSZ`
- **Why Layer 2** — it connects Android accessibility/display configuration to an upstream public capability; size and rendering semantics stay upstream

### Core host integration boundary

- **Title**
  - OSC 0/2 changes stay upstream-parsed
  - Layer 2 listens through `Terminal.onTitleChange`, removes C0/DEL control characters, bounds the value to 1024 Unicode code points, stores it with the service-owned PTY session, and restores it to a replacement frontend
  - Layer 3 decides whether and where to show it
- **Strings** — Android resources supply only xterm's public `promptLabel` and `tooMuchOutput`; Layer 2 sends the current locale tag and applies them through `Terminal.strings` with a neutral 512-code-point bound; product copy is Layer 3
- **Window operations**
  - only reports xterm can answer from its own geometry and title state are enabled
  - upstream default handlers keep cell-pixel, terminal-pixel, row/column, and title-stack semantics
  - public parser/input/refresh APIs handle refresh and current-title reports
  - Android desktop-window approximations are forbidden

### Stable addon integration wave

Layer 2 loads these automatically through their public APIs:

- **ClipboardAddon** — official default Base64 implementation with a bounded plain-text Android provider
- **ImageAddon** — upstream constructor defaults
- **ProgressAddon** — exposes neutral state
- **SearchAddon** — exposes its engine without UI
- **Unicode11Addon** — registered without changing the active provider; `allowProposedApi` is enabled solely because the official Unicode namespace requires it
- **WebFontsAddon** — exposes loading/relayout without selecting a font

Ligatures:

- the official LigaturesAddon 0.10.0 ESM entry stays unmodified in Layer 1 and is exposed through a minimal Layer 2 module adapter
- a one-time Layer 2 capability, activated only when Layer 3 explicitly requests it
- an active WebGL renderer is then reactivated through the Layer 2 renderer controller, as the official ligatures contract requires

### Login shell boundary

- The native bridge executes the Android-provided `/system/bin/sh` directly with the unchanged environment
- It marks a login shell solely by passing `-sh` as `argv[0]`, the conventional shell interface
- It adds no shell wrapper, profile injection, userland, loader, or command string
- Startup-file interpretation stays with the Android-provided shell

### Upstream update delegation

Layer 2 never copies upstream feature logic just to expose it on Android. For each capability, in order:

1. use xterm.js core when core owns the capability
2. use an official addon when an addon owns it
3. connect that public surface to Android native APIs when an Android connection is required
4. keep an explicit pending or exclusion state instead of a private substitute

Feature updates stay with xterm.js; this repository owns only Android integration.

## Layer 3: optional customization scaffold

Layer 3 exists physically and loads after Layer 2. Layer 2 completion does not depend on it. These stay complete when Layer 3 is empty or omitted:

- PTY, WebMessagePort, lifecycle recovery, renderer fallback
- explicit clipboard actions, link activation, accessibility
- localized upstream strings, neutral title state, safe window reports
- font-scale adaptation, storage, document transport

Dependency direction:

```text
Layer 1 public API
        ↓
Layer 2 stable capability (`AndroidTerminalLayer2`)
        ↓
Layer 3 customization
```

- **Layer 2** — never imports or names the Layer 3 implementation
- **Layer 3** — may use only the stable Layer 2 capability and the public xterm.js APIs it exposes; no access to WebMessagePort, JNI, PTY/session internals, or xterm.js private objects
- **Contracts** — extension contract 4 adds an immutable completion manifest and a read-only runtime snapshot; Layer 3 scaffold contract 2 binds that schema without Layer 2 requiring it

Current scaffold:

- **Owns** — project light/dark terminal palettes and touch arbitration (product policy); Layer 2 owns neutral Android state and operations
- **Does not own** — a terminal model or a persistent WebView toolbar
- **Selection** — long press maps public buffer cells into xterm's public `select()`; Layer 3 neither parses terminal text nor keeps a second selection buffer
- **Selection action menu (planned)** — Layer 3 requests a bounded native selection-action surface through Layer 2 and consumes only the resulting Copy/Paste/Select all events; a prototype of that facade exists
- **Future, as separate decisions** — special keys, modifier bars, user themes, font selection, search UI, progress presentation, userland, workspace features

## Upgrade and change boundary

```text
upstream update       vendor/** and exact receipt only
Android adaptation    bridge/**, Kotlin platform host, JNI/C, manifest, verifier
product customization customization/** and TerminalCustomization.kt only
```

- **`tools/verify-layer-boundaries.py`** rejects modified or unexpected Layer 1 assets, Layer 2 dependencies on Layer 3, Layer 3 access to transport/native internals, xterm.js private API use, custom terminal semantics, and Android adaptation that bypasses the stable contract
- **Capability authority** — [`upstream-capabilities.json`](upstream-capabilities.json), verified by `tools/verify-upstream-capabilities.py`; [`capability-matrix.md`](capability-matrix.md) is its human-readable view
- **Repository closure** — [`layer2-completion.json`](layer2-completion.json) and `tools/verify-layer2-completion.py` cross-check the asset receipt, runtime extension contract, CSP requirements, Layer 3 scaffold contract, version, and remaining device gates
