# Single-device smoke validation

**Observed:** 2026-07-24
**Repository state:** `c56cda280a3f8d6762cc1454144e86051982320b`
**Evidence class:** owner-reported bounded manual smoke test
**Project status:** `repository-complete-device-validation-pending`

This receipt records a practical single-device smoke test. It does not claim an OEM matrix, full protocol conformance, Play Store readiness, or exhaustive real-device validation.

## Passed scope

The owner reported all of the bounded baseline probes in `docs/device-validation.md` as passing for the tested device:

- direct `/system/bin/sh` login-session startup;
- `cwd == HOME` with the app files directory as `HOME`;
- `TMPDIR == cacheDir/tmp` and a writable private temporary directory;
- a fresh `HOME` without app-created profile, XDG, `storage`, or `imports` entries;
- PTY input, resize, rotation, background/resume, and session survival;
- UTF-8/IME input, clipboard copy/paste, and OSC 52 clipboard transfer;
- direct `/storage/emulated/0` pathname access after the Android system grant;
- continued private-HOME terminal operation when broad storage access is denied;
- OSC 8/plain-text external links and basic renderer behavior.

## Writable-HOME executable probe

Execution of an owner-provided Android-native `uv` binary from writable app-private `HOME` passed.

The earlier example of copying `/system/bin/sh` was not used because the device prevented copying that system executable. This is not treated as a terminal failure: the actual contract under test is execution of an owner-provided compatible binary from `HOME`, and `uv` exercised that contract directly.

## Not tested

SAF runtime import/export was not exercised because no Layer 3 caller or product UI exists. The neutral Layer 2 SAF bridge remains covered by repository tests, but real picker, provider, cancellation, and destination behavior remain device nonclaims.

The following also remain outside this bounded smoke receipt:

- multi-device, Android-version, or OEM compatibility matrices;
- forced WebGL context-loss and renderer-process termination;
- exhaustive SIXEL/iTerm image combinations;
- full Unicode, font, ligature, accessibility, and physical-keyboard matrices;
- exact inherited-environment comparison against Android internals;
- release signing, long-duration stress, and store-policy validation.

## Result

```text
single-device-smoke-test=passed
home-executable-probe=passed-with-uv
saf-runtime=not-tested-no-layer3-caller
repository-complete-device-validation-pending
```

This bounded result is sufficient for the current GitHub-release-oriented workflow. The broader device gate remains pending rather than being converted into a stronger claim.
