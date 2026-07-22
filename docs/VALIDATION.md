# Validation model

## Classification

The product is class **T** in intent. Assistant-side evidence is limited to class **L**:

- exact local Git content and identity;
- native source shape and NDK r27d compilation when that NDK exists;
- JavaScript codec/protocol behavior independent of xterm.js bytes;
- WebView policy and absence of a bundled userland;
- no installation, device-runtime, OEM-policy, or sustained-performance claim.

## Repository verifier

`tools/verify-repository.sh` checks:

- API 29, NDK r27d, and arm64-only declarations;
- Kotlin/WebView/WebMessagePort frontend and absence of the removed custom parser;
- direct `/system/bin/sh` execution and `TERM=xterm-256color`;
- no AndroidX, Compose, Rust, network permission, or bundled shell/userland;
- local asset allowlist and restrictive WebView policy;
- success, expected-negative, and missing-input verifier fixtures.

## External asset gate

`tools/acquire-web-terminal-assets.sh` is the only normal asset acquisition path. It
pins official npm URLs and fixed npm SHA-512 integrity values, checks archive safety,
extracts only the required production files and license texts, and freezes the acquired
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
r27d sysroot, API 29 stubs, headers, and compiler runtime. Output is validation evidence
only and is not committed. Gradle packages the same generated arm64 library and does not
invoke CMake or the incompatible NDK host linker.

## Android SDK build gate

`tools/prepare-android-sdk.sh` resolves or creates one SDK root, pins the official Android
command-line tools archive and SHA-256, installs platform 35 plus build-tools 35.0.0, and writes
only the ignored `local.properties`. On Android/Termux it selects the native `aapt2` executable
instead of allowing AGP to launch Google's x86_64 Linux binary. APK assembly passes that exact
path through `android.aapt2FromMavenOverride`.

## Device gate

A device PASS requires a bounded receipt containing at least:

- device identity, Android API, and Android System WebView version;
- APK SHA-256 and installed package identity;
- local page and message-channel startup;
- shell startup, `id`, environment, and executable resolution;
- PTY echo, Ctrl+C, resize, UTF-8/IME, scrollback, and lifecycle behavior;
- complete first-failure context if any step fails.
