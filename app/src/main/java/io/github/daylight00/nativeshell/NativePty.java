package io.github.daylight00.nativeshell;

import java.io.IOException;

final class NativePty {
    static {
        System.loadLibrary("shellbridge");
    }

    private NativePty() {
    }

    static native long spawn(
            String shellPath,
            String cwd,
            String home,
            String temporaryDirectory,
            int rows,
            int columns) throws IOException;

    static native int read(long handle, byte[] destination, int offset, int length) throws IOException;

    static native int write(long handle, byte[] source, int offset, int length) throws IOException;

    static native void resize(
            long handle,
            int rows,
            int columns,
            int pixelWidth,
            int pixelHeight) throws IOException;

    static native void signalProcessGroup(long handle, int signalNumber) throws IOException;

    static native int waitFor(long handle) throws IOException;

    static native void destroy(long handle);
}
