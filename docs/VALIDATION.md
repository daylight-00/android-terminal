# Validation model

## Classification

The product is class **T** in intent. Assistant-side evidence is limited to class **L**:

- exact local Git content and identity;
- native source shape and NDK r27d compilation when that NDK exists;
- JavaScript codec/protocol behavior independent of xterm.js bytes;
- pure JavaScript WebGL activation, context-loss cleanup, one-way fallback, and no-retry behavior;
- WebView policy and absence of a bundled userland;
- no installation, device-runtime, OEM-policy, or sustained-performance claim.

## Layer-boundary verifier

`tools/verify-layer-boundaries.py` checks that upstream assets remain isolated, Layer 2 uses only the stable contract and public xterm.js surface, Layer 3 loads strictly after Layer 2, Layer 2 never depends on the Layer 3 implementation, and Layer 3 cannot reach transport/native/private internals. It also requires matching protocol versions, the declared script load order, and a complete Android-native mapping for each capability marked connected.

`tools/verify-upstream-capabilities.py` validates the machine-readable xterm.js core/addon inventory, requires every officially maintained addon to appear exactly once with the approved classification, and binds the human-readable capability matrix to that authority. Success, missing-row, missing-authority, Layer 3 bypass, Layer 2 dependency, and theme-authority fixtures are mandatory.

`tools/verify-layer2-completion.py` cross-checks `layer2-completion.json` against the exact provisioned asset receipt, runtime extension manifest, protocol/page capability, Layer 3 scaffold contract, app version, debug-only inspection surface, and the ImageAddon WebAssembly CSP requirement. Its negative fixtures remove the CSP permission and a pinned addon coordinate.

## Repository verifier

`tools/verify-repository.sh` checks:

- minimum/native API 29, compatibility target API 28, NDK r27d, and arm64-only declarations;
- Kotlin/WebView/WebMessagePort frontend and absence of the removed custom parser;
- direct login-shell `/system/bin/sh` execution through `argv[0] = -sh` and `TERM=xterm-256color`;
- no AndroidX, Compose, Rust, network permission, or bundled shell/userland;
- local asset allowlist and restrictive WebView policy;
- success, expected-negative, and missing-input verifier fixtures, including Android font-scale, service-owned title, localized-string, and safe-window-report authorities.

## External asset gate

`tools/acquire-web-terminal-assets.sh` is the only normal asset acquisition path. It
pins exact official npm URLs. Existing packages retain fixed npm SHA-512 values; newly connected
stable addons resolve the exact-version registry record and require its exact tarball URL and SHA-512
integrity before archive validation. The provisioner extracts only required production files and freezes the acquired
archive and installed-file SHA-256/size values in the owner-side receipt. The repository
does not claim pre-acquisition tarball SHA-256/size values that were unavailable to the
assistant; the authoritative npm SHA-512 integrity is the fail-closed pre-acquisition pin. Repository verification distinguishes an intentionally unprovisioned
tree from a fully provisioned tree and rejects partial or unreceipted assets.

## NDK verifier

`tools/verify-native-ndk.sh` invokes `tools/build-native-bridge.sh`, creates one temporary
`libshellbridge.so`, and checks ELF machine, dependencies, and JNI exports. The builder
uses the official NDK r27d compiler/linker when those host binaries execute normally. On
native Android/Termux, where the NDK `linux-x86_64` linker is not a valid ARM64 Bionic
host executable, it uses Termux's host-native `clang` and `ld.lld` with the exact NDK
r27d sysroot, API 29 stubs, headers, and compiler runtime. Output is validation evidence only and is not committed. Gradle packages the same generated
arm64 library. A separate `build-tools/pyproject.toml` and CMake entry point provide the canonical
x86 Linux workstation path through the official NDK CMake toolchain; the Termux path remains the
narrow host adaptation because Google's NDK host executables are x86_64.

## Android SDK build gate

`tools/prepare-android-sdk.sh` uses the standard `$HOME/Android/Sdk` root by default and fails
closed unless platform 35, build-tools 35.0.0, and NDK 27.3.13750724 already exist there. It does
not download another SDK or install Termux packages. On Android/Termux it selects an already
installed host-native `aapt2` instead of allowing AGP to launch Google's x86_64 Linux binary.
APK assembly passes that exact path through `android.aapt2FromMavenOverride`.

## Writable app-home execution boundary

Static verification requires `targetSdk 28` while preserving `minSdk 29` and the native API 29 build floor. This binds the intended Android compatibility behavior without introducing a custom linker, loader wrapper, or executable relocation mechanism. Repository and APK evidence can prove the declared target; launching an owner-provided ELF from app-private HOME remains a real-device gate.

## Device gate

A device PASS requires a bounded receipt containing at least:

- device identity, Android API, and Android System WebView version;
- APK SHA-256 and installed package identity;
- local page and message-channel startup;
- shell startup, `id`, environment, and executable resolution;
- PTY echo, Ctrl+C, resize, UTF-8/IME, scrollback, and lifecycle behavior;
- complete first-failure context if any step fails.

## WebView channel startup

The terminal page must replace the loading overlay after receiving the exact `native-shell` marker with one transferred message port. It must not reject the native channel by comparing `MessageEvent.origin`, and it exposes a five-second startup diagnostic instead of leaving an indefinite loading overlay.


## Protocol v6, serialized-state, service-session, geometry, and platform boundary

Repository verification compiles and exercises the pure Kotlin rolling replay buffer, opaque serialized-snapshot store, and terminal
geometry state, executes protocol v6 in Node, and statically verifies that the Android service owns
the PTY while the Activity only binds a frontend. The geometry test rejects transient zero layouts,
deduplicates unchanged sizes, and verifies changed WebView/IME viewport geometry before it can reach
`TIOCSWINSZ`. It also compiles the pure URI/clipboard policy and the Android platform adapter
against an API-shape stub, then executes the clipboard, OSC 8 link, bell, Layer 3 palette, accessibility,
Android-localized xterm strings, service-owned title restore/update, safe window reports, document import/export request-result, and stale-attachment paths in Node. Pure Kotlin tests verify
private-HOME path confinement, caller-selected import destinations, absence of a fixed HOME inbox, name sanitation, MIME bounding, collision handling, and the document
size limit. The API-shape compile covers `ACTION_OPEN_DOCUMENT`, `ACTION_CREATE_DOCUMENT`,
`OpenableColumns`, and streaming `ContentResolver` access. The owner APK build remains the authority
for compiling the real Android framework integration.

ADB runtime validation is deferred when no authorized device transport is available. The missing
device gate must remain a non-claim: Activity recreation, WebView replacement, stale-generation rejection, task-removal cleanup,
serialized-state restore, bounded snapshot/tail gap handling, IME show/hide, rotation, split-screen, clipboard privacy behavior, external-link
routing, haptic bell behavior, accessibility services, physical-keyboard state, WebGL activation/context loss/DOM fallback, SAF provider import/export, cancellation and large-file behavior, and OEM WebView
viewport behavior still require a later real-device test.

## Plain-text web-link adaptation

Repository verification requires the pinned official Web Links addon, checks that the Layer 1 bytes
are installed only through the bounded npm acquisition path, and executes the page bridge with a fake
official addon callback. Both OSC 8 and detected plain-text links must use the same validated Android
external-URI operation; a fixture that replaces this route with direct browser navigation must fail,
and a fixture missing the addon script authority must fail. Touch activation and external intent
resolution remain bounded device evidence.

## Android font-scale adaptation

Repository verification executes the Layer 2 platform mapper with fake xterm.js instances whose
public upstream defaults differ. It proves that Android scale is bounded to 0.5–3.0, repeated
updates recompute from the captured upstream baseline instead of compounding, invalid scale input
returns to scale 1, and no project-specific numeric base font is encoded. The main channel test also
checks capability negotiation and the mapping of Android `fontScale` to xterm's public `fontSize`
option. Static verification requires `fontScale` in Activity configuration handling, the mirrored
native/page capabilities, and the dedicated success, expected-negative, and missing-authority
fixtures. Actual glyph metrics, user-visible sizing, rotation behavior, and PTY geometry after a
system font-size change remain device evidence.

## Core title, localization, and safe-window integration

Repository verification executes `Terminal.onTitleChange` transport, control-character removal, the 1024-code-point service title bound, replacement-frontend restoration, and Layer 3 title-state notification. It compiles Android locale/resource mapping and checks application of `promptLabel` and `tooMuchOutput` through the public `Terminal.strings` surface. The Node fixture enables only truthful xterm cell-pixel, terminal-pixel, row/column, title-stack, refresh, and current-title behavior; expected-negative fixtures reject desktop/screen window operations, an unsanitized service title, and missing localization authority. Actual OSC title behavior, TalkBack announcements, locale switching, font metrics, and terminal-query responses remain device evidence.

## WebGL renderer fallback

Repository verification executes the pure Layer 2 renderer controller with a fake official addon surface. It verifies automatic addon activation, public `onContextLoss` handling, disposal of the addon and event subscription, permanent fallback to xterm core DOM rendering for the current frontend, activation-failure fallback, unavailable-addon fallback, and no retry loop. Real System WebView GPU support and context-loss behavior remain device gates.

## Native account/session and direct shared storage

Repository verification compiles the environment merge helper with a synthetic Android parent environment and proves that unrelated values are preserved while exactly one `HOME`, `TMPDIR`, and `TERM` override is produced. It rejects fixed `PATH`, locale, `ANDROID_*`, XDG, and storage-variable synthesis. A Kotlin test proves `TMPDIR == cacheDir/tmp`, recreates it when absent, rejects a non-directory path, and verifies that session setup leaves `HOME` untouched.

The shared-storage fixture executes the API 29 runtime-permission and API 30+ all-files settings branches, verifies app-specific settings first, generic fallback, startup request ownership, grant-state reporting, and the Android-reported direct path. Static policy rejects `HOME/storage`, symlink creation, a shared-storage JNI argument, and child environment synthesis. Real permission dialogs, OEM settings routing, inherited environment values, direct read/write behavior, cache eviction, and protected `/Android` subtrees remain device gates.

## WebView renderer recovery

Repository verification checks that `onRenderProcessGone` destroys the failed WebView frontend, invalidates its attachment generation, and installs a replacement against the existing service-owned PTY. A pure Kotlin recovery coordinator rejects duplicate and stale callbacks. Real renderer termination remains an ADB/device gate.

## Stable official addon wave

Repository verification loads the official Clipboard, Image, Progress, Search, Unicode 11, Web Fonts, and Ligatures addons through `Terminal.loadAddon`. Clipboard uses the official addon's default Base64 implementation and a bounded plain-text Android provider. Image uses upstream constructor defaults. Progress exposes neutral state, while Search, Unicode selection, web-font loading/relayout, and ligature activation are UI-free Layer 2 capabilities for Layer 3. Unicode 11 registration is the sole reason for the explicit `allowProposedApi` opt-in and Layer 2 does not change the active Unicode provider. The acquisition fixture rejects the obsolete CommonJS filename and requires the official `lib/addon-ligatures.mjs` entry plus package `module` metadata. Ligature activation reactivates an active WebGL addon as required by the upstream contract. Expected-negative fixtures reject a wrong ClipboardAddon constructor boundary, missing addon assets, and loss of login-shell `argv[0]` semantics. The pinned ImageAddon contains WebAssembly compilation sinks, so verification requires `script-src 'self' 'wasm-unsafe-eval'` and rejects JavaScript `'unsafe-eval'`. Real OSC 52, inline-image protocols and WebAssembly enforcement, WebView font access, ligature rendering, and shell startup-file behavior remain device evidence. The bounded procedure is documented in `docs/device-validation.md`; debug builds alone enable WebView inspection of `AndroidTerminalLayer2.completion.snapshot()`.
