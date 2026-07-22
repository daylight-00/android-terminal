#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PACKAGE_ROOT="$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal"

python3 - "$PACKAGE_ROOT/LocalAssetWebViewClient.kt" "$PACKAGE_ROOT/MainActivity.kt" "$PACKAGE_ROOT/TerminalController.kt" <<'PYCODE'
from pathlib import Path
import sys
web_client, activity, controller = (Path(path).read_text(encoding='utf-8') for path in sys.argv[1:])
for token in ('override fun onRenderProcessGone', 'RenderProcessGoneDetail', 'onRendererGone(detail.didCrash())'):
    assert token in web_client, token
for token in ('recoverRenderer(', 'installFrontend(binder)', 'TerminalFrontendRecoveryState'):
    assert token in activity, token
for token in ('shutdown(rendererProcessGone = true)', 'sessionHost.detach', 'onRendererGone(this, didCrash)'):
    assert token in controller, token
PYCODE

if ! command -v kotlinc >/dev/null 2>&1; then
  echo "PASS renderer-recovery-api static-python kotlinc=unavailable"
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p \
  "$WORK/android/app" \
  "$WORK/android/content" \
  "$WORK/android/content/res" \
  "$WORK/android/net" \
  "$WORK/android/os" \
  "$WORK/android/util" \
  "$WORK/android/view" \
  "$WORK/android/webkit" \
  "$WORK/android/widget" \
  "$WORK/io/github/daylight00/androidterminal"

cat > "$WORK/android/app/Activity.kt" <<'KT'
package android.app

import android.content.Intent
import android.content.ServiceConnection
import android.content.res.Resources
import android.os.Bundle
import android.view.View
import android.view.Window

open class Activity : android.content.Context() {
    val window: Window = Window()
    val resources: Resources = Resources()
    val assets: android.content.res.AssetManager = android.content.res.AssetManager()
    val isFinishing: Boolean = false
    val isDestroyed: Boolean = false
    open fun onCreate(savedInstanceState: Bundle?) {}
    open fun onResume() {}
    open fun onWindowFocusChanged(hasFocus: Boolean) {}
    open fun onConfigurationChanged(newConfig: android.content.res.Configuration) {}
    open fun onDestroy() {}
    fun setContentView(view: View) {}
    fun startService(intent: Intent): android.content.ComponentName? = null
    fun bindService(intent: Intent, connection: ServiceConnection, flags: Int): Boolean = true
    fun unbindService(connection: ServiceConnection) {}
}
KT

cat > "$WORK/android/content/Content.kt" <<'KT'
package android.content

open class Context {
    companion object { const val BIND_AUTO_CREATE: Int = 1 }
}
class Intent(val context: Context, val cls: Class<*>)
class ComponentName
interface ServiceConnection {
    fun onServiceConnected(name: ComponentName, service: android.os.IBinder)
    fun onServiceDisconnected(name: ComponentName)
}
KT

cat > "$WORK/android/content/res/Resources.kt" <<'KT'
package android.content.res
class AssetManager {
    fun open(path: String, mode: Int): java.io.InputStream = java.io.ByteArrayInputStream(byteArrayOf())
    companion object { const val ACCESS_STREAMING: Int = 2 }
}
class Configuration
class Resources(val configuration: Configuration = Configuration())
KT

cat > "$WORK/android/net/Uri.kt" <<'KT'
package android.net
class Uri(val scheme: String? = null, val host: String? = null, val port: Int = -1, val path: String? = null) {
    companion object { fun parse(value: String): Uri = Uri() }
}
KT

cat > "$WORK/android/os/Os.kt" <<'KT'
package android.os
open class Bundle
interface IBinder
KT

cat > "$WORK/android/util/Log.kt" <<'KT'
package android.util
object Log { fun e(tag: String, message: String): Int = 0 }
KT

cat > "$WORK/android/view/View.kt" <<'KT'
package android.view
open class WindowInsets
fun interface OnApplyWindowInsetsListener { fun onApplyWindowInsets(v: View, insets: WindowInsets): WindowInsets }
fun interface OnLayoutChangeListener {
    fun onLayoutChange(v: View, left: Int, top: Int, right: Int, bottom: Int, oldLeft: Int, oldTop: Int, oldRight: Int, oldBottom: Int)
}
open class View {
    var parent: Any? = null
    var systemUiVisibility: Int = 0
    fun setOnApplyWindowInsetsListener(listener: OnApplyWindowInsetsListener?) {}
    fun addOnLayoutChangeListener(listener: OnLayoutChangeListener) {}
    fun requestApplyInsets() {}
    fun post(action: Runnable): Boolean { action.run(); return true }
    companion object {
        const val SYSTEM_UI_FLAG_LIGHT_STATUS_BAR: Int = 0x2000
        const val SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR: Int = 0x10
    }
}
open class ViewGroup : View() {
    open class LayoutParams(val width: Int, val height: Int) {
        companion object { const val MATCH_PARENT: Int = -1 }
    }
    fun removeAllViews() {}
    fun addView(view: View, params: LayoutParams) {}
}
class Window {
    var statusBarColor: Int = 0
    var navigationBarColor: Int = 0
    val decorView: View = View()
    fun setSoftInputMode(mode: Int) {}
}
class WindowManager { class LayoutParams { companion object { const val SOFT_INPUT_ADJUST_RESIZE: Int = 1 } } }
KT

cat > "$WORK/android/widget/FrameLayout.kt" <<'KT'
package android.widget
class FrameLayout(context: android.content.Context) : android.view.ViewGroup() {
    class LayoutParams(width: Int, height: Int) : android.view.ViewGroup.LayoutParams(width, height)
    fun setBackgroundColor(color: Int) {}
}
KT

cat > "$WORK/android/webkit/Webkit.kt" <<'KT'
package android.webkit
class RenderProcessGoneDetail { fun didCrash(): Boolean = false }
interface WebResourceRequest { val url: android.net.Uri }
class WebResourceResponse {
    constructor(mimeType: String, encoding: String, statusCode: Int, reasonPhrase: String, responseHeaders: Map<String, String>, data: java.io.InputStream)
}
open class WebView : android.view.View()
open class WebViewClient {
    open fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? = null
    open fun shouldInterceptRequest(view: WebView, url: String): WebResourceResponse? = null
    open fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = false
    open fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean = false
    open fun onPageFinished(view: WebView, url: String) {}
    open fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean = false
}
KT

cat > "$WORK/io/github/daylight00/androidterminal/Stubs.kt" <<'KT'
package io.github.daylight00.androidterminal

object TerminalContract {
    const val DOCUMENT_PATH: String = "/terminal/index.html"
    const val HOST: String = "app.local"
}
object TerminalCustomization {
    fun backgroundColor(configuration: android.content.res.Configuration): Int = 0
    fun usesLightSystemBars(configuration: android.content.res.Configuration): Boolean = false
}
class TerminalSessionService {
    inner class LocalBinder : android.os.IBinder
}
class TerminalController(
    activity: android.app.Activity,
    sessionHost: TerminalSessionService.LocalBinder,
    onRendererGone: (TerminalController, Boolean) -> Unit,
) {
    val view: android.view.View = android.view.View()
    fun close() {}
    fun requestGeometrySync() {}
    fun requestPlatformStateSync() {}
    fun updateAppearance(configuration: android.content.res.Configuration) {}
}
KT

kotlinc -nowarn \
  "$WORK/android/app/Activity.kt" \
  "$WORK/android/content/Content.kt" \
  "$WORK/android/content/res/Resources.kt" \
  "$WORK/android/net/Uri.kt" \
  "$WORK/android/os/Os.kt" \
  "$WORK/android/util/Log.kt" \
  "$WORK/android/view/View.kt" \
  "$WORK/android/webkit/Webkit.kt" \
  "$WORK/android/widget/FrameLayout.kt" \
  "$WORK/io/github/daylight00/androidterminal/Stubs.kt" \
  "$PACKAGE_ROOT/TerminalFrontendRecoveryState.kt" \
  "$PACKAGE_ROOT/LocalAssetWebViewClient.kt" \
  "$PACKAGE_ROOT/MainActivity.kt" \
  -d "$WORK/renderer-recovery.jar"

echo "PASS renderer-recovery-api runtime=kotlinc api=android29-shape"
