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
| Minimum/target API | API 29 |
| Native API floor | API 29 |
| NDK | r27d (`27.3.13750724`) |
| Android SDK build input | platform 35 + build-tools 35.0.0 |
| ABI | `arm64-v8a` only |
| Android glue | Kotlin 2.4.10, platform APIs only |
| Terminal frontend | system WebView + `@xterm/xterm` 6.0.0 |
| Fit logic | `@xterm/addon-fit` 0.11.0 |
| Native bridge | C11/JNI, `forkpty`, `execve`, `read`, `write`, `ioctl` |
| Shell | device `/system/bin/sh` |
| PATH | `/system/bin` |
| TERM | `xterm-256color` |

`compileSdk` is separate from the API 29 runtime/native floor. The app uses no Compose,
AndroidX, Rust, custom terminal parser, or custom terminal renderer.

## Architecture

```text
Kotlin Activity
    |
    v
platform WebView ---- local bundled xterm.js
    |
    | platform WebMessagePort, Base64 byte batches
    v
small Kotlin session bridge
    |
    | JNI
    v
libshellbridge.so
    |
    | PTY
    v
/system/bin/sh -> Android system executables
```

The application process, shell, and shell children remain in the application's Linux
UID and SELinux domain. Starting a system binary does not grant ADB's UID 2000 `shell`
account and does not grant root privileges.

## Thin-layer decisions

- WebView supplies the browser runtime already present on Android.
- xterm.js supplies VT/xterm parsing, Unicode layout, selection, scrollback, cursor,
  color, IME integration, and rendering.
- Kotlin only owns Android lifecycle, WebView policy, message batching, and JNI calls.
- C only owns the PTY and process syscalls that Android's managed API does not expose.
- Runtime network access is absent; no `INTERNET` permission is declared.
- The terminal page is served from APK assets through an allowlisted synthetic HTTPS
  origin and rejects every other resource or navigation.

## Upstream asset provisioning

Exact xterm.js bytes are not acquired in the assistant environment. Before building,
run the bounded owner-side acquisition script:

```sh
./tools/acquire-web-terminal-assets.sh
```

It downloads only the pinned official npm tarballs, checks their fixed npm SHA-512
integrity values, validates archive members, installs only the required production
files, and freezes the acquired archive and installed-file SHA-256/size values in a receipt under `app/src/main/assets/terminal/vendor/`.
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

Prepare a bounded SDK location before the first APK build:

```sh
SDK_ENV_FILE="$TMPDIR/android-terminal-sdk.env" ./tools/prepare-android-sdk.sh
. "$TMPDIR/android-terminal-sdk.env"
```

The SDK helper reuses an existing compatible SDK when present. Otherwise it pins the official
Android command-line tools, installs platform 35 and build-tools 35.0.0, writes the untracked
`local.properties`, and selects a host-native `aapt2` (installing the Termux `aapt2` package when
necessary). This prevents AGP from trying to execute Google's x86_64 Linux `aapt2` on ARM64
Android.

After provisioning assets and the SDK, build with a trusted Gradle installation. Gradle runs
the host-aware native builder and packages its generated `arm64-v8a/libshellbridge.so`:

```sh
gradle -Pandroid.aapt2FromMavenOverride="$AAPT2_PATH" :app:assembleDebug
```

## Runtime probe

After installation:

```sh
id
printf '%s\n' "$SHELL" "$PATH" "$HOME" "$TERM"
command -v sh
command -v toybox
getprop ro.build.version.sdk
```

Expected policy properties are app-UID execution, `/system/bin/sh`, `PATH=/system/bin`,
`TERM=xterm-256color`, and an app-private `HOME`. Exact output remains device evidence.
