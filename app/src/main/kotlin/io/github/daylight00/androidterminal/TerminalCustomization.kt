package io.github.daylight00.androidterminal

/**
 * Layer 3 native extension point.
 *
 * Layer 2 must not import this object. Future product-specific Android behavior may
 * be added here only through stable Layer 2 capabilities.
 */
internal object TerminalCustomization {
    const val CONTRACT_VERSION = 1
}
