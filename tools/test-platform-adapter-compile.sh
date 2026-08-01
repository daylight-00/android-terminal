#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PACKAGE_ROOT="$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal"

if ! command -v kotlinc >/dev/null 2>&1; then
  python3 - "$PACKAGE_ROOT/TerminalPlatformAdapter.kt" "$PACKAGE_ROOT/TerminalWindowInsets.kt" "$PACKAGE_ROOT/TerminalDocumentTransport.kt" <<'PY'
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
    "PopupWindow(",
    "PopupWindow.INPUT_METHOD_NOT_NEEDED",
    "SOFT_INPUT_ADJUST_NOTHING",
    "getLocationOnScreen",
    "getWindowVisibleDisplayFrame",
    "showAtLocation",
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
  "$WORK/android/graphics/drawable" \
  "$WORK/android/net" \
  "$WORK/android/os" \
  "$WORK/android/provider" \
  "$WORK/android/util" \
  "$WORK/android/view" \
  "$WORK/android/view/accessibility" \
  "$WORK/android/view/inputmethod" \
  "$WORK/android/webkit" \
  "$WORK/android/widget" \
  "$WORK/org/json" \
  "$WORK/io/github/daylight00/androidterminal"

cat > "$WORK/android/util/TypedValue.kt" <<'KT'
package android.util
class TypedValue {
    var resourceId: Int = 0
    var data: Int = 0xff202124.toInt()
}
KT

cat > "$WORK/android/content/res/Configuration.kt" <<'KT'
package android.content.res

import android.util.TypedValue

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

class DisplayMetrics { var density: Float = 2f }

class Theme {
    fun resolveAttribute(attribute: Int, value: TypedValue, resolveRefs: Boolean): Boolean {
        value.resourceId = 0
        value.data = 0xff202124.toInt()
        return true
    }
}

class Resources(
    val configuration: Configuration = Configuration(),
    val displayMetrics: DisplayMetrics = DisplayMetrics(),
)
KT

cat > "$WORK/android/app/Activity.kt" <<'KT'
package android.app

import android.content.ContentResolver
import android.content.Intent
import android.content.res.Resources
import android.content.res.Theme
import java.io.File

open class Activity {
    val resources: Resources = Resources()
    val theme: Theme = Theme()
    val contentResolver: ContentResolver = ContentResolver()
    val filesDir: File = File(System.getProperty("java.io.tmpdir"), "android-files")
    fun <T> getSystemService(serviceClass: Class<T>): T? = null
    fun startActivity(intent: Intent) {}
    fun startActivityForResult(intent: Intent, requestCode: Int) {}
    fun runOnUiThread(action: () -> Unit) = action()
    fun getString(id: Int): String = "localized-$id"
    fun getText(id: Int): CharSequence = "localized-$id"
    fun getColor(id: Int): Int = 0xff202124.toInt()
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

cat > "$WORK/android/graphics/Graphics.kt" <<'KT'
package android.graphics
object Color {
    const val BLACK: Int = 0xff000000.toInt()
    const val WHITE: Int = 0xffffffff.toInt()
    const val DKGRAY: Int = 0xff444444.toInt()
    const val TRANSPARENT: Int = 0x00000000
    fun rgb(red: Int, green: Int, blue: Int): Int = 0
}
class Rect(
    var left: Int = 0,
    var top: Int = 0,
    var right: Int = 1080,
    var bottom: Int = 1920,
) {
    fun set(left: Int, top: Int, right: Int, bottom: Int) {
        this.left = left; this.top = top; this.right = right; this.bottom = bottom
    }
}
KT

cat > "$WORK/android/graphics/drawable/Drawable.kt" <<'KT'
package android.graphics.drawable
open class Drawable
class ColorDrawable(val color: Int) : Drawable()
class GradientDrawable : Drawable() {
    var cornerRadius: Float = 0f
    fun setColor(color: Int) {}
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

cat > "$WORK/android/R.kt" <<'KT'
package android
object R {
    object string {
        const val copy: Int = 1
        const val paste: Int = 2
        const val selectAll: Int = 3
    }
    object attr {
        const val colorBackgroundFloating: Int = 11
        const val textColorPrimary: Int = 12
        const val selectableItemBackgroundBorderless: Int = 13
    }
}
KT

cat > "$WORK/android/view/View.kt" <<'KT'
package android.view

import android.graphics.Rect
import android.graphics.drawable.Drawable

open class View {
    open var width: Int = 1080
    open var height: Int = 1920
    open var measuredWidth: Int = 300
    open var measuredHeight: Int = 52
    open var background: Drawable? = null
    open var elevation: Float = 0f
    open var minHeight: Int = 0
    open var isClickable: Boolean = false
    open var isFocusable: Boolean = false
    open fun measure(widthSpec: Int, heightSpec: Int) {}
    open fun setPadding(left: Int, top: Int, right: Int, bottom: Int) {}
    open fun setBackgroundResource(resourceId: Int) {}
    open fun setOnClickListener(listener: (View) -> Unit) {}
    open fun getLocationOnScreen(location: IntArray) { location[0] = 0; location[1] = 0 }
    open fun getWindowVisibleDisplayFrame(rect: Rect) {
        rect.left = 0; rect.top = 0; rect.right = 1080; rect.bottom = 1920
    }
    object MeasureSpec {
        const val UNSPECIFIED: Int = 0
        fun makeMeasureSpec(size: Int, mode: Int): Int = 0
    }
}

open class ViewGroup : View() {
    class LayoutParams {
        companion object { const val WRAP_CONTENT: Int = -2 }
    }
}

object Gravity {
    const val NO_GRAVITY: Int = 0
    const val CENTER: Int = 17
    const val CENTER_VERTICAL: Int = 16
}

object HapticFeedbackConstants { const val CLOCK_TICK: Int = 4 }

object WindowManager {
    object LayoutParams { const val SOFT_INPUT_ADJUST_NOTHING: Int = 0x30 }
}
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

cat > "$WORK/android/widget/Widgets.kt" <<'KT'
package android.widget

import android.app.Activity
import android.graphics.drawable.Drawable
import android.view.View
import android.view.ViewGroup

open class LinearLayout(activity: Activity) : ViewGroup() {
    var orientation: Int = HORIZONTAL
    var gravity: Int = 0
    fun addView(view: View) {}
    companion object { const val HORIZONTAL: Int = 0 }
}

open class TextView(activity: Activity) : View() {
    var text: CharSequence = ""
    var gravity: Int = 0
    fun setTextColor(color: Int) {}
}

class PopupWindow(
    val contentView: View,
    width: Int,
    height: Int,
    focusable: Boolean,
) {
    var isTouchable: Boolean = false
    var isOutsideTouchable: Boolean = false
    var isClippingEnabled: Boolean = false
    var inputMethodMode: Int = 0
    var softInputMode: Int = 0
    var elevation: Float = 0f
    var isShowing: Boolean = false
    private var dismissListener: (() -> Unit)? = null
    fun setBackgroundDrawable(drawable: Drawable?) {}
    fun setOnDismissListener(listener: () -> Unit) { dismissListener = listener }
    fun dismiss() { val was = isShowing; isShowing = false; if (was) dismissListener?.invoke() }
    fun update(x: Int, y: Int, width: Int, height: Int) { isShowing = true }
    fun showAtLocation(parent: View, gravity: Int, x: Int, y: Int) { isShowing = true }
    companion object { const val INPUT_METHOD_NOT_NEEDED: Int = 2 }
}
KT

cat > "$WORK/android/view/accessibility/AccessibilityManager.kt" <<'KT'
package android.view.accessibility
open class AccessibilityManager {
    fun interface AccessibilityStateChangeListener { fun onAccessibilityStateChanged(enabled: Boolean) }
    fun interface TouchExplorationStateChangeListener { fun onTouchExplorationStateChanged(enabled: Boolean) }
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
import android.view.View
import android.view.WindowInsets
open class WebView : View() {
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
    fun optDouble(name: String, fallback: Double): Double = fallback
}
KT

kotlinc -nowarn \
  "$WORK/android/util/TypedValue.kt" \
  "$WORK/android/content/res/Configuration.kt" \
  "$WORK/android/app/Activity.kt" \
  "$WORK/android/content/Content.kt" \
  "$WORK/android/database/Cursor.kt" \
  "$WORK/android/R.kt" \
  "$WORK/android/graphics/Graphics.kt" \
  "$WORK/android/graphics/drawable/Drawable.kt" \
  "$WORK/android/net/Uri.kt" \
  "$WORK/android/os/SystemClock.kt" \
  "$WORK/android/os/Build.kt" \
  "$WORK/android/provider/OpenableColumns.kt" \
  "$WORK/android/view/View.kt" \
  "$WORK/android/view/WindowInsets.kt" \
  "$WORK/android/widget/Widgets.kt" \
  "$WORK/android/view/accessibility/AccessibilityManager.kt" \
  "$WORK/android/view/inputmethod/InputMethodManager.kt" \
  "$WORK/android/webkit/WebView.kt" \
  "$WORK/org/json/JSONObject.kt" \
  "$WORK/io/github/daylight00/androidterminal/R.kt" \
  "$WORK/io/github/daylight00/androidterminal/TerminalSharedStorage.kt" \
  "$PACKAGE_ROOT/TerminalContract.kt" \
  "$PACKAGE_ROOT/TerminalPlatformState.kt" \
  "$PACKAGE_ROOT/TerminalWindowInsets.kt" \
  "$PACKAGE_ROOT/TerminalPlatformPolicy.kt" \
  "$PACKAGE_ROOT/TerminalDocumentPolicy.kt" \
  "$PACKAGE_ROOT/TerminalDocumentTransport.kt" \
  "$PACKAGE_ROOT/TerminalPlatformAdapter.kt" \
  -d "$WORK/platform-adapter.jar"

echo "PASS terminal-platform-adapter runtime=kotlinc api=android29-shape localization=android-resources documents=saf-private-file storage-state=direct-path soft-input=explicit visibility=window-insets selection-toolbar=popupwindow"
