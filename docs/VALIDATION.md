# Validation model

## Repository evidence

Repository verification covers:

- exact local Git content and identity
- native source shape and NDK r27d compilation when that NDK exists
- JavaScript codec/protocol behavior independent of xterm.js bytes
- pure JavaScript WebGL activation, context-loss cleanup, one-way fallback, and no-retry behavior
- WebView local-origin/network isolation, native child network permission, and absence of a bundled userland

It makes no installation, device-runtime, OEM-policy, or sustained-performance claim.

## Layer-boundary verifier

- **`tools/verify-layer-boundaries.py`**
  - upstream assets stay isolated
  - Layer 2 uses only the stable contract and the public xterm.js surface
  - Layer 3 loads strictly after Layer 2; Layer 2 never depends on it
  - Layer 3 cannot reach transport, native, or private internals
  - protocol versions and script load order match
  - every capability marked connected has a complete Android-native mapping
- **`tools/verify-upstream-capabilities.py`**
  - validates the machine-readable xterm.js core/addon inventory
  - requires every officially maintained addon exactly once, with the approved classification
  - binds the human-readable capability matrix to that inventory
  - mandatory fixtures: success, missing row, missing authority, Layer 3 bypass, Layer 2 dependency, theme authority
- **`tools/verify-layer2-completion.py`**
  - cross-checks `layer2-completion.json` against the asset receipt, runtime extension manifest, protocol/page capability, Layer 3 scaffold contract, app version, debug-only inspection surface, and the ImageAddon WebAssembly CSP requirement
  - negative fixtures remove the CSP permission and a pinned addon coordinate

## Repository verifier

`tools/verify-repository.sh` checks:

- minimum/native API 29, compatibility target API 28, NDK r27d, and arm64-only declarations
- Kotlin/WebView/WebMessagePort frontend and absence of the removed custom parser
- direct login-shell `/system/bin/sh` execution through `argv[0] = -sh` and `TERM=xterm-256color`
- no AndroidX, Compose, Rust, bundled shell/userland, or WebView runtime network path; native child processes intentionally inherit the app UID `INTERNET` permission
- local asset allowlist and restrictive WebView policy
- success, expected-negative, and missing-input fixtures, including Android font-scale, service-owned title, localized-string, and safe-window-report authorities

## External asset gate

- **Acquisition** — `tools/acquire-web-terminal-assets.sh` is the only normal path; it pins exact official npm URLs
- **Integrity** — existing packages keep fixed npm SHA-512 values; newly connected stable addons resolve the exact-version registry record and must match its tarball URL and SHA-512 before archive validation
- **Receipt** — the provisioner extracts only required production files and records archive and installed-file SHA-256/size in `ASSET_RECEIPT.json`
- **Pre-acquisition pin** — npm SHA-512 integrity, fail-closed; no pre-acquisition tarball SHA-256/size is claimed
- **Verification** — distinguishes an intentionally unprovisioned tree from a fully provisioned one, and rejects partial or unreceipted assets

## NDK verifier

- **`tools/verify-native-ndk.sh`** — runs `tools/build-native-bridge.sh`, builds one temporary `libshellbridge.so`, checks ELF machine, dependencies, and JNI exports; output is validation evidence and is not committed
- **Official toolchain** — the builder uses the NDK r27d compiler/linker when those host binaries execute normally
- **Native Android/Termux** — the NDK `linux-x86_64` linker is not a valid ARM64 Bionic executable, so the builder uses Termux's host-native `clang` and `ld.lld` with the exact NDK r27d sysroot, API 29 stubs, headers, and compiler runtime
- **x86 Linux workstation** — canonical path through `build-tools/pyproject.toml` and a CMake entry point using the official NDK CMake toolchain
- **Packaging** — Gradle packages the same generated arm64 library

## Android SDK build gate

- **`tools/prepare-android-sdk.sh`** — defaults to `$HOME/Android/Sdk` and fails closed unless platform 35, build-tools 35.0.0, and NDK 27.3.13750724 already exist there
- **No installs** — it downloads no SDK and installs no Termux packages
- **`aapt2`** — on Android/Termux it selects an installed host-native `aapt2` instead of letting AGP launch Google's x86_64 Linux binary
- **APK assembly** — passes that path through `android.aapt2FromMavenOverride`

## Writable app-home execution boundary

- **Static check** — `targetSdk 28` with `minSdk 29` and the native API 29 build floor
- **What it binds** — the intended Android compatibility behavior, with no custom linker, loader wrapper, or executable relocation mechanism
- **Proven by repository and APK** — the declared target
- **Real-device gate** — launching a user-provided ELF from app-private `HOME`

## Device gate

A device PASS requires a bounded receipt with at least:

- device identity, Android API, and Android System WebView version
- APK SHA-256 and installed package identity
- local page and message-channel startup
- shell startup, `id`, environment, and executable resolution
- PTY echo, Ctrl+C, resize, UTF-8/IME, scrollback, and lifecycle behavior
- complete first-failure context if any step fails

## Bounded single-device smoke evidence

- **Release policy** — the full device gate need not be closed before a GitHub release; a bounded manual smoke receipt may coexist with `repository-complete-device-validation-pending` when scope and nonclaims are explicit
- **2026-07-24 run** — one device passed the native account/session, writable-`HOME` executable, PTY/lifecycle, clipboard, direct shared-storage, external-link, and basic renderer probes
- **Executable probe** — used a user-provided `uv` binary, because the device blocked copying `/system/bin/sh`
- **SAF runtime** — `NOT_TESTED`, since no Layer 3 caller or product UI exists
- **Details** — [`device-smoke-validation.md`](device-smoke-validation.md)

## WebView channel startup

- The page replaces the loading overlay after receiving the exact `native-shell` marker with one transferred message port
- It does not reject the native channel by comparing `MessageEvent.origin`
- It shows a five-second startup diagnostic instead of an indefinite loading overlay

## Protocol v6, serialized-state, service-session, geometry, and platform boundary

Repository verification:

- **Pure Kotlin** — compiles and exercises the rolling replay buffer, opaque serialized-snapshot store, and terminal geometry state
- **Protocol** — executes protocol v6 in Node
- **Service ownership** — statically verifies that the service owns the PTY and the Activity only binds a frontend
- **Geometry** — rejects transient zero layouts, deduplicates unchanged sizes, and verifies changed WebView/IME viewport geometry before it reaches `TIOCSWINSZ`
- **Platform adapter** — compiles the pure URI/clipboard policy and the adapter against an API-shape stub, then runs these paths in Node:
  - clipboard, OSC 8 links, bell
  - Layer 3 palette, accessibility
  - Android-localized xterm strings
  - service-owned title restore/update, safe window reports
  - document import/export request-result, stale attachment
- **Documents** — pure Kotlin tests cover private-`HOME` path confinement, caller-selected import destinations, no fixed `HOME` inbox, name sanitation, MIME bounding, collision handling, and the size limit
- **API-shape compile** — covers `ACTION_OPEN_DOCUMENT`, `ACTION_CREATE_DOCUMENT`, `OpenableColumns`, and streaming `ContentResolver` access
- **Real framework integration** — the APK build (`gradle :app:assembleDebug`) is the authority for compiling it

ADB runtime validation is deferred when no authorized device transport is available. The missing device gate stays a non-claim. These still need a real-device test:

- Activity recreation, WebView replacement, stale-generation rejection, task-removal cleanup
- serialized-state restore, bounded snapshot/tail gap handling
- IME show/hide, rotation, split-screen
- clipboard privacy, external-link routing, haptic bell, accessibility services, physical-keyboard state
- WebGL activation, context loss, DOM fallback
- SAF provider import/export, cancellation, large files
- OEM WebView viewport behavior

## Plain-text web-link adaptation

Repository verification:

- requires the pinned official Web Links addon
- checks its Layer 1 bytes are installed only through the bounded npm acquisition path
- runs the page bridge with a fake official addon callback
- requires OSC 8 and detected plain-text links to use the same validated Android external-URI operation
- fails a fixture that replaces this route with direct browser navigation
- fails a fixture missing the addon script authority

Device evidence: touch activation and external intent resolution.

## Android font-scale adaptation

Repository verification:

- **Mapper** — runs the Layer 2 platform mapper with fake xterm.js instances whose public upstream defaults differ
- **Bounds** — Android scale is bounded to 0.5–3.0; invalid input returns to scale 1
- **Baseline** — repeated updates recompute from the captured upstream baseline and do not compound; no project-specific numeric base font is encoded
- **Channel test** — checks capability negotiation and the mapping of Android `fontScale` to xterm's public `fontSize` option
- **Static** — requires `fontScale` in Activity configuration handling, mirrored native/page capabilities, and dedicated success, expected-negative, and missing-authority fixtures

Device evidence: glyph metrics, visible sizing, rotation, PTY geometry after a system font-size change.

## Core title, localization, and safe-window integration

Repository verification:

- **Title** — runs `Terminal.onTitleChange` transport, control-character removal, the 1024-code-point service bound, replacement-frontend restoration, and Layer 3 notification
- **Localization** — compiles Android locale/resource mapping and checks `promptLabel` and `tooMuchOutput` through the public `Terminal.strings` surface
- **Window reports** — the Node fixture enables only truthful cell-pixel, terminal-pixel, row/column, title-stack, refresh, and current-title behavior
- **Negative fixtures** — reject desktop/screen window operations, an unsanitized service title, and missing localization authority

Device evidence: OSC title behavior, TalkBack announcements, locale switching, font metrics, terminal-query responses.

## WebGL renderer fallback

Repository verification runs the pure Layer 2 renderer controller with a fake official addon surface and checks:

- automatic addon activation
- public `onContextLoss` handling
- disposal of the addon and its event subscription
- permanent fallback to xterm core DOM rendering for the current frontend
- activation-failure and unavailable-addon fallback
- no retry loop

Device gate: System WebView GPU support and real context-loss behavior.

## Native account/session and direct shared storage

Repository verification:

- **Environment merge** — compiles the helper with a synthetic Android parent environment; unrelated values are preserved and exactly one `HOME`, `TMPDIR`, and `TERM` override is produced
- **Rejected synthesis** — fixed `PATH`, locale, `ANDROID_*`, XDG, and storage variables
- **`TMPDIR`** — Kotlin test proves `TMPDIR == cacheDir/tmp`, recreation when absent, rejection of a non-directory path, and an untouched `HOME`
- **Shared-storage fixture** — runs the API 29 runtime-permission and API 30+ all-files settings branches; checks app-specific settings first, generic fallback, startup request ownership, grant-state reporting, and the Android-reported direct path
- **Static policy** — rejects `HOME/storage`, symlink creation, a shared-storage JNI argument, and child environment synthesis

Device gates: permission dialogs, OEM settings routing, inherited environment values, direct read/write, cache eviction, protected `/Android` subtrees.

## WebView renderer recovery

- `onRenderProcessGone` destroys the failed WebView frontend, invalidates its attachment generation, and installs a replacement against the existing service-owned PTY
- a pure Kotlin recovery coordinator rejects duplicate and stale callbacks
- real renderer termination remains an ADB/device gate

## Stable official addon wave

Repository verification loads the official Clipboard, Image, Progress, Search, Unicode 11, Web Fonts, and Ligatures addons through `Terminal.loadAddon`.

- **Clipboard** — official addon's default Base64 implementation and a bounded plain-text Android provider
- **Image** — upstream constructor defaults
- **Progress** — exposes neutral state
- **Search, Unicode selection, web-font loading/relayout, ligature activation** — UI-free Layer 2 capabilities for Layer 3
- **Unicode 11** — the sole reason for the explicit `allowProposedApi` opt-in; Layer 2 does not change the active Unicode provider
- **Ligatures** — acquisition rejects the obsolete CommonJS filename and requires the official `lib/addon-ligatures.mjs` entry plus package `module` metadata; activation reactivates an active WebGL addon as upstream requires
- **WebAssembly** — the pinned ImageAddon has compilation sinks, so verification requires `script-src 'self' 'wasm-unsafe-eval'` and rejects JavaScript `'unsafe-eval'`
- **Negative fixtures** — wrong ClipboardAddon constructor boundary, missing addon assets, loss of login-shell `argv[0]` semantics

Device evidence: OSC 52, inline-image protocols and WebAssembly enforcement, WebView font access, ligature rendering, shell startup-file behavior.

- **Procedure** — [`device-validation.md`](device-validation.md)
- **Inspection** — only debug builds enable WebView inspection of `AndroidTerminalLayer2.completion.snapshot()`

## Native network and gesture-focus smoke

The manifest `INTERNET` permission is an app-UID capability for the native shell and user-provided executables. The terminal WebView stays local-only.

Bounded device check:

```sh
curl -I https://example.com
```

- A successful HTTPS response verifies the native-process path
- It does not cover DNS, proxy, VPN, captive-portal, cleartext HTTP, or OEM network policy

Gesture focus:

- With the soft keyboard hidden, scroll and pinch, then release all fingers; the gesture must not open the keyboard
- With the keyboard already visible, the same gestures must not deliberately hide it
- The Layer 3 fixture covers this:
  - terminal-screen touch ownership begins at `touchstart`
  - committed gestures replay no focus event
  - a below-threshold release replays one ordinary tap, so keyboard activation by a real tap still works
