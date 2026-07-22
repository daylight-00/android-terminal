package io.github.daylight00.androidterminal

import android.app.Activity
import android.content.res.Configuration
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.ViewGroup
import android.webkit.WebMessage
import android.webkit.WebMessagePort
import android.webkit.WebSettings
import android.webkit.WebView
import org.json.JSONArray
import org.json.JSONObject
import java.util.TreeMap

/** Layer 2 WebView transport. The PTY/session itself is owned by TerminalSessionService. */
internal class TerminalController(
    private val activity: Activity,
    private val sessionHost: TerminalSessionService.LocalBinder,
    private val onRendererGone: (TerminalController, didCrash: Boolean) -> Unit,
) : AutoCloseable {
    val view: WebView = WebView(activity)

    private val mainHandler = Handler(Looper.getMainLooper())
    private val platformAdapter = TerminalPlatformAdapter(activity, view) { state ->
        mainHandler.post { sendPlatformState(state) }
    }
    private val queueLock = Object()
    private val outputQueue = TreeMap<Long, ByteArray>()

    @Volatile
    private var connectionGeneration = 0L

    @Volatile
    private var sessionId = ""

    @Volatile
    private var attachmentReadyForDrain = false

    private var messagePort: WebMessagePort? = null
    private var pageChannelCreated = false
    private var pageReady = false
    private var closed = false
    private var rendererRecoveryDispatched = false
    private var queuedBytes = 0
    private var inFlightSequence = 0L
    private var inFlightSize = 0
    private var pendingState: TerminalSessionState? = null
    private var pendingExitCode: Int? = null
    private var pendingFailure: String? = null

    private val serviceClient = object : TerminalSessionService.Client {
        override fun onOutput(
            connectionGeneration: Long,
            sessionId: String,
            record: TerminalOutputRecord,
        ) {
            if (closed) return
            val activeGeneration = this@TerminalController.connectionGeneration
            val activeSessionId = this@TerminalController.sessionId
            if (activeGeneration != 0L &&
                (connectionGeneration != activeGeneration || sessionId != activeSessionId)
            ) {
                return
            }
            enqueueOutput(record, waitForCapacity = true)
        }

        override fun onState(
            connectionGeneration: Long,
            sessionId: String,
            state: TerminalSessionState,
            exitCode: Int?,
            failure: String?,
        ) {
            mainHandler.post {
                if (!isCurrentAttachment(connectionGeneration, sessionId)) return@post
                queueState(state, exitCode, failure)
            }
        }
    }

    init {
        configureWebView()
        view.loadUrl(TerminalContract.DOCUMENT_URL)
    }

    override fun close() {
        shutdown(rendererProcessGone = false)
    }

    private fun handleRendererGone(didCrash: Boolean) {
        if (closed || rendererRecoveryDispatched) return
        rendererRecoveryDispatched = true
        shutdown(rendererProcessGone = true)
        onRendererGone(this, didCrash)
    }

    private fun shutdown(rendererProcessGone: Boolean) {
        if (closed) return
        closed = true
        val generation = connectionGeneration
        val currentSessionId = sessionId
        if (generation != 0L && currentSessionId.isNotBlank()) {
            sessionHost.detach(serviceClient, generation, currentSessionId)
        }
        attachmentReadyForDrain = false
        synchronized(queueLock) {
            outputQueue.clear()
            queuedBytes = 0
            inFlightSequence = 0L
            inFlightSize = 0
            pendingState = null
            pendingExitCode = null
            pendingFailure = null
            queueLock.notifyAll()
        }
        platformAdapter.close()
        runCatching { messagePort?.close() }
        messagePort = null
        if (!rendererProcessGone) runCatching { view.stopLoading() }
        (view.parent as? ViewGroup)?.removeView(view)
        view.destroy()
    }

    fun requestGeometrySync() {
        mainHandler.post {
            if (closed || !isCurrentAttachment(connectionGeneration, sessionId)) return@post
            sendJson(
                JSONObject()
                    .put("type", TerminalContract.MessageType.GEOMETRY)
                    .put("connectionGeneration", connectionGeneration)
                    .put("sessionId", sessionId),
            )
        }
    }

    fun requestPlatformStateSync() {
        mainHandler.post {
            if (closed) return@post
            platformAdapter.publishState()
        }
    }

    fun updateAppearance(configuration: Configuration) {
        view.setBackgroundColor(TerminalCustomization.backgroundColor(configuration))
    }

    private fun configureWebView() {
        view.setBackgroundColor(TerminalCustomization.backgroundColor(activity.resources.configuration))
        view.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        view.isLongClickable = true
        view.settings.apply {
            javaScriptEnabled = true
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
            allowFileAccess = false
            allowContentAccess = false
            blockNetworkLoads = true
            domStorageEnabled = false
            databaseEnabled = false
            cacheMode = WebSettings.LOAD_NO_CACHE
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            mediaPlaybackRequiresUserGesture = true
            builtInZoomControls = false
            displayZoomControls = false
            textZoom = TerminalCustomization.webTextZoom
            safeBrowsingEnabled = true
        }
        WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG)
        view.webViewClient = LocalAssetWebViewClient(
            assets = activity.assets,
            onPageReady = { createMessageChannel() },
            onRendererGone = ::handleRendererGone,
        )
    }

    private fun createMessageChannel() {
        if (pageChannelCreated || closed) return
        pageChannelCreated = true
        val ports = view.createWebMessageChannel()
        val nativePort = ports[0]
        nativePort.setWebMessageCallback(object : WebMessagePort.WebMessageCallback() {
            override fun onMessage(port: WebMessagePort, message: WebMessage) {
                handlePageMessage(message.data ?: return)
            }
        })
        messagePort = nativePort
        view.postWebMessage(
            WebMessage(TerminalContract.CHANNEL_MARKER, arrayOf(ports[1])),
            Uri.parse(TerminalContract.ORIGIN),
        )
    }

    private fun handlePageMessage(raw: String) {
        if (closed) return
        if (raw.length > MAX_PAGE_MESSAGE_CHARACTERS) {
            sendError("terminal page message too large")
            return
        }
        val message = try {
            JSONObject(raw)
        } catch (_: Throwable) {
            sendError("invalid message from terminal page")
            return
        }
        if (message.optInt("contractVersion", -1) != TerminalContract.PROTOCOL_VERSION) {
            sendError("terminal protocol version mismatch")
            return
        }
        when (message.optString("type")) {
            TerminalContract.MessageType.READY -> handleReady(message)
            TerminalContract.MessageType.INPUT -> ifCurrentMessage(message, ::handleInput)
            TerminalContract.MessageType.RESIZE -> ifCurrentMessage(message, ::handleResize)
            TerminalContract.MessageType.ACK -> ifCurrentMessage(message, ::handleAck)
            TerminalContract.MessageType.PLATFORM_REQUEST -> ifCurrentMessage(message, ::handlePlatformRequest)
            else -> sendError("unsupported terminal page message")
        }
    }

    private fun handleReady(message: JSONObject) {
        if (pageReady || closed) return
        val capabilities = buildSet {
            val values = message.optJSONArray("capabilities")
            if (values != null) {
                for (index in 0 until values.length()) {
                    val capability = values.optString(index)
                    if (capability.isNotBlank()) add(capability)
                }
            }
        }
        if (!capabilities.containsAll(TerminalContract.REQUIRED_PAGE_CAPABILITIES)) {
            sendError("terminal page capabilities are incomplete")
            return
        }

        val dimensions = dimensionsFrom(message)
        if (dimensions == null) {
            sendError("terminal page geometry is unavailable")
            return
        }

        pageReady = true
        attachmentReadyForDrain = false
        val attachment = sessionHost.attach(
            serviceClient,
            dimensions.rows,
            dimensions.columns,
            dimensions.pixelWidth,
            dimensions.pixelHeight,
        )
        connectionGeneration = attachment.connectionGeneration
        sessionId = attachment.sessionId

        sendJson(
            JSONObject()
                .put("type", TerminalContract.MessageType.ATTACHED)
                .put("connectionGeneration", attachment.connectionGeneration)
                .put("sessionId", attachment.sessionId)
                .put("state", attachment.state.wireName)
                .put("exitCode", attachment.exitCode ?: JSONObject.NULL)
                .put("failure", attachment.failure ?: JSONObject.NULL)
                .put("replayAvailable", attachment.replayAvailable)
                .put("replayTruncated", attachment.replayTruncated)
                .put("nextSequence", attachment.nextSequence)
                .put("nativeCapabilities", JSONArray(TerminalContract.NATIVE_CAPABILITIES)),
        )
        sendPlatformState(platformAdapter.currentState())

        attachment.replayRecords.forEach { record ->
            enqueueOutput(record, waitForCapacity = false)
        }
        pendingState = attachment.state
        pendingExitCode = attachment.exitCode
        pendingFailure = attachment.failure
        attachmentReadyForDrain = true
        drainOutput()
    }

    private fun ifCurrentMessage(message: JSONObject, action: (JSONObject) -> Unit) {
        val generation = message.optLong("connectionGeneration", -1L)
        val messageSessionId = message.optString("sessionId")
        if (!isCurrentAttachment(generation, messageSessionId)) return
        action(message)
    }

    private fun handleInput(message: JSONObject) {
        val encoded = message.optString("data")
        if (encoded.length > MAX_INPUT_BASE64) {
            sendError("terminal input message too large")
            return
        }
        val bytes = try {
            Base64.decode(encoded, Base64.NO_WRAP)
        } catch (_: IllegalArgumentException) {
            sendError("invalid terminal input encoding")
            return
        }
        sessionHost.write(connectionGeneration, sessionId, bytes)
    }

    private fun handleResize(message: JSONObject) {
        val dimensions = dimensionsFrom(message) ?: return
        sessionHost.resize(
            connectionGeneration,
            sessionId,
            dimensions.rows,
            dimensions.columns,
            dimensions.pixelWidth,
            dimensions.pixelHeight,
        )
    }

    private fun handlePlatformRequest(message: JSONObject) {
        val requestId = message.optString("requestId")
        if (!PLATFORM_REQUEST_ID.matches(requestId)) {
            sendError("invalid platform request identifier")
            return
        }
        val operation = message.optString("operation")
        val payload = message.optJSONObject("payload") ?: JSONObject()
        val result = platformAdapter.handle(operation, payload)
        sendPlatformResult(requestId, result)
    }

    private fun handleAck(message: JSONObject) {
        val sequence = message.optLong("seq", -1L)
        synchronized(queueLock) {
            if (sequence != inFlightSequence || inFlightSequence == 0L) return
            queuedBytes -= inFlightSize
            inFlightSequence = 0L
            inFlightSize = 0
            queueLock.notifyAll()
        }
        drainOutput()
    }

    private fun enqueueOutput(record: TerminalOutputRecord, waitForCapacity: Boolean) {
        synchronized(queueLock) {
            if (outputQueue.containsKey(record.sequence)) return
            if (waitForCapacity) {
                while (!closed && queuedBytes + record.bytes.size > MAX_QUEUED_BYTES) {
                    queueLock.wait()
                }
            } else if (queuedBytes + record.bytes.size > MAX_QUEUED_BYTES) {
                sendError("terminal replay exceeded the bounded frontend queue")
                return
            }
            if (closed) return
            outputQueue[record.sequence] = record.bytes.copyOf()
            queuedBytes += record.bytes.size
        }
        mainHandler.post { drainOutput() }
    }

    private fun drainOutput() {
        if (closed || !pageReady || !attachmentReadyForDrain || messagePort == null) return
        var bytes: ByteArray? = null
        var sequence = 0L
        var stateToSend: TerminalSessionState? = null
        var exitToSend: Int? = null
        var failureToSend: String? = null
        synchronized(queueLock) {
            if (inFlightSequence != 0L) return
            if (outputQueue.isNotEmpty()) {
                val entry = outputQueue.pollFirstEntry()
                sequence = entry.key
                bytes = entry.value
                inFlightSequence = sequence
                inFlightSize = entry.value.size
            } else if (pendingState != null) {
                stateToSend = pendingState
                exitToSend = pendingExitCode
                failureToSend = pendingFailure
                pendingState = null
                pendingExitCode = null
                pendingFailure = null
            } else {
                return
            }
        }
        val outputBytes = bytes
        if (outputBytes != null) {
            sendJson(
                JSONObject()
                    .put("type", TerminalContract.MessageType.OUTPUT)
                    .put("connectionGeneration", connectionGeneration)
                    .put("sessionId", sessionId)
                    .put("seq", sequence)
                    .put("data", Base64.encodeToString(outputBytes, Base64.NO_WRAP)),
            )
        } else if (stateToSend != null) {
            sendState(stateToSend!!, exitToSend, failureToSend)
        }
    }

    private fun queueState(state: TerminalSessionState, exitCode: Int?, failure: String?) {
        synchronized(queueLock) {
            pendingState = state
            pendingExitCode = exitCode
            pendingFailure = failure
        }
        drainOutput()
    }

    private fun sendState(state: TerminalSessionState, exitCode: Int?, failure: String?) {
        sendJson(
            JSONObject()
                .put("type", TerminalContract.MessageType.STATE)
                .put("connectionGeneration", connectionGeneration)
                .put("sessionId", sessionId)
                .put("state", state.wireName)
                .put("exitCode", exitCode ?: JSONObject.NULL)
                .put("failure", failure ?: JSONObject.NULL),
        )
    }

    private fun sendPlatformState(state: TerminalPlatformState) {
        if (!isCurrentAttachment(connectionGeneration, sessionId)) return
        sendJson(
            JSONObject()
                .put("type", TerminalContract.MessageType.PLATFORM_STATE)
                .put("connectionGeneration", connectionGeneration)
                .put("sessionId", sessionId)
                .put("colorScheme", state.colorScheme)
                .put("accessibilityEnabled", state.accessibilityEnabled)
                .put("touchExplorationEnabled", state.touchExplorationEnabled)
                .put("hardwareKeyboardPresent", state.hardwareKeyboardPresent)
                .put("fontScale", state.fontScale),
        )
    }

    private fun sendPlatformResult(requestId: String, result: TerminalPlatformResult) {
        sendJson(
            JSONObject()
                .put("type", TerminalContract.MessageType.PLATFORM_RESULT)
                .put("connectionGeneration", connectionGeneration)
                .put("sessionId", sessionId)
                .put("requestId", requestId)
                .put("ok", result.ok)
                .put("data", result.data)
                .put("error", result.error ?: JSONObject.NULL),
        )
    }

    private fun sendError(message: String) {
        val payload = JSONObject()
            .put("type", TerminalContract.MessageType.ERROR)
            .put("message", message)
        if (connectionGeneration != 0L && sessionId.isNotBlank()) {
            payload
                .put("connectionGeneration", connectionGeneration)
                .put("sessionId", sessionId)
        }
        sendJson(payload)
    }

    private fun sendJson(message: JSONObject) {
        if (closed) return
        message.put("contractVersion", TerminalContract.PROTOCOL_VERSION)
        try {
            messagePort?.postMessage(WebMessage(message.toString()))
        } catch (_: IllegalStateException) {
            // Closing or replacing the Activity invalidates this frontend connection only.
        }
    }

    private fun isCurrentAttachment(generation: Long, expectedSessionId: String): Boolean =
        generation != 0L &&
            generation == connectionGeneration &&
            expectedSessionId == sessionId &&
            sessionId.isNotBlank()

    private fun dimensionsFrom(message: JSONObject): TerminalDimensions? {
        val candidate = TerminalDimensions(
            rows = message.optInt("rows", 0),
            columns = message.optInt("columns", 0),
            pixelWidth = message.optInt("pixelWidth", 0),
            pixelHeight = message.optInt("pixelHeight", 0),
        )
        return if (candidate.isUsable()) candidate.sanitized() else null
    }

    private companion object {
        const val MAX_PAGE_MESSAGE_CHARACTERS = 512 * 1024
        const val MAX_INPUT_BASE64 = 256 * 1024
        const val MAX_QUEUED_BYTES = 2 * 1024 * 1024
        val PLATFORM_REQUEST_ID = Regex("[A-Za-z0-9._-]{1,64}")
    }
}
