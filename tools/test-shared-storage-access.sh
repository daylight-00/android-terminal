#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE="$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSharedStorage.kt"
ACTIVITY="$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal/MainActivity.kt"
SESSION="$ROOT/app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSession.kt"
NATIVE="$ROOT/app/src/main/c/shell_bridge.c"
MANIFEST="$ROOT/app/src/main/AndroidManifest.xml"

python3 - "$SOURCE" "$ACTIVITY" "$SESSION" "$NATIVE" "$MANIFEST" <<'PY'
from pathlib import Path
import sys
source, activity, session, native, manifest = (Path(p).read_text(encoding='utf-8') for p in sys.argv[1:])
for token in (
    'Environment.isExternalStorageManager()',
    'Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION',
    'Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION',
    'Manifest.permission.READ_EXTERNAL_STORAGE',
    'Manifest.permission.WRITE_EXTERNAL_STORAGE',
    'Environment.getExternalStorageDirectory()',
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
if 'TerminalSharedStorage.requestAccess(this)' not in activity:
    raise SystemExit('Activity must immediately enter the Android system grant flow')
for forbidden in ('prepareHomeLink', 'Os.symlink', 'File(homeDirectory, "storage")'):
    if forbidden in source or forbidden in session:
        raise SystemExit(f'forbidden HOME storage mapping remains: {forbidden}')
for forbidden in ('EXTERNAL_STORAGE=', 'ANDROID_STORAGE=/storage', 'shared_storage_directory'):
    if forbidden in native:
        raise SystemExit(f'forbidden child environment/path synthesis remains: {forbidden}')
print('PASS shared-storage-access static-policy startup-request=yes home-link=no child-env-synthesis=no')
PY

if ! command -v kotlinc >/dev/null 2>&1 || ! command -v kotlin >/dev/null 2>&1; then
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p \
  "$WORK/android/app" \
  "$WORK/android/content" \
  "$WORK/android/content/pm" \
  "$WORK/android/net" \
  "$WORK/android/os" \
  "$WORK/android/provider" \
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
    open fun checkSelfPermission(permission: String): Int = permissions[permission] ?: -1
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

cat > "$WORK/io/github/daylight00/androidterminal/Test.kt" <<'KT'
package io.github.daylight00.androidterminal

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.os.Build
import android.os.Environment
import android.provider.Settings
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
    check(TerminalSharedStorage.directory().absolutePath == "/storage/emulated/0")

    println("PASS shared-storage-access runtime=kotlinc api29=runtime-permissions api30=all-files startup=host-owned home-link=absent")
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
  "$SOURCE" \
  "$WORK/io/github/daylight00/androidterminal/Test.kt" \
  -include-runtime -d "$WORK/test.jar"

kotlin -classpath "$WORK/test.jar" io.github.daylight00.androidterminal.TestKt
