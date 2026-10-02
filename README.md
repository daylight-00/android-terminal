# Android Terminal

A thin terminal frontend for Android’s native shell, powered by xterm.js.

The app connects the device’s `/system/bin/sh` to a WebView through a native PTY. It bundles no shell, libc, package manager, or Linux distribution.

## Highlights

- **System shell** — login shell on the device’s own `/system/bin/sh`
- **Unmodified xterm.js** — official addons: WebGL, Unicode 11, OSC 52 clipboard, inline images, links, ligatures
- **Persistent session** — owned by a service; survives rotation and backgrounding
- **Touch** — drag to scroll, pinch to zoom, long-press to select
- **Offline** — page served from APK assets; WebView network blocked

## Environment

- **`HOME`** — app files directory, empty until you populate it
- **`TMPDIR`** — `<cache dir>/tmp`
- **`TERM`** — `xterm-256color`
- **Everything else** — inherited from Android unchanged

See [`docs/native-account-session.md`](docs/native-account-session.md).

## Requirements

- **Device** — Android 10+ (API 29), `arm64-v8a`
- **Build** — JDK 17+, Gradle 8.10+, Android SDK platform 35, build-tools 35.0.0, NDK `27.3.13750724`

## Build

```sh
export ANDROID_TERMINAL_SDK_ROOT="$HOME/Android/Sdk"
export AAPT2_PATH="$ANDROID_TERMINAL_SDK_ROOT/build-tools/35.0.0/aapt2"
SDK_ENV_FILE=/tmp/android-terminal-sdk.env ./tools/prepare-android-sdk.sh
. /tmp/android-terminal-sdk.env
gradle -Pandroid.aapt2FromMavenOverride="$AAPT2_PATH" :app:assembleDebug
```

- **Output** — `app/build/outputs/apk/debug/app-debug.apk`
- **Verify** — `./tools/verify-repository.sh`
- **xterm.js assets** — committed under `app/src/main/assets/terminal/vendor/`; refresh with `./tools/acquire-web-terminal-assets.sh`

## Documentation

- [`architecture.md`](docs/architecture.md) — three layers: upstream, Android adaptation, optional customization
- [`DESIGN.md`](docs/DESIGN.md) — runtime, protocol, security
- [`capability-matrix.md`](docs/capability-matrix.md) — upstream capability handling
- [`layer3-touch-interactions.md`](docs/layer3-touch-interactions.md) — touch scrolling, zoom, selection
- [`VALIDATION.md`](docs/VALIDATION.md), [`device-validation.md`](docs/device-validation.md) — verification and device checklist

## License

[MIT](LICENSE). Bundled xterm.js and addons: [MIT](app/src/main/assets/terminal/vendor/LICENSE.xterm.txt).
