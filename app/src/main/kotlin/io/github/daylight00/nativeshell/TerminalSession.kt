package io.github.daylight00.nativeshell

import android.system.OsConstants
import java.io.File
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

internal class TerminalSession(
    private val homeDirectory: File,
    private val temporaryDirectory: File,
    private val listener: Listener,
) : AutoCloseable {
    interface Listener {
        fun onOutput(bytes: ByteArray)
        fun onExit(exitCode: Int)
        fun onFailure(error: Throwable)
    }

    private val closed = AtomicBoolean(false)
    private val nativeHandleLock = Any()
    private val commandExecutor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "native-shell-command").apply { isDaemon = true }
    }

    @Volatile
    private var handle: Long = 0L

    @Volatile
    private var pendingSize = Size(24, 80, 0, 0)

    fun start(rows: Int, columns: Int, pixelWidth: Int, pixelHeight: Int) {
        pendingSize = Size(rows, columns, pixelWidth, pixelHeight).sanitized()
        Thread({ runSession() }, "native-shell-reader").apply {
            isDaemon = true
            start()
        }
    }

    fun write(bytes: ByteArray) {
        if (bytes.isEmpty() || closed.get()) return
        val copy = bytes.copyOf()
        submitCommand {
            synchronized(nativeHandleLock) {
                val current = handle
                if (current == 0L || closed.get()) return@synchronized
                NativePty.write(current, copy, 0, copy.size)
            }
        }
    }

    fun resize(rows: Int, columns: Int, pixelWidth: Int, pixelHeight: Int) {
        val size = Size(rows, columns, pixelWidth, pixelHeight).sanitized()
        pendingSize = size
        submitCommand {
            synchronized(nativeHandleLock) {
                val current = handle
                if (current == 0L || closed.get()) return@synchronized
                NativePty.resize(
                    current,
                    size.rows,
                    size.columns,
                    size.pixelWidth,
                    size.pixelHeight,
                )
            }
        }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        try {
            commandExecutor.execute {
                synchronized(nativeHandleLock) {
                    val current = handle
                    if (current == 0L) return@synchronized
                    try {
                        NativePty.signalProcessGroup(current, OsConstants.SIGHUP)
                    } catch (_: IOException) {
                        try {
                            NativePty.signalProcessGroup(current, OsConstants.SIGKILL)
                        } catch (_: IOException) {
                            // The reader thread remains the native-session owner.
                        }
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            // Natural process exit can win the race with Activity destruction.
        } finally {
            commandExecutor.shutdown()
        }
    }

    private fun submitCommand(command: () -> Unit) {
        if (closed.get() || commandExecutor.isShutdown) return
        try {
            commandExecutor.execute {
                try {
                    command()
                } catch (error: IOException) {
                    if (!closed.get()) listener.onFailure(error)
                }
            }
        } catch (_: RejectedExecutionException) {
            // The reader thread has already completed and closed the command lane.
        }
    }

    private fun runSession() {
        var nativeHandle = 0L
        var exitCode: Int? = null
        try {
            val initial = pendingSize
            nativeHandle = NativePty.spawn(
                SHELL_PATH,
                homeDirectory.absolutePath,
                homeDirectory.absolutePath,
                temporaryDirectory.absolutePath,
                initial.rows,
                initial.columns,
            )
            synchronized(nativeHandleLock) {
                handle = nativeHandle
            }

            if (closed.get()) {
                try {
                    NativePty.signalProcessGroup(nativeHandle, OsConstants.SIGHUP)
                } catch (_: IOException) {
                    // waitFor below remains the authority for process completion.
                }
            } else {
                val latest = pendingSize
                NativePty.resize(
                    nativeHandle,
                    latest.rows,
                    latest.columns,
                    latest.pixelWidth,
                    latest.pixelHeight,
                )
            }

            val buffer = ByteArray(READ_BUFFER_SIZE)
            while (!closed.get()) {
                val count = NativePty.read(nativeHandle, buffer, 0, buffer.size)
                if (count <= 0) break
                listener.onOutput(buffer.copyOf(count))
            }

            exitCode = NativePty.waitFor(nativeHandle)
        } catch (error: Throwable) {
            if (!closed.get()) listener.onFailure(error)
        } finally {
            closed.set(true)
            synchronized(nativeHandleLock) {
                handle = 0L
            }
            commandExecutor.shutdownNow()
            val commandsStopped = try {
                commandExecutor.awaitTermination(COMMAND_STOP_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                false
            }
            if (nativeHandle != 0L && commandsStopped) {
                NativePty.destroy(nativeHandle)
            } else if (nativeHandle != 0L) {
                listener.onFailure(
                    IllegalStateException("native command lane did not stop; session cleanup was deferred"),
                )
            }
        }
        if (exitCode != null) listener.onExit(exitCode)
    }

    private data class Size(
        val rows: Int,
        val columns: Int,
        val pixelWidth: Int,
        val pixelHeight: Int,
    ) {
        fun sanitized(): Size = Size(
            rows.coerceIn(1, MAX_ROWS),
            columns.coerceIn(1, MAX_COLUMNS),
            pixelWidth.coerceIn(0, MAX_PIXELS),
            pixelHeight.coerceIn(0, MAX_PIXELS),
        )
    }

    private companion object {
        const val SHELL_PATH = "/system/bin/sh"
        const val READ_BUFFER_SIZE = 16 * 1024
        const val MAX_ROWS = 2_000
        const val MAX_COLUMNS = 2_000
        const val MAX_PIXELS = 65_535
        const val COMMAND_STOP_TIMEOUT_SECONDS = 5L
    }
}
