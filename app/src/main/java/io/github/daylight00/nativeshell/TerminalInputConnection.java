package io.github.daylight00.nativeshell;

import android.view.KeyEvent;
import android.view.inputmethod.BaseInputConnection;

final class TerminalInputConnection extends BaseInputConnection {
    private final TerminalView terminalView;

    TerminalInputConnection(TerminalView terminalView) {
        super(terminalView, false);
        this.terminalView = terminalView;
    }

    @Override
    public boolean commitText(CharSequence text, int newCursorPosition) {
        if (text != null && text.length() > 0) {
            terminalView.sendText(text.toString());
        }
        return true;
    }

    @Override
    public boolean setComposingText(CharSequence text, int newCursorPosition) {
        terminalView.setComposingText(text == null ? "" : text.toString());
        return true;
    }

    @Override
    public boolean finishComposingText() {
        terminalView.setComposingText("");
        return true;
    }

    @Override
    public boolean deleteSurroundingText(int beforeLength, int afterLength) {
        if (beforeLength > 0) {
            for (int count = 0; count < beforeLength; count++) {
                terminalView.sendByte(0x7f);
            }
        }
        return true;
    }

    @Override
    public boolean sendKeyEvent(KeyEvent event) {
        return terminalView.dispatchKeyEvent(event) || super.sendKeyEvent(event);
    }
}
