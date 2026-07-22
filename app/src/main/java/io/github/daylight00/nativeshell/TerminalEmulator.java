package io.github.daylight00.nativeshell;

import java.util.ArrayList;
import java.util.List;

final class TerminalEmulator {
    private static final int STATE_GROUND = 0;
    private static final int STATE_ESCAPE = 1;
    private static final int STATE_CSI = 2;

    private final TerminalBuffer buffer;
    private final StringBuilder csi = new StringBuilder(64);

    private int state = STATE_GROUND;
    private int utf8CodePoint;
    private int utf8Remaining;
    private int utf8Minimum;

    TerminalEmulator(int rows, int columns) {
        buffer = new TerminalBuffer(rows, columns);
    }

    synchronized void resize(int rows, int columns) {
        buffer.resize(rows, columns);
    }

    synchronized void consume(byte[] bytes, int offset, int length) {
        if (offset < 0 || length < 0 || offset + length > bytes.length) {
            throw new IndexOutOfBoundsException("invalid terminal input range");
        }
        for (int index = offset; index < offset + length; index++) {
            processByte(bytes[index] & 0xff);
        }
    }

    synchronized TerminalBuffer.Snapshot snapshot() {
        return buffer.snapshot();
    }

    private void processByte(int value) {
        if (utf8Remaining > 0) {
            if ((value & 0xc0) == 0x80) {
                utf8CodePoint = (utf8CodePoint << 6) | (value & 0x3f);
                utf8Remaining--;
                if (utf8Remaining == 0) {
                    int completed = utf8CodePoint;
                    if (completed < utf8Minimum || completed > 0x10ffff ||
                            (completed >= 0xd800 && completed <= 0xdfff)) {
                        completed = 0xfffd;
                    }
                    processCodePoint(completed);
                }
                return;
            }
            utf8Remaining = 0;
            processCodePoint(0xfffd);
        }

        if (value < 0x80) {
            processCodePoint(value);
        } else if ((value & 0xe0) == 0xc0) {
            utf8CodePoint = value & 0x1f;
            utf8Remaining = 1;
            utf8Minimum = 0x80;
        } else if ((value & 0xf0) == 0xe0) {
            utf8CodePoint = value & 0x0f;
            utf8Remaining = 2;
            utf8Minimum = 0x800;
        } else if ((value & 0xf8) == 0xf0) {
            utf8CodePoint = value & 0x07;
            utf8Remaining = 3;
            utf8Minimum = 0x10000;
        } else {
            processCodePoint(0xfffd);
        }
    }

    private void processCodePoint(int codePoint) {
        if (state == STATE_ESCAPE) {
            processEscape(codePoint);
            return;
        }
        if (state == STATE_CSI) {
            processCsi(codePoint);
            return;
        }

        switch (codePoint) {
            case 0x07:
                return;
            case 0x08:
                buffer.backspace();
                return;
            case 0x09:
                buffer.tab();
                return;
            case 0x0a:
            case 0x0b:
            case 0x0c:
                buffer.lineFeed();
                return;
            case 0x0d:
                buffer.carriageReturn();
                return;
            case 0x1b:
                state = STATE_ESCAPE;
                return;
            case 0x7f:
                return;
            default:
                if (codePoint >= 0x20) {
                    buffer.putCodePoint(codePoint);
                }
        }
    }

    private void processEscape(int codePoint) {
        state = STATE_GROUND;
        switch (codePoint) {
            case '[':
                csi.setLength(0);
                state = STATE_CSI;
                break;
            case '7':
                buffer.saveCursor();
                break;
            case '8':
                buffer.restoreCursor();
                break;
            case 'D':
                buffer.lineFeed();
                break;
            case 'E':
                buffer.nextLine();
                break;
            case 'M':
                buffer.reverseIndex();
                break;
            case 'c':
                buffer.reset();
                break;
            default:
                break;
        }
    }

    private void processCsi(int codePoint) {
        if (codePoint >= 0x40 && codePoint <= 0x7e) {
            executeCsi((char) codePoint, csi.toString());
            csi.setLength(0);
            state = STATE_GROUND;
            return;
        }
        if (csi.length() < 128 && codePoint >= 0x20 && codePoint <= 0x3f) {
            csi.append((char) codePoint);
        } else {
            csi.setLength(0);
            state = STATE_GROUND;
        }
    }

    private void executeCsi(char command, String parameterText) {
        boolean privateMode = parameterText.startsWith("?");
        if (privateMode) {
            parameterText = parameterText.substring(1);
        }
        int[] parameters = parseParameters(parameterText);
        int first = parameter(parameters, 0, 1);

        switch (command) {
            case 'A':
                buffer.moveCursorRelative(-first, 0);
                break;
            case 'B':
            case 'e':
                buffer.moveCursorRelative(first, 0);
                break;
            case 'C':
                buffer.moveCursorRelative(0, first);
                break;
            case 'D':
                buffer.moveCursorRelative(0, -first);
                break;
            case 'G':
                buffer.setCursorColumn(first);
                break;
            case 'H':
            case 'f':
                buffer.setCursorPosition(parameter(parameters, 0, 1), parameter(parameters, 1, 1));
                break;
            case 'd':
                buffer.setCursorRow(first);
                break;
            case 'J':
                buffer.eraseDisplay(parameter(parameters, 0, 0));
                break;
            case 'K':
                buffer.eraseLine(parameter(parameters, 0, 0));
                break;
            case 'm':
                applyRendition(parameters);
                break;
            case 'r':
                buffer.setScrollRegion(
                        parameter(parameters, 0, 1),
                        parameter(parameters, 1, 0));
                break;
            case 's':
                buffer.saveCursor();
                break;
            case 'u':
                buffer.restoreCursor();
                break;
            case 'h':
            case 'l':
                if (privateMode) {
                    boolean enabled = command == 'h';
                    for (int parameter : parameters) {
                        if (parameter == 25) {
                            buffer.setCursorVisible(enabled);
                        }
                    }
                }
                break;
            default:
                break;
        }
    }

    private void applyRendition(int[] parameters) {
        if (parameters.length == 0) {
            buffer.resetRendition();
            return;
        }
        for (int parameter : parameters) {
            if (parameter == 0) {
                buffer.resetRendition();
            } else if (parameter == 1) {
                buffer.setAttribute(TerminalBuffer.ATTRIBUTE_BOLD, true);
            } else if (parameter == 4) {
                buffer.setAttribute(TerminalBuffer.ATTRIBUTE_UNDERLINE, true);
            } else if (parameter == 7) {
                buffer.setAttribute(TerminalBuffer.ATTRIBUTE_INVERSE, true);
            } else if (parameter == 22) {
                buffer.setAttribute(TerminalBuffer.ATTRIBUTE_BOLD, false);
            } else if (parameter == 24) {
                buffer.setAttribute(TerminalBuffer.ATTRIBUTE_UNDERLINE, false);
            } else if (parameter == 27) {
                buffer.setAttribute(TerminalBuffer.ATTRIBUTE_INVERSE, false);
            } else if (parameter >= 30 && parameter <= 37) {
                buffer.setForeground(parameter - 30);
            } else if (parameter >= 40 && parameter <= 47) {
                buffer.setBackground(parameter - 40);
            } else if (parameter >= 90 && parameter <= 97) {
                buffer.setForeground(parameter - 90 + 8);
            } else if (parameter >= 100 && parameter <= 107) {
                buffer.setBackground(parameter - 100 + 8);
            } else if (parameter == 39) {
                buffer.resetForeground();
            } else if (parameter == 49) {
                buffer.resetBackground();
            }
        }
    }

    private static int[] parseParameters(String text) {
        if (text.isEmpty()) {
            return new int[0];
        }
        String[] parts = text.split(";", -1);
        List<Integer> values = new ArrayList<>(parts.length);
        for (String part : parts) {
            if (part.isEmpty()) {
                values.add(0);
                continue;
            }
            try {
                values.add(Integer.parseInt(part));
            } catch (NumberFormatException ignored) {
                values.add(0);
            }
        }
        int[] result = new int[values.size()];
        for (int index = 0; index < values.size(); index++) {
            result[index] = values.get(index);
        }
        return result;
    }

    private static int parameter(int[] parameters, int index, int defaultValue) {
        if (index >= parameters.length || parameters[index] == 0) {
            return defaultValue;
        }
        return parameters[index];
    }
}
