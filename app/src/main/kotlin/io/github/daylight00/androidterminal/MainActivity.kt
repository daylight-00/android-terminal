package io.github.daylight00.androidterminal

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.res.Configuration
import android.os.Bundle
import android.os.IBinder
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout

class MainActivity : Activity() {
    private lateinit var root: FrameLayout
    private var controller: TerminalController? = null
    private var sessionHost: TerminalSessionService.LocalBinder? = null
    private var serviceBound = false
    private var sharedStorageRequestStarted = false
    private val frontendRecovery = TerminalFrontendRecoveryState()

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, service: IBinder) {
            val binder = service as? TerminalSessionService.LocalBinder ?: return
            if (isFinishing || isDestroyed) return
            sessionHost = binder
            installFrontend(binder)
        }

        override fun onServiceDisconnected(name: ComponentName) {
            frontendRecovery.invalidate()
            sessionHost = null
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
        sharedStorageRequestStarted = TerminalSharedStorage.requestAccess(this)
    }

    override fun onResume() {
        super.onResume()
        if (sharedStorageRequestStarted && TerminalSharedStorage.isAccessGranted(this)) {
            sharedStorageRequestStarted = false
        }
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

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == TerminalSharedStorage.RUNTIME_PERMISSION_REQUEST_CODE) {
            sharedStorageRequestStarted = false
            controller?.requestPlatformStateSync()
        }
    }

    @Deprecated("Uses platform APIs only; Activity Result API would require AndroidX")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        controller?.handleActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        frontendRecovery.invalidate()
        sessionHost = null
        controller?.close()
        controller = null
        if (serviceBound) {
            unbindService(serviceConnection)
            serviceBound = false
        }
        super.onDestroy()
    }

    private fun installFrontend(binder: TerminalSessionService.LocalBinder) {
        if (isFinishing || isDestroyed) return
        controller?.close()
        val frontendGeneration = frontendRecovery.registerFrontend()
        val terminal = TerminalController(
            activity = this,
            sessionHost = binder,
            onRendererGone = { failed, didCrash ->
                recoverRenderer(failed, frontendGeneration, didCrash)
            },
        )
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

    private fun recoverRenderer(
        failed: TerminalController,
        frontendGeneration: Long,
        didCrash: Boolean,
    ) {
        if (controller !== failed) return
        if (!frontendRecovery.beginRecovery(frontendGeneration)) return
        Log.e(TAG, "WebView renderer exited; didCrash=$didCrash; replacing frontend")
        controller = null
        root.removeAllViews()
        root.post {
            if (!frontendRecovery.completeRecovery(frontendGeneration)) return@post
            val binder = sessionHost ?: return@post
            if (isFinishing || isDestroyed) return@post
            installFrontend(binder)
        }
    }

    private fun applyAppearance(configuration: Configuration) {
        val background = TerminalHostAppearance.backgroundColor(configuration)
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
        flags = if (TerminalHostAppearance.usesLightSystemBars(configuration)) {
            flags or lightMask
        } else {
            flags and lightMask.inv()
        }
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = flags
    }

    private companion object {
        const val TAG = "AndroidTerminal"
    }
}
