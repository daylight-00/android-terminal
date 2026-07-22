package io.github.daylight00.androidterminal

import java.net.URI
import java.util.Locale

/** Pure validation and bounding rules used by the Layer 2 Android platform adapter. */
internal object TerminalPlatformPolicy {
    const val MAX_CLIPBOARD_CHARACTERS = 64 * 1024
    const val MAX_EXTERNAL_URI_CHARACTERS = 4096
    const val MIN_BELL_INTERVAL_MILLIS = 100L

    fun boundedClipboardText(value: CharSequence?, allowEmpty: Boolean = false): String? {
        val text = value?.toString() ?: return null
        if ((!allowEmpty && text.isEmpty()) || text.length > MAX_CLIPBOARD_CHARACTERS) return null
        return text
    }

    fun validatedExternalUri(value: String, allowedSchemes: Set<String>): String? {
        if (value.isBlank() || value.length > MAX_EXTERNAL_URI_CHARACTERS) return null
        val parsed = runCatching { URI(value) }.getOrNull() ?: return null
        val scheme = parsed.scheme?.lowercase(Locale.ROOT) ?: return null
        if (scheme !in allowedSchemes) return null
        if (parsed.userInfo != null) return null
        if (scheme == "http" || scheme == "https") {
            if (parsed.isOpaque || parsed.host.isNullOrBlank()) return null
        }
        return parsed.toASCIIString()
    }
}
