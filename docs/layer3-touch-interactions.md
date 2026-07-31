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

Android reports IME visibility through the exact `WindowInsets` delivered to the Activity root. Layer 3 never uses that asynchronous state to blur xterm at `touchstart` or `touchend`; device evidence showed that even a briefly stale false value caused the keyboard to lower immediately and then rise again when the gesture completed.

When Android reports the specific transition `softInputVisible: true → false`, Layer 3 calls the public `terminal.blur()` exactly once. This releases the hidden xterm textarea focus retained after the user dismisses the keyboard, preventing WebView from reopening the IME on the release of a later scroll, pinch, or long press. Repeated hidden-state updates do not blur again.

The stable policy is: an observed visible-to-hidden IME transition releases retained xterm input, and the start of every later hidden-IME gesture reasserts that blur before WebView can reactivate the focused helper textarea. Visible-IME gestures never blur. Scroll, pinch, and long-press release without focusing or requesting soft input; only a completed short tap replays the compatibility mouse sequence, focuses xterm, and requests Android soft input. IME state remains outside gesture classification except for the hidden-gesture focus guard.


## Long-press selection

A stationary one-finger touch becomes selection after 500 milliseconds. Synthetic xterm mouse selection is not used because its mousedown path also focuses the hidden textarea and can activate the Android keyboard. Layer 3 instead maps the touch to a public xterm buffer cell, uses the public `terminal.options.wordSeparator` value to find the initial word within that line, and applies the result through public `terminal.select(column, bufferRow, length)`.

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

Crossing the six-pixel movement threshold before the timer fires cancels selection and commits scrolling. A second finger cancels selection and commits pinch. The selection model remains xterm's public buffer and public selection API; Layer 3 stores only the gesture anchors. The existing Layer 2 bounded clipboard operations are surfaced through a WebView-local Copy/Paste/Select all toolbar after selection release. The toolbar is outside the terminal touch surface and never focuses xterm or requests soft input. This wave still adds no movable selection handles.

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
- Android-native floating `ActionMode`;
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

The production baseline therefore keeps xterm as the viewport authority and restores the proven public `scrollLines()` drag/inertia path. Pinch continues to change public `terminal.options.fontSize` and synchronize PTY geometry. The production path now uses xterm's public buffer and `terminal.select()` APIs for long press and drag expansion without activating the hidden textarea. Browser DOM selection and custom Android ActionMode are not active production authorities; movable handles remain future work; Copy/Paste/Select all use the WebView-local Layer 3 toolbar and existing Layer 2 clipboard bridge.
