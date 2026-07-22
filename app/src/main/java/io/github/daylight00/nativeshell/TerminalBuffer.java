package io.github.daylight00.nativeshell;

import java.util.Arrays;

final class TerminalBuffer {
    static final int ATTRIBUTE_BOLD = 1;
    static final int ATTRIBUTE_UNDERLINE = 1 << 1;
    static final int ATTRIBUTE_INVERSE = 1 << 2;

    private int rows;
    private int columns;
    private int[][] codePoints;
    private int[][] foregrounds;
    private int[][] backgrounds;
    private int[][] attributes;

    private int cursorRow;
    private int cursorColumn;
    private int savedCursorRow;
    private int savedCursorColumn;
    private int scrollTop;
    private int scrollBottom;
    private boolean cursorVisible = true;

    private int currentForeground = 7;
    private int currentBackground = 0;
    private int currentAttributes;
    private boolean pendingWrap;

    TerminalBuffer(int rows, int columns) {
        resize(rows, columns);
    }

    void resize(int newRows, int newColumns) {
        if (newRows <= 0 || newColumns <= 0) {
            throw new IllegalArgumentException("terminal dimensions must be positive");
        }

        int[][] newCodePoints = new int[newRows][newColumns];
        int[][] newForegrounds = new int[newRows][newColumns];
        int[][] newBackgrounds = new int[newRows][newColumns];
        int[][] newAttributes = new int[newRows][newColumns];
        for (int row = 0; row < newRows; row++) {
            Arrays.fill(newForegrounds[row], 7);
        }

        if (codePoints != null) {
            int rowsToCopy = Math.min(rows, newRows);
            int columnsToCopy = Math.min(columns, newColumns);
            for (int row = 0; row < rowsToCopy; row++) {
                System.arraycopy(codePoints[row], 0, newCodePoints[row], 0, columnsToCopy);
                System.arraycopy(foregrounds[row], 0, newForegrounds[row], 0, columnsToCopy);
                System.arraycopy(backgrounds[row], 0, newBackgrounds[row], 0, columnsToCopy);
                System.arraycopy(attributes[row], 0, newAttributes[row], 0, columnsToCopy);
            }
        }

        rows = newRows;
        columns = newColumns;
        codePoints = newCodePoints;
        foregrounds = newForegrounds;
        backgrounds = newBackgrounds;
        attributes = newAttributes;
        cursorRow = clamp(cursorRow, 0, rows - 1);
        cursorColumn = clamp(cursorColumn, 0, columns - 1);
        savedCursorRow = clamp(savedCursorRow, 0, rows - 1);
        savedCursorColumn = clamp(savedCursorColumn, 0, columns - 1);
        scrollTop = 0;
        scrollBottom = rows - 1;
        pendingWrap = false;
    }

    void reset() {
        currentForeground = 7;
        currentBackground = 0;
        currentAttributes = 0;
        cursorVisible = true;
        cursorRow = 0;
        cursorColumn = 0;
        savedCursorRow = 0;
        savedCursorColumn = 0;
        scrollTop = 0;
        scrollBottom = rows - 1;
        pendingWrap = false;
        eraseDisplay(2);
    }

    void putCodePoint(int codePoint) {
        if (pendingWrap) {
            cursorColumn = 0;
            lineFeed();
            pendingWrap = false;
        }
        codePoints[cursorRow][cursorColumn] = codePoint;
        foregrounds[cursorRow][cursorColumn] = currentForeground;
        backgrounds[cursorRow][cursorColumn] = currentBackground;
        attributes[cursorRow][cursorColumn] = currentAttributes;
        if (cursorColumn == columns - 1) {
            pendingWrap = true;
        } else {
            cursorColumn++;
        }
    }

    void carriageReturn() {
        cursorColumn = 0;
        pendingWrap = false;
    }

    void lineFeed() {
        pendingWrap = false;
        if (cursorRow == scrollBottom) {
            scrollUp();
        } else if (cursorRow < rows - 1) {
            cursorRow++;
        }
    }

    void reverseIndex() {
        pendingWrap = false;
        if (cursorRow == scrollTop) {
            scrollDown();
        } else if (cursorRow > 0) {
            cursorRow--;
        }
    }

    void nextLine() {
        carriageReturn();
        lineFeed();
    }

    void backspace() {
        if (cursorColumn > 0) {
            cursorColumn--;
        }
        pendingWrap = false;
    }

    void tab() {
        int nextStop = ((cursorColumn / 8) + 1) * 8;
        cursorColumn = Math.min(columns - 1, nextStop);
        pendingWrap = false;
    }

    void moveCursorRelative(int rowDelta, int columnDelta) {
        cursorRow = clamp(cursorRow + rowDelta, 0, rows - 1);
        cursorColumn = clamp(cursorColumn + columnDelta, 0, columns - 1);
        pendingWrap = false;
    }

    void setCursorPosition(int oneBasedRow, int oneBasedColumn) {
        cursorRow = clamp(Math.max(1, oneBasedRow) - 1, 0, rows - 1);
        cursorColumn = clamp(Math.max(1, oneBasedColumn) - 1, 0, columns - 1);
        pendingWrap = false;
    }

    void setCursorRow(int oneBasedRow) {
        cursorRow = clamp(Math.max(1, oneBasedRow) - 1, 0, rows - 1);
        pendingWrap = false;
    }

    void setCursorColumn(int oneBasedColumn) {
        cursorColumn = clamp(Math.max(1, oneBasedColumn) - 1, 0, columns - 1);
        pendingWrap = false;
    }

    void saveCursor() {
        savedCursorRow = cursorRow;
        savedCursorColumn = cursorColumn;
    }

    void restoreCursor() {
        cursorRow = savedCursorRow;
        cursorColumn = savedCursorColumn;
        pendingWrap = false;
    }

    void setScrollRegion(int oneBasedTop, int oneBasedBottom) {
        int top = Math.max(1, oneBasedTop) - 1;
        int bottom = oneBasedBottom <= 0 ? rows - 1 : oneBasedBottom - 1;
        top = clamp(top, 0, rows - 1);
        bottom = clamp(bottom, 0, rows - 1);
        if (top < bottom) {
            scrollTop = top;
            scrollBottom = bottom;
            setCursorPosition(1, 1);
        }
    }

    void eraseDisplay(int mode) {
        if (mode == 2 || mode == 3) {
            for (int row = 0; row < rows; row++) {
                clearRange(row, 0, columns);
            }
            return;
        }
        if (mode == 0) {
            clearRange(cursorRow, cursorColumn, columns);
            for (int row = cursorRow + 1; row < rows; row++) {
                clearRange(row, 0, columns);
            }
        } else if (mode == 1) {
            for (int row = 0; row < cursorRow; row++) {
                clearRange(row, 0, columns);
            }
            clearRange(cursorRow, 0, cursorColumn + 1);
        }
    }

    void eraseLine(int mode) {
        if (mode == 2) {
            clearRange(cursorRow, 0, columns);
        } else if (mode == 1) {
            clearRange(cursorRow, 0, cursorColumn + 1);
        } else {
            clearRange(cursorRow, cursorColumn, columns);
        }
    }

    void resetRendition() {
        currentForeground = 7;
        currentBackground = 0;
        currentAttributes = 0;
    }

    void setForeground(int color) {
        currentForeground = clamp(color, 0, 15);
    }

    void setBackground(int color) {
        currentBackground = clamp(color, 0, 15);
    }

    void resetForeground() {
        currentForeground = 7;
    }

    void resetBackground() {
        currentBackground = 0;
    }

    void setAttribute(int attribute, boolean enabled) {
        if (enabled) {
            currentAttributes |= attribute;
        } else {
            currentAttributes &= ~attribute;
        }
    }

    void setCursorVisible(boolean visible) {
        cursorVisible = visible;
    }

    Snapshot snapshot() {
        int[][] codePointCopy = new int[rows][];
        int[][] foregroundCopy = new int[rows][];
        int[][] backgroundCopy = new int[rows][];
        int[][] attributeCopy = new int[rows][];
        for (int row = 0; row < rows; row++) {
            codePointCopy[row] = codePoints[row].clone();
            foregroundCopy[row] = foregrounds[row].clone();
            backgroundCopy[row] = backgrounds[row].clone();
            attributeCopy[row] = attributes[row].clone();
        }
        return new Snapshot(
                rows,
                columns,
                codePointCopy,
                foregroundCopy,
                backgroundCopy,
                attributeCopy,
                cursorRow,
                cursorColumn,
                cursorVisible);
    }

    private void scrollUp() {
        int[] removedCodePoints = codePoints[scrollTop];
        int[] removedForegrounds = foregrounds[scrollTop];
        int[] removedBackgrounds = backgrounds[scrollTop];
        int[] removedAttributes = attributes[scrollTop];
        for (int row = scrollTop; row < scrollBottom; row++) {
            codePoints[row] = codePoints[row + 1];
            foregrounds[row] = foregrounds[row + 1];
            backgrounds[row] = backgrounds[row + 1];
            attributes[row] = attributes[row + 1];
        }
        codePoints[scrollBottom] = removedCodePoints;
        foregrounds[scrollBottom] = removedForegrounds;
        backgrounds[scrollBottom] = removedBackgrounds;
        attributes[scrollBottom] = removedAttributes;
        clearRange(scrollBottom, 0, columns);
    }

    private void scrollDown() {
        int[] removedCodePoints = codePoints[scrollBottom];
        int[] removedForegrounds = foregrounds[scrollBottom];
        int[] removedBackgrounds = backgrounds[scrollBottom];
        int[] removedAttributes = attributes[scrollBottom];
        for (int row = scrollBottom; row > scrollTop; row--) {
            codePoints[row] = codePoints[row - 1];
            foregrounds[row] = foregrounds[row - 1];
            backgrounds[row] = backgrounds[row - 1];
            attributes[row] = attributes[row - 1];
        }
        codePoints[scrollTop] = removedCodePoints;
        foregrounds[scrollTop] = removedForegrounds;
        backgrounds[scrollTop] = removedBackgrounds;
        attributes[scrollTop] = removedAttributes;
        clearRange(scrollTop, 0, columns);
    }

    private void clearRange(int row, int start, int endExclusive) {
        int safeStart = clamp(start, 0, columns);
        int safeEnd = clamp(endExclusive, safeStart, columns);
        Arrays.fill(codePoints[row], safeStart, safeEnd, 0);
        Arrays.fill(foregrounds[row], safeStart, safeEnd, currentForeground);
        Arrays.fill(backgrounds[row], safeStart, safeEnd, currentBackground);
        Arrays.fill(attributes[row], safeStart, safeEnd, currentAttributes);
    }

    private static int clamp(int value, int minimum, int maximum) {
        return Math.max(minimum, Math.min(maximum, value));
    }

    static final class Snapshot {
        final int rows;
        final int columns;
        final int[][] codePoints;
        final int[][] foregrounds;
        final int[][] backgrounds;
        final int[][] attributes;
        final int cursorRow;
        final int cursorColumn;
        final boolean cursorVisible;

        Snapshot(
                int rows,
                int columns,
                int[][] codePoints,
                int[][] foregrounds,
                int[][] backgrounds,
                int[][] attributes,
                int cursorRow,
                int cursorColumn,
                boolean cursorVisible) {
            this.rows = rows;
            this.columns = columns;
            this.codePoints = codePoints;
            this.foregrounds = foregrounds;
            this.backgrounds = backgrounds;
            this.attributes = attributes;
            this.cursorRow = cursorRow;
            this.cursorColumn = cursorColumn;
            this.cursorVisible = cursorVisible;
        }

        String rowText(int row) {
            StringBuilder result = new StringBuilder(columns);
            for (int column = 0; column < columns; column++) {
                int codePoint = codePoints[row][column];
                result.appendCodePoint(codePoint == 0 ? ' ' : codePoint);
            }
            return result.toString();
        }
    }
}
