# Layer 3 touch interactions

This policy sits above the completed Layer 2 terminal surface. It does not change the PTY, shell, pinned xterm.js assets, Android account/session contract, or byte transport.

## Current proof of concept

The Android touch path is a WebView-native selection experiment. Layer 3 requests xterm's built-in DOM renderer through the additive public Layer 2 `useDomRenderer()` capability, marks the rendered rows as browser-selectable, and leaves stationary one-finger touches unconsumed. WebView/Chromium therefore owns long-press recognition, DOM text selection, Android selection handles, and the standard contextual menu.

The pinned xterm 6.0.0 asset is unchanged. The adaptation uses only public xterm surfaces exposed by Layer 2:

- `terminal.element` identifies the xterm DOM surface;
- `terminal.textarea` is positioned at the cursor as the native Paste target;
- `terminal.paste()` receives one captured native paste event;
- `terminal.scrollLines()` remains the fallback after one-finger movement is proven;
- `terminal.options.fontSize` plus the existing geometry sync remain the pinch authority.

Native DOM selection is intentionally viewport-limited and is a device-validated POC, not a cross-OEM behavior claim.

## Touch arbitration

```text
one finger, pending
  ├─ stationary / long press         → WebView default tap or native selection
  └─ movement beyond 6 CSS pixels    → xterm scrollLines() fallback

two fingers                          → xterm font-size pinch
```

Layer 3 does not cancel the initial stationary touch. It claims and consumes the gesture only after scrolling or pinch is established. A touch-generated compatibility `mousedown` is stopped before xterm's own mouse-selection handler, without calling `preventDefault()`, so WebView can keep one native selection model instead of competing with xterm's internal selection model. Hardware mouse input and active terminal mouse tracking remain outside that suppression.

## Native Copy and Paste

The selected text, handles, word boundaries, and contextual Copy action are WebView/Chromium-owned DOM selection behavior. The previous custom Android floating `ActionMode` remains an available Layer 2 capability but is not requested by this Layer 3 POC.

For Paste, Layer 3 places the public xterm helper textarea at the terminal cursor with a minimum 80 × 32 CSS-pixel touch target. A native paste event with clipboard data is captured, cancelled once, and forwarded through public `terminal.paste()` so the terminal input path remains authoritative and duplicate insertion is avoided.

This POC does not claim:

- selection beyond the currently rendered DOM viewport;
- equivalence across Android WebView or OEM versions;
- persistence of selection across renderer refresh, resize, font-size change, or output churn;
- correct native Paste behavior until verified on the target device;
- preservation of an already-visible IME during scroll or pinch.

## One-finger scrolling

After movement exceeds six CSS pixels, Layer 3 claims the gesture and converts CSS-pixel motion to rows using the rendered `.xterm-screen` height divided by `terminal.rows`.

- dragging down requests negative rows and reveals older scrollback;
- dragging up requests positive rows and returns toward the live bottom;
- release velocity drives bounded `requestAnimationFrame` deceleration;
- a new touch or pinch cancels the previous fling.

The fallback operates only in the normal buffer while terminal mouse tracking is inactive. The xterm scrollbar remains browser-owned. Alternate-buffer gestures and mouse-protocol synthesis are not approximated.

## Pinch font zoom

Two-finger pinch changes public `terminal.options.fontSize` in one-pixel steps whenever distance crosses a ten-percent threshold, then requests the existing Layer 2 geometry synchronization.

```text
upstream xterm font size
× Android system font scale
× Layer 3 user font scale
```

The user scale is bounded to `0.5–3.0` and remains session-local. Pinch does not use WebView page scaling.

## Bounded device check

Generate selectable scrollback:

```sh
printf 'alpha beta gamma\n'
seq 1 1000
```

Verify:

1. long-pressing rendered text shows Android-native selection handles and the standard contextual menu;
2. moving either native handle changes the selected DOM text naturally;
3. Copy produces exact ASCII, wrapped-line, CJK, and wide-character text;
4. long-pressing the cursor/helper-textarea area offers Paste and inserts clipboard text exactly once;
5. a stationary ordinary tap still activates terminal input and the IME;
6. a one-finger drag crosses the threshold and scrolls without leaving a stale native selection;
7. pinch still changes xterm font size and PTY geometry together;
8. selection limitations at viewport edges, during output churn, and after resize are recorded rather than generalized.
