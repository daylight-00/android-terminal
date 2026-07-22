package io.github.daylight00.androidterminal

/**
 * Opaque xterm.js framebuffer snapshot produced by the official serialize addon.
 * Layer 2 stores and replays these bytes without parsing terminal semantics.
 */
internal class TerminalSerializedSnapshotStore(private val maximumBytes: Int) {
    init {
        require(maximumBytes > 0) { "maximumBytes must be positive" }
    }

    private var current: TerminalSerializedSnapshot? = null

    fun update(
        throughSequence: Long,
        latestSequence: Long,
        bytes: ByteArray,
    ): Boolean {
        if (throughSequence < 0L || throughSequence > latestSequence) return false
        if (bytes.size > maximumBytes) return false
        val previous = current
        if (previous != null && throughSequence < previous.throughSequence) return false
        current = TerminalSerializedSnapshot(throughSequence, bytes.copyOf())
        return true
    }

    fun snapshot(): TerminalSerializedSnapshot? = current?.let {
        TerminalSerializedSnapshot(it.throughSequence, it.bytes.copyOf())
    }

    fun reset() {
        current = null
    }
}

internal data class TerminalSerializedSnapshot(
    val throughSequence: Long,
    val bytes: ByteArray,
)
