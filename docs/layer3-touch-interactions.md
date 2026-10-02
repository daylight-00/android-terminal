# Layer 3 touch interactions

This policy sits above the completed Layer 2 terminal surface. It does not change the PTY, shell, xterm.js vendor assets, Android account/session contract, or terminal transport.

## Why Layer 3 owns scrolling

- **Pinned runtime** — xterm.js `6.0.0` provides `Terminal.scrollLines()` and a scrollback viewport
- **No touch recognizer** — its `MouseService` only converts pointer coordinates, and its `Viewport` connects the scroll model to the browser scrollbar and wheel path
- **Device result** — pinch font zoom worked and one-finger scrolling did not
- **Later upstream work** — a later upstream touch-to-viewport integration does not apply to the pinned release

## Authority

- The terminal page stays fixed; browser page scrolling and WebView page zoom are not enabled
- xterm is the sole owner of the terminal buffer and viewport position
- The xterm scrollbar stays browser-owned; gestures that begin on it are not intercepted
- Layer 3 owns only touch interpretation:

```text
one-finger CSS-pixel movement
→ measured xterm cell height
→ integer row delta
→ public Terminal.scrollLines()
```

This is not a second scrollback model. Layer 3 keeps only the sub-row pixel remainder and short-lived gesture velocity; xterm clamps and applies the authoritative viewport position.

## One-finger scrolling

- **Threshold** — a drag starts after six pixels, preserving ordinary taps
- **Rows** — motion accumulates in CSS pixels and converts using the rendered `.xterm-screen` height divided by `terminal.rows`; a font-size fallback applies only when rendered geometry is unavailable
- **Direction** — normal touch content semantics
  - drag down requests negative rows, revealing older scrollback
  - drag up requests positive rows, returning toward the live bottom
- **Fling** — on release, recent motion samples drive a bounded `requestAnimationFrame` deceleration; a new touch or pinch cancels it
- **Scope** — normal buffer with terminal mouse tracking inactive; no mouse-wheel protocol messages and no alternate-buffer arrow keys

## Soft-keyboard focus preservation

Suppressing `mousedown`, `mouseup`, and `click` only after a drag or pinch has committed is too late on Android WebView: the initial `touchstart` can already arm xterm/WebView focus activation, and the keyboard appears on release.

Layer 3 owns a normal-buffer terminal-screen touch from the first `touchstart`. It prevents the browser compatibility activation for the whole candidate gesture and decides the outcome itself:

```text
movement crosses threshold or a second finger joins
→ scroll or pinch
→ no focus replay

release below threshold
→ ordinary tap
→ replay mousedown, mouseup, click
→ focus xterm input
→ request Android InputMethodManager activation through the existing Layer 2 platform bridge
```

- **Soft-input request**
  - synthetic JavaScript mouse events are not trusted Android input, so `terminal.focus()` alone can focus the hidden xterm textarea without WebView reopening the IME
  - the ordinary-tap path follows DOM focus with an explicit native `soft-input-show` request
  - scroll and pinch never send it
- **IME visibility** — Android reports it through the exact `WindowInsets` delivered to the Activity root
- **No blur at touch boundaries** — Layer 3 never uses that asynchronous state to blur xterm at `touchstart` or `touchend`; a briefly stale false value lowers the keyboard and raises it again when the gesture completes
- **Visible-to-hidden transition** — on `softInputVisible: true → false`, Layer 3 calls public `terminal.blur()` exactly once
  - releases the hidden textarea focus retained after the keyboard is dismissed, so a later scroll, pinch, or long press does not reopen the IME
  - repeated hidden-state updates do not blur again

Stable policy:

- an observed visible-to-hidden IME transition releases retained xterm input
- the start of every later hidden-IME gesture reasserts that blur before WebView can reactivate the helper textarea
- visible-IME gestures never blur
- scroll, pinch, and long-press release neither focus nor request soft input
- only a completed short tap replays the compatibility mouse sequence, focuses xterm, and requests Android soft input
- IME state stays outside gesture classification except for the hidden-gesture focus guard

## Long-press selection

A stationary one-finger touch becomes selection after 500 milliseconds.

- **Why not xterm mouse selection** — its `mousedown` path also focuses the hidden textarea and can activate the Android keyboard
- **Instead** — Layer 3 maps the touch to a public xterm buffer cell, finds the initial word in that line with public `terminal.options.wordSeparator`, and applies it through public `terminal.select(column, bufferRow, length)`

```text
500 ms stationary hold
→ touch position mapped to xterm viewport cell
→ public buffer line and wordSeparator determine the initial range
→ terminal.select() applies the selection

continued touch movement
→ current xterm cell updates terminal.select()
→ selection expands in either direction

release
→ selected range remains active
→ no focus or IME request
```

- **Cancel** — crossing the six-pixel threshold before the timer fires cancels selection and commits scrolling; a second finger cancels selection and commits pinch
- **Model** — xterm's public buffer and selection API; Layer 3 keeps only the gesture anchors

## Selection actions (planned)

- **Menu** — Copy, Paste, and Select all after selection release; planned, not yet a supported feature
- **Prototype** — a Layer 2 selection-action facade with a non-focusable native `PopupWindow`; Layer 3 sends only the release coordinates and receives bounded `copy`, `paste`, and `select-all` events
- **Authority** — xterm keeps the selection; the menu never owns or reconstructs terminal text and never requests IME focus
- **Copy** — keeps the selected range and closes the menu
- **Paste** — calls `terminal.paste()`, clears the selection, and closes the menu
- **Select all** — calls `terminal.selectAll()` and keeps the menu open
- **Clipboard data** — travels through the existing bounded Layer 2 bridge
- **Handles** — movable selection handles are a separate, later wave

## Pinch font zoom

- **Step** — two-finger pinch changes public `Terminal.options.fontSize` in one-pixel steps whenever the pinch distance crosses a ten-percent threshold, then requests the existing Layer 2 geometry synchronization
- **Scale** — the user scale is bounded to `0.5–3.0` and is session-local
- **WebView** — pinch does not use WebView page scaling

Effective font size:

```text
upstream xterm font size
× Android system font scale
× Layer 3 user font scale
```

## Deliberate nonclaims

This policy does not add:

- Android-style movable text-selection handles
- movable selection handles attached to the native `PopupWindow`
- a supported selection action menu (planned)
- a Layer 3 key toolbar
- persistent zoom preferences
- browser page scrolling or page zoom
- touch wheel-protocol synthesis for mouse-tracking applications
- alternate-buffer swipe-to-arrow translation

## Bounded device check

Generate scrollback:

```sh
seq 1 1000
```

- Dragging down reveals older output
- Dragging up returns toward the prompt
- A faster release continues briefly as a fling
- Pinch zoom still changes glyph size and terminal geometry without replacing the shell session

## Rejected approach: WebView-native selection

Device trials of the browser-native path failed for this app:

- xterm DOM rows did not become selectable through Android WebView long press
- Android selection handles did not appear
- exposing the xterm helper textarea produced only an editor Paste menu
- WebView native overflow did not scroll xterm scrollback
- handing one-finger touch from WebView to Layer 3 after a movement threshold interrupted scrolling

Resulting design:

- xterm stays the viewport authority, with the public `scrollLines()` drag/inertia path
- pinch changes public `terminal.options.fontSize` and synchronizes PTY geometry
- long press and drag expansion use xterm's public buffer and `terminal.select()` without activating the hidden textarea
- browser DOM selection is not active
- xterm stays the selection authority; a native `PopupWindow` would own only transient menu presentation
