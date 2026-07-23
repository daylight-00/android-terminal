# Android Terminal

A thin terminal frontend for Android’s native shell, powered by xterm.js.

The APK connects the device-provided `/system/bin/sh` to the platform WebView through
a native PTY. It does not bundle a shell, Toybox, libc, a package manager, a root
filesystem, or a Linux distribution.

## Frozen baseline

| Boundary | Value |
|---|---|
| Repository | `android-terminal` |
| Application ID | `io.github.daylight00.androidterminal` |
| Android compile SDK | API 35 |
| Minimum API | API 29 |
| Compatibility target API | API 28 |
| Native API floor | API 29 |
| NDK | r27d (`27.3.13750724`) |
| Android SDK build input | platform 35 + build-tools 35.0.0 |
| ABI | `arm64-v8a` only |
| Android glue | Kotlin 2.4.10, platform APIs only |
| Terminal frontend | system WebView + `@xterm/xterm` 6.0.0 |
| Fit logic | `@xterm/addon-fit` 0.11.0 |
| Frontend state serialization | `@xterm/addon-serialize` 0.13.0 |
| Plain-text web links | `@xterm/addon-web-links` 0.12.0 |
| Optional accelerated renderer | `@xterm/addon-webgl` 0.19.0 |
| Native bridge | C11/JNI, `forkpty`, `execve`, `read`, `write`, `ioctl` |
| Shell | device `/system/bin/sh` |
| PATH | `/system/bin` |
| TERM | `xterm-256color` |

`compileSdk`, the API 28 compatibility target, and the API 29 runtime/native floor are separate. The app uses no Compose,
AndroidX, Rust, custom terminal parser, or custom terminal renderer.

## Architecture

```text
Layer 1  unmodified xterm.js/addons and Android-provided runtime
   ↓ public upstream APIs
Layer 2  complete Android adaptation, native integration, stable protocol, PTY/JNI bridge
   ↓ stable optional capability
Layer 3  product customization scaffold; optional and downstream of Layer 2
```

The repository is a platform host. Layer 1 owns terminal and shell semantics, Layer 2
connects upstream capabilities completely to Android, and Layer 3 consumes only the stable
optional Layer 2 capability. Layer 2 must remain operational when the customization scaffold is
empty or omitted. See [`docs/architecture.md`](docs/architecture.md) for the ownership and
upgrade boundary, [`docs/capability-matrix.md`](docs/capability-matrix.md) for the human-readable
classification, and [`docs/upstream-capabilities.json`](docs/upstream-capabilities.json) for the
machine-verified inventory.

## Thin-layer decisions

- WebView supplies the browser runtime already present on Android.
- xterm.js supplies VT/xterm parsing, Unicode layout, selection, scrollback, cursor,
  color, IME integration, and rendering.
- Kotlin only owns Android lifecycle, the Activity-independent session service, WebView policy and renderer recovery, message batching, and JNI calls.
- C only owns the PTY and process syscalls that Android's managed API does not expose.
- Android window, inset, rotation, and IME viewport changes are reduced to positive, deduplicated
  geometry before `addon-fit` dimensions reach `TIOCSWINSZ`.
- A bounded protocol v6 platform bridge connects explicit clipboard actions, OSC 8 links, official
  plain-text web-link activation, bell events, service-owned OSC 0/2 title state, Android-localized
  xterm accessibility strings, truthful safe window reports, Android color-scheme state, accessibility
  state, Android font scale, hardware-keyboard presence, and SAF document import/export without adding a
  terminal parser or replacing WebView/xterm input semantics.
- Layer 2 exposes the stable `AndroidTerminalLayer2` capability. It includes neutral title-state,
  platform-state, geometry-sync, and safe-window-report views. The Layer 3 scaffold loads after it,
  currently owns only the project light/dark terminal palettes, and never accesses WebMessagePort,
  JNI, PTY internals, or xterm.js private APIs.
- Android font scale multiplies the font size reported by each new upstream xterm.js instance. Layer 2
  captures that upstream default once, applies a bounded system scale through the public `fontSize`
  option, and refits geometry without defining a project-specific base font or preference.
- The official serialize addon produces opaque xterm framebuffer snapshots; Layer 2 stores them with an output-sequence watermark and bridges later bytes through a bounded raw tail journal without interpreting terminal state.
- The official WebGL addon is attempted by Layer 2. Activation failure or context loss disposes only the addon and permanently falls back to xterm core's DOM renderer for that frontend; the PTY, serialized state, and WebView session remain untouched.
- Android shared-storage permissions expose ordinary POSIX paths through `EXTERNAL_STORAGE` and a non-destructive `HOME/storage` symlink. SAF imports remain real files under app-private `HOME/imports`, and exports accept only validated HOME-relative regular files; no `content://` URI is presented as a POSIX path or virtual mount.
- The manifest targets API 28 as a narrow Android compatibility boundary so the native shell can execute owner-provided binaries from the writable app-private HOME without adding a custom linker or loader path. The minimum runtime and native ABI floor remain API 29.
- Runtime network access is absent; no `INTERNET` permission is declared.
- The terminal page is served from APK assets through an allowlisted synthetic HTTPS
  origin and rejects every other resource or navigation. The optional Layer 3 script is local,
  loads after Layer 2, and may consume only the stable customization capability.

## Upstream asset provisioning

Exact xterm.js bytes are not acquired in the assistant environment. Before building,
run the bounded owner-side acquisition script:

```sh
./tools/acquire-web-terminal-assets.sh
```

It downloads only the pinned official npm tarballs, checks their fixed npm SHA-512
integrity values, validates archive members, installs only the required production
files, and freezes the acquired archive and installed-file SHA-256/size values in a receipt under `app/src/main/assets/terminal/vendor/`. Exact package metadata for serialize, Web Links, and WebGL is retained and each `MIT` declaration is validated against the project-wide xterm.js license; no addon-specific license file is synthesized.
The app never loads a CDN or remote page at runtime.

## Local verification

Repository-only checks:

```sh
./tools/verify-repository.sh
```

Native bridge compile with NDK r27d:

```sh
ANDROID_NDK_HOME="$HOME/opt/android-ndk-r27d" ./tools/verify-native-ndk.sh
```

The builder first tries the official NDK host compiler and linker. On ARM64 Android/Termux,
it falls back to the installed host-native `clang` and `ld.lld` while still using the exact
NDK r27d sysroot and API 29 target libraries. This avoids executing the NDK's
`linux-x86_64/ld.lld` through Android's Bionic loader.

Verify the standard Android SDK before the first APK build:

```sh
SDK_ENV_FILE="$TMPDIR/android-terminal-sdk.env" ./tools/prepare-android-sdk.sh
. "$TMPDIR/android-terminal-sdk.env"
```

The SDK helper uses `$HOME/Android/Sdk` by default and fails closed unless platform 35,
build-tools 35.0.0, and NDK 27.3.13750724 already exist there. It writes only the untracked
`local.properties` and selects an already installed host-native `aapt2`; it does not download a
second SDK tree or mutate Termux packages.

After provisioning assets and the SDK, build with a trusted Gradle installation. Gradle runs
the host-aware native builder and packages its generated `arm64-v8a/libshellbridge.so`:

```sh
gradle -Pandroid.aapt2FromMavenOverride="$AAPT2_PATH" :app:assembleDebug
```

### Build tool environments

The canonical Linux workstation native build uses the official NDK CMake toolchain through
`build-tools/pyproject.toml` and `uv`. On ARM64 Termux, the official NDK host executables are
x86_64, so the verified host-native Clang path remains the narrow Android-host adaptation while
using the same NDK r27d sysroot and API 29 stubs.

## Runtime probe

After installation:

```sh
id
printf '%s\n' "$SHELL" "$PATH" "$HOME" "$TERM" "$ANDROID_STORAGE" "$EXTERNAL_STORAGE"
ls -ld "$HOME/storage"
command -v sh
command -v toybox
getprop ro.build.version.sdk
```

Expected policy properties are app-UID execution, `/system/bin/sh`, `PATH=/system/bin`,
`TERM=xterm-256color`, an app-private `HOME`, `ANDROID_STORAGE=/storage`, and—after the user grants the required Android access—an `EXTERNAL_STORAGE` path reachable through the non-destructive `HOME/storage` link. Exact output and read/write behavior remain device evidence.
