# Architecture

Android Terminal is a platform host for upstream xterm.js and Android's native shell, not a terminal emulator or userland implementation.

## Layers

```text
Layer 3  explicit product customization
   ↓
Layer 2  Android platform integration and stable terminal contract
   ↓
Layer 1  upstream xterm.js plus Android-provided shell/runtime
```

## Layer 1: upstream runtime

Layer 1 has two upstream authorities.

### Vendored frontend

`app/src/main/assets/terminal/vendor/` contains the exact production files selected from the pinned official npm releases of `@xterm/xterm` and `@xterm/addon-fit`. The files are acquired by `tools/acquire-web-terminal-assets.sh`, recorded in `ASSET_RECEIPT.json`, and are not edited by hand.

xterm.js owns terminal parsing, screen state, Unicode layout, cursor behavior, selection, scrollback, IME integration, and rendering. `addon-fit` owns geometry-to-row/column calculation.

### Device-provided runtime

Android provides the System WebView, Bionic libc, dynamic linker, `/system/bin/sh`, and `/system/bin` executables. None of these are copied into the APK.

## Layer 2: required Android integration

```text
Android lifecycle and secure local WebView host
                    ↓
             TerminalContract.kt
                    ↕
          terminal-contract.js
                    ↓
            terminal-bridge.js
                    ↓
           public xterm.js APIs

/system/bin/sh ↔ PTY/JNI ↔ TerminalSession ↔ WebMessagePort ↔ xterm.js
```

Layer 2 supplies only the connections required to make upstream functionality usable on Android:

- Activity and WebView lifecycle;
- a started/bound Android service that owns the PTY independently of the Activity;
- exact local HTTPS-like asset origin and CSP;
- versioned message contract, connection generations, and capability handshake;
- byte-preserving bounded transport with ACK/backpressure;
- Android IME/WebView input delivery to xterm.js;
- Android root-layout, window-inset, configuration, focus, WebView, and IME viewport changes;
- geometry changes through `addon-fit`, a deduplicated protocol v4 geometry contract, and `TIOCSWINSZ`;
- text-only clipboard reads/writes through xterm selection and paste public APIs plus Android `ClipboardManager`;
- OSC 8 link activation through xterm's public `linkHandler` and an exact HTTP/HTTPS Android `ACTION_VIEW` allowlist;
- xterm bell events through a bounded Android haptic adapter whose activation remains Layer 3 policy;
- Android light/dark, accessibility, touch-exploration, hardware-keyboard, and font-scale state signals;
- PTY creation, process execution, signals, reads, writes, and cleanup;
- bounded raw-output replay for replacement frontends, with explicit truncation;
- explicit startup and protocol failure reporting.

Layer 2 must use public xterm.js APIs and must not contain terminal appearance policy, a VT parser, a screen model, or shell-command semantics. `TerminalSessionService` is the session authority; `MainActivity` and `TerminalController` are replaceable frontend hosts. Protocol v4 retains the v2 session attachment identity, the v3 geometry contract, and adds a bounded request/result platform capability bridge. Every attachment is identified by a session ID and monotonically increasing connection generation so stale WebView messages cannot control the current PTY attachment.

The raw replay journal is intentionally bounded to 1 MiB. Before that bound is exceeded, a replacement frontend can reconstruct the terminal by replaying the unmodified PTY stream from session start. Once exceeded, Layer 2 does not attempt to parse or synthesize terminal state; it reports replay unavailability and continues with live output. Unlimited exact restoration requires an official upstream serialization capability rather than a custom terminal model.

## Layer 3: explicit customization

Web customization is isolated under `app/src/main/assets/terminal/customization/`:

- terminal options such as font size, scrollback, cursor, and colors;
- visual styling and loading/error text;
- an empty `#custom-ui-root` for optional future UI.

Native customization is isolated in `TerminalCustomization.kt`. It owns host colors, WebView text zoom, external-URI scheme policy, system-theme following, and whether terminal bells produce haptic feedback. Web customization owns light/dark palettes and whether Android accessibility state enables xterm screen-reader mode.

Layer 3 may use public Layer 2 capabilities, but it may not access the message port, JNI, PTY, or xterm.js private internals.

## Upgrade boundary

A routine upstream update should modify only `vendor/**` and its receipt. A platform integration change should modify Layer 2 without silently changing product policy. A product decision should modify Layer 3 without changing the PTY or transport contract.

```text
upstream asset commit       vendor/** only
platform integration commit bridge/Kotlin/C contract code
product policy commit       customization/** or TerminalCustomization.kt
```

`tools/verify-layer-boundaries.py` enforces the principal ownership rules. Any exception requires an explicit reviewed change to both the architecture document and verifier. The current and pending upstream connections are tracked in [`capability-matrix.md`](capability-matrix.md).
