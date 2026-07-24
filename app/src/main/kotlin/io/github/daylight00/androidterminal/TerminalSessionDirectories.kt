package io.github.daylight00.androidterminal

import java.io.File
import java.io.IOException

/** Minimal account/session directory mapping. This never populates HOME. */
internal object TerminalSessionDirectories {
    @Throws(IOException::class)
    fun prepareTemporaryDirectory(directory: File): File {
        if (directory.exists()) {
            if (!directory.isDirectory) {
                throw IOException("TMPDIR path is not a directory: ${directory.absolutePath}")
            }
        } else if (!directory.mkdirs() && !directory.isDirectory) {
            throw IOException("Unable to create TMPDIR: ${directory.absolutePath}")
        }
        if (!directory.canRead() || !directory.canWrite()) {
            throw IOException("TMPDIR is not readable and writable: ${directory.absolutePath}")
        }
        return directory
    }
}
