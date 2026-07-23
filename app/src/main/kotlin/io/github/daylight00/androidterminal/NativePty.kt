package io.github.daylight00.androidterminal

import java.io.IOException

internal object NativePty {
    init {
        System.loadLibrary("shellbridge")
    }

    @Throws(IOException::class)
    external fun spawn(
        shellPath: String,
        cwd: String,
        home: String,
        temporaryDirectory: String,
        sharedStorageDirectory: String,
        rows: Int,
        columns: Int,
    ): Long

    @Throws(IOException::class)
    external fun read(handle: Long, destination: ByteArray, offset: Int, length: Int): Int

    @Throws(IOException::class)
    external fun write(handle: Long, source: ByteArray, offset: Int, length: Int): Int

    @Throws(IOException::class)
    external fun resize(
        handle: Long,
        rows: Int,
        columns: Int,
        pixelWidth: Int,
        pixelHeight: Int,
    )

    @Throws(IOException::class)
    external fun signalProcessGroup(handle: Long, signalNumber: Int)

    @Throws(IOException::class)
    external fun waitFor(handle: Long): Int

    external fun destroy(handle: Long)
}
