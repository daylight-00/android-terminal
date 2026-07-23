package io.github.daylight00.androidterminal

/** Neutral, service-owned OSC 0/2 title state for the current native session. */
internal object TerminalSessionTitle {
    const val MAX_CODE_POINTS = 1024

    fun sanitize(value: String): String {
        val result = StringBuilder(minOf(value.length, MAX_CODE_POINTS))
        var index = 0
        var accepted = 0
        while (index < value.length && accepted < MAX_CODE_POINTS) {
            val codePoint = value.codePointAt(index)
            index += Character.charCount(codePoint)
            if (codePoint < 0x20 || codePoint == 0x7f) continue
            result.appendCodePoint(codePoint)
            accepted += 1
        }
        return result.toString()
    }
}
