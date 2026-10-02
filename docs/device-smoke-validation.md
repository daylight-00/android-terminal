# Single-device smoke validation

- **Observed** — 2026-07-24
- **Repository state** — `c56cda280a3f8d6762cc1454144e86051982320b`
- **Evidence** — bounded manual smoke test on one device
- **Project status** — `repository-complete-device-validation-pending`

The test passed all bounded baseline probes in [`device-validation.md`](device-validation.md). It does not cover an OEM matrix, full protocol conformance, Play Store readiness, or exhaustive device validation.

## Passed scope

- direct `/system/bin/sh` login-session startup
- `cwd == HOME` with the app files directory as `HOME`
- `TMPDIR == cacheDir/tmp` and a writable private temporary directory
- a fresh `HOME` without app-created profile, XDG, `storage`, or `imports` entries
- PTY input, resize, rotation, background/resume, and session survival
- UTF-8/IME input, clipboard copy/paste, and OSC 52 clipboard transfer
- direct `/storage/emulated/0` pathname access after the Android system grant
- continued private-`HOME` terminal operation when broad storage access is denied
- OSC 8/plain-text external links and basic renderer behavior

## Writable-HOME executable probe

- **Result** — a user-provided Android-native `uv` binary executed from writable app-private `HOME`
- **System shell copy** — not used; the device prevented copying `/system/bin/sh`
- **Why that is not a failure** — the contract under test is execution of a user-provided compatible binary from `HOME`, and `uv` exercised it directly

## Not tested

- **SAF runtime import/export** — not exercised, since no Layer 3 caller or product UI exists; the neutral Layer 2 SAF bridge is covered by repository tests, but real picker, provider, cancellation, and destination behavior remain device nonclaims
- multi-device, Android-version, or OEM compatibility matrices
- forced WebGL context loss and renderer-process termination
- exhaustive SIXEL/iTerm image combinations
- full Unicode, font, ligature, accessibility, and physical-keyboard matrices
- exact inherited-environment comparison against Android internals
- release signing, long-duration stress, and store-policy validation

## Result

```text
single-device-smoke-test=passed
home-executable-probe=passed-with-uv
saf-runtime=not-tested-no-layer3-caller
repository-complete-device-validation-pending
```

The broader device gate stays pending.
