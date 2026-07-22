package io.github.daylight00.androidterminal

/** Byte-stream-neutral terminal geometry shared by the WebView adapter and PTY host. */
internal data class TerminalDimensions(
    val rows: Int,
    val columns: Int,
    val pixelWidth: Int,
    val pixelHeight: Int,
) {
    fun isUsable(): Boolean = rows > 0 && columns > 0 && pixelWidth > 0 && pixelHeight > 0

    fun sanitized(): TerminalDimensions = TerminalDimensions(
        rows.coerceIn(1, MAX_ROWS),
        columns.coerceIn(1, MAX_COLUMNS),
        pixelWidth.coerceIn(1, MAX_PIXELS),
        pixelHeight.coerceIn(1, MAX_PIXELS),
    )

    private companion object {
        const val MAX_ROWS = 2_000
        const val MAX_COLUMNS = 2_000
        const val MAX_PIXELS = 65_535
    }
}

/** Accepts only usable, changed geometry so transient zero layouts and duplicate resizes stop here. */
internal class TerminalGeometryState {
    private var current: TerminalDimensions? = null

    fun accept(candidate: TerminalDimensions): TerminalDimensions? {
        if (!candidate.isUsable()) return null
        val sanitized = candidate.sanitized()
        if (sanitized == current) return null
        current = sanitized
        return sanitized
    }

    fun snapshot(): TerminalDimensions? = current

    fun reset() {
        current = null
    }
}
