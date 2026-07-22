package io.github.daylight00.androidterminal

import android.content.res.AssetManager
import android.net.Uri
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import java.io.ByteArrayInputStream
import java.io.FileNotFoundException

internal class LocalAssetWebViewClient(
    private val assets: AssetManager,
    private val onPageReady: () -> Unit,
) : WebViewClient() {
    override fun shouldInterceptRequest(
        view: WebView,
        request: WebResourceRequest,
    ): WebResourceResponse = responseFor(request.url)

    @Suppress("DEPRECATION")
    override fun shouldInterceptRequest(view: WebView, url: String): WebResourceResponse =
        responseFor(Uri.parse(url))

    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
        !isAllowedDocument(request.url)

    @Suppress("DEPRECATION")
    override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean =
        !isAllowedDocument(Uri.parse(url))

    override fun onPageFinished(view: WebView, url: String) {
        if (isAllowedDocument(Uri.parse(url))) onPageReady()
    }

    private fun responseFor(uri: Uri): WebResourceResponse {
        if (!isAllowedOrigin(uri)) return notFound()
        val asset = PATHS[uri.path] ?: return notFound()
        return try {
            WebResourceResponse(
                asset.mimeType,
                "UTF-8",
                200,
                "OK",
                SECURITY_HEADERS,
                assets.open(asset.path, AssetManager.ACCESS_STREAMING),
            )
        } catch (_: FileNotFoundException) {
            notFound()
        }
    }

    private fun isAllowedDocument(uri: Uri): Boolean =
        isAllowedOrigin(uri) && uri.path == DOCUMENT_PATH

    private fun isAllowedOrigin(uri: Uri): Boolean =
        uri.scheme == "https" && uri.host == HOST && (uri.port == -1 || uri.port == 443)

    private fun notFound(): WebResourceResponse = WebResourceResponse(
        "text/plain",
        "UTF-8",
        404,
        "Not Found",
        SECURITY_HEADERS,
        ByteArrayInputStream("not found".toByteArray()),
    )

    private data class Asset(val path: String, val mimeType: String)

    companion object {
        const val ORIGIN = "https://app.local"
        const val DOCUMENT_PATH = "/terminal/index.html"
        const val DOCUMENT_URL = "$ORIGIN$DOCUMENT_PATH"
        const val HOST = "app.local"

        private val SECURITY_HEADERS = mapOf(
            "Cache-Control" to "no-store",
            "Content-Security-Policy" to (
                "default-src 'none'; " +
                    "script-src 'self'; style-src 'self' 'unsafe-inline'; " +
                    "font-src 'self'; img-src 'self' data:; connect-src 'none'; " +
                    "object-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'"
                ),
            "Cross-Origin-Resource-Policy" to "same-origin",
            "X-Content-Type-Options" to "nosniff",
        )

        private val PATHS = mapOf(
            DOCUMENT_PATH to Asset("terminal/index.html", "text/html"),
            "/terminal/terminal.css" to Asset("terminal/terminal.css", "text/css"),
            "/terminal/terminal-codec.js" to Asset(
                "terminal/terminal-codec.js",
                "application/javascript",
            ),
            "/terminal/terminal.js" to Asset("terminal/terminal.js", "application/javascript"),
            "/terminal/vendor/xterm.css" to Asset("terminal/vendor/xterm.css", "text/css"),
            "/terminal/vendor/xterm.js" to Asset("terminal/vendor/xterm.js", "application/javascript"),
            "/terminal/vendor/addon-fit.js" to Asset(
                "terminal/vendor/addon-fit.js",
                "application/javascript",
            ),
        )
    }
}
