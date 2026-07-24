# Upstream capability matrix

This document is the human-readable view of [`upstream-capabilities.json`](upstream-capabilities.json), the machine-verified authority for Layer 2 completion.

The project connects only the necessary intersection between xterm.js/System WebView and Android native operation:

```text
unmodified upstream capability
            ∩
Android operation required to make it usable
            =
Layer 2 integration scope
```

A WebView feature that turns the application into a general browser is outside this intersection. A product preference or optional UI belongs to Layer 3 even when it consumes a Layer 2 capability.

## Classification

| Classification | Meaning |
|---|---|
| **Layer 2 runtime** | Automatically active because the upstream feature needs an Android or PTY connection to operate completely. |
| **Layer 2 capability** | Layer 2 exposes a neutral engine/state/API; Layer 3 owns optional UI, preference, or presentation. |
| **Native already** | The upstream public capability works in System WebView without another Android adapter. |
| **Not applicable** | No necessary intersection exists with the selected service-owned native PTY host. |
| **Experimental** | Excluded from the Layer 2 completion gate until upstream stabilizes it. |

`Connected with bounds` means the capability is complete but carries a neutral lifecycle, ordering, memory, or safety bound. It does not authorize product policy in Layer 2.

## Core capability inventory

| Capability | Upstream authority | Classification | Status | Layer 2 Android boundary | Layer 3 boundary |
|---|---|---|---|---|---|
| Terminal emulation | `@xterm/xterm` parser, buffers, modes, cursor, selection, scrollback, reflow, mouse protocol, renderers | Native already | Connected | Raw PTY bytes enter `Terminal.write()`; Android does not reinterpret terminal state | None |
| PTY input | `onData`, `onBinary` | Layer 2 runtime | Connected | Byte-preserving transport to the service-owned PTY | Special keys, modifier bars, and macros |
| PTY output and flow control | `write(data, callback)`, `onWriteParsed` | Layer 2 runtime | Connected with bounds | Ordered sequence ACK, one in-flight batch, bounded recovery state | None |
| Geometry | `resize`, `@xterm/addon-fit` | Layer 2 runtime | Connected | Android layout/insets/rotation/IME viewport converge on deduplicated `TIOCSWINSZ` | Optional layout chrome must request refit through Layer 2 |
| Focus, IME, hardware keyboard | xterm DOM input and System WebView | Native already | Connected | WebView remains input authority; Android reports hardware-keyboard state only | Optional key UI |
| Explicit clipboard actions | selection APIs and `paste()` | Layer 2 runtime | Connected | Bounded Android `ClipboardManager` read/write | Buttons, gestures, and preference policy |
| OSC 52 clipboard | xterm OSC 52 + official ClipboardAddon provider | Layer 2 runtime | **Connected with bounds** | Official addon backed by bounded Android `ClipboardManager` operations | Clipboard UX and policy |
| OSC 8 links | core `linkHandler` | Layer 2 runtime | Connected | Validated HTTP/HTTPS URI to `ACTION_VIEW` | Menus, previews, history, browser UI |
| Bell | `onBell` | Layer 2 runtime | Connected with bounds | Neutral rate-limited Android haptic signal | Sound, pattern, and enablement preferences |
| Terminal title | `onTitleChange` | Layer 2 capability | Connected with bounds | Sanitize to 1024 Unicode code points, retain in the service-owned session, restore on attachment, and answer truthful title reports | Toolbar, tab, notification, or task-label presentation |
| Platform color scheme | Android `uiMode` + public xterm theme option | Layer 2 capability | Connected | Expose light/dark state through the stable customization capability; Layer 2 defines no palette | Theme objects and user theme selection |
| Accessibility | `screenReaderMode` + upstream localizable strings | Layer 2 runtime | Connected | Android accessibility/touch exploration drive screen-reader mode; Android resources provide upstream accessibility strings | Product-specific accessibility UI |
| Localizable xterm strings | `Terminal.strings` / `ILocalizableStrings` | Layer 2 runtime | Connected with bounds | Bind `promptLabel` and `tooMuchOutput` to Android locale resources with a neutral 512-code-point bound | Product copy outside upstream strings |
| Font scale | public `options.fontSize` | Layer 2 runtime | Connected | Android scale multiplies each instance's captured upstream default, then refits | Font family, explicit size, line height, letter spacing |
| Safe window reports | `IWindowOptions`, public parser/input/refresh APIs, actual geometry/title | Layer 2 runtime | Connected with bounds | Enable truthful cell-pixel, window-pixel, row/column, title-stack, refresh, and current-title behavior; leave desktop/screen/position/resize operations disabled | Fullscreen/product window-management UI |
| Public extension APIs | addons, parser, buffer, markers, decorations, link providers, key/wheel handlers | Native already | Available | No wrapper where Android is unnecessary; private xterm APIs remain forbidden | Layer 3 may consume the stable public surface |
| Frontend lifecycle | serialize/write APIs + Android Service/WebView lifecycle | Layer 2 runtime | Connected with bounds | Service-owned PTY survives replacement frontend; snapshot + bounded raw tail restore it | Tabs, persistence, session/workspace management |

Desktop move, raise/lower, iconify, maximize, screen-size, host-position, and terminal-driven Activity resize operations are not meaningful or not safely equivalent for this Android activity model and are not mapped to approximate behavior.

## Existing Android Layer 2 foundation

These host capabilities are not xterm.js addons, but they remain prerequisite Layer 2 infrastructure for the inventory above.

| Host capability | Status | Boundary |
|---|---|---|
| Direct shared-storage paths | Connected; device gate passed | Android storage permission and non-destructive `HOME/storage` mapping expose ordinary POSIX paths without pretending SAF URIs are files. |
| SAF document transport | Connected with bounds | Explicit import/export copies between a selected document and private POSIX files. |
| Frontend reconnection | Connected with bounds | A service-owned PTY survives Activity and WebView replacement. |
| WebView renderer recovery | Connected with bounds | Replacement frontend restores an opaque upstream snapshot plus bounded post-watermark output. |

## Official maintained addon inventory

The official xterm.js repository currently lists the following 13 maintained addons. Every addon appears exactly once in the machine-readable authority.

| Official addon | Classification | Status | Default Layer 2 state | Android integration | Layer 3 boundary |
|---|---|---|---|---|---|
| `@xterm/addon-attach` | Not applicable | Excluded | None | Current backend is a native PTY, not WebSocket transport | Future remote session product |
| `@xterm/addon-clipboard` | Layer 2 runtime | Connected with bounds | Automatic | Official provider maps OSC 52 to bounded Android `ClipboardManager` operations | Clipboard UI/policy |
| `@xterm/addon-fit` | Layer 2 runtime | Connected | Automatic | Container fit → bounded PTY geometry | None |
| `@xterm/addon-image` | Layer 2 runtime | Connected with upstream defaults | Automatic | Official SIXEL/IIP/partial Kitty support and public storage/image APIs | User protocol toggles and custom resource limits |
| `@xterm/addon-ligatures` | Layer 2 capability | Available | Registered | Neutral one-time enable capability; not active by default | Font and ligature enablement |
| `@xterm/addon-progress` | Layer 2 runtime | Connected | Automatic | Parse OSC 9;4 and expose neutral bounded progress state | Toolbar, notification, tab badge, display policy |
| `@xterm/addon-search` | Layer 2 capability | Available | Registered | Expose official find/clear/result APIs without UI | Search field, shortcuts, controls, decorations |
| `@xterm/addon-serialize` | Layer 2 runtime | Connected with bounds | Automatic | Replacement-frontend snapshot authority | Persistent history |
| `@xterm/addon-unicode-graphemes` | Experimental | Excluded from completion gate | None | Upstream marks it experimental and not published to npm | Explicit later experiment only |
| `@xterm/addon-unicode11` | Layer 2 capability | Available | Registered | Register provider without selecting it active | Active Unicode-version policy |
| `@xterm/addon-web-fonts` | Layer 2 capability | Available | Registered | Expose official preload and relayout operations | Font assets, family choice, fallback policy |
| `@xterm/addon-web-links` | Layer 2 runtime | Connected | Automatic | Detected links use validated Android `ACTION_VIEW` bridge | Link UX/history/browser behavior |
| `@xterm/addon-webgl` | Layer 2 runtime | Connected with bounds | Automatic attempt | WebGL2 with one-way DOM fallback | Renderer preference UI |

The inventory follows the current maintained-addon list, while implementation pins must be compatible with the repository's pinned `@xterm/xterm@6.0.0`. Stable addon coordinates are exact. Existing locked packages retain fixed integrity values; newly connected packages resolve the exact version metadata from the official npm registry, verify the returned SHA-512 integrity and tarball URL, and must reproduce the same receipt and Git tree in isolated preflight and canonical application.

`@xterm/addon-canvas` is legacy for this baseline. The selected renderer path is xterm core DOM plus the official WebGL addon, so canvas is not part of the maintained inventory or completion gate.

## System WebView boundary

### In scope

- local DOM and CSS required by xterm.js;
- canvas and WebGL2 used by official renderers/addons;
- `ResizeObserver`, `visualViewport`, focus, IME, accessibility primitives;
- `WebMessagePort` transport to Android;
- local font loading required by a future official Web Fonts integration.

### Not applicable

- generic remote navigation and browser history;
- arbitrary page permissions or web authentication;
- generic browser file chooser and download manager;
- browser chrome, tabs, bookmarks, or general-purpose page hosting.

These exclusions are product boundaries, not incomplete Layer 2 terminal adaptation.

## Layer 3 scaffold rule

Layer 3 exists as an optional scaffold and is loaded after Layer 2. Layer 2 must operate when the scaffold is empty or omitted. Layer 3 may consume only the stable `AndroidTerminalLayer2` capability and public xterm.js APIs exposed through it.

The current scaffold owns the project palette used to present Android light/dark state. It does not own PTY transport, WebMessagePort, JNI, lifecycle recovery, renderer fallback, clipboard transport, link validation, font-scale adaptation, or any xterm private object.

## Completion rule

A Layer 2 completion claim requires:

1. every maintained official addon to have one explicit classification;
2. every relevant stable core capability to be connected, connected with bounds, native already, or explicitly pending only when its selected official addon remains unintegrated;
3. unmodified Layer 1 bytes and public upstream APIs only;
4. success, expected-negative, and incomplete/missing verification for each changed authority;
5. bounded device evidence for Android runtime claims;
6. optional UI, preferences, userland, and product policy to remain in Layer 3.
