# Layer 3 touch interactions

This policy sits above the completed Layer 2 terminal surface. It does not change the PTY, shell, pinned xterm.js assets, Android account/session contract, or byte transport.

## Current isolation proof of concept

The current experiment answers one question only: can Android System WebView select the real terminal row DOM produced by xterm's built-in DOM renderer?

Layer 3 requests the DOM renderer through the public Layer 2 `useDomRenderer()` capability, marks the rendered rows as browser-selectable, and leaves every one-finger touch unconsumed from `touchstart` through completion. WebView therefore owns ordinary taps, long-press recognition, native DOM selection, Android selection handles, contextual Copy UI, and overflow panning. Layer 3 claims only a proven two-finger font-size pinch.

The pinned xterm 6.0.0 asset is unchanged. The adaptation uses only public surfaces:

- `terminal.element` identifies the xterm DOM surface;
- `terminal.options.fontSize` plus the existing geometry sync remain the pinch authority;
- `useDomRenderer()` disposes the active WebGL addon and leaves xterm's built-in DOM renderer active.

The previous helper-textarea Paste experiment and the one-finger `scrollLines()` fallback are intentionally absent. Their removal prevents an editable textarea or a mid-gesture JavaScript handoff from contaminating the row-selection result.

## Touch ownership

```text
one finger
  → WebView owns the complete gesture
     tap / long press / native row selection / native overflow pan

two fingers
  → Layer 3 owns xterm font-size pinch
```

Layer 3 never calls `preventDefault()` for a one-finger touch. A touch-generated compatibility `mousedown` is stopped before xterm's separate mouse-selection handler, without cancelling the browser default action. Hardware mouse input and active terminal mouse tracking remain outside that suppression.

The CSS boundary explicitly restores `user-select: text`, `pointer-events: auto`, and `touch-action: auto` on the xterm root, viewport, screen, rendered rows, and row descendants.

## Deliberate non-claims

This isolation POC does not claim that:

- Android WebView will actually recognize xterm DOM rows as selectable text;
- native selection handles or Copy UI will appear on every WebView/OEM version;
- WebView overflow panning will synchronize correctly with xterm scrollback;
- selection can extend beyond the currently rendered viewport;
- selection survives output churn, resize, font-size changes, or renderer refresh;
- native Paste is available;
- an already-visible IME remains visible during pinch.

A failure to select rows in this isolated configuration is meaningful evidence: CSS-level exposure of the current xterm 6.0.0 DOM renderer is insufficient on the target WebView, and another selection authority is required.

## Pinch font zoom

Two-finger pinch changes public `terminal.options.fontSize` in one-pixel steps whenever distance crosses a ten-percent threshold, then requests the existing Layer 2 geometry synchronization.

```text
upstream xterm font size
× Android system font scale
× Layer 3 user font scale
```

The user scale is bounded to `0.5–3.0` and remains session-local. Pinch does not use WebView page scaling.

## Bounded device check

Generate visible terminal text and scrollback:

```sh
printf 'alpha beta gamma\n'
seq 1 1000
```

Verify in this order:

1. long-press the middle of a rendered terminal word, away from the cursor;
2. record whether the word is highlighted and native selection handles appear;
3. record the exact contextual menu items;
4. drag one handle and record whether the selected row text changes;
5. drag one finger vertically and record whether WebView scrolls smoothly, does nothing, or moves the page incorrectly;
6. pinch and confirm xterm font size and PTY geometry still change together;
7. confirm no cursor-local helper-textarea Paste menu appears merely because the cursor was touched.
