package io.github.daylight00.androidterminal

import java.util.ArrayDeque

/**
 * Rolling raw PTY byte journal. It preserves only enough unparsed output to bridge the gap between
 * the most recent official xterm.js serialized snapshot and a replacement frontend.
 */
internal class SessionReplayBuffer(private val maximumBytes: Int) {
    init {
        require(maximumBytes > 0) { "maximumBytes must be positive" }
    }

    private val records = ArrayDeque<TerminalOutputRecord>()
    private var retainedBytes = 0
    private var nextSequence = 1L
    private var truncated = false

    fun append(bytes: ByteArray): TerminalOutputRecord {
        require(bytes.isNotEmpty()) { "empty PTY output records are not allowed" }
        val record = TerminalOutputRecord(nextSequence++, bytes.copyOf())
        if (record.bytes.size > maximumBytes) {
            records.clear()
            retainedBytes = 0
            truncated = true
            return record
        }
        while (records.isNotEmpty() && retainedBytes + record.bytes.size > maximumBytes) {
            retainedBytes -= records.removeFirst().bytes.size
            truncated = true
        }
        records.addLast(record)
        retainedBytes += record.bytes.size
        return record
    }

    fun snapshotAfter(throughSequence: Long): TerminalReplaySnapshot {
        val latestSequence = latestSequence()
        val earliestSequence = records.firstOrNull()?.sequence ?: nextSequence
        val requestedFirstSequence = throughSequence + 1L
        val available = throughSequence in 0L..latestSequence &&
            (requestedFirstSequence >= earliestSequence || requestedFirstSequence >= nextSequence)
        val selected = if (available) {
            records.asSequence()
                .filter { it.sequence > throughSequence }
                .map { TerminalOutputRecord(it.sequence, it.bytes.copyOf()) }
                .toList()
        } else {
            emptyList()
        }
        return TerminalReplaySnapshot(
            available = available,
            truncated = truncated,
            records = selected,
            nextSequence = nextSequence,
            earliestSequence = earliestSequence,
        )
    }

    fun latestSequence(): Long = nextSequence - 1L

    fun reset() {
        records.clear()
        retainedBytes = 0
        nextSequence = 1L
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
    val earliestSequence: Long,
)
