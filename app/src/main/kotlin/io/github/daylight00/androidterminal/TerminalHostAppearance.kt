package io.github.daylight00.androidterminal

import android.content.res.Configuration
import android.graphics.Color

/** Layer 2 mapping from Android configuration to the WebView host surface. */
internal object TerminalHostAppearance {
    private val darkBackgroundColor: Int = Color.BLACK
    private val lightBackgroundColor: Int = Color.rgb(250, 250, 250)

    const val WEB_TEXT_ZOOM = 100

    fun backgroundColor(configuration: Configuration): Int =
        if (configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES) {
            darkBackgroundColor
        } else {
            lightBackgroundColor
        }

    fun usesLightSystemBars(configuration: Configuration): Boolean =
        configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK != Configuration.UI_MODE_NIGHT_YES
}
