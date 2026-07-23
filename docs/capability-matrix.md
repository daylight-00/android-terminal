# Upstream capability matrix

This matrix is the authority for Layer 2 completion. A capability is complete only when the pinned upstream public surface works in System WebView and every required Android native connection is present. Layer 3 is reserved and does not block or disable Layer 2 capabilities.

## Status definitions

| Status | Meaning |
|---|---|
| Native already | Upstream works in Android System WebView without an additional Android adapter. |
| Connected | Layer 2 supplies the required Android/PTY connection through a public upstream API. |
| Connected with bounds | The connection is complete but intentionally bounded for lifecycle or resource safety. |
| Upstream pending | An official upstream addon or selected upstream public surface is not yet vendored/connected. |
| Device gate pending | Repository evidence exists; real Android behavior still needs bounded device evidence. |
| Intentionally excluded | The feature belongs outside the thin Layer 2 host. |

## Current capability coverage

| Capability | Upstream authority | Layer 2 Android connection | Status |
|---|---|---|---|
| VT/xterm parsing and screen state | `@xterm/xterm` core | Raw PTY output is delivered to `Terminal.write()` | Connected |
| Keyboard and IME input | `@xterm/xterm` core | `onData()` and `onBinary()` are transported to the PTY; WebView remains input authority | Connected |
| Geometry | `@xterm/addon-fit` | Android layout/insets/configuration/focus and WebView viewport signals converge on positive deduplicated `TIOCSWINSZ` updates | Connected |
| Output flow control | xterm `write(data, callback)` | One in-flight batch and bounded ACK queue | Connected with bounds |
| Activity-independent shell session | Android native shell and PTY | Started/bound Service owns the PTY independently of Activity/WebView | Connected |
| Frontend reconnection | xterm public `write()` | Attachment identity reconnects replacement frontends to the same service session | Connected |
| WebView renderer recovery | Android System WebView | `onRenderProcessGone` replaces only the frontend and preserves the PTY session | Connected; device gate pending |
| Screen/scrollback restoration | `@xterm/addon-serialize` plus raw PTY bytes | Bounded opaque snapshot with output watermark plus contiguous raw tail | Connected with bounds; device gate pending |
| Clipboard | xterm selection and `paste()` APIs | Focus-gated bounded text bridge to Android `ClipboardManager` | Connected |
| Search | `@xterm/addon-search` | Not yet vendored or connected | Upstream pending |
| OSC 8 links | xterm core `linkHandler` | Validated HTTP/HTTPS activation through Android `ACTION_VIEW` | Connected |
| Plain-text web links | `@xterm/addon-web-links` | Not yet vendored or connected | Upstream pending |
| Bell | xterm `onBell` | Rate-limited Android haptic feedback | Connected; device gate pending |
| System theme | xterm `options.theme` | Android light/dark configuration maps to Layer 2 host palettes | Connected |
| Hardware keyboard | WebView DOM and xterm input APIs | No key duplication; Android physical-keyboard presence is reported | Native already + state connected |
| Accessibility | xterm `screenReaderMode` | Android accessibility and touch-exploration listeners control screen-reader mode | Connected; device gate pending |
| Font scale | xterm public `options.fontSize` | Android configuration scales the captured upstream default, bounded to 0.5–3.0, then re-runs fit/PTY geometry without a custom base font | Connected |
| Images | official xterm image addon | Not yet vendored or connected | Upstream pending |
| WebGL renderer | `@xterm/addon-webgl` | Automatically attempted; public context-loss event causes permanent per-frontend DOM fallback without session loss | Connected; device gate pending |
| SAF import/export | Android Storage Access Framework | Selected document bytes stream to/from bounded private-HOME regular files | Connected; device gate pending |
| Direct shared-storage paths | Android storage permission model | API 28 compatibility target, API 29 runtime permissions, API 30+ all-files settings, `EXTERNAL_STORAGE`, and non-destructive `HOME/storage` link | Connected; device gate pending |
| Writable app-private executable launch | Android app compatibility behavior and native `execve()` | API 28 compatibility target; no custom linker, loader shim, relocation service, or bundled userland | Connected; device gate pending |
| WebView download/upload/file chooser APIs | Android System WebView | No remote page or generic browser surface exists in the current secure local host | Intentionally excluded from current page model |
| Bundled shell/userland/package manager | none | Deliberately absent from Layer 2 | Intentionally excluded; Layer 3 only |
| Custom VT parser or screen renderer | none | Forbidden | Intentionally excluded |
| SAF/FUSE virtual mount | none | Not required once direct shared-storage permission and explicit SAF transactions are available | Intentionally excluded |

## Completion rule

For every future row:

1. preserve unmodified upstream bytes in Layer 1;
2. use core or an official addon public API;
3. add the thinnest Android native connection needed for full operation;
4. provide success, expected-negative, and incomplete/missing verification for the changed authority;
5. require device evidence for Android runtime claims;
6. keep unrelated product features and userland out of Layer 2.
