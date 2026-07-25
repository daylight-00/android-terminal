# Layer 3 touch interactions

This policy sits above the completed Layer 2 terminal surface. It does not change the PTY, shell, pinned xterm.js assets, Android account/session contract, or byte transport.

## Authority

The terminal page remains fixed. Browser page scrolling and WebView page zoom are disabled. xterm remains the sole owner of terminal buffers, viewport position, text selection, wrapping, wide-character coordinates, and rendered selection state.

Layer 3 owns only touch arbitration:

```text
one finger, pending
  ├─ release before threshold       → terminal tap
  ├─ movement beyond 6 CSS pixels   → xterm scrollLines()
  ├─ 500 ms long press              → xterm selection input path
  └─ second finger                  → font-size pinch
```

This is not a second terminal, scrollback, or selection model. Layer 3 stores only short-lived gesture state, sub-row scroll remainder, and fling velocity.

## One-finger scrolling

Motion is accumulated in CSS pixels and converted to rows using the rendered `.xterm-screen` height divided by `terminal.rows`. A font-size fallback is used only when rendered geometry is unavailable.

- dragging down requests negative rows and reveals older scrollback;
- dragging up requests positive rows and returns toward the live bottom;
- release velocity drives a bounded `requestAnimationFrame` deceleration;
- a new touch or pinch cancels the previous fling.

The normal buffer is handled only while terminal mouse tracking is inactive. The xterm scrollbar remains browser-owned. Alternate-buffer gestures and mouse-protocol synthesis are not approximated.

## Long-press selection

A 500 ms stationary press delegates to xterm's existing selection input path with synthetic mouse events. A double-click-form `mousedown` lets xterm select the word under the touch, subsequent `mousemove` events extend the range, and `mouseup` completes it.

Layer 3 does not inspect xterm private objects and does not calculate selected text. Public xterm APIs remain authoritative:

```text
getSelectionPosition()
hasSelection()
getSelection()
clearSelection()
selectAll()
```

The Android host supplies a floating `ActionMode` anchored to the selected xterm cells, or to the touched cell when no text was selected. Its commands are:

- **Copy** — enabled only when xterm reports a selection; uses the existing bounded Android clipboard-write bridge;
- **Paste** — enabled when Android reports direct clipboard text; uses the existing clipboard-read bridge and `Terminal.paste()`;
- **Select all** — calls public `Terminal.selectAll()` and updates the floating anchor.

Long-pressing blank terminal space can therefore still expose Paste and Select all without inventing a DOM selection. Closing the Android action mode clears the xterm selection.

Movable Android-style selection handles are not part of this wave. A later handle implementation must update the same xterm-owned selection rather than create a second text model.

## Soft-keyboard boundary

Layer 3 owns normal-buffer terminal-screen touches from the first `touchstart`, preventing WebView compatibility mouse activation from deciding a pending gesture before Layer 3 classifies it.

```text
ordinary tap
→ replay mouse tap to xterm
→ focus terminal input
→ request Android soft input only when it was reported hidden

scroll / pinch / long-press selection
→ no tap replay
→ no explicit showSoftInput request
```

When Android reports the IME hidden at touch start, Layer 3 calls public `Terminal.blur()` to prevent a retained hidden textarea focus from reopening it. When Android reports the IME visible, Layer 3 does not deliberately blur it.

Device evidence currently establishes that a dismissed IME stays dismissed during scroll and pinch. Preservation of an already-visible IME during those gestures is **not established** and remains outside this change's claim. Long-press selection likewise makes no IME-visibility claim; it only guarantees that the selection path does not issue the tap-only soft-input request.

## Pinch font zoom

Two-finger pinch changes public `Terminal.options.fontSize` in one-pixel steps whenever distance crosses a ten-percent threshold, then requests the existing Layer 2 geometry synchronization.

```text
upstream xterm font size
× Android system font scale
× Layer 3 user font scale
```

The user scale is bounded to `0.5–3.0` and remains session-local. Pinch does not use WebView page scaling.

## Deliberate nonclaims

This policy does not add:

- movable start/end selection handles;
- a custom HTML copy/paste toolbar;
- a Layer 3 special-key toolbar;
- persistent zoom preferences;
- browser page scrolling or page zoom;
- touch wheel-protocol synthesis;
- alternate-buffer swipe-to-arrow translation;
- guaranteed preservation of an already-visible IME during gestures.

## Bounded device check

Generate selectable scrollback:

```sh
printf 'alpha beta gamma\n'
seq 1 1000
```

Verify:

1. long-pressing a word selects it and shows the Android floating Copy/Paste/Select all menu;
2. dragging while still pressed extends the xterm selection;
3. long-pressing blank space still offers Paste and Select all, with Copy disabled;
4. Copy and Paste round-trip through Android `ClipboardManager` and xterm's public paste path;
5. ordinary tap, scroll, fling, and pinch continue to follow their existing paths;
6. a manually dismissed keyboard does not reopen during scroll, pinch, or selection.
