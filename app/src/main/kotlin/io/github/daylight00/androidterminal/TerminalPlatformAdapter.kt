package io.github.daylight00.androidterminal

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.SystemClock
import android.view.HapticFeedbackConstants
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
) : AutoCloseable {
    private val clipboardManager = activity.getSystemService(ClipboardManager::class.java)
    private val accessibilityManager = activity.getSystemService(AccessibilityManager::class.java)
    private val inputMethodManager = activity.getSystemService(InputMethodManager::class.java)
    private val documentTransport = TerminalDocumentTransport(activity)

    private val accessibilityStateListener =
        AccessibilityManager.AccessibilityStateChangeListener { publishState() }
    private val touchExplorationStateListener =
        AccessibilityManager.TouchExplorationStateChangeListener { publishState() }

    private var closed = false
    private var lastBellMillis = Long.MIN_VALUE
    private var nextDocumentToken = 1L
    private var pendingDocumentRequest: PendingDocumentRequest? = null

    init {
        accessibilityManager?.addAccessibilityStateChangeListener(accessibilityStateListener)
        accessibilityManager?.addTouchExplorationStateChangeListener(touchExplorationStateListener)
    }

    override fun close() {
        if (closed) return
        closed = true
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
            fontScale = configuration.fontScale.toDouble().coerceIn(0.5, 3.0),
            sharedStorageAccessGranted = TerminalSharedStorage.isAccessGranted(activity),
            sharedStoragePath = TerminalSharedStorage.directory().absolutePath,
        )
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
