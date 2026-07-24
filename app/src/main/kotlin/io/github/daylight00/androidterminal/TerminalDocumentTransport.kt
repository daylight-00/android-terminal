package io.github.daylight00.androidterminal

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.util.UUID

/**
 * Layer 2 stream transport between Android SAF URIs and real files under app-private HOME.
 * It does not infer formats, impose a fixed HOME inbox, expose content URIs to the shell,
 * or emulate a filesystem mount.
 */
internal class TerminalDocumentTransport(private val activity: Activity) {
    data class ExportSource(
        val file: File,
        val relativePath: String,
        val suggestedName: String,
        val mimeType: String,
    )

    fun importIntent(requestedMimeType: String?): Intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        addCategory(Intent.CATEGORY_OPENABLE)
        type = TerminalDocumentPolicy.boundedMimeType(requestedMimeType, "*/*")
    }

    fun prepareExport(payload: JSONObject): ExportSource? {
        val relativePath = TerminalDocumentPolicy.validatedRelativeHomePath(payload.optString("path"))
            ?: return null
        val source = TerminalDocumentPolicy.resolvePrivateExportSource(activity.filesDir, relativePath)
            ?: return null
        val suggestedName = TerminalDocumentPolicy.sanitizedDisplayName(
            payload.optString("suggestedName").takeIf { it.isNotBlank() },
            source.name,
        )
        val mimeType = TerminalDocumentPolicy.boundedMimeType(payload.optString("mimeType"))
        return ExportSource(source, relativePath, suggestedName, mimeType)
    }

    fun exportIntent(source: ExportSource): Intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
        addCategory(Intent.CATEGORY_OPENABLE)
        type = source.mimeType
        putExtra(Intent.EXTRA_TITLE, source.suggestedName)
    }

    fun importDocument(uri: Uri, destinationDirectory: String): TerminalPlatformResult {
        val resolver = activity.contentResolver
        val metadata = queryMetadata(uri)
        if (metadata.size != null && metadata.size > TerminalDocumentPolicy.MAX_DOCUMENT_BYTES) {
            return TerminalPlatformResult.failure("selected document exceeds the bounded transport limit")
        }

        val importDirectory = TerminalDocumentPolicy.resolvePrivateImportDirectory(
            activity.filesDir,
            destinationDirectory,
        ) ?: return TerminalPlatformResult.failure(
            "import destination must be a writable HOME-relative directory",
        )
        val validatedDestination = TerminalDocumentPolicy.validatedRelativeHomeDirectory(
            destinationDirectory,
        ) ?: return TerminalPlatformResult.failure("invalid HOME-relative import destination")
        val displayName = TerminalDocumentPolicy.sanitizedDisplayName(
            metadata.displayName ?: uri.lastPathSegment,
            "document",
        )
        val target = TerminalDocumentPolicy.uniqueImportTarget(importDirectory, displayName)
        val temporary = File(importDirectory, ".import-${UUID.randomUUID()}.tmp")

        return try {
            val bytes = resolver.openInputStream(uri).use { input ->
                requireNotNull(input) { "selected document is not readable" }
                FileOutputStream(temporary).use { output ->
                    copyBounded(input::read, output::write)
                }
            }
            Files.move(temporary.toPath(), target.toPath())
            val relativePath = if (validatedDestination.isEmpty()) {
                target.name
            } else {
                "$validatedDestination/${target.name}"
            }
            TerminalPlatformResult.success(
                JSONObject()
                    .put("path", target.absolutePath)
                    .put("relativePath", relativePath)
                    .put("destinationDirectory", validatedDestination)
                    .put("name", target.name)
                    .put("mimeType", TerminalDocumentPolicy.boundedMimeType(metadata.mimeType))
                    .put("bytes", bytes),
            )
        } catch (error: Throwable) {
            temporary.delete()
            TerminalPlatformResult.failure(error.message ?: "document import failed")
        }
    }

    fun exportDocument(uri: Uri, source: ExportSource): TerminalPlatformResult {
        val currentSource = TerminalDocumentPolicy.resolvePrivateExportSource(
            activity.filesDir,
            source.relativePath,
        ) ?: return TerminalPlatformResult.failure("export source is no longer a readable private file")
        return try {
            val bytes = activity.contentResolver.openOutputStream(uri, "w").use { output ->
                requireNotNull(output) { "created document is not writable" }
                currentSource.inputStream().use { input ->
                    copyBounded(input::read, output::write)
                }
            }
            TerminalPlatformResult.success(
                JSONObject()
                    .put("relativePath", source.relativePath)
                    .put("name", source.suggestedName)
                    .put("mimeType", source.mimeType)
                    .put("bytes", bytes),
            )
        } catch (error: Throwable) {
            TerminalPlatformResult.failure(error.message ?: "document export failed")
        }
    }

    private fun queryMetadata(uri: Uri): DocumentMetadata {
        var displayName: String? = null
        var size: Long? = null
        val cursor = runCatching {
            activity.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null,
            )
        }.getOrNull()
        cursor?.use {
            if (it.moveToFirst()) {
                displayName = stringColumn(it, OpenableColumns.DISPLAY_NAME)
                size = longColumn(it, OpenableColumns.SIZE)
            }
        }
        val mimeType = runCatching { activity.contentResolver.getType(uri) }.getOrNull()
        return DocumentMetadata(displayName, size, mimeType)
    }

    private fun stringColumn(cursor: Cursor, name: String): String? {
        val index = cursor.getColumnIndex(name)
        return if (index >= 0 && !cursor.isNull(index)) cursor.getString(index) else null
    }

    private fun longColumn(cursor: Cursor, name: String): Long? {
        val index = cursor.getColumnIndex(name)
        return if (index >= 0 && !cursor.isNull(index)) cursor.getLong(index) else null
    }

    private fun copyBounded(
        read: (ByteArray) -> Int,
        write: (ByteArray, Int, Int) -> Unit,
    ): Long {
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0L
        while (true) {
            val count = read(buffer)
            if (count < 0) break
            if (count == 0) continue
            total += count
            if (total > TerminalDocumentPolicy.MAX_DOCUMENT_BYTES) {
                throw IllegalStateException("document exceeds the bounded transport limit")
            }
            write(buffer, 0, count)
        }
        return total
    }

    private data class DocumentMetadata(
        val displayName: String?,
        val size: Long?,
        val mimeType: String?,
    )
}
