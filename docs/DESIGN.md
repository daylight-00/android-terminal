# Design boundary

## Product definition

Android Terminal is a thin terminal frontend for Android’s native shell, not a new userland.

- **Android provides** — dynamic linker, Bionic libc, `/system/bin/sh`, system command binaries
- **The app provides** — a UI/frontend and the PTY/process bridge that makes that environment interactive inside an app UID

## Three-layer ownership

- The runtime is split into unmodified upstream, required Android integration, and an optional downstream customization scaffold
- File ownership and upgrade rules: [`architecture.md`](architecture.md)
- This document covers the runtime and security mechanics inside those boundaries

## Standard platform boundary

### Android SDK

- `android.app.Activity` owns the replaceable window/frontend host
- `android.app.Service` owns the PTY session independently of the Activity and WebView
- `android.webkit.WebView` supplies the rendering and JavaScript runtime
- `android.webkit.WebMessagePort` carries bounded terminal messages
- `WebViewClient.shouldInterceptRequest` serves an exact allowlist of APK assets from the synthetic `https://app.local` origin, with no server and no WebView network fetch
- Kotlin is used only for Android lifecycle and bridge glue

### Web terminal frontend

- **xterm.js** — pinned production files provide the parser, screen model, Unicode and IME behavior, scrollback, selection, cursor, and core DOM renderer; no custom VT parser or cell renderer remains
- **WebGL** — the official addon is a Layer 1 renderer that Layer 2 attempts automatically; on the public context-loss event Layer 2 disposes it and falls back to the core renderer without touching terminal state
- **Geometry** — `addon-fit` computes rows and columns from the WebView geometry
  - protocol v6 treats Android root layout, window-inset, configuration, focus, `ResizeObserver`, and `visualViewport` changes as geometry invalidations
  - only positive, changed row/column and pixel dimensions go to the service and then to `TIOCSWINSZ`
  - transient zero layouts and duplicates are discarded without implementing terminal semantics

Page-to-native protocol:

- **Messages** — JSON control messages
- **PTY bytes** — Base64, because platform API 29 `WebMessage` is string-based
- **Flow** — one output batch in flight at a time; xterm.js acknowledges completion through its `write` callback
- **Bounds** — frontend transport queue 2 MiB; the session service keeps at most 1 MiB of the unmodified raw PTY stream so a replacement frontend can attach and replay it without implementing terminal semantics
- **Overflow** — replay becomes explicitly unavailable while the live PTY continues

### Android NDK / Bionic

- `forkpty()` creates a PTY and child process
- `execve()` replaces the child with `/system/bin/sh`
- `read()` and `write()` transfer PTY bytes
- `ioctl(TIOCSWINSZ)` updates terminal dimensions
- the child gets a deliberately small environment and no custom loader path

## Security boundary

The WebView:

- runs under an app UID that declares `INTERNET` for native child processes, while WebView network loads stay blocked
- disables file and content access
- rejects all navigation except the single local document
- serves only twelve exact Layer 1/2 asset paths
- uses a restrictive Content Security Policy
- enables no JavaScript object bridge
- uses an HTML message channel transferred only to the local page

Native shell:

- **Network** — shares the app UID and its normal `INTERNET` permission
  - a direct Android capability: no proxy, resolver, certificate store, command wrapper, or network daemon
  - the local terminal page stays offline through `blockNetworkLoads`, exact local interception, navigation rejection, and CSP `connect-src 'none'`
- **Identity** — the child inherits the app UID and app SELinux domain; it is not ADB's UID 2000 `shell`
- **Limits** — system binary execution stays subject to file mode, seccomp, SELinux, Android permissions, and OEM policy

Environment:

- **Source** — the child inherits the Android application process environment
- **Merge** — before `forkpty()`, Layer 2 copies it, removes any `HOME`, `TMPDIR`, and `TERM` entries, and appends exactly:

```text
HOME=<app files directory>
TMPDIR=<app cache directory>/tmp
TERM=xterm-256color
```

- **Not introduced** — a fixed `PATH`, `SHELL`, `LANG`, `ANDROID_*`, `EXTERNAL_STORAGE`, XDG variable, `LD_LIBRARY_PATH`, Termux prefix, copied shell, or package manager
- **Child path** — descriptor closure, `chdir(HOME)`, direct `execve()`, `_exit()`

## External-input boundary

- **CSP** — the synthetic local origin uses `script-src 'self' 'wasm-unsafe-eval'`; the second source is required by the pinned official ImageAddon's embedded WebAssembly decoder and does not permit JavaScript `eval` or `Function`
- **Pins** — `@xterm/xterm` 6.0.0 plus fit 0.11.0, serialize 0.13.0, clipboard 0.2.0, image 0.9.0, progress 0.2.0, search 0.16.0, Unicode 11 0.9.0, web-fonts 0.1.0, ligatures 0.10.0 (unmodified ESM entry through a Layer 2 module adapter), web-links 0.12.0, WebGL 0.19.0
- **Acquisition** — the acquisition script fetches official npm tarballs, validates fixed npm SHA-512 integrity and safe members, and records extracted file SHA-256 and size in a local receipt
- **Licenses** — exact package metadata is retained for the serialize and WebGL addons, and their package-level `MIT` declarations are validated instead of inventing addon-specific license paths
- **Channel transfer** — the initial native-to-page transfer is target-origin restricted on Android; page JavaScript validates the channel marker and transferred port rather than assuming `MessageEvent.origin` identifies the native sender

## Known limitations

- Platform WebMessagePort on API 29 is string-based, so PTY data uses Base64
- WebView behavior varies with the installed Android System WebView
- WebGL is attempted automatically by Layer 2; activation, context loss, and DOM fallback still need real-device evidence
- ImageAddon WebAssembly compilation is authorized by the narrow CSP source; System WebView enforcement and inline-image rendering still need real-device evidence
- The PTY survives Activity/WebView replacement within the app process, but the service stops when the app task is removed
- Frontend reconstruction uses an official serialized xterm snapshot bounded to 8 MiB plus a rolling 1 MiB raw-output tail, and restores only state kept by the configured xterm scrollback
- Direct shared-storage access depends on user-granted Android storage access; settings routing, path readability/writability, and protected `/Android` subtrees need device evidence
- Device-runtime success and OEM `/system/bin` policy need device evidence

## Core host state and window reports

- **Title** — Layer 2 keeps OSC 0/2 title state with the service-owned PTY and exposes it through the stable Layer 2 capability; presentation is Layer 3
- **Strings** — Android locale resources populate xterm's public accessibility strings
- **Window reports** — limited to truthful cell/terminal geometry, rows/columns, title stack, refresh, and current-title behavior through public xterm APIs
- **Not mapped** — desktop position, stacking, iconify, maximize, screen metrics, fullscreen, terminal-driven host resizing

## Login-shell adaptation

- Layer 2 launches the Android-provided `/system/bin/sh` with `-sh` as `argv[0]`; that is the complete login-shell adaptation
- Unchanged: executable path, environment, direct `execve`, PTY ownership, Android-provided startup-file semantics
- Not introduced: an `-l` wrapper, command string, alternate loader, profile injection, bundled shell
