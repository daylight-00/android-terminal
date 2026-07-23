package io.github.daylight00.androidterminal

internal data class TerminalPlatformState(
    val colorScheme: String,
    val accessibilityEnabled: Boolean,
    val touchExplorationEnabled: Boolean,
    val localeTag: String,
    val promptLabel: String,
    val tooMuchOutput: String,
    val hardwareKeyboardPresent: Boolean,
    val fontScale: Double,
    val sharedStorageAccessGranted: Boolean,
    val sharedStoragePath: String,
)
