package io.github.daylight00.androidterminal

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.IBinder
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout

class MainActivity : Activity() {
    private lateinit var root: FrameLayout
    private var controller: TerminalController? = null
    private var serviceBound = false

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, service: IBinder) {
            val binder = service as? TerminalSessionService.LocalBinder ?: return
            if (isFinishing || isDestroyed) return
            controller?.close()
            val terminal = TerminalController(this@MainActivity, binder)
            controller = terminal
            root.removeAllViews()
            root.addView(
                terminal.view,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
        }

        override fun onServiceDisconnected(name: ComponentName) {
            controller?.close()
            controller = null
            root.removeAllViews()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = TerminalCustomization.backgroundColor
        window.navigationBarColor = TerminalCustomization.backgroundColor
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)

        root = FrameLayout(this).apply {
            setBackgroundColor(TerminalCustomization.backgroundColor)
        }
        setContentView(root)

        val serviceIntent = Intent(this, TerminalSessionService::class.java)
        startService(serviceIntent)
        serviceBound = bindService(serviceIntent, serviceConnection, Context.BIND_AUTO_CREATE)
    }

    override fun onDestroy() {
        controller?.close()
        controller = null
        if (serviceBound) {
            unbindService(serviceConnection)
            serviceBound = false
        }
        super.onDestroy()
    }
}
