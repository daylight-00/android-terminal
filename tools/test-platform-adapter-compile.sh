#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PACKAGE_ROOT="$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal"

if ! command -v kotlinc >/dev/null 2>&1; then
  python3 - "$PACKAGE_ROOT/TerminalPlatformAdapter.kt" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
for token in (
    "ClipboardManager",
    "ClipData.newPlainText",
    "Intent.ACTION_VIEW",
    "performHapticFeedback",
    "AccessibilityStateChangeListener",
    "TouchExplorationStateChangeListener",
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
  "$WORK/android/graphics" \
  "$WORK/android/net" \
  "$WORK/android/os" \
  "$WORK/android/view" \
  "$WORK/android/view/accessibility" \
  "$WORK/android/webkit" \
  "$WORK/org/json"

cat > "$WORK/android/app/Activity.kt" <<'KT'
package android.app

import android.content.Intent
import android.content.res.Resources

open class Activity {
    val resources: Resources = Resources()
    fun <T> getSystemService(serviceClass: Class<T>): T? = null
    fun startActivity(intent: Intent) {}
}
KT

cat > "$WORK/android/content/Content.kt" <<'KT'
package android.content

import android.net.Uri

open class ActivityNotFoundException : RuntimeException()

class Intent(val action: String, val data: Uri? = null) {
    companion object { const val ACTION_VIEW: String = "android.intent.action.VIEW" }
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

class Configuration {
    var uiMode: Int = 0
    var keyboard: Int = KEYBOARD_NOKEYS
    var fontScale: Float = 1f
    companion object {
        const val UI_MODE_NIGHT_MASK: Int = 0x30
        const val UI_MODE_NIGHT_YES: Int = 0x20
        const val KEYBOARD_UNDEFINED: Int = 0
        const val KEYBOARD_NOKEYS: Int = 1
    }
}

class Resources(val configuration: Configuration = Configuration())
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
    companion object { fun parse(value: String): Uri = Uri(value) }
}
KT

cat > "$WORK/android/os/SystemClock.kt" <<'KT'
package android.os
object SystemClock { fun elapsedRealtime(): Long = 0L }
KT

cat > "$WORK/android/view/HapticFeedbackConstants.kt" <<'KT'
package android.view
object HapticFeedbackConstants { const val CLOCK_TICK: Int = 4 }
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

cat > "$WORK/android/webkit/WebView.kt" <<'KT'
package android.webkit
open class WebView {
    fun hasWindowFocus(): Boolean = true
    fun performHapticFeedback(feedbackConstant: Int): Boolean = true
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
  "$WORK/android/graphics/Color.kt" \
  "$WORK/android/net/Uri.kt" \
  "$WORK/android/os/SystemClock.kt" \
  "$WORK/android/view/HapticFeedbackConstants.kt" \
  "$WORK/android/view/accessibility/AccessibilityManager.kt" \
  "$WORK/android/webkit/WebView.kt" \
  "$WORK/org/json/JSONObject.kt" \
  "$PACKAGE_ROOT/TerminalContract.kt" \
  "$PACKAGE_ROOT/TerminalCustomization.kt" \
  "$PACKAGE_ROOT/TerminalPlatformState.kt" \
  "$PACKAGE_ROOT/TerminalPlatformPolicy.kt" \
  "$PACKAGE_ROOT/TerminalPlatformAdapter.kt" \
  -d "$WORK/platform-adapter.jar"

echo "PASS terminal-platform-adapter runtime=kotlinc api=android29-shape"
