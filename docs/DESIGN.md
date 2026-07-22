# Design boundary

## Product definition

This project is an Android-system-shell terminal frontend. It does not create a new
userland. Android provides the executable format, dynamic linker, Bionic libc, shell,
and command binaries. The application provides only the interfaces needed to make that
existing system environment interactive in an app window.

## Standard platform boundary

### Android SDK

- `android.app.Activity` owns the visible window.
- `android.view.View` and `android.graphics.Canvas` render terminal cells.
- `android.view.inputmethod.InputConnection` receives IME text and composition.
- App lifecycle is intentionally tied to the foreground Activity in v0.1.

### Android NDK / Bionic

- `forkpty()` creates a PTY and child process.
- `execve()` replaces the child with `/system/bin/sh`.
- `read()` and `write()` transfer PTY bytes.
- `ioctl(TIOCSWINSZ)` updates terminal dimensions.
- The child receives a deliberately small environment and no custom loader path.

## JNI boundary

The JNI surface is intentionally procedural and byte-oriented:

- spawn
- read
- write
- resize
- signal process group
- wait
- destroy

The native layer never calls Java objects asynchronously. A Java reader thread performs
a blocking native read and schedules screen invalidation on the main thread.

## Process and security boundary

The child inherits the app UID and app SELinux domain. The child is not ADB's UID 2000
`shell` account. All system binary execution remains subject to file mode, seccomp,
SELinux, Android permissions, and OEM policy.

The child uses an explicit environment:

```text
HOME=<app files directory>
TMPDIR=<app cache directory>
PATH=/system/bin
SHELL=/system/bin/sh
TERM=vt100
LANG=C.UTF-8
ANDROID_ROOT=/system
ANDROID_DATA=/data
```

No `LD_LIBRARY_PATH` or Termux-style prefix is introduced.

## Terminal compatibility boundary

The initial parser implements the subset necessary for an interactive shell prompt and
basic line-oriented commands: incremental UTF-8, C0 controls, cursor movement, erase,
scroll regions, saved cursor, 16-color SGR, and cursor visibility.

`TERM=vt100` is an honest declaration for this initial scope. The project must not set
`TERM=xterm-256color` until the corresponding behavior is implemented and verified.

## Known v0.1 limitations

- Unicode code points occupy one cell regardless of East Asian width.
- Combining marks are not attached to prior cells.
- No scrollback or alternate screen exists.
- IME composing text is shown as a bottom overlay and committed text alone reaches PTY.
- Session persistence across Activity destruction is out of scope.
