package io.github.daylight00.androidterminal

internal object TerminalContract {
    const val PROTOCOL_VERSION = 1
    const val ORIGIN = "https://app.local"
    const val HOST = "app.local"
    const val DOCUMENT_PATH = "/terminal/index.html"
    const val DOCUMENT_URL = "$ORIGIN$DOCUMENT_PATH"
    const val CHANNEL_MARKER = "native-shell"

    object MessageType {
        const val READY = "ready"
        const val INPUT = "input"
        const val RESIZE = "resize"
        const val ACK = "ack"
        const val OUTPUT = "output"
        const val EXIT = "exit"
        const val ERROR = "error"
    }

    val REQUIRED_PAGE_CAPABILITIES = setOf(
        "xterm-core",
        "binary-input",
        "fit",
        "output-ack",
    )
}
