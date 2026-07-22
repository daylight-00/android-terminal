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
| Geometry to rows/columns | `@xterm/addon-fit` | Web geometry is sent to `TIOCSWINSZ` | Resize debounce remains minimal | Connected |
| Output flow control | xterm `write(data, callback)` | One in-flight batch plus bounded ACK queue | Queue limits are fixed host policy | Connected |
| Activity-independent shell session | Android native shell and PTY | Started/bound platform `Service` owns the PTY | Session stops when the app task is removed | Connected |
| Frontend reconnection | xterm public `write()` | Protocol v2 attaches a replacement WebView to the service session | No persistent background session | Connected |
| Frontend replay | Raw upstream PTY byte stream | Bounded 1 MiB journal is replayed without parsing terminal semantics | Explicit truncation notice | Connected with bound |
| Full screen restoration after unlimited output | xterm serialize addon | Not present | Not selected | Upstream pending |
| Clipboard | xterm selection/input APIs | Android `ClipboardManager` adapter absent | Read/paste policy undecided | Policy pending |
| Search | `@xterm/addon-search` | Not vendored | Search UI undecided | Upstream pending |
| Web/OSC links | xterm link APIs or official web-links addon | Android `ACTION_VIEW` adapter absent | Scheme allowlist undecided | Policy pending |
| Bell | xterm bell event | Android haptic/audio adapter absent | Default disabled/enabled undecided | Policy pending |
| System theme | xterm options | Android configuration signal absent | Palette undecided | Policy pending |
| Hardware keyboard supplement | xterm input APIs | Android physical `KeyEvent` supplement absent | Modifier behavior undecided | Policy pending |
| Accessibility | xterm accessibility support | Android accessibility state adapter absent | Activation policy undecided | Policy pending |
| Images | official xterm image addon | Not vendored | GPU/memory policy undecided | Upstream pending |
| WebGL renderer | official xterm WebGL addon | Renderer-loss fallback absent | Default renderer undecided | Upstream pending |
| SAF import/export | Android Storage Access Framework | URI-to-private-file transport absent | User-facing actions undecided | Policy pending |
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
