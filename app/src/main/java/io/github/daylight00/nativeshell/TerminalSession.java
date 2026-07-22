package io.github.daylight00.nativeshell;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

final class TerminalSession implements AutoCloseable {
    interface Listener {
        void onScreenChanged();

        void onSessionFinished(int exitCode, String errorMessage);
    }

    private static final int SIGNAL_HANGUP = 1;

    private final TerminalEmulator emulator;
    private final Listener listener;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService writer = Executors.newSingleThreadExecutor(runnable -> {
        Thread thread = new Thread(runnable, "native-shell-writer");
        thread.setDaemon(true);
        return thread;
    });
    private final AtomicBoolean closing = new AtomicBoolean();
    private final long handle;
    private final Thread readerThread;

    TerminalSession(Context context, int rows, int columns, Listener listener) throws IOException {
        this.listener = listener;
        emulator = new TerminalEmulator(rows, columns);
        String home = context.getFilesDir().getAbsolutePath();
        String temporaryDirectory = context.getCacheDir().getAbsolutePath();
        handle = NativePty.spawn(
                "/system/bin/sh",
                home,
                home,
                temporaryDirectory,
                rows,
                columns);
        if (handle == 0) {
            throw new IOException("native PTY returned an invalid handle");
        }
        readerThread = new Thread(this::readLoop, "native-shell-reader");
        readerThread.setDaemon(true);
        readerThread.start();
    }

    TerminalBuffer.Snapshot snapshot() {
        return emulator.snapshot();
    }

    void resize(int rows, int columns, int pixelWidth, int pixelHeight) {
        emulator.resize(rows, columns);
        try {
            NativePty.resize(handle, rows, columns, pixelWidth, pixelHeight);
        } catch (IOException error) {
            finish(-1, error.getMessage());
        }
    }

    void sendText(String text) {
        sendBytes(text.getBytes(StandardCharsets.UTF_8));
    }

    void sendByte(int value) {
        sendBytes(new byte[]{(byte) value});
    }

    void sendBytes(byte[] bytes) {
        if (bytes.length == 0 || closing.get()) {
            return;
        }
        byte[] copy = bytes.clone();
        writer.execute(() -> {
            try {
                NativePty.write(handle, copy, 0, copy.length);
            } catch (IOException error) {
                finish(-1, error.getMessage());
            }
        });
    }

    private void readLoop() {
        byte[] bytes = new byte[16 * 1024];
        int exitCode = -1;
        String errorMessage = null;
        try {
            while (!closing.get()) {
                int count = NativePty.read(handle, bytes, 0, bytes.length);
                if (count <= 0) {
                    break;
                }
                emulator.consume(bytes, 0, count);
                mainHandler.post(listener::onScreenChanged);
            }
            exitCode = NativePty.waitFor(handle);
        } catch (IOException error) {
            errorMessage = error.getMessage();
        } finally {
            closing.set(true);
            writer.shutdownNow();
            NativePty.destroy(handle);
            finish(exitCode, errorMessage);
        }
    }

    private void finish(int exitCode, String errorMessage) {
        mainHandler.post(() -> listener.onSessionFinished(exitCode, errorMessage));
    }

    @Override
    public void close() {
        if (!closing.compareAndSet(false, true)) {
            return;
        }
        writer.shutdownNow();
        try {
            NativePty.signalProcessGroup(handle, SIGNAL_HANGUP);
        } catch (IOException ignored) {
            // The child may already have exited.
        }
    }
}
