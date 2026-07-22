package io.github.daylight00.androidterminal

import android.content.res.Configuration
import android.graphics.Color

/** Layer 3 native product policy. Platform integration must not hard-code these values. */
internal object TerminalCustomization {
    private val darkBackgroundColor: Int = Color.BLACK
    private val lightBackgroundColor: Int = Color.rgb(250, 250, 250)

    const val followSystemTheme = true
    const val webTextZoom = 100
    const val hapticBellEnabled = false

    val allowedExternalUriSchemes: Set<String> = setOf("http", "https")

    fun backgroundColor(configuration: Configuration): Int {
        if (!followSystemTheme) return darkBackgroundColor
        return if (
            configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        ) {
            darkBackgroundColor
        } else {
            lightBackgroundColor
        }
    }

    fun usesLightSystemBars(configuration: Configuration): Boolean =
        followSystemTheme &&
            configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK != Configuration.UI_MODE_NIGHT_YES
}
