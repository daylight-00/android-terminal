# Android Native Shell

A minimal Android terminal frontend that starts the device-provided `/system/bin/sh`
through a native PTY. The APK does not bundle a shell, Toybox, libc, a package manager,
a root filesystem, or a Linux distribution.

## Frozen baseline

| Boundary | Value |
|---|---|
| Repository | `android-native-shell` |
| Application ID | `io.github.daylight00.nativeshell` |
| Java compile SDK | Android API 35 |
| App minimum API | Android API 29 |
| App target API | Android API 29 |
| Native API floor | Android API 29 |
| NDK | r27d (`27.3.13750724`) |
| ABI | `arm64-v8a` only |
| UI layer | Android platform `Activity`, `View`, `Canvas`, `InputConnection` |
| Terminal core | Pure Java VT100 subset |
| Process bridge | C11, JNI, `forkpty`, `execve`, `read`, `write`, `ioctl` |
| Shell | Device `/system/bin/sh` |
| PATH | `/system/bin` |
| TERM | `vt100` |

`compileSdk` is deliberately separate from the API 29 runtime/native floor. It only
controls which Android Java APIs can be compiled. The initial application behavior
contract and native symbol floor remain API 29.

## Architecture

```text
Android Activity / TerminalView / InputConnection
                    |
                    | small JNI surface
                    v
             libshellbridge.so
                    |
                    | PTY
                    v
              /system/bin/sh
                    |
                    v
          Android system executables
```

The application process, shell, and shell children remain in the application's Linux
UID and SELinux domain. Starting a system binary does not grant the `shell` UID used by
ADB and does not grant root privileges.

## Included

- Platform-only Android UI; no AndroidX and no Compose.
- A small cell buffer and incremental UTF-8/VT100 parser.
- PTY creation and `/system/bin/sh` execution in C.
- Physical keyboard and Android IME input paths.
- PTY resize propagation with `TIOCSWINSZ`.
- A host-runnable terminal-core test.
- A direct NDK r27d native compile verifier.

## Deliberately not included in v0.1

- A bundled shell or command suite.
- A package manager or prefix.
- `proot`, `chroot`, or a copied root filesystem.
- Network permission.
- External-storage integration.
- Background or persistent sessions.
- Scrollback, alternate screen, 256 colors, true color, mouse modes, bracketed paste,
  wide-cell layout, or combining-mark layout.
- A claim that every OEM permits every `/system/bin` program from an untrusted app.
- A device-runtime PASS claim before owner-device evidence exists.

## Local verification

The repository-only checks require Bash, Git, Python 3, and a JDK:

```sh
./tools/verify-repository.sh
```

The native bridge can be compiled directly with NDK r27d without Gradle:

```sh
ANDROID_NDK_HOME="$HOME/opt/android-ndk-r27d" ./tools/verify-native-ndk.sh
```

The script also discovers common side-by-side SDK locations automatically.

## Android build

The source is a standard Android Gradle Plugin project. A Gradle wrapper binary is not
committed because this repository was created in an assistant environment where remote
artifact acquisition is prohibited. Use an already trusted Gradle 8.9 installation or
open the project in an Android Studio installation that can provision the build tooling.

```sh
gradle :app:assembleDebug
```

The configured NDK revision must be installed under the SDK's side-by-side `ndk`
directory or selected by an equivalent local SDK configuration.

## Runtime probe

After installing the debug APK, the first bounded device probe is:

```sh
id
printf '%s\n' "$SHELL" "$PATH" "$HOME" "$TERM"
command -v sh
command -v toybox
getprop ro.build.version.sdk
```

Expected policy properties are app UID execution, `/system/bin/sh`, `PATH=/system/bin`,
and an app-private `HOME`. Exact output is device evidence, not a repository-only claim.
