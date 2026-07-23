package io.github.daylight00.androidterminal

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import java.io.File

/** Layer 2 adaptation for direct POSIX access to Android shared storage. */
internal object TerminalSharedStorage {
    const val RUNTIME_PERMISSION_REQUEST_CODE = 0x5403

    fun isAccessGranted(activity: Activity): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            activity.checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED &&
                activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }

    fun requestAccess(activity: Activity): Boolean {
        if (isAccessGranted(activity)) return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            openAllFilesSettings(activity)
        } else {
            activity.requestPermissions(
                arrayOf(
                    Manifest.permission.READ_EXTERNAL_STORAGE,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE,
                ),
                RUNTIME_PERMISSION_REQUEST_CODE,
            )
            true
        }
    }

    @Suppress("DEPRECATION")
    fun directory(): File = Environment.getExternalStorageDirectory()

    /**
     * Provides the conventional HOME/storage path without replacing any owner-created entry.
     * Access through the link remains governed entirely by Android's storage permission model.
     */
    fun prepareHomeLink(homeDirectory: File): File? {
        val target = directory()
        val link = File(homeDirectory, "storage")
        try {
            Os.lstat(link.absolutePath)
            return link
        } catch (error: ErrnoException) {
            if (error.errno != OsConstants.ENOENT) return null
        }
        return try {
            Os.symlink(target.absolutePath, link.absolutePath)
            link
        } catch (_: ErrnoException) {
            null
        }
    }

    private fun openAllFilesSettings(activity: Activity): Boolean {
        val packageUri = Uri.parse("package:${activity.packageName}")
        val appIntent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, packageUri)
        return try {
            activity.startActivity(appIntent)
            true
        } catch (_: ActivityNotFoundException) {
            try {
                activity.startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                true
            } catch (_: ActivityNotFoundException) {
                false
            } catch (_: SecurityException) {
                false
            }
        } catch (_: SecurityException) {
            false
        }
    }
}
