# Layer 3 touch interactions

This policy sits above the completed Layer 2 terminal surface. It does not change the PTY, shell, xterm.js vendor assets, Android account/session contract, or terminal transport.

## Device finding

The initial device wave confirmed that pinch font zoom worked but one-finger scrolling did not. The earlier assumption that the pinned xterm.js `6.0.0` browser runtime connected its internal touch recognizer to the terminal viewport was incorrect.

The pinned public runtime provides `Terminal.scrollLines()` and a scrollback viewport, but its `MouseService` only converts pointer coordinates and its `Viewport` connects the scroll model to the browser scrollbar and wheel path. The later upstream touch-to-viewport integration must not be attributed retroactively to the pinned release.

## Authority

The terminal page remains fixed. Browser page scrolling and WebView page zoom are not enabled. xterm remains the sole owner of the terminal buffer and viewport position.

Layer 3 owns only touch interpretation:

```text
one-finger CSS-pixel movement
→ measured xterm cell height
→ integer row delta
→ public Terminal.scrollLines()
```

This is not a second scrollback model. Layer 3 stores only sub-row pixel remainder and short-lived gesture velocity; xterm still clamps and applies the authoritative viewport position.

The existing xterm scrollbar remains browser-owned. Gestures that begin on the scrollbar are not intercepted.

## One-finger scrolling

A drag starts only after a six-pixel threshold, preserving ordinary taps. Motion is accumulated in CSS pixels and converted to rows using the rendered `.xterm-screen` height divided by `terminal.rows`. A font-size fallback is used only when rendered geometry is unavailable.

The direction follows normal touch content semantics:

- dragging down requests negative rows, revealing older scrollback;
- dragging up requests positive rows, returning toward the live bottom.

On release, recent motion samples drive a bounded `requestAnimationFrame` deceleration. Starting a new touch or pinch cancels the previous fling.

The current policy is deliberately limited to the normal buffer when terminal mouse tracking is inactive. It does not synthesize mouse-wheel protocol messages or alternate-buffer arrow keys.


## Soft-keyboard focus preservation

The first device attempt suppressed `mousedown`, `mouseup`, and `click` only after a drag or pinch had already committed. That was too late on Android WebView: the initial `touchstart` could already arm xterm/WebView focus activation, with the soft keyboard appearing when the fingers were released.

Layer 3 now owns a normal-buffer terminal-screen touch from the first `touchstart`. It prevents the browser compatibility activation for the entire candidate gesture and decides the outcome itself:

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

Synthetic JavaScript mouse events are not trusted Android input events, so `terminal.focus()` alone can focus the hidden xterm textarea without causing WebView to reopen the IME. The ordinary-tap path therefore follows DOM focus with an explicit native `soft-input-show` platform request. Scroll and pinch never send that request.

xterm can retain focus on its hidden textarea after the Android keyboard has been dismissed. Android WebView can then reopen the IME for the next native touch even if JavaScript later consumes that touch as a scroll or pinch. Android therefore reports IME visibility from the exact `WindowInsets` delivered to the Activity root. Layer 3 preserves xterm focus when that delivered state says the IME is visible, and calls the public `terminal.blur()` only when the IME was already hidden. A completed hidden-IME tap restores terminal focus and sends the explicit native `soft-input-show` request; committed scroll, pinch, and selection gestures never send that request.

The listener-delivered inset value is cached in Layer 2 rather than re-queried from the child WebView. This avoids a stale false value that previously caused every press to lower the keyboard and every release to raise it again. The xterm scrollbar and unsupported alternate-buffer/mouse-tracking paths remain outside this touch owner and retain their existing behavior.


## Long-press selection

A stationary one-finger touch becomes selection after 500 milliseconds. Layer 3 does not interpret terminal text or calculate word boundaries. It replays xterm's existing double-click mouse-selection sequence through the rendered terminal surface:

```text
500 ms stationary hold
→ xterm mousedown with double-click detail
→ xterm selects the word

continued touch movement
→ xterm mousemove with the primary button held
→ xterm expands the selection

release
→ xterm mouseup
```

Crossing the six-pixel movement threshold before the timer fires cancels selection and commits scrolling. A second finger cancels selection and commits pinch. Selection does not focus the hidden textarea, request the IME, or define a second terminal-buffer model. The existing Layer 2 bounded clipboard operations remain available, but this wave intentionally adds no selection handles or new copy/paste menu UI.

## Pinch font zoom

Two-finger pinch changes the public `Terminal.options.fontSize` value in one-pixel steps whenever the pinch distance crosses a ten-percent threshold, then requests the existing Layer 2 geometry synchronization.

The effective font size is:

```text
upstream xterm font size
× Android system font scale
× Layer 3 user font scale
```

The user scale is bounded to `0.5–3.0` and remains session-local. Pinch does not use WebView page scaling.

## Deliberate nonclaims

This policy does not add:

- Android-style movable text-selection handles;
- a new long-press copy/paste menu;
- a Layer 3 key toolbar;
- persistent zoom preferences;
- browser page scrolling or page zoom;
- touch wheel-protocol synthesis for mouse-tracking applications;
- alternate-buffer swipe-to-arrow translation.

Long-press xterm selection is active; movable handles and menu UX remain separate interaction waves.

## Bounded device check

Generate scrollback:

```sh
seq 1 1000
```

Verify that dragging down reveals older output, dragging up returns toward the prompt, and a faster release continues briefly as a fling. Then confirm that pinch zoom still changes glyph size and terminal geometry without replacing the shell session.

## Android WebView native-selection experiment outcome

Device trials of versions 0.25.0 and 0.25.1 rejected the browser-native path for this app:

- xterm DOM rows did not become selectable through Android WebView long press,
- Android selection handles did not appear,
- exposing the xterm helper textarea produced only an editor Paste menu,
- WebView native overflow did not scroll xterm scrollback,
- handing one-finger touch from WebView to Layer 3 after a movement threshold caused interrupted scrolling.

The production baseline therefore keeps xterm as the viewport authority and restores the proven public `scrollLines()` drag/inertia path. Pinch continues to change public `terminal.options.fontSize` and synchronize PTY geometry. The production path now uses xterm's own mouse-selection surface for long press and drag expansion. Browser DOM selection and custom Android ActionMode are not active production authorities; movable handles and copy/paste menu UX remain future work.
