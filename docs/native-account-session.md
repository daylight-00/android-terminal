# Native account and session baseline

This repository implements two project-level concerns:

1. the terminal mechanism itself; and
2. the minimum account/session baseline required to expose Android's native shell as a usable user session.

Actual user configuration, tools, dotfiles, projects, and workflows are outside this repository.

The repository-internal Layer 1/2/3 design is orthogonal to those project-level concerns. It is primarily the method used to connect upstream xterm.js and Android-native behavior with the least possible intervention.

## Governing rule

Android and the APK sandbox are the system environment. The app does not construct a parallel userland, prefix, root filesystem, loader, libc, package repository, or shell distribution.

A fresh installation should resemble a newly allocated unprivileged account on a managed Linux cluster:

- the account has a writable `HOME`;
- the system shell and commands remain those supplied by the host;
- temporary storage exists;
- the login shell starts in `HOME`;
- the user may later install binaries and configuration under `HOME`;
- the app does not populate the account on the user's behalf.

## Child-process contract

```text
executable:       /system/bin/sh
argv[0]:          -sh
working directory: HOME
HOME:             Context.getFilesDir()
TMPDIR:           Context.getCacheDir()/tmp
TERM:             xterm-256color
environment:      inherited Android application environment with only HOME, TMPDIR, and TERM replaced
```

`PATH`, `SHELL`, `LANG`, `ANDROID_*`, `EXTERNAL_STORAGE`, and `XDG_*` are not synthesized. Values supplied by the Android parent process are inherited. Missing values remain missing.

The merged environment is constructed before `forkpty()`. The child performs only descriptor closure, `chdir()`, `execve()`, and `_exit()`.

## Filesystem baseline

Layer 2 creates only the dedicated `TMPDIR` namespace when necessary:

```text
filesDir/          HOME; not populated by session startup
cacheDir/
└── tmp/           TMPDIR
```

It does not create profiles, rc files, XDG directories, `.local`, `storage`, `imports`, or any other HOME entry during account initialization. An explicit SAF import writes into HOME itself or into a caller-selected validated HOME-relative directory; only that user-initiated transfer may create its requested destination.

## Shared storage

Direct shared-storage access is a host capability, not a home-directory layout policy.

- The manifest declares the Android permissions required by the supported platform branches.
- On startup, the app immediately enters the official Android system permission flow when the grant is absent.
- No project settings screen or enablement UI is added.
- The shell sees the real Android filesystem and the permissions of the app UID.
- The app does not create `HOME/storage` or any other convenience link.
- The shared-storage path does not enter the JNI spawn signature or child environment.
- Permission denial does not prevent the private `HOME` shell or SAF document transport from working.

The Android-reported shared-storage path and grant state remain available as neutral platform state, but they do not redefine the shell environment.

## SAF

SAF remains an independent Android-native document capability. Explicit import/export transfers data between a selected document provider and ordinary private files. Import has no fixed inbox: an empty destination places the provider-named file in HOME, and a caller may supply a validated HOME-relative destination directory. Collision handling preserves existing files. No `content://` URI is exposed as a POSIX path or virtual mount.

## User-owned layer

The user may later create, for example:

```sh
# ~/.profile
export PATH="$HOME/.local/bin:$PATH"
export ENV="$HOME/.mkshrc"
```

Whether `/system/bin/sh` reads a particular startup file is controlled by the native shell implementation on the device. The app does not inject or emulate startup-file semantics.
