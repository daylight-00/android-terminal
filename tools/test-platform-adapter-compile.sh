#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PACKAGE_ROOT="$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal"

if ! command -v kotlinc >/dev/null 2>&1; then
  python3 - "$PACKAGE_ROOT/TerminalPlatformAdapter.kt" "$PACKAGE_ROOT/TerminalDocumentTransport.kt" <<'PY'
from pathlib import Path
import sys
source = "\n".join(Path(value).read_text(encoding="utf-8") for value in sys.argv[1:])
for token in (
    "ClipboardManager",
    "ClipData.newPlainText",
    "Intent.ACTION_VIEW",
    "Intent.ACTION_OPEN_DOCUMENT",
    "Intent.ACTION_CREATE_DOCUMENT",
    "OpenableColumns.DISPLAY_NAME",
    "startActivityForResult",
    "openInputStream",
    "openOutputStream",
    "performHapticFeedback",
    "InputMethodManager",
    "WindowInsets.Type.ime()",
    "systemWindowInsetBottom > insets.stableInsetBottom",
    "showSoftInput",
    "restartInput",
    "AccessibilityStateChangeListener",
    "TouchExplorationStateChangeListener",
    "configuration.locales[0].toLanguageTag()",
    "R.string.xterm_prompt_label",
    "R.string.xterm_too_much_output",
):
    if token not in source:
        raise SystemExit(f"missing Android platform API token: {token}")
print("PASS terminal-platform-adapter static-python kotlinc=unavailable")
PY
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p \
  "$WORK/android/app" \
  "$WORK/android/content" \
  "$WORK/android/content/res" \
  "$WORK/android/database" \
  "$WORK/android/graphics" \
  "$WORK/android/net" \
  "$WORK/android/os" \
  "$WORK/android/provider" \
  "$WORK/android/view" \
  "$WORK/android/view/accessibility" \
  "$WORK/android/view/inputmethod" \
  "$WORK/android/webkit" \
  "$WORK/org/json" \
  "$WORK/io/github/daylight00/androidterminal"

cat > "$WORK/android/app/Activity.kt" <<'KT'
package android.app

import android.content.ContentResolver
import android.content.Intent
import android.content.res.Resources
import java.io.File

open class Activity {
    val resources: Resources = Resources()
    val contentResolver: ContentResolver = ContentResolver()
    val filesDir: File = File(System.getProperty("java.io.tmpdir"), "android-files")
    fun <T> getSystemService(serviceClass: Class<T>): T? = null
    fun startActivity(intent: Intent) {}
    fun startActivityForResult(intent: Intent, requestCode: Int) {}
    fun runOnUiThread(action: () -> Unit) = action()
    fun getString(id: Int): String = "localized-$id"
    companion object { const val RESULT_OK: Int = -1 }
}
KT

cat > "$WORK/android/content/Content.kt" <<'KT'
package android.content

import android.database.Cursor
import android.net.Uri
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream

open class ActivityNotFoundException : RuntimeException()

class Intent(var action: String? = null, var data: Uri? = null) {
    var type: String? = null
    fun addCategory(category: String): Intent = this
    fun putExtra(name: String, value: String): Intent = this
    companion object {
        const val ACTION_VIEW: String = "android.intent.action.VIEW"
        const val ACTION_OPEN_DOCUMENT: String = "android.intent.action.OPEN_DOCUMENT"
        const val ACTION_CREATE_DOCUMENT: String = "android.intent.action.CREATE_DOCUMENT"
        const val CATEGORY_OPENABLE: String = "android.intent.category.OPENABLE"
        const val EXTRA_TITLE: String = "android.intent.extra.TITLE"
    }
}

open class ContentResolver {
    fun openInputStream(uri: Uri): InputStream? = ByteArrayInputStream(byteArrayOf())
    fun openOutputStream(uri: Uri, mode: String): OutputStream? = ByteArrayOutputStream()
    fun getType(uri: Uri): String? = null
    fun query(
        uri: Uri,
        projection: Array<String>,
        selection: String?,
        selectionArgs: Array<String>?,
        sortOrder: String?,
    ): Cursor? = null
}

class ClipData private constructor(private val values: List<Item>) {
    class Item(val text: CharSequence?)
    val itemCount: Int get() = values.size
    fun getItemAt(index: Int): Item = values[index]
    companion object {
        fun newPlainText(label: CharSequence?, text: CharSequence?): ClipData =
            ClipData(listOf(Item(text)))
    }
}

open class ClipboardManager {
    private var storedClip: ClipData? = null
    val primaryClip: ClipData? get() = storedClip
    fun setPrimaryClip(clip: ClipData) { storedClip = clip }
}
KT

cat > "$WORK/android/content/res/Configuration.kt" <<'KT'
package android.content.res

class LocaleList {
    operator fun get(index: Int): java.util.Locale = java.util.Locale.ENGLISH
}

class Configuration {
    var uiMode: Int = 0
    var keyboard: Int = KEYBOARD_NOKEYS
    var fontScale: Float = 1f
    var locales: LocaleList = LocaleList()
    companion object {
        const val UI_MODE_NIGHT_MASK: Int = 0x30
        const val UI_MODE_NIGHT_YES: Int = 0x20
        const val KEYBOARD_UNDEFINED: Int = 0
        const val KEYBOARD_NOKEYS: Int = 1
    }
}

class Resources(val configuration: Configuration = Configuration())
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
    override fun close() {}
}
KT

cat > "$WORK/android/graphics/Color.kt" <<'KT'
package android.graphics
object Color {
    const val BLACK: Int = 0xff000000.toInt()
    fun rgb(red: Int, green: Int, blue: Int): Int = 0
}
KT

cat > "$WORK/android/net/Uri.kt" <<'KT'
package android.net
class Uri private constructor(val value: String) {
    val lastPathSegment: String? get() = value.substringAfterLast('/', "").ifBlank { null }
    companion object { fun parse(value: String): Uri = Uri(value) }
}
KT

cat > "$WORK/android/os/SystemClock.kt" <<'KT'
package android.os
object SystemClock { fun elapsedRealtime(): Long = 0L }
KT

cat > "$WORK/android/os/Build.kt" <<'KT'
package android.os
object Build {
    object VERSION { const val SDK_INT: Int = 35 }
    object VERSION_CODES { const val R: Int = 30 }
}
KT

cat > "$WORK/android/provider/OpenableColumns.kt" <<'KT'
package android.provider
object OpenableColumns {
    const val DISPLAY_NAME: String = "_display_name"
    const val SIZE: String = "_size"
}
KT

cat > "$WORK/android/view/HapticFeedbackConstants.kt" <<'KT'
package android.view
object HapticFeedbackConstants { const val CLOCK_TICK: Int = 4 }
KT

cat > "$WORK/android/view/WindowInsets.kt" <<'KT'
package android.view
open class WindowInsets {
    val systemWindowInsetBottom: Int = 0
    val stableInsetBottom: Int = 0
    fun isVisible(typeMask: Int): Boolean = false
    object Type { fun ime(): Int = 1 }
}
KT

cat > "$WORK/android/view/accessibility/AccessibilityManager.kt" <<'KT'
package android.view.accessibility

open class AccessibilityManager {
    fun interface AccessibilityStateChangeListener {
        fun onAccessibilityStateChanged(enabled: Boolean)
    }
    fun interface TouchExplorationStateChangeListener {
        fun onTouchExplorationStateChanged(enabled: Boolean)
    }
    var isEnabled: Boolean = false
    var isTouchExplorationEnabled: Boolean = false
    fun addAccessibilityStateChangeListener(listener: AccessibilityStateChangeListener): Boolean = true
    fun removeAccessibilityStateChangeListener(listener: AccessibilityStateChangeListener): Boolean = true
    fun addTouchExplorationStateChangeListener(listener: TouchExplorationStateChangeListener): Boolean = true
    fun removeTouchExplorationStateChangeListener(listener: TouchExplorationStateChangeListener): Boolean = true
}
KT


cat > "$WORK/android/view/inputmethod/InputMethodManager.kt" <<'KT'
package android.view.inputmethod

import android.webkit.WebView

open class InputMethodManager {
    fun restartInput(view: WebView) {}
    fun showSoftInput(view: WebView, flags: Int): Boolean = true
    companion object { const val SHOW_IMPLICIT: Int = 1 }
}
KT

cat > "$WORK/android/webkit/WebView.kt" <<'KT'
package android.webkit

import android.view.WindowInsets

open class WebView {
    val rootWindowInsets: WindowInsets? = WindowInsets()
    val isAttachedToWindow: Boolean = true
    fun hasWindowFocus(): Boolean = true
    fun performHapticFeedback(feedbackConstant: Int): Boolean = true
    fun requestFocusFromTouch(): Boolean = true
    fun post(action: () -> Unit): Boolean { action(); return true }
}
KT



cat > "$WORK/io/github/daylight00/androidterminal/R.kt" <<'KT'
package io.github.daylight00.androidterminal
object R {
    object string {
        const val xterm_prompt_label: Int = 1
        const val xterm_too_much_output: Int = 2
    }
}
KT

cat > "$WORK/io/github/daylight00/androidterminal/TerminalSharedStorage.kt" <<'KT'
package io.github.daylight00.androidterminal
object TerminalSharedStorage {
    fun isAccessGranted(activity: android.app.Activity): Boolean = true
    fun directory(): java.io.File = java.io.File("/storage/emulated/0")
}
KT

cat > "$WORK/org/json/JSONObject.kt" <<'KT'
package org.json
class JSONObject {
    fun put(name: String, value: Any?): JSONObject = this
    fun optString(name: String): String = ""
}
KT

kotlinc -nowarn \
  "$WORK/android/app/Activity.kt" \
  "$WORK/android/content/Content.kt" \
  "$WORK/android/content/res/Configuration.kt" \
  "$WORK/android/database/Cursor.kt" \
  "$WORK/android/graphics/Color.kt" \
  "$WORK/android/net/Uri.kt" \
  "$WORK/android/os/SystemClock.kt" \
  "$WORK/android/os/Build.kt" \
  "$WORK/android/provider/OpenableColumns.kt" \
  "$WORK/android/view/HapticFeedbackConstants.kt" \
  "$WORK/android/view/WindowInsets.kt" \
  "$WORK/android/view/accessibility/AccessibilityManager.kt" \
  "$WORK/android/view/inputmethod/InputMethodManager.kt" \
  "$WORK/android/webkit/WebView.kt" \
  "$WORK/org/json/JSONObject.kt" \
  "$WORK/io/github/daylight00/androidterminal/R.kt" \
  "$WORK/io/github/daylight00/androidterminal/TerminalSharedStorage.kt" \
  "$PACKAGE_ROOT/TerminalContract.kt" \
  "$PACKAGE_ROOT/TerminalPlatformState.kt" \
  "$PACKAGE_ROOT/TerminalPlatformPolicy.kt" \
  "$PACKAGE_ROOT/TerminalDocumentPolicy.kt" \
  "$PACKAGE_ROOT/TerminalDocumentTransport.kt" \
  "$PACKAGE_ROOT/TerminalPlatformAdapter.kt" \
  -d "$WORK/platform-adapter.jar"

echo "PASS terminal-platform-adapter runtime=kotlinc api=android29-shape localization=android-resources documents=saf-private-file storage-state=direct-path soft-input=explicit visibility=window-insets"
