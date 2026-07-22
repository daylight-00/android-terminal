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

`tools/verify-native-ndk.sh` invokes `aarch64-linux-android29-clang`, creates one temporary
`libshellbridge.so`, and checks ELF machine, dependencies, and JNI exports. Output is
validation evidence only and is not committed.

## Device gate

A device PASS requires a bounded receipt containing at least:

- device identity, Android API, and Android System WebView version;
- APK SHA-256 and installed package identity;
- local page and message-channel startup;
- shell startup, `id`, environment, and executable resolution;
- PTY echo, Ctrl+C, resize, UTF-8/IME, scrollback, and lifecycle behavior;
- complete first-failure context if any step fails.
