package io.github.daylight00.androidterminal

import android.app.Activity
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.ViewGroup
import android.webkit.WebMessage
import android.webkit.WebMessagePort
import android.webkit.WebSettings
import android.webkit.WebView
import org.json.JSONObject
import java.util.ArrayDeque

internal class TerminalController(private val activity: Activity) : AutoCloseable {
    val view: WebView = WebView(activity)

    private val mainHandler = Handler(Looper.getMainLooper())
    private val queueLock = Object()
    private val outputQueue = ArrayDeque<ByteArray>()

    private var messagePort: WebMessagePort? = null
    private var session: TerminalSession? = null
    private var pageChannelCreated = false
    private var pageReady = false
    private var closed = false
    private var queuedBytes = 0
    private var inFlightSequence = 0L
    private var inFlightSize = 0
    private var nextSequence = 1L

    init {
        configureWebView()
        view.loadUrl(TerminalContract.DOCUMENT_URL)
    }

    override fun close() {
        if (closed) return
        closed = true
        synchronized(queueLock) {
            outputQueue.clear()
            queuedBytes = 0
            queueLock.notifyAll()
        }
        session?.close()
        session = null
        messagePort?.close()
        messagePort = null
        view.stopLoading()
        (view.parent as? ViewGroup)?.removeView(view)
        view.destroy()
    }

    private fun configureWebView() {
        view.setBackgroundColor(TerminalCustomization.backgroundColor)
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
        view.webViewClient = LocalAssetWebViewClient(activity.assets) {
            createMessageChannel()
        }
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
            TerminalContract.MessageType.INPUT -> handleInput(message)
            TerminalContract.MessageType.RESIZE -> handleResize(message)
            TerminalContract.MessageType.ACK -> handleAck(message)
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
        pageReady = true
        val dimensions = Dimensions.from(message)
        val newSession = TerminalSession(
            activity.filesDir,
            activity.cacheDir,
            object : TerminalSession.Listener {
                override fun onOutput(bytes: ByteArray) = enqueueOutput(bytes)

                override fun onExit(exitCode: Int) {
                    mainHandler.post {
                        sendJson(
                            JSONObject()
                                .put("type", TerminalContract.MessageType.EXIT)
                                .put("code", exitCode),
                        )
                    }
                }

                override fun onFailure(error: Throwable) {
                    mainHandler.post { sendError(error.message ?: error.javaClass.simpleName) }
                }
            },
        )
        session = newSession
        newSession.start(
            dimensions.rows,
            dimensions.columns,
            dimensions.pixelWidth,
            dimensions.pixelHeight,
        )
    }

    private fun handleInput(message: JSONObject) {
        if (!pageReady) return
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
        session?.write(bytes)
    }

    private fun handleResize(message: JSONObject) {
        val dimensions = Dimensions.from(message)
        session?.resize(
            dimensions.rows,
            dimensions.columns,
            dimensions.pixelWidth,
            dimensions.pixelHeight,
        )
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

    private fun enqueueOutput(bytes: ByteArray) {
        synchronized(queueLock) {
            while (!closed && queuedBytes + bytes.size > MAX_QUEUED_BYTES) {
                queueLock.wait()
            }
            if (closed) return
            outputQueue.addLast(bytes)
            queuedBytes += bytes.size
        }
        mainHandler.post { drainOutput() }
    }

    private fun drainOutput() {
        if (closed || !pageReady || messagePort == null) return
        val bytes: ByteArray
        val sequence: Long
        synchronized(queueLock) {
            if (inFlightSequence != 0L || outputQueue.isEmpty()) return
            bytes = outputQueue.removeFirst()
            sequence = nextSequence++
            inFlightSequence = sequence
            inFlightSize = bytes.size
        }
        sendJson(
            JSONObject()
                .put("type", TerminalContract.MessageType.OUTPUT)
                .put("seq", sequence)
                .put("data", Base64.encodeToString(bytes, Base64.NO_WRAP)),
        )
    }

    private fun sendError(message: String) {
        sendJson(
            JSONObject()
                .put("type", TerminalContract.MessageType.ERROR)
                .put("message", message),
        )
    }

    private fun sendJson(message: JSONObject) {
        if (closed) return
        message.put("contractVersion", TerminalContract.PROTOCOL_VERSION)
        try {
            messagePort?.postMessage(WebMessage(message.toString()))
        } catch (_: IllegalStateException) {
            // Closing the Activity invalidates the message port.
        }
    }

    private data class Dimensions(
        val rows: Int,
        val columns: Int,
        val pixelWidth: Int,
        val pixelHeight: Int,
    ) {
        companion object {
            fun from(message: JSONObject): Dimensions = Dimensions(
                message.optInt("rows", 24).coerceIn(1, 2_000),
                message.optInt("columns", 80).coerceIn(1, 2_000),
                message.optInt("pixelWidth", 0).coerceIn(0, 65_535),
                message.optInt("pixelHeight", 0).coerceIn(0, 65_535),
            )
        }
    }

    private companion object {
        const val MAX_QUEUED_BYTES = 1024 * 1024
        const val MAX_INPUT_BASE64 = 64 * 1024
    }
}
