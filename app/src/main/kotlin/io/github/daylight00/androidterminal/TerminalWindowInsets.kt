package io.github.daylight00.androidterminal

import android.os.Build
import android.view.WindowInsets

/** Shared Android authority for interpreting IME visibility from delivered window insets. */
internal object TerminalWindowInsets {
    fun isSoftInputVisible(insets: WindowInsets): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            insets.isVisible(WindowInsets.Type.ime())
        } else {
            @Suppress("DEPRECATION")
            insets.systemWindowInsetBottom > insets.stableInsetBottom
        }
}
