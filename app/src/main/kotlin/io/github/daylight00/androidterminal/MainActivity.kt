package io.github.daylight00.androidterminal

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.view.WindowManager

class MainActivity : Activity() {
    private var controller: TerminalController? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.BLACK
        window.navigationBarColor = Color.BLACK
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)

        val terminal = TerminalController(this)
        controller = terminal
        setContentView(terminal.view)
    }

    override fun onDestroy() {
        controller?.close()
        controller = null
        super.onDestroy()
    }
}
