package io.github.daylight00.androidterminal

internal object TerminalContract {
    const val PROTOCOL_VERSION = 6
    const val ORIGIN = "https://app.local"
    const val HOST = "app.local"
    const val DOCUMENT_PATH = "/terminal/index.html"
    const val DOCUMENT_URL = "$ORIGIN$DOCUMENT_PATH"
    const val CHANNEL_MARKER = "native-shell"
    const val MAX_SERIALIZED_SNAPSHOT_BYTES = 8 * 1024 * 1024
    const val MAX_SERIALIZED_SNAPSHOT_BASE64_CHARACTERS =
        ((MAX_SERIALIZED_SNAPSHOT_BYTES + 2) / 3) * 4

    object MessageType {
        const val READY = "ready"
        const val INPUT = "input"
        const val RESIZE = "resize"
        const val ACK = "ack"
        const val PLATFORM_REQUEST = "platform-request"
        const val SESSION_TITLE = "session-title"
        const val SNAPSHOT = "snapshot"
        const val RESTORE_ACK = "restore-ack"
        const val ATTACHED = "attached"
        const val OUTPUT = "output"
        const val STATE = "state"
        const val GEOMETRY = "geometry"
        const val PLATFORM_STATE = "platform-state"
        const val PLATFORM_RESULT = "platform-result"
        const val ERROR = "error"
    }

    object PlatformOperation {
        const val CLIPBOARD_READ = "clipboard-read"
        const val CLIPBOARD_WRITE = "clipboard-write"
        const val OPEN_EXTERNAL_URI = "open-external-uri"
        const val BELL = "bell"
        const val DOCUMENT_IMPORT = "document-import"
        const val DOCUMENT_EXPORT = "document-export"
    }

    val REQUIRED_PAGE_CAPABILITIES = setOf(
        "xterm-core",
        "binary-input",
        "fit",
        "output-ack",
        "session-attach-v2",
        "geometry-dedup-v1",
        "platform-bridge-v2",
        "android-font-scale-v1",
        "web-links-v1",
        "document-transport-v1",
        "serialize-state-v1",
        "webgl-renderer-fallback-v1",
        "layer3-scaffold-v1",
        "session-title-state-v1",
        "localized-xterm-strings-v1",
        "safe-window-reports-v1",
        "stable-addon-wave-v1",
        "login-shell-v1",
        "native-account-session-v1",
        "layer2-completion-v1",
    )

    val NATIVE_CAPABILITIES = listOf(
        "android-service-session-host",
        "bounded-raw-replay",
        "byte-transport",
        "pty-resize",
        "frontend-reconnect",
        "webview-renderer-recovery",
        "android-window-geometry",
        "android-clipboard",
        "android-external-uri",
        "android-haptic-bell",
        "android-system-theme",
        "android-accessibility-state",
        "android-localized-xterm-strings",
        "android-hardware-keyboard-state",
        "android-font-scale-state",
        "android-document-transport",
        "android-shared-storage-direct-path",
        "android-native-account-session",
        "xterm-serialized-state",
    )
}
