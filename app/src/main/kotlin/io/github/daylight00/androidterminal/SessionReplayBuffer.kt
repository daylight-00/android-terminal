package io.github.daylight00.androidterminal

import java.util.ArrayDeque

/**
 * Bounded raw PTY stream journal used only to rebuild a newly attached xterm.js frontend.
 * It deliberately stores bytes without interpreting terminal semantics.
 */
internal class SessionReplayBuffer(private val maximumBytes: Int) {
    init {
        require(maximumBytes > 0) { "maximumBytes must be positive" }
    }

    private val records = ArrayDeque<TerminalOutputRecord>()
    private var retainedBytes = 0
    private var nextSequence = 1L
    private var replayAvailable = true
    private var truncated = false

    fun append(bytes: ByteArray): TerminalOutputRecord {
        require(bytes.isNotEmpty()) { "empty PTY output records are not allowed" }
        val record = TerminalOutputRecord(nextSequence++, bytes.copyOf())
        if (replayAvailable) {
            if (retainedBytes + record.bytes.size <= maximumBytes) {
                records.addLast(record)
                retainedBytes += record.bytes.size
            } else {
                records.clear()
                retainedBytes = 0
                replayAvailable = false
                truncated = true
            }
        }
        return record
    }

    fun snapshot(): TerminalReplaySnapshot = TerminalReplaySnapshot(
        available = replayAvailable,
        truncated = truncated,
        records = records.map { record ->
            TerminalOutputRecord(record.sequence, record.bytes.copyOf())
        },
        nextSequence = nextSequence,
    )

    fun reset() {
        records.clear()
        retainedBytes = 0
        nextSequence = 1L
        replayAvailable = true
        truncated = false
    }
}

internal data class TerminalOutputRecord(
    val sequence: Long,
    val bytes: ByteArray,
)

internal data class TerminalReplaySnapshot(
    val available: Boolean,
    val truncated: Boolean,
    val records: List<TerminalOutputRecord>,
    val nextSequence: Long,
)
