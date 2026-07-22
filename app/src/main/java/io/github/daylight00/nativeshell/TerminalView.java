package io.github.daylight00.nativeshell;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.os.Build;
import android.text.InputType;
import android.util.TypedValue;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputMethodManager;

import java.io.IOException;

final class TerminalView extends View implements TerminalSession.Listener, AutoCloseable {
    private static final int[] COLORS = {
            0xff000000, 0xffaa0000, 0xff00aa00, 0xffaa5500,
            0xff0000aa, 0xffaa00aa, 0xff00aaaa, 0xffaaaaaa,
            0xff555555, 0xffff5555, 0xff55ff55, 0xffffff55,
            0xff5555ff, 0xffff55ff, 0xff55ffff, 0xffffffff,
    };

    private final Paint textPaint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.SUBPIXEL_TEXT_FLAG);
    private final Paint backgroundPaint = new Paint();
    private final Paint cursorPaint = new Paint();

    private TerminalSession session;
    private float cellWidth;
    private float cellHeight;
    private float baselineOffset;
    private int rows;
    private int columns;
    private String composingText = "";
    private String statusText = "Starting /system/bin/sh…";
    private boolean closed;

    TerminalView(Context context) {
        super(context);
        setBackgroundColor(COLORS[0]);
        setFocusable(true);
        setFocusableInTouchMode(true);
        setKeepScreenOn(true);

        textPaint.setTypeface(Typeface.MONOSPACE);
        textPaint.setTextSize(TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_SP,
                15.0f,
                getResources().getDisplayMetrics()));
        textPaint.setColor(COLORS[7]);

        Paint.FontMetrics metrics = textPaint.getFontMetrics();
        cellWidth = Math.max(1.0f, textPaint.measureText("M"));
        cellHeight = Math.max(1.0f, metrics.descent - metrics.ascent);
        baselineOffset = -metrics.ascent;

        cursorPaint.setColor(0x99ffffff);
    }

    @Override
    public boolean onCheckIsTextEditor() {
        return true;
    }

    @Override
    public InputConnection onCreateInputConnection(EditorInfo outAttributes) {
        outAttributes.inputType = InputType.TYPE_CLASS_TEXT
                | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
                | InputType.TYPE_TEXT_FLAG_MULTI_LINE;
        outAttributes.imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI
                | EditorInfo.IME_FLAG_NO_FULLSCREEN
                | EditorInfo.IME_ACTION_NONE;
        if (Build.VERSION.SDK_INT >= 30) {
            outAttributes.setInitialSurroundingText("");
        }
        return new TerminalInputConnection(this);
    }

    @Override
    protected void onSizeChanged(int width, int height, int oldWidth, int oldHeight) {
        super.onSizeChanged(width, height, oldWidth, oldHeight);
        int newColumns = Math.max(1, (int) Math.floor(width / cellWidth));
        int newRows = Math.max(1, (int) Math.floor(height / cellHeight));
        if (newRows == rows && newColumns == columns) {
            return;
        }
        rows = newRows;
        columns = newColumns;
        if (session == null && !closed) {
            startSession();
        } else if (session != null) {
            session.resize(rows, columns, width, height);
        }
    }

    private void startSession() {
        try {
            session = new TerminalSession(getContext(), rows, columns, this);
            statusText = "";
        } catch (IOException error) {
            statusText = "Unable to start /system/bin/sh: " + error.getMessage();
        }
        invalidate();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        TerminalSession currentSession = session;
        if (currentSession == null) {
            drawStatus(canvas);
            return;
        }

        TerminalBuffer.Snapshot snapshot = currentSession.snapshot();
        for (int row = 0; row < snapshot.rows; row++) {
            float top = row * cellHeight;
            float baseline = top + baselineOffset;
            for (int column = 0; column < snapshot.columns; column++) {
                int foreground = snapshot.foregrounds[row][column];
                int background = snapshot.backgrounds[row][column];
                int attributes = snapshot.attributes[row][column];
                if ((attributes & TerminalBuffer.ATTRIBUTE_INVERSE) != 0) {
                    int swap = foreground;
                    foreground = background;
                    background = swap;
                }

                float left = column * cellWidth;
                if (background != 0) {
                    backgroundPaint.setColor(COLORS[background & 0x0f]);
                    canvas.drawRect(left, top, left + cellWidth, top + cellHeight, backgroundPaint);
                }

                int codePoint = snapshot.codePoints[row][column];
                if (codePoint != 0) {
                    textPaint.setColor(COLORS[foreground & 0x0f]);
                    textPaint.setFakeBoldText((attributes & TerminalBuffer.ATTRIBUTE_BOLD) != 0);
                    textPaint.setUnderlineText((attributes & TerminalBuffer.ATTRIBUTE_UNDERLINE) != 0);
                    canvas.drawText(new String(Character.toChars(codePoint)), left, baseline, textPaint);
                }
            }
        }
        textPaint.setFakeBoldText(false);
        textPaint.setUnderlineText(false);

        if (snapshot.cursorVisible && hasWindowFocus()) {
            float left = snapshot.cursorColumn * cellWidth;
            float top = snapshot.cursorRow * cellHeight;
            canvas.drawRect(left, top + cellHeight - 2.0f, left + cellWidth, top + cellHeight, cursorPaint);
        }

        if (!composingText.isEmpty()) {
            drawComposingText(canvas);
        }
        if (!statusText.isEmpty()) {
            drawStatus(canvas);
        }
    }

    private void drawComposingText(Canvas canvas) {
        float top = Math.max(0.0f, getHeight() - cellHeight);
        backgroundPaint.setColor(0xff333333);
        canvas.drawRect(0.0f, top, getWidth(), getHeight(), backgroundPaint);
        textPaint.setColor(COLORS[15]);
        textPaint.setFakeBoldText(false);
        textPaint.setUnderlineText(true);
        canvas.drawText(composingText, 0.0f, top + baselineOffset, textPaint);
        textPaint.setUnderlineText(false);
    }

    private void drawStatus(Canvas canvas) {
        if (statusText.isEmpty()) {
            return;
        }
        backgroundPaint.setColor(0xcc000000);
        canvas.drawRect(0.0f, 0.0f, getWidth(), cellHeight * 2.0f, backgroundPaint);
        textPaint.setColor(COLORS[7]);
        textPaint.setFakeBoldText(false);
        textPaint.setUnderlineText(false);
        canvas.drawText(statusText, 0.0f, baselineOffset, textPaint);
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
            requestFocus();
            InputMethodManager manager = getContext().getSystemService(InputMethodManager.class);
            if (manager != null) {
                manager.showSoftInput(this, InputMethodManager.SHOW_IMPLICIT);
            }
            return true;
        }
        return super.onTouchEvent(event);
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (session == null) {
            return super.onKeyDown(keyCode, event);
        }

        if (event.isCtrlPressed()) {
            if (keyCode >= KeyEvent.KEYCODE_A && keyCode <= KeyEvent.KEYCODE_Z) {
                sendByte(keyCode - KeyEvent.KEYCODE_A + 1);
                return true;
            }
            if (keyCode == KeyEvent.KEYCODE_SPACE) {
                sendByte(0);
                return true;
            }
            if (keyCode == KeyEvent.KEYCODE_LEFT_BRACKET) {
                sendByte(0x1b);
                return true;
            }
            if (keyCode == KeyEvent.KEYCODE_BACKSLASH) {
                sendByte(0x1c);
                return true;
            }
            if (keyCode == KeyEvent.KEYCODE_RIGHT_BRACKET) {
                sendByte(0x1d);
                return true;
            }
        }

        switch (keyCode) {
            case KeyEvent.KEYCODE_ENTER:
            case KeyEvent.KEYCODE_NUMPAD_ENTER:
                sendByte('\r');
                return true;
            case KeyEvent.KEYCODE_DEL:
                sendByte(0x7f);
                return true;
            case KeyEvent.KEYCODE_FORWARD_DEL:
                sendText("\u001b[3~");
                return true;
            case KeyEvent.KEYCODE_TAB:
                sendByte('\t');
                return true;
            case KeyEvent.KEYCODE_ESCAPE:
                sendByte(0x1b);
                return true;
            case KeyEvent.KEYCODE_DPAD_UP:
                sendText("\u001b[A");
                return true;
            case KeyEvent.KEYCODE_DPAD_DOWN:
                sendText("\u001b[B");
                return true;
            case KeyEvent.KEYCODE_DPAD_RIGHT:
                sendText("\u001b[C");
                return true;
            case KeyEvent.KEYCODE_DPAD_LEFT:
                sendText("\u001b[D");
                return true;
            case KeyEvent.KEYCODE_MOVE_HOME:
                sendText("\u001b[H");
                return true;
            case KeyEvent.KEYCODE_MOVE_END:
                sendText("\u001b[F");
                return true;
            case KeyEvent.KEYCODE_PAGE_UP:
                sendText("\u001b[5~");
                return true;
            case KeyEvent.KEYCODE_PAGE_DOWN:
                sendText("\u001b[6~");
                return true;
            default:
                int unicode = event.getUnicodeChar(event.getMetaState() & ~KeyEvent.META_CTRL_MASK);
                if (unicode != 0) {
                    sendText(new String(Character.toChars(unicode)));
                    return true;
                }
                return super.onKeyDown(keyCode, event);
        }
    }

    void sendText(String text) {
        TerminalSession currentSession = session;
        if (currentSession != null) {
            currentSession.sendText(text);
        }
    }

    void sendByte(int value) {
        TerminalSession currentSession = session;
        if (currentSession != null) {
            currentSession.sendByte(value);
        }
    }

    void setComposingText(String text) {
        composingText = text;
        invalidate();
    }

    @Override
    public void onScreenChanged() {
        postInvalidateOnAnimation();
    }

    @Override
    public void onSessionFinished(int exitCode, String errorMessage) {
        if (errorMessage != null && !errorMessage.isEmpty()) {
            statusText = "Shell error: " + errorMessage;
        } else {
            statusText = "Shell exited with status " + exitCode;
        }
        invalidate();
    }

    @Override
    public void close() {
        closed = true;
        TerminalSession currentSession = session;
        session = null;
        if (currentSession != null) {
            currentSession.close();
        }
    }
}
