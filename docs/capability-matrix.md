# Upstream capability matrix

This matrix is the authority for deciding whether Android Terminal has preserved an upstream
capability, supplied the Android connection it requires, or intentionally left product policy to
Layer 3. A capability is not considered complete merely because xterm.js exposes an API.

## Status definitions

| Status | Meaning |
|---|---|
| Native already | The pinned upstream runtime works in the Android System WebView without an Android adapter. |
| Connected | Layer 2 supplies the required Android/PTY connection through a public upstream API. |
| Policy pending | Layer 2 can support the capability, but Layer 3 has not selected its user experience or default. |
| Upstream pending | The required official xterm.js addon is not yet vendored. |
| Intentionally excluded | The capability conflicts with the thin host boundary or needs a separate project. |

## Current capability coverage

| Capability | Upstream authority | Layer 2 Android connection | Layer 3 policy | Status |
|---|---|---|---|---|
| VT/xterm parsing and screen state | `@xterm/xterm` core | PTY output is delivered as bytes to `Terminal.write()` | Appearance only | Connected |
| Keyboard and IME text input | `@xterm/xterm` core | `onData()` and `onBinary()` are transported to the PTY | No custom IME | Connected |
| Geometry to rows/columns | `@xterm/addon-fit` | Android root layout, insets, configuration, focus, WebView `ResizeObserver`, and `visualViewport` changes converge on deduplicated `TIOCSWINSZ` updates; transient zero geometry is ignored | No separate product policy | Connected |
| Output flow control | xterm `write(data, callback)` | One in-flight batch plus bounded ACK queue | Queue limits are fixed host policy | Connected |
| Activity-independent shell session | Android native shell and PTY | Started/bound platform `Service` owns the PTY | Session stops when the app task is removed | Connected |
| Frontend reconnection | xterm public `write()` | Protocol v4 retains attachment identity and reconnects replacement Activity/WebView frontends to the service session | No persistent background session | Connected |
| WebView renderer recovery | Android System WebView | `onRenderProcessGone` destroys only the failed frontend, detaches its stale connection generation, and installs a new WebView against the same service-owned PTY session | Automatic while the Activity and service binding remain alive | Connected; device gate pending |
| Frontend replay | `@xterm/addon-serialize` plus raw upstream PTY bytes | Opaque serialized xterm state is stored with an output-sequence watermark; a rolling 1 MiB raw tail bridges bytes produced after the snapshot without parsing terminal semantics | Explicit failure notice if the bounded snapshot and tail cannot bridge a gap | Connected with bounds |
| Current xterm screen and configured scrollback restoration after arbitrary session output | `@xterm/addon-serialize` | Protocol v6 restores a bounded 8 MiB opaque snapshot before replaying the contiguous raw tail | Existing xterm scrollback limit remains Layer 3 policy | Connected with bounds |
| Clipboard | xterm `hasSelection()`, `getSelection()`, and `paste()` | Bounded text-only `ClipboardManager` request/result adapter; reads require application focus and occur only after an explicit platform request | Visible copy/paste controls remain a Layer 3 choice | Connected |
| Search | `@xterm/addon-search` | Not vendored | Search UI undecided | Upstream pending |
| OSC 8 links | xterm core `linkHandler` | Exact HTTP/HTTPS validation followed by Android `ACTION_VIEW`; unsafe, credential-bearing, file, content, intent, data, and JavaScript URIs are rejected | HTTP/HTTPS only | Connected |
| Plain-text web links | `@xterm/addon-web-links` | Not vendored | Activation UI and hover behavior undecided | Upstream pending |
| Bell | xterm `onBell` | Android `performHapticFeedback` adapter | Haptic effect is explicitly disabled by default | Connected, policy-disabled |
| System theme | xterm `options.theme` | Android configuration state is sent on attach, resume, focus, and configuration changes | Follow system light/dark with explicit palettes | Connected |
| Hardware keyboard | WebView DOM keyboard events and xterm input APIs | WebView remains the input authority; Android reports physical-keyboard presence without intercepting or duplicating key events | Modifier bar and overrides remain unselected | Native already + state connected |
| Accessibility | xterm `screenReaderMode` | Android accessibility and touch-exploration state listeners feed the platform state contract | Active touch exploration maps to xterm screen-reader mode | Connected |
| Images | official xterm image addon | Not vendored | GPU/memory policy undecided | Upstream pending |
| WebGL renderer | official xterm WebGL addon | Renderer-loss fallback absent | Default renderer undecided | Upstream pending |
| SAF import/export | Android Storage Access Framework | `ACTION_OPEN_DOCUMENT` streams one selected document into a bounded real file under private `HOME/imports`; `ACTION_CREATE_DOCUMENT` streams one validated HOME-relative regular file out without exposing a virtual mount | User-facing controls remain undecided | Connected; UI policy pending |
| Bundled shell/userland/package manager | none | Deliberately absent | Deliberately absent | Intentionally excluded |
| Custom VT parser or screen renderer | none | Forbidden | Forbidden | Intentionally excluded |
| SAF/FUSE virtual mount | none | Forbidden by current thin boundary | Separate project if ever required | Intentionally excluded |

## Completion rule

A future feature must preserve this order:

1. use the xterm.js core public API when it owns the capability;
2. use an official xterm.js addon when the capability is provided there;
3. add only the Android connection required to expose that capability;
4. place activation, appearance, confirmation, and user-interface choices in Layer 3;
5. document an explicit exclusion instead of silently reimplementing upstream behavior.
