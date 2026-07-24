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
```

No `blur()` operation is used. An already visible keyboard is not deliberately hidden, while a hidden keyboard receives no new focus request from a scroll or pinch. The xterm scrollbar and unsupported alternate-buffer/mouse-tracking paths remain outside this touch owner and retain their existing behavior.

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
- a Layer 3 key toolbar;
- persistent zoom preferences;
- browser page scrolling or page zoom;
- touch wheel-protocol synthesis for mouse-tracking applications;
- alternate-buffer swipe-to-arrow translation.

Mobile text selection remains a separate interaction wave.

## Bounded device check

Generate scrollback:

```sh
seq 1 1000
```

Verify that dragging down reveals older output, dragging up returns toward the prompt, and a faster release continues briefly as a fling. Then confirm that pinch zoom still changes glyph size and terminal geometry without replacing the shell session.
