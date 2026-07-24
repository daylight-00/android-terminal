#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PACKAGE_ROOT="$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal"

if ! command -v kotlinc >/dev/null 2>&1 || ! command -v java >/dev/null 2>&1; then
  python3 - "$PACKAGE_ROOT/TerminalDocumentTransport.kt" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
for token in (
    "Intent.ACTION_OPEN_DOCUMENT",
    "Intent.ACTION_CREATE_DOCUMENT",
    "OpenableColumns.DISPLAY_NAME",
    "resolvePrivateImportDirectory",
    "destinationDirectory",
    "openInputStream",
    "openOutputStream",
    "Files.move",
    "copyBounded",
):
    if token not in source:
        raise SystemExit(f"missing document transport token: {token}")
print("PASS terminal-document-transport static-python kotlinc=unavailable")
PY
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p \
  "$WORK/android/app" \
  "$WORK/android/content" \
  "$WORK/android/database" \
  "$WORK/android/net" \
  "$WORK/android/provider" \
  "$WORK/org/json" \
  "$WORK/io/github/daylight00/androidterminal"

cat > "$WORK/android/app/Activity.kt" <<'KT'
package android.app

import android.content.ContentResolver
import java.io.File

open class Activity(
    val filesDir: File,
    val contentResolver: ContentResolver,
)
KT

cat > "$WORK/android/content/Content.kt" <<'KT'
package android.content

import android.database.Cursor
import android.net.Uri
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream

class Intent(val action: String) {
    var type: String? = null
    val categories = mutableListOf<String>()
    val extras = mutableMapOf<String, String>()
    fun addCategory(category: String): Intent { categories += category; return this }
    fun putExtra(name: String, value: String): Intent { extras[name] = value; return this }
    companion object {
        const val ACTION_OPEN_DOCUMENT = "android.intent.action.OPEN_DOCUMENT"
        const val ACTION_CREATE_DOCUMENT = "android.intent.action.CREATE_DOCUMENT"
        const val CATEGORY_OPENABLE = "android.intent.category.OPENABLE"
        const val EXTRA_TITLE = "android.intent.extra.TITLE"
    }
}

open class ContentResolver {
    var inputBytes: ByteArray = byteArrayOf()
    var outputBytes: ByteArray = byteArrayOf()
    var displayName: String = "input.txt"
    var declaredSize: Long? = null
    var mimeType: String? = "text/plain"

    open fun openInputStream(uri: Uri): InputStream? = ByteArrayInputStream(inputBytes)
    open fun openOutputStream(uri: Uri, mode: String): OutputStream? = object : ByteArrayOutputStream() {
        override fun close() {
            outputBytes = toByteArray()
            super.close()
        }
    }
    open fun getType(uri: Uri): String? = mimeType
    open fun query(
        uri: Uri,
        projection: Array<String>,
        selection: String?,
        selectionArgs: Array<String>?,
        sortOrder: String?,
    ): Cursor? = TestCursor(displayName, declaredSize)
}

private class TestCursor(
    private val displayName: String,
    private val declaredSize: Long?,
) : Cursor {
    override fun moveToFirst(): Boolean = true
    override fun getColumnIndex(name: String): Int = when (name) {
        "_display_name" -> 0
        "_size" -> 1
        else -> -1
    }
    override fun isNull(index: Int): Boolean = index == 1 && declaredSize == null
    override fun getString(index: Int): String = displayName
    override fun getLong(index: Int): Long = declaredSize ?: 0L
    override fun close() {}
}
KT

cat > "$WORK/android/database/Cursor.kt" <<'KT'
package android.database

import java.io.Closeable

interface Cursor : Closeable {
    fun moveToFirst(): Boolean
    fun getColumnIndex(name: String): Int
    fun isNull(index: Int): Boolean
    fun getString(index: Int): String
    fun getLong(index: Int): Long
}
KT

cat > "$WORK/android/net/Uri.kt" <<'KT'
package android.net
class Uri private constructor(val value: String) {
    val lastPathSegment: String? get() = value.substringAfterLast('/', "").ifBlank { null }
    companion object { fun parse(value: String): Uri = Uri(value) }
}
KT

cat > "$WORK/android/provider/OpenableColumns.kt" <<'KT'
package android.provider
object OpenableColumns {
    const val DISPLAY_NAME = "_display_name"
    const val SIZE = "_size"
}
KT

cat > "$WORK/org/json/JSONObject.kt" <<'KT'
package org.json
class JSONObject {
    private val values = mutableMapOf<String, Any?>()
    fun put(name: String, value: Any?): JSONObject { values[name] = value; return this }
    fun optString(name: String): String = values[name] as? String ?: ""
    fun string(name: String): String = values[name] as String
    fun long(name: String): Long = values[name] as Long
}
KT

cat > "$WORK/io/github/daylight00/androidterminal/Test.kt" <<'KT'
package io.github.daylight00.androidterminal

import android.app.Activity
import android.content.ContentResolver
import android.net.Uri
import org.json.JSONObject
import java.io.File

internal data class TerminalPlatformResult(
    val ok: Boolean,
    val data: JSONObject,
    val error: String?,
) {
    companion object {
        fun success(data: JSONObject) = TerminalPlatformResult(true, data, null)
        fun failure(message: String) = TerminalPlatformResult(false, JSONObject(), message)
    }
}

fun main() {
    val root = File(System.getProperty("java.io.tmpdir"), "terminal-document-transport-${System.nanoTime()}")
    check(root.mkdirs())
    try {
        val resolver = ContentResolver().apply {
            inputBytes = "payload".toByteArray()
            displayName = "folder/input.txt"
            declaredSize = inputBytes.size.toLong()
            mimeType = "text/plain"
        }
        val activity = Activity(root, resolver)
        val transport = TerminalDocumentTransport(activity)

        val importIntent = transport.importIntent("text/plain")
        check(importIntent.action == android.content.Intent.ACTION_OPEN_DOCUMENT)
        check(importIntent.type == "text/plain")

        val first = transport.importDocument(Uri.parse("content://provider/document/1"), "")
        check(first.ok)
        val firstPath = File(first.data.string("path"))
        check(firstPath.parentFile.canonicalFile == root.canonicalFile)
        check(firstPath.readText() == "payload")
        check(first.data.string("relativePath") == "input.txt")
        check(first.data.string("destinationDirectory") == "")
        check(first.data.long("bytes") == 7L)
        check(!File(root, "imports").exists())

        val second = transport.importDocument(Uri.parse("content://provider/document/2"), "")
        check(second.ok)
        check(second.data.string("relativePath") == "input (1).txt")

        val nested = transport.importDocument(Uri.parse("content://provider/document/3"), "incoming")
        check(nested.ok)
        check(nested.data.string("relativePath") == "incoming/input.txt")
        check(nested.data.string("destinationDirectory") == "incoming")
        check(File(root, "incoming/input.txt").readText() == "payload")

        val exportPayload = JSONObject()
            .put("path", "input.txt")
            .put("suggestedName", "output.txt")
            .put("mimeType", "text/plain")
        val source = checkNotNull(transport.prepareExport(exportPayload))
        val exportIntent = transport.exportIntent(source)
        check(exportIntent.action == android.content.Intent.ACTION_CREATE_DOCUMENT)
        val exported = transport.exportDocument(Uri.parse("content://provider/document/out"), source)
        check(exported.ok)
        check(resolver.outputBytes.contentEquals("payload".toByteArray()))

        check(!transport.importDocument(Uri.parse("content://provider/document/escape"), "../escape").ok)
        check(transport.prepareExport(JSONObject().put("path", "../escape")) == null)
        resolver.declaredSize = TerminalDocumentPolicy.MAX_DOCUMENT_BYTES + 1L
        check(!transport.importDocument(Uri.parse("content://provider/document/large"), "").ok)

        println("PASS terminal-document-transport runtime=kotlinc import=caller-home-destination export=streamed")
    } finally {
        root.deleteRecursively()
    }
}
KT

kotlinc -nowarn \
  "$WORK/android/app/Activity.kt" \
  "$WORK/android/content/Content.kt" \
  "$WORK/android/database/Cursor.kt" \
  "$WORK/android/net/Uri.kt" \
  "$WORK/android/provider/OpenableColumns.kt" \
  "$WORK/org/json/JSONObject.kt" \
  "$PACKAGE_ROOT/TerminalDocumentPolicy.kt" \
  "$PACKAGE_ROOT/TerminalDocumentTransport.kt" \
  "$WORK/io/github/daylight00/androidterminal/Test.kt" \
  -include-runtime -d "$WORK/document-transport.jar"
java -jar "$WORK/document-transport.jar"
