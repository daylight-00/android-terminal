# Design boundary

## Product definition

Android Terminal is a thin terminal frontend for Android’s native shell, not a new userland. Android
provides the dynamic linker, Bionic libc, `/system/bin/sh`, and system command binaries.
The application provides only a UI/frontend and the PTY/process bridge needed to make
that existing environment interactive inside an app UID.

## Standard platform boundary

### Android SDK

- `android.app.Activity` owns the window.
- `android.webkit.WebView` supplies the rendering and JavaScript runtime.
- `android.webkit.WebMessagePort` carries bounded terminal messages.
- `WebViewClient.shouldInterceptRequest` serves an exact allowlist of APK assets from
  the synthetic `https://app.local` origin without a server or network permission.
- Kotlin is used only for Android lifecycle and bridge glue.

### Web terminal frontend

Pinned xterm.js production files provide the terminal parser, screen model, Unicode and
IME behavior, scrollback, selection, cursor, and renderer. `addon-fit` computes rows and
columns from the WebView geometry. No custom VT parser or cell renderer remains.

The page-to-native protocol carries JSON control messages. PTY bytes are Base64 encoded
because platform API 29 `WebMessage` is string-based. Output is one batch in flight at a
time; xterm.js acknowledges completion through its `write` callback. Native backpressure
caps queued PTY output at 1 MiB.

### Android NDK / Bionic

- `forkpty()` creates a PTY and child process.
- `execve()` replaces the child with `/system/bin/sh`.
- `read()` and `write()` transfer PTY bytes.
- `ioctl(TIOCSWINSZ)` updates terminal dimensions.
- The child receives a deliberately small environment and no custom loader path.

## Security boundary

The WebView:

- requests no `INTERNET` permission;
- disables file and content access;
- rejects all navigation except the single local document;
- serves only seven exact asset paths;
- uses a restrictive Content Security Policy;
- enables no JavaScript object bridge;
- uses an HTML message channel transferred only to the local page.

The child inherits the app UID and app SELinux domain. It is not ADB's UID 2000 `shell`
account. System binary execution remains subject to file mode, seccomp, SELinux, Android
permissions, and OEM policy.

The child environment is:

```text
HOME=<app files directory>
TMPDIR=<app cache directory>
PATH=/system/bin
SHELL=/system/bin/sh
TERM=xterm-256color
LANG=C.UTF-8
ANDROID_ROOT=/system
ANDROID_DATA=/data
```

No `LD_LIBRARY_PATH`, Termux prefix, copied shell, or package manager is introduced.

## External-input boundary

Repository source pins `@xterm/xterm` 6.0.0 and `@xterm/addon-fit` 0.11.0, but does not
pretend to contain bytes the assistant could not acquire through the project authority
path. The owner-side acquisition script fetches official npm tarballs, validates fixed
npm SHA-512 integrity values and safe members, then freezes extracted file SHA-256 and
size metadata in a local receipt.

## Known first-version limitations

- Platform WebMessagePort on API 29 is string-based, so PTY data uses Base64.
- WebView implementation behavior varies with the installed Android System WebView.
- Session persistence across Activity destruction is out of scope.
- Device-runtime success and OEM `/system/bin` policy require owner-device evidence.
