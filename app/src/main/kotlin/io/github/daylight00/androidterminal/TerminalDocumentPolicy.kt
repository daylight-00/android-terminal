package io.github.daylight00.androidterminal

import java.io.File

/** Pure Layer 2 bounds for SAF-to-private-file transport. */
internal object TerminalDocumentPolicy {
    const val IMPORT_DIRECTORY_NAME = "imports"
    const val MAX_DOCUMENT_BYTES = 1024L * 1024L * 1024L
    const val MAX_DISPLAY_NAME_CHARACTERS = 160
    const val MAX_RELATIVE_PATH_CHARACTERS = 4096
    const val MAX_MIME_TYPE_CHARACTERS = 255

    private val mimeTypePattern = Regex("^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+*-]+$")

    fun sanitizedDisplayName(value: String?, fallback: String = "document"): String {
        val leaf = value
            ?.substringAfterLast('/')
            ?.substringAfterLast('\\')
            .orEmpty()
        val sanitized = buildString(leaf.length.coerceAtMost(MAX_DISPLAY_NAME_CHARACTERS)) {
            for (character in leaf) {
                if (length >= MAX_DISPLAY_NAME_CHARACTERS) break
                append(
                    when {
                        character == '/' || character == '\\' -> '_'
                        character.code in 0..31 || character.code == 127 -> '_'
                        else -> character
                    },
                )
            }
        }.trim()
        if (sanitized.isBlank() || sanitized == "." || sanitized == "..") {
            return fallback.take(MAX_DISPLAY_NAME_CHARACTERS).ifBlank { "document" }
        }
        return sanitized
    }

    fun boundedMimeType(value: String?, fallback: String = "application/octet-stream"): String {
        val candidate = value?.trim().orEmpty()
        return if (
            candidate.length in 1..MAX_MIME_TYPE_CHARACTERS &&
            (candidate == "*/*" || mimeTypePattern.matches(candidate))
        ) {
            candidate
        } else {
            fallback
        }
    }

    fun validatedRelativeHomePath(value: String): String? {
        if (value.isBlank() || value.length > MAX_RELATIVE_PATH_CHARACTERS) return null
        if (value.startsWith('/') || value.startsWith('\\')) return null
        if ('\u0000' in value || '\\' in value) return null
        val parts = value.split('/')
        if (parts.any { part ->
                part.isEmpty() || part == "." || part == ".." ||
                    part.any { it.code in 0..31 || it.code == 127 }
            }
        ) {
            return null
        }
        return parts.joinToString("/")
    }

    fun resolvePrivateExportSource(homeDirectory: File, relativePath: String): File? {
        val validated = validatedRelativeHomePath(relativePath) ?: return null
        val root = runCatching { homeDirectory.canonicalFile }.getOrNull() ?: return null
        val candidate = runCatching { File(root, validated).canonicalFile }.getOrNull() ?: return null
        val rootPrefix = root.path + File.separator
        if (candidate.path != root.path && !candidate.path.startsWith(rootPrefix)) return null
        if (!candidate.isFile || !candidate.canRead()) return null
        if (candidate.length() < 0L || candidate.length() > MAX_DOCUMENT_BYTES) return null
        return candidate
    }

    fun uniqueImportTarget(directory: File, displayName: String): File {
        val safeName = sanitizedDisplayName(displayName)
        val first = File(directory, safeName)
        if (!first.exists()) return first

        val dot = safeName.lastIndexOf('.')
        val base = if (dot > 0) safeName.substring(0, dot) else safeName
        val extension = if (dot > 0) safeName.substring(dot) else ""
        for (index in 1..9999) {
            val suffix = " ($index)$extension"
            val limitedBase = base.take((MAX_DISPLAY_NAME_CHARACTERS - suffix.length).coerceAtLeast(1))
            val candidate = File(directory, limitedBase + suffix)
            if (!candidate.exists()) return candidate
        }
        return File(directory, "document-${System.nanoTime()}")
    }
}
