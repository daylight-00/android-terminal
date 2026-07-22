package io.github.daylight00.nativeshell;

import java.nio.charset.StandardCharsets;

public final class TerminalEmulatorTest {
    public static void main(String[] arguments) {
        writesUtf8Text();
        handlesCarriageReturnAndLineFeed();
        movesCursorWithCsi();
        erasesLine();
        appliesColorAndAttributes();
        scrollsAtBottom();
        decodesUtf8AcrossChunks();
        replacesMalformedUtf8();
        rejectsInvalidRange();
        System.out.println("TerminalEmulatorTest: PASS");
    }

    private static void writesUtf8Text() {
        TerminalEmulator emulator = new TerminalEmulator(2, 12);
        consume(emulator, "hello 한");
        assertStartsWith(emulator.snapshot().rowText(0), "hello 한", "UTF-8 text");
    }

    private static void handlesCarriageReturnAndLineFeed() {
        TerminalEmulator emulator = new TerminalEmulator(3, 8);
        consume(emulator, "abc\rZ\nQ");
        TerminalBuffer.Snapshot snapshot = emulator.snapshot();
        assertStartsWith(snapshot.rowText(0), "Zbc", "carriage return");
        assertStartsWith(snapshot.rowText(1), " Q", "line feed preserves column");
    }

    private static void movesCursorWithCsi() {
        TerminalEmulator emulator = new TerminalEmulator(3, 8);
        consume(emulator, "abc\u001b[2;3HX");
        TerminalBuffer.Snapshot snapshot = emulator.snapshot();
        if (snapshot.codePoints[1][2] != 'X') {
            throw new AssertionError("CSI cursor positioning failed");
        }
    }

    private static void erasesLine() {
        TerminalEmulator emulator = new TerminalEmulator(2, 8);
        consume(emulator, "abcdef\u001b[3D\u001b[K");
        assertEquals("abc     ", emulator.snapshot().rowText(0), "erase to end of line");
    }

    private static void appliesColorAndAttributes() {
        TerminalEmulator emulator = new TerminalEmulator(2, 8);
        consume(emulator, "\u001b[1;31mR");
        TerminalBuffer.Snapshot snapshot = emulator.snapshot();
        if (snapshot.foregrounds[0][0] != 1) {
            throw new AssertionError("red SGR failed");
        }
        if ((snapshot.attributes[0][0] & TerminalBuffer.ATTRIBUTE_BOLD) == 0) {
            throw new AssertionError("bold SGR failed");
        }
    }

    private static void scrollsAtBottom() {
        TerminalEmulator emulator = new TerminalEmulator(2, 4);
        consume(emulator, "a\r\nb\r\nc");
        TerminalBuffer.Snapshot snapshot = emulator.snapshot();
        assertStartsWith(snapshot.rowText(0), "b", "scroll first row");
        assertStartsWith(snapshot.rowText(1), "c", "scroll second row");
    }

    private static void decodesUtf8AcrossChunks() {
        TerminalEmulator emulator = new TerminalEmulator(2, 8);
        byte[] bytes = "한".getBytes(StandardCharsets.UTF_8);
        emulator.consume(bytes, 0, 1);
        emulator.consume(bytes, 1, bytes.length - 1);
        assertStartsWith(emulator.snapshot().rowText(0), "한", "split UTF-8 sequence");
    }

    private static void replacesMalformedUtf8() {
        TerminalEmulator emulator = new TerminalEmulator(2, 8);
        byte[] bytes = {(byte) 0xc0, (byte) 0xaf};
        emulator.consume(bytes, 0, bytes.length);
        if (emulator.snapshot().codePoints[0][0] != 0xfffd) {
            throw new AssertionError("malformed UTF-8 was not replaced");
        }
    }

    private static void rejectsInvalidRange() {
        TerminalEmulator emulator = new TerminalEmulator(2, 8);
        try {
            emulator.consume(new byte[1], 1, 1);
            throw new AssertionError("invalid range unexpectedly passed");
        } catch (IndexOutOfBoundsException expected) {
            // Expected-negative fixture.
        }
    }

    private static void consume(TerminalEmulator emulator, String text) {
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        emulator.consume(bytes, 0, bytes.length);
    }

    private static void assertStartsWith(String actual, String expected, String label) {
        if (!actual.startsWith(expected)) {
            throw new AssertionError(label + ": expected prefix <" + expected + "> but was <" + actual + ">");
        }
    }

    private static void assertEquals(String expected, String actual, String label) {
        if (!expected.equals(actual)) {
            throw new AssertionError(label + ": expected <" + expected + "> but was <" + actual + ">");
        }
    }
}
