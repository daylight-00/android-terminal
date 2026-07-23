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

`app/src/main/assets/terminal/vendor/` contains the exact production files selected from the pinned official npm releases of `@xterm/xterm`, `@xterm/addon-fit`, and `@xterm/addon-serialize`. The files are acquired by `tools/acquire-web-terminal-assets.sh`, recorded in `ASSET_RECEIPT.json`, and are not edited by hand.

`@xterm/addon-serialize@0.13.0` publishes no standalone `LICENSE` member. Layer 1 therefore retains its exact `package.json` to record the package-level `MIT` declaration, while `LICENSE.xterm.txt` preserves the upstream xterm.js project license. No license text is synthesized or attributed to a nonexistent archive member.

xterm.js owns terminal parsing, screen state, Unicode layout, cursor behavior, selection, scrollback, IME integration, and rendering. `addon-fit` owns geometry-to-row/column calculation. `addon-serialize` owns xterm framebuffer and mode serialization.

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

- Activity and WebView lifecycle, including renderer-process replacement without restarting the PTY;
- a started/bound Android service that owns the PTY independently of the Activity;
- exact local HTTPS-like asset origin and CSP;
- versioned message contract, connection generations, and capability handshake;
- byte-preserving bounded transport with ACK/backpressure;
- Android IME/WebView input delivery to xterm.js;
- Android root-layout, window-inset, configuration, focus, WebView, and IME viewport changes;
- geometry changes through `addon-fit`, a deduplicated protocol v6 geometry contract, and `TIOCSWINSZ`;
- text-only clipboard reads/writes through xterm selection and paste public APIs plus Android `ClipboardManager`;
- OSC 8 link activation through xterm's public `linkHandler` and an exact HTTP/HTTPS Android `ACTION_VIEW` allowlist;
- xterm bell events through a bounded Android haptic adapter whose activation remains Layer 3 policy;
- Android light/dark, accessibility, touch-exploration, hardware-keyboard, and font-scale state signals;
- bounded SAF import from one `content://` document into a real file under the app-private `HOME/imports`;
- bounded SAF export from one validated HOME-relative readable file through `ACTION_CREATE_DOCUMENT`;
- PTY creation, process execution, signals, reads, writes, and cleanup;
- opaque official xterm serialized snapshots plus a bounded raw-output tail for replacement frontends;
- explicit startup and protocol failure reporting.

Layer 2 must use public xterm.js APIs and must not contain terminal appearance policy, a VT parser, a screen model, or shell-command semantics. `TerminalSessionService` is the session authority; `MainActivity` and `TerminalController` are replaceable frontend hosts. Protocol v6 retains the v2 session attachment identity and v3 geometry contract, extends the bounded request/result platform bridge, and adds asynchronous SAF document transport. Every attachment is identified by a session ID and monotonically increasing connection generation so stale WebView messages cannot control the current PTY attachment.

The official serialize addon produces an opaque xterm state stream after acknowledged output. Layer 2 stores at most 8 MiB of that stream together with the exact PTY output sequence it covers, without parsing terminal semantics. A rolling 1 MiB raw-output journal then supplies only the contiguous tail after that watermark. During frontend replacement the serialized state is restored first, acknowledged, and followed by the raw tail. If either bound cannot bridge the sequence gap, Layer 2 fails explicitly rather than synthesizing a screen model. This restores the current configured xterm buffer regardless of how much older output the session produced; it does not claim archival recovery of data already discarded by xterm scrollback policy.

SAF transport copies bytes immediately and never presents a `content://` URI as a POSIX path. Imports receive sanitized collision-safe names under `HOME/imports`; exports accept only bounded HOME-relative readable files whose canonical path remains inside the private HOME. Directory trees, persistent URI grants, virtual mounts, FUSE, and format interpretation remain outside Layer 2.

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
