#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE="$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSharedStorage.kt"

if ! command -v kotlinc >/dev/null 2>&1 || ! command -v kotlin >/dev/null 2>&1; then
  python3 - "$SOURCE" "$ROOT/app/src/main/AndroidManifest.xml" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding='utf-8')
manifest = Path(sys.argv[2]).read_text(encoding='utf-8')
for token in (
    'Environment.isExternalStorageManager()',
    'Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION',
    'Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION',
    'Manifest.permission.READ_EXTERNAL_STORAGE',
    'Manifest.permission.WRITE_EXTERNAL_STORAGE',
    'Os.symlink',
):
    if token not in source:
        raise SystemExit(f'missing shared-storage token: {token}')
for token in (
    'android.permission.MANAGE_EXTERNAL_STORAGE',
    'android.permission.READ_EXTERNAL_STORAGE',
    'android.permission.WRITE_EXTERNAL_STORAGE',
    'android:requestLegacyExternalStorage="true"',
):
    if token not in manifest:
        raise SystemExit(f'missing manifest storage token: {token}')
print('PASS shared-storage-access static-python kotlinc=unavailable')
PY
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p \
  "$WORK/android" \
  "$WORK/android/app" \
  "$WORK/android/content" \
  "$WORK/android/content/pm" \
  "$WORK/android/net" \
  "$WORK/android/os" \
  "$WORK/android/provider" \
  "$WORK/android/system" \
  "$WORK/io/github/daylight00/androidterminal"

cat > "$WORK/android/Manifest.kt" <<'KT'
package android
object Manifest {
    object permission {
        const val READ_EXTERNAL_STORAGE: String = "android.permission.READ_EXTERNAL_STORAGE"
        const val WRITE_EXTERNAL_STORAGE: String = "android.permission.WRITE_EXTERNAL_STORAGE"
    }
}
KT

cat > "$WORK/android/content/pm/PackageManager.kt" <<'KT'
package android.content.pm
object PackageManager { const val PERMISSION_GRANTED: Int = 0 }
KT

cat > "$WORK/android/content/Content.kt" <<'KT'
package android.content
open class ActivityNotFoundException : RuntimeException()
class Intent(val action: String, val data: android.net.Uri? = null)
KT

cat > "$WORK/android/net/Uri.kt" <<'KT'
package android.net
class Uri private constructor(val value: String) {
    companion object { fun parse(value: String): Uri = Uri(value) }
}
KT

cat > "$WORK/android/app/Activity.kt" <<'KT'
package android.app

import android.content.Intent
import android.content.pm.PackageManager

open class Activity {
    var packageName: String = "io.github.daylight00.androidterminal"
    val permissions = mutableMapOf<String, Int>()
    val started = mutableListOf<Intent>()
    var requestedPermissions: Array<String>? = null
    var requestedCode: Int = -1
    open fun checkSelfPermission(permission: String): Int =
        permissions[permission] ?: -1
    open fun requestPermissions(permissions: Array<String>, requestCode: Int) {
        requestedPermissions = permissions
        requestedCode = requestCode
    }
    open fun startActivity(intent: Intent) { started += intent }
    fun grant(permission: String) { permissions[permission] = PackageManager.PERMISSION_GRANTED }
}
KT

cat > "$WORK/android/os/Build.kt" <<'KT'
package android.os
object Build {
    object VERSION { var SDK_INT: Int = 29 }
    object VERSION_CODES { const val R: Int = 30 }
}
object Environment {
    var manager: Boolean = false
    var root: java.io.File = java.io.File("/storage/emulated/0")
    fun isExternalStorageManager(): Boolean = manager
    fun getExternalStorageDirectory(): java.io.File = root
}
KT

cat > "$WORK/android/provider/Settings.kt" <<'KT'
package android.provider
object Settings {
    const val ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION: String = "app-all-files"
    const val ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION: String = "all-files"
}
KT

cat > "$WORK/android/system/System.kt" <<'KT'
package android.system
class ErrnoException(val functionName: String, val errno: Int) : Exception()
object OsConstants { const val ENOENT: Int = 2 }
object Os {
    val entries = mutableSetOf<String>()
    val links = mutableMapOf<String, String>()
    fun lstat(path: String): Any {
        if (path !in entries) throw ErrnoException("lstat", OsConstants.ENOENT)
        return Any()
    }
    fun symlink(target: String, link: String) {
        entries += link
        links[link] = target
    }
}
KT

cat > "$WORK/io/github/daylight00/androidterminal/Test.kt" <<'KT'
package io.github.daylight00.androidterminal

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.system.Os
import java.io.File

private class FallbackActivity : Activity() {
    var calls = 0
    override fun startActivity(intent: android.content.Intent) {
        calls += 1
        if (calls == 1) throw ActivityNotFoundException()
        super.startActivity(intent)
    }
}

private class DeniedActivity : Activity() {
    override fun startActivity(intent: android.content.Intent) {
        throw SecurityException("settings blocked")
    }
}

fun main() {
    Build.VERSION.SDK_INT = 29
    val api29 = Activity()
    check(!TerminalSharedStorage.isAccessGranted(api29))
    check(TerminalSharedStorage.requestAccess(api29))
    check(api29.requestedCode == TerminalSharedStorage.RUNTIME_PERMISSION_REQUEST_CODE)
    check(api29.requestedPermissions?.toSet() == setOf(
        Manifest.permission.READ_EXTERNAL_STORAGE,
        Manifest.permission.WRITE_EXTERNAL_STORAGE,
    ))
    api29.grant(Manifest.permission.READ_EXTERNAL_STORAGE)
    api29.grant(Manifest.permission.WRITE_EXTERNAL_STORAGE)
    check(TerminalSharedStorage.isAccessGranted(api29))
    check(!TerminalSharedStorage.requestAccess(api29))

    Build.VERSION.SDK_INT = 30
    Environment.manager = false
    val api30 = Activity()
    check(TerminalSharedStorage.requestAccess(api30))
    check(api30.started.single().action == Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
    check(api30.started.single().data?.value == "package:${api30.packageName}")
    Environment.manager = true
    check(TerminalSharedStorage.isAccessGranted(api30))
    check(!TerminalSharedStorage.requestAccess(api30))

    Environment.manager = false
    val fallback = FallbackActivity()
    check(TerminalSharedStorage.requestAccess(fallback))
    check(fallback.started.single().action == Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)

    val denied = DeniedActivity()
    check(!TerminalSharedStorage.requestAccess(denied))

    Environment.root = File("/storage/emulated/0")
    val home = File("/data/user/0/app/files")
    val link = TerminalSharedStorage.prepareHomeLink(home)
    check(link?.path == File(home, "storage").path)
    check(Os.links[link?.absolutePath] == Environment.root.absolutePath)
    check(TerminalSharedStorage.prepareHomeLink(home)?.path == link?.path)
    check(Os.links.size == 1)

    val ownerHome = File("/data/user/0/app/owner-files")
    val ownerEntry = File(ownerHome, "storage")
    Os.entries += ownerEntry.absolutePath
    check(TerminalSharedStorage.prepareHomeLink(ownerHome)?.path == ownerEntry.path)
    check(ownerEntry.absolutePath !in Os.links)
    check(Os.links.size == 1)

    println("PASS shared-storage-access runtime=kotlinc api29=runtime-permissions api30=all-files settings-failure=bounded home-link=non-destructive")
}
KT

kotlinc -nowarn \
  "$WORK/android/Manifest.kt" \
  "$WORK/android/app/Activity.kt" \
  "$WORK/android/content/Content.kt" \
  "$WORK/android/content/pm/PackageManager.kt" \
  "$WORK/android/net/Uri.kt" \
  "$WORK/android/os/Build.kt" \
  "$WORK/android/provider/Settings.kt" \
  "$WORK/android/system/System.kt" \
  "$SOURCE" \
  "$WORK/io/github/daylight00/androidterminal/Test.kt" \
  -include-runtime -d "$WORK/test.jar"

kotlin -classpath "$WORK/test.jar" io.github.daylight00.androidterminal.TestKt
