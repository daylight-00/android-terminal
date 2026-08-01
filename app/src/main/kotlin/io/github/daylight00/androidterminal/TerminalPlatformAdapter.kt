package io.github.daylight00.androidterminal

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.SystemClock
import android.graphics.Color
import android.graphics.Rect
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.PopupWindow
import android.widget.TextView
import android.view.inputmethod.InputMethodManager
import android.view.accessibility.AccessibilityManager
import android.webkit.WebView
import org.json.JSONObject

/**
 * Layer 2 adapter for bounded Android platform capabilities exposed to the terminal page.
 * Security bounds and Android mappings remain in Layer 2.
 */
internal class TerminalPlatformAdapter(
    private val activity: Activity,
    private val terminalView: WebView,
    private val onStateChanged: (TerminalPlatformState) -> Unit,
    private val onSelectionAction: (String) -> Unit,
) : AutoCloseable {
    private val clipboardManager = activity.getSystemService(ClipboardManager::class.java)
    private val accessibilityManager = activity.getSystemService(AccessibilityManager::class.java)
    private val inputMethodManager = activity.getSystemService(InputMethodManager::class.java)
    private val documentTransport = TerminalDocumentTransport(activity)
    private var selectionPopupWindow: PopupWindow? = null

    private val accessibilityStateListener =
        AccessibilityManager.AccessibilityStateChangeListener { publishState() }
    private val touchExplorationStateListener =
        AccessibilityManager.TouchExplorationStateChangeListener { publishState() }

    private var closed = false
    private var lastBellMillis = Long.MIN_VALUE
    private var nextDocumentToken = 1L
    private var pendingDocumentRequest: PendingDocumentRequest? = null
    private var observedSoftInputVisible: Boolean? = null

    init {
        accessibilityManager?.addAccessibilityStateChangeListener(accessibilityStateListener)
        accessibilityManager?.addTouchExplorationStateChangeListener(touchExplorationStateListener)
    }

    override fun close() {
        if (closed) return
        closed = true
        selectionPopupWindow?.dismiss()
        selectionPopupWindow = null
        pendingDocumentRequest = null
        accessibilityManager?.removeAccessibilityStateChangeListener(accessibilityStateListener)
        accessibilityManager?.removeTouchExplorationStateChangeListener(touchExplorationStateListener)
    }

    fun currentState(configuration: Configuration = activity.resources.configuration): TerminalPlatformState {
        val colorScheme = if (
            configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        ) {
            "dark"
        } else {
            "light"
        }
        return TerminalPlatformState(
            colorScheme = colorScheme,
            accessibilityEnabled = accessibilityManager?.isEnabled == true,
            touchExplorationEnabled = accessibilityManager?.isTouchExplorationEnabled == true,
            localeTag = configuration.locales[0].toLanguageTag(),
            promptLabel = activity.getString(R.string.xterm_prompt_label),
            tooMuchOutput = activity.getString(R.string.xterm_too_much_output),
            hardwareKeyboardPresent = configuration.keyboard != Configuration.KEYBOARD_NOKEYS &&
                configuration.keyboard != Configuration.KEYBOARD_UNDEFINED,
            softInputVisible = isSoftInputVisible(),
            fontScale = configuration.fontScale.toDouble().coerceIn(0.5, 3.0),
            sharedStorageAccessGranted = TerminalSharedStorage.isAccessGranted(activity),
            sharedStoragePath = TerminalSharedStorage.directory().absolutePath,
        )
    }

    private fun isSoftInputVisible(): Boolean {
        observedSoftInputVisible?.let { return it }
        val insets = terminalView.rootWindowInsets ?: return false
        return TerminalWindowInsets.isSoftInputVisible(insets)
    }

    fun updateSoftInputVisibility(visible: Boolean) {
        val changed = observedSoftInputVisible != visible
        observedSoftInputVisible = visible
        if (changed) publishState()
    }

    fun publishState() {
        if (!closed) onStateChanged(currentState())
    }

    fun handle(
        operation: String,
        payload: JSONObject,
        completion: (TerminalPlatformResult) -> Unit,
    ) {
        if (closed) return
        when (operation) {
            TerminalContract.PlatformOperation.CLIPBOARD_READ -> completion(readClipboard())
            TerminalContract.PlatformOperation.CLIPBOARD_WRITE -> {
                completion(writeClipboard(payload.optString("text")))
            }
            TerminalContract.PlatformOperation.OPEN_EXTERNAL_URI -> {
                completion(openExternalUri(payload.optString("uri")))
            }
            TerminalContract.PlatformOperation.BELL -> completion(performBell())
            TerminalContract.PlatformOperation.SOFT_INPUT_SHOW -> completion(requestSoftInput())
            TerminalContract.PlatformOperation.DOCUMENT_IMPORT -> {
                beginDocumentImport(payload, completion)
            }
            TerminalContract.PlatformOperation.DOCUMENT_EXPORT -> {
                beginDocumentExport(payload, completion)
            }
            TerminalContract.PlatformOperation.SELECTION_ACTIONS_SHOW -> {
                completion(showSelectionActions(payload))
            }
            TerminalContract.PlatformOperation.SELECTION_ACTIONS_HIDE -> {
                completion(hideSelectionActions())
            }
            else -> completion(TerminalPlatformResult.failure("unsupported platform operation"))
        }
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_IMPORT_DOCUMENT && requestCode != REQUEST_EXPORT_DOCUMENT) {
            return false
        }
        val pending = pendingDocumentRequest ?: return true
        if (pending.requestCode != requestCode) return true
        pendingDocumentRequest = null

        if (closed) return true
        if (resultCode != Activity.RESULT_OK) {
            pending.completion(TerminalPlatformResult.failure("document operation was cancelled"))
            return true
        }
        val uri = data?.data
        if (uri == null) {
            pending.completion(TerminalPlatformResult.failure("document provider returned no URI"))
            return true
        }

        Thread {
            val result = when (pending) {
                is PendingDocumentRequest.Import -> documentTransport.importDocument(
                    uri,
                    pending.destinationDirectory,
                )
                is PendingDocumentRequest.Export -> documentTransport.exportDocument(uri, pending.source)
            }
            activity.runOnUiThread {
                if (!closed && pending.token < nextDocumentToken) {
                    pending.completion(result)
                }
            }
        }.start()
        return true
    }

    private fun beginDocumentImport(
        payload: JSONObject,
        completion: (TerminalPlatformResult) -> Unit,
    ) {
        if (pendingDocumentRequest != null) {
            completion(TerminalPlatformResult.failure("another document operation is already active"))
            return
        }
        val destinationDirectory = TerminalDocumentPolicy.validatedRelativeHomeDirectory(
            payload.optString("destinationDirectory"),
        )
        if (destinationDirectory == null) {
            completion(
                TerminalPlatformResult.failure(
                    "import destination must be a HOME-relative directory",
                ),
            )
            return
        }
        val token = nextDocumentToken++
        pendingDocumentRequest = PendingDocumentRequest.Import(
            token = token,
            requestCode = REQUEST_IMPORT_DOCUMENT,
            completion = completion,
            destinationDirectory = destinationDirectory,
        )
        try {
            activity.startActivityForResult(
                documentTransport.importIntent(payload.optString("mimeType")),
                REQUEST_IMPORT_DOCUMENT,
            )
        } catch (_: ActivityNotFoundException) {
            pendingDocumentRequest = null
            completion(TerminalPlatformResult.failure("no Android document picker is available"))
        } catch (_: SecurityException) {
            pendingDocumentRequest = null
            completion(TerminalPlatformResult.failure("Android denied the document picker"))
        }
    }

    private fun beginDocumentExport(
        payload: JSONObject,
        completion: (TerminalPlatformResult) -> Unit,
    ) {
        if (pendingDocumentRequest != null) {
            completion(TerminalPlatformResult.failure("another document operation is already active"))
            return
        }
        val source = documentTransport.prepareExport(payload)
        if (source == null) {
            completion(
                TerminalPlatformResult.failure(
                    "export source must be a bounded readable file under the app-private HOME",
                ),
            )
            return
        }
        val token = nextDocumentToken++
        pendingDocumentRequest = PendingDocumentRequest.Export(
            token = token,
            requestCode = REQUEST_EXPORT_DOCUMENT,
            completion = completion,
            source = source,
        )
        try {
            activity.startActivityForResult(
                documentTransport.exportIntent(source),
                REQUEST_EXPORT_DOCUMENT,
            )
        } catch (_: ActivityNotFoundException) {
            pendingDocumentRequest = null
            completion(TerminalPlatformResult.failure("no Android document creator is available"))
        } catch (_: SecurityException) {
            pendingDocumentRequest = null
            completion(TerminalPlatformResult.failure("Android denied document creation"))
        }
    }

    private fun showSelectionActions(payload: JSONObject): TerminalPlatformResult {
        if (!terminalView.isAttachedToWindow || terminalView.width <= 0 || terminalView.height <= 0) {
            return TerminalPlatformResult.failure("terminal WebView is not attached or laid out")
        }
        val x = payload.optDouble("x", Double.NaN)
        val y = payload.optDouble("y", Double.NaN)
        val viewportWidth = payload.optDouble("viewportWidth", Double.NaN)
        val viewportHeight = payload.optDouble("viewportHeight", Double.NaN)
        if (!x.isFinite() || !y.isFinite() ||
            !viewportWidth.isFinite() || viewportWidth <= 0.0 ||
            !viewportHeight.isFinite() || viewportHeight <= 0.0
        ) {
            return TerminalPlatformResult.failure("selection action anchor is invalid")
        }

        val popup = selectionPopupWindow ?: createSelectionPopupWindow().also {
            selectionPopupWindow = it
        }
        val localX = (x * terminalView.width.toDouble() / viewportWidth).toInt()
            .coerceIn(0, terminalView.width - 1)
        val localY = (y * terminalView.height.toDouble() / viewportHeight).toInt()
            .coerceIn(0, terminalView.height - 1)
        val location = IntArray(2)
        terminalView.getLocationOnScreen(location)
        val anchorScreenX = location[0] + localX
        val anchorScreenY = location[1] + localY

        val content = popup.contentView
        content.measure(
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
        )
        val popupWidth = content.measuredWidth.coerceAtLeast(dp(1))
        val popupHeight = content.measuredHeight.coerceAtLeast(dp(1))
        val visibleFrame = Rect()
        terminalView.getWindowVisibleDisplayFrame(visibleFrame)
        val margin = dp(8)
        val gap = dp(10)
        val minimumX = visibleFrame.left + margin
        val maximumX = (visibleFrame.right - popupWidth - margin).coerceAtLeast(minimumX)
        val popupX = (anchorScreenX - popupWidth / 2).coerceIn(minimumX, maximumX)
        val minimumY = visibleFrame.top + margin
        val maximumY = (visibleFrame.bottom - popupHeight - margin).coerceAtLeast(minimumY)
        var popupY = anchorScreenY - popupHeight - gap
        if (popupY < minimumY) popupY = anchorScreenY + gap
        popupY = popupY.coerceIn(minimumY, maximumY)

        val reused = popup.isShowing
        if (reused) {
            popup.update(popupX, popupY, -1, -1)
        } else {
            popup.showAtLocation(terminalView, Gravity.NO_GRAVITY, popupX, popupY)
        }
        return TerminalPlatformResult.success(
            JSONObject()
                .put("shown", true)
                .put("reused", reused)
                .put("anchorX", anchorScreenX)
                .put("anchorY", anchorScreenY)
                .put("popupX", popupX)
                .put("popupY", popupY),
        )
    }

    private fun hideSelectionActions(): TerminalPlatformResult {
        val popup = selectionPopupWindow
        selectionPopupWindow = null
        popup?.dismiss()
        return TerminalPlatformResult.success(JSONObject().put("hidden", popup != null))
    }

    private fun createSelectionPopupWindow(): PopupWindow {
        val content = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(4), 0, dp(4), 0)
            background = GradientDrawable().apply {
                setColor(resolveThemeColor(android.R.attr.colorBackgroundFloating, Color.DKGRAY))
                cornerRadius = dp(12).toFloat()
            }
            elevation = dp(8).toFloat()
            addView(selectionActionView(android.R.string.copy, SELECTION_ACTION_COPY))
            addView(selectionActionView(android.R.string.paste, SELECTION_ACTION_PASTE))
            addView(selectionActionView(android.R.string.selectAll, SELECTION_ACTION_SELECT_ALL))
        }
        val popup = PopupWindow(
            content,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            false,
        ).apply {
            isTouchable = true
            isOutsideTouchable = true
            isClippingEnabled = true
            inputMethodMode = PopupWindow.INPUT_METHOD_NOT_NEEDED
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            elevation = dp(8).toFloat()
        }
        popup.setOnDismissListener {
            if (selectionPopupWindow === popup) selectionPopupWindow = null
        }
        return popup
    }

    private fun selectionActionView(label: Int, action: String): TextView = TextView(activity).apply {
        text = activity.getText(label)
        gravity = Gravity.CENTER
        minHeight = dp(48)
        setPadding(dp(16), 0, dp(16), 0)
        setTextColor(resolveThemeColor(android.R.attr.textColorPrimary, Color.WHITE))
        val selectableBackground = TypedValue()
        if (activity.theme.resolveAttribute(
                android.R.attr.selectableItemBackgroundBorderless,
                selectableBackground,
                true,
            ) && selectableBackground.resourceId != 0
        ) {
            setBackgroundResource(selectableBackground.resourceId)
        }
        isClickable = true
        isFocusable = false
        setOnClickListener {
            onSelectionAction(action)
            if (action != SELECTION_ACTION_SELECT_ALL) {
                selectionPopupWindow?.dismiss()
                selectionPopupWindow = null
            }
        }
    }

    private fun resolveThemeColor(attribute: Int, fallback: Int): Int {
        val value = TypedValue()
        if (!activity.theme.resolveAttribute(attribute, value, true)) return fallback
        return if (value.resourceId != 0) activity.getColor(value.resourceId) else value.data
    }

    private fun dp(value: Int): Int =
        (value * activity.resources.displayMetrics.density + 0.5f).toInt()

    private fun readClipboard(): TerminalPlatformResult {
        if (!terminalView.hasWindowFocus()) {
            return TerminalPlatformResult.failure("clipboard read requires application focus")
        }
        val clip = clipboardManager?.primaryClip
            ?: return TerminalPlatformResult.failure("clipboard has no readable text")
        if (clip.itemCount <= 0) return TerminalPlatformResult.failure("clipboard is empty")
        val value = clip.getItemAt(0).text
            ?: return TerminalPlatformResult.failure("clipboard has no direct text item")
        val text = TerminalPlatformPolicy.boundedClipboardText(value, allowEmpty = true)
            ?: return TerminalPlatformResult.failure("clipboard text exceeds the bounded limit")
        return TerminalPlatformResult.success(JSONObject().put("text", text))
    }

    private fun writeClipboard(value: String): TerminalPlatformResult {
        val text = TerminalPlatformPolicy.boundedClipboardText(value, allowEmpty = true)
            ?: return TerminalPlatformResult.failure("clipboard text exceeds the bounded limit")
        val manager = clipboardManager
            ?: return TerminalPlatformResult.failure("Android clipboard service is unavailable")
        manager.setPrimaryClip(ClipData.newPlainText("Terminal selection", text))
        return TerminalPlatformResult.success(JSONObject().put("characters", text.length))
    }

    private fun openExternalUri(value: String): TerminalPlatformResult {
        val validated = TerminalPlatformPolicy.validatedExternalUri(
            value,
            TerminalPlatformPolicy.ALLOWED_EXTERNAL_URI_SCHEMES,
        ) ?: return TerminalPlatformResult.failure("external URI is not allowed")
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(validated))
        return try {
            activity.startActivity(intent)
            TerminalPlatformResult.success(JSONObject())
        } catch (_: ActivityNotFoundException) {
            TerminalPlatformResult.failure("no Android activity can open this URI")
        } catch (_: SecurityException) {
            TerminalPlatformResult.failure("Android denied the external URI")
        }
    }

    private fun requestSoftInput(): TerminalPlatformResult {
        val manager = inputMethodManager
            ?: return TerminalPlatformResult.failure("Android input method service is unavailable")
        if (!terminalView.isAttachedToWindow) {
            return TerminalPlatformResult.failure("terminal WebView is not attached")
        }
        terminalView.post {
            if (closed || !terminalView.isAttachedToWindow) return@post
            terminalView.requestFocusFromTouch()
            manager.restartInput(terminalView)
            manager.showSoftInput(terminalView, InputMethodManager.SHOW_IMPLICIT)
        }
        return TerminalPlatformResult.success(JSONObject().put("requested", true))
    }

    private fun performBell(): TerminalPlatformResult {
        val now = SystemClock.elapsedRealtime()
        if (lastBellMillis != Long.MIN_VALUE &&
            now - lastBellMillis < TerminalPlatformPolicy.MIN_BELL_INTERVAL_MILLIS
        ) {
            return TerminalPlatformResult.success(
                JSONObject().put("performed", false).put("rateLimited", true),
            )
        }
        lastBellMillis = now
        val performed = terminalView.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
        return TerminalPlatformResult.success(JSONObject().put("performed", performed))
    }

    private sealed class PendingDocumentRequest(
        val token: Long,
        val requestCode: Int,
        val completion: (TerminalPlatformResult) -> Unit,
    ) {
        class Import(
            token: Long,
            requestCode: Int,
            completion: (TerminalPlatformResult) -> Unit,
            val destinationDirectory: String,
        ) : PendingDocumentRequest(token, requestCode, completion)

        class Export(
            token: Long,
            requestCode: Int,
            completion: (TerminalPlatformResult) -> Unit,
            val source: TerminalDocumentTransport.ExportSource,
        ) : PendingDocumentRequest(token, requestCode, completion)
    }

    private companion object {
        const val REQUEST_IMPORT_DOCUMENT = 0x5401
        const val REQUEST_EXPORT_DOCUMENT = 0x5402
        const val SELECTION_ACTION_COPY = "copy"
        const val SELECTION_ACTION_PASTE = "paste"
        const val SELECTION_ACTION_SELECT_ALL = "select-all"
    }
}

internal data class TerminalPlatformResult(
    val ok: Boolean,
    val data: JSONObject,
    val error: String?,
) {
    companion object {
        fun success(data: JSONObject): TerminalPlatformResult = TerminalPlatformResult(true, data, null)
        fun failure(message: String): TerminalPlatformResult =
            TerminalPlatformResult(false, JSONObject(), message)
    }
}
