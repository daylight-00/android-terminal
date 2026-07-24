# Layer 3 touch interactions

This wave adds the first product interaction policy above the completed Layer 2 terminal surface. It does not change the PTY, shell, xterm.js vendor assets, Android account/session contract, or terminal transport.

## Authority

The terminal page remains fixed. Browser page scrolling and WebView page zoom are not enabled. The xterm.js viewport remains the only scrollback authority.

The customization stylesheet applies `touch-action: none` only to the rendered xterm screen and its canvases. This prevents Android WebView from claiming a terminal gesture as browser page pan or browser page zoom, allowing the upstream xterm.js touch recognizer to receive one-finger gestures without a native Android gesture bridge. The xterm viewport and its scrollbar remain browser-owned.

## One-finger scrolling

One-finger scrolling is still implemented by the pinned upstream xterm.js runtime. Layer 3 does not duplicate `scrollLines`, synthesize wheel events, or maintain a second scroll position. Upstream remains responsible for normal-buffer scrollback, alternate-buffer key behavior, mouse-protocol behavior, and inertia.

## Pinch font zoom

Two-finger pinch is owned by the Layer 3 customization controller. It changes the public `Terminal.options.fontSize` value in one-pixel steps whenever the pinch distance crosses a ten-percent threshold, then requests the existing Layer 2 geometry synchronization.

The effective font size is:

```text
upstream xterm font size
× Android system font scale
× Layer 3 user font scale
```

The user scale is bounded to `0.5–3.0`. It is session-local in this wave. No settings UI or persistence is added.

Pinch does not use WebView page scaling. Rows and columns are recalculated through the existing fit and PTY geometry path.

## Deliberate nonclaims

This wave does not add:

- Android-style movable text-selection handles;
- a Layer 3 key toolbar;
- persistent zoom preferences;
- a second JavaScript scroll implementation;
- WebView page scrolling or generic browser behavior.

Mobile text selection remains a separate interaction wave after touch ownership and upstream scrolling are confirmed on the device.

## Bounded device check

Generate scrollback and verify that one-finger dragging and fling move through the transcript:

```sh
seq 1 1000
```

Then pinch in and out. The glyph size, rows, and columns should change while the same shell session remains attached. Returning to normal typing must still follow the live bottom of the terminal.
