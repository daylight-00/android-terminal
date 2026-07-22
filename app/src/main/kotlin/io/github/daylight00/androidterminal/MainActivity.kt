package io.github.daylight00.androidterminal

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.res.Configuration
import android.os.Bundle
import android.os.IBinder
import android.view.View
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
            applyAppearance(resources.configuration)
            root.requestApplyInsets()
            root.post {
                terminal.requestGeometrySync()
                terminal.requestPlatformStateSync()
            }
        }

        override fun onServiceDisconnected(name: ComponentName) {
            controller?.close()
            controller = null
            root.removeAllViews()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)

        root = FrameLayout(this).apply {
            setOnApplyWindowInsetsListener { _, insets ->
                controller?.requestGeometrySync()
                insets
            }
            addOnLayoutChangeListener { _, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
                if (
                    right - left != oldRight - oldLeft ||
                    bottom - top != oldBottom - oldTop
                ) {
                    controller?.requestGeometrySync()
                }
            }
        }
        setContentView(root)
        applyAppearance(resources.configuration)
        root.requestApplyInsets()

        val serviceIntent = Intent(this, TerminalSessionService::class.java)
        startService(serviceIntent)
        serviceBound = bindService(serviceIntent, serviceConnection, Context.BIND_AUTO_CREATE)
    }

    override fun onResume() {
        super.onResume()
        root.post {
            controller?.requestGeometrySync()
            controller?.requestPlatformStateSync()
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            root.post {
                controller?.requestGeometrySync()
                controller?.requestPlatformStateSync()
            }
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        applyAppearance(newConfig)
        root.requestApplyInsets()
        root.post {
            controller?.requestGeometrySync()
            controller?.requestPlatformStateSync()
        }
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

    private fun applyAppearance(configuration: Configuration) {
        val background = TerminalCustomization.backgroundColor(configuration)
        window.statusBarColor = background
        window.navigationBarColor = background
        root.setBackgroundColor(background)
        controller?.updateAppearance(configuration)

        @Suppress("DEPRECATION")
        var flags = window.decorView.systemUiVisibility
        @Suppress("DEPRECATION")
        val lightMask = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or
            View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        @Suppress("DEPRECATION")
        flags = if (TerminalCustomization.usesLightSystemBars(configuration)) {
            flags or lightMask
        } else {
            flags and lightMask.inv()
        }
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = flags
    }
}
