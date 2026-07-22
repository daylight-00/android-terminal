package io.github.daylight00.androidterminal

/**
 * Layer 2 coordinator for replacing a failed WebView once per active frontend.
 * The PTY remains owned by TerminalSessionService and is never restarted here.
 */
internal class TerminalFrontendRecoveryState {
    private var activeGeneration = 0L
    private var pendingGeneration = 0L

    fun registerFrontend(): Long {
        activeGeneration += 1L
        pendingGeneration = 0L
        return activeGeneration
    }

    fun beginRecovery(frontendGeneration: Long): Boolean {
        if (frontendGeneration == 0L || frontendGeneration != activeGeneration) return false
        if (pendingGeneration != 0L) return false
        pendingGeneration = frontendGeneration
        return true
    }

    fun completeRecovery(frontendGeneration: Long): Boolean {
        if (frontendGeneration != activeGeneration) return false
        if (pendingGeneration != frontendGeneration) return false
        pendingGeneration = 0L
        return true
    }

    fun invalidate() {
        activeGeneration += 1L
        pendingGeneration = 0L
    }
}
