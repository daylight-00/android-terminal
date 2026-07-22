# Validation model

## Classification

The initial repository is class **T** in intent because it defines a new Android product,
but the assistant-side evidence is limited to class **L** claims:

- exact repository content and Git identity;
- host terminal-core behavior;
- native source shape and, where NDK r27d is present, exact arm64 API 29 compilation;
- no device runtime, installability, OEM behavior, or long-duration session claim.

## Repository verifier

`tools/verify-repository.sh` checks:

- clean expected Git configuration values;
- API 29, NDK r27d, and arm64-only build declarations;
- direct `/system/bin/sh` execution;
- absence of bundled shell/userland payloads;
- terminal core success and expected-negative fixtures;
- shell syntax and Git whitespace integrity.

## NDK verifier

`tools/verify-native-ndk.sh` discovers the exact r27d installation, invokes the
`aarch64-linux-android29-clang` driver, creates one temporary `libshellbridge.so`, and
checks its ELF machine, dependencies, and exported JNI entry points. The output is
validation evidence only and is not committed.

## Device gate

A device PASS requires an installed APK and one bounded receipt containing at least:

- device identity and Android API;
- APK SHA-256 and installed package identity;
- shell startup result;
- `id`, environment, and executable resolution output;
- PTY echo, Ctrl+C, resize, IME UTF-8, and lifecycle results;
- complete first-failure context if any step fails.
