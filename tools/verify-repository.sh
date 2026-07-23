#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT" || exit 1

RC=0
check() {
  local label=$1
  shift
  if "$@"; then
    printf 'PASS %s\n' "$label"
  else
    local stage_rc=$?
    printf 'FAIL %s rc=%d\n' "$label" "$stage_rc" >&2
    RC=1
  fi
}

check git-diff-check git diff --check
check web-terminal "$ROOT/tools/test-web-terminal.sh"
check webgl-renderer "$ROOT/tools/test-webgl-renderer.sh"
check session-replay "$ROOT/tools/test-session-replay.sh"
check terminal-geometry "$ROOT/tools/test-terminal-geometry.sh"
check terminal-platform-policy "$ROOT/tools/test-platform-policy.sh"
check terminal-document-policy "$ROOT/tools/test-document-policy.sh"
check terminal-document-transport "$ROOT/tools/test-document-transport.sh"
check terminal-platform-adapter "$ROOT/tools/test-platform-adapter-compile.sh"
check shared-storage-access "$ROOT/tools/test-shared-storage-access.sh"
check frontend-recovery "$ROOT/tools/test-frontend-recovery.sh"
check renderer-recovery-api "$ROOT/tools/test-renderer-recovery-compile.sh"
check asset-provisioner "$ROOT/tools/test-asset-provisioner.sh"
check policy-verifier python3 "$ROOT/tools/verify_policy.py" "$ROOT"
check layer-boundaries python3 "$ROOT/tools/verify-layer-boundaries.py" "$ROOT"
check web-assets python3 "$ROOT/tools/verify-web-assets.py" "$ROOT"
check verifier-fixtures "$ROOT/tools/test-verifier.sh"
check shell-syntax bash -n \
  "$ROOT/tools/acquire-web-terminal-assets.sh" \
  "$ROOT/tools/build-native-bridge.sh" \
  "$ROOT/tools/build-native-bridge-cmake.sh" \
  "$ROOT/tools/prepare-android-sdk.sh" \
  "$ROOT/tools/test-asset-provisioner.sh" \
  "$ROOT/tools/test-web-terminal.sh" \
  "$ROOT/tools/test-webgl-renderer.sh" \
  "$ROOT/tools/test-session-replay.sh" \
  "$ROOT/tools/test-terminal-geometry.sh" \
  "$ROOT/tools/test-platform-policy.sh" \
  "$ROOT/tools/test-document-policy.sh" \
  "$ROOT/tools/test-document-transport.sh" \
  "$ROOT/tools/test-platform-adapter-compile.sh" \
  "$ROOT/tools/test-shared-storage-access.sh" \
  "$ROOT/tools/test-frontend-recovery.sh" \
  "$ROOT/tools/test-renderer-recovery-compile.sh" \
  "$ROOT/tools/verify-no-saf-virtual-mount.sh" \
  "$ROOT/tools/test-no-saf-virtual-mount.sh" \
  "$ROOT/tools/verify-repository.sh" \
  "$ROOT/tools/verify-native-ndk.sh" \
  "$ROOT/tools/test-verifier.sh"
check python-syntax python3 -m py_compile \
  "$ROOT/tools/provision-web-terminal-assets.py" \
  "$ROOT/tools/verify_policy.py" \
  "$ROOT/tools/verify-layer-boundaries.py" \
  "$ROOT/tools/verify-web-assets.py"
check identity-name test "$(git config --local user.name)" = 'daylight-00'
check identity-email test "$(git config --local user.email)" = 'hwjang00@snu.ac.kr'
check main-branch test "$(git branch --show-current)" = 'main'
check project-name grep -Fxq "rootProject.name = 'android-terminal'" settings.gradle
check application-id grep -Fxq "        applicationId 'io.github.daylight00.androidterminal'" app/build.gradle
check app-label grep -Fq 'android:label="Terminal"' app/src/main/AndroidManifest.xml
check project-description grep -Fq 'A thin terminal frontend for Android’s native shell, powered by xterm.js.' README.md
check min-api grep -Fxq '        minSdk 29' app/build.gradle
check target-api grep -Fxq '        targetSdk 29' app/build.gradle
check ndk-r27d grep -Fxq "    ndkVersion '27.3.13750724'" app/build.gradle
check arm64-only grep -Fxq "            abiFilters 'arm64-v8a'" app/build.gradle
check generated-jni grep -Fq 'generated/jniLibs' app/build.gradle
check native-gradle-task grep -Fq "tasks.register('buildNativeBridge', Exec)" app/build.gradle
check no-external-native-build sh -c '! grep -Fq externalNativeBuild app/build.gradle'
check host-native-ndk-fallback grep -Fq 'host-native-clang-ndk-sysroot' tools/build-native-bridge.sh
check buildconfig-enabled grep -Fq 'buildConfig true' app/build.gradle
check standard-sdk-root grep -Fq 'ANDROID_TERMINAL_SDK_ROOT:-"$HOME/Android/Sdk"' tools/prepare-android-sdk.sh
check no-sdk-bootstrap sh -c '! grep -Eq "curl |sdkmanager|pkg install" tools/prepare-android-sdk.sh'
check cmake-project grep -Fq 'add_library(shellbridge SHARED' app/src/main/c/CMakeLists.txt
check uv-cmake-project grep -Fq 'uv run --project' tools/build-native-bridge-cmake.sh
check system-shell grep -Fq 'const val SHELL_PATH = "/system/bin/sh"' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSession.kt
check session-service grep -Fq 'class TerminalSessionService : Service()' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSessionService.kt
check serialized-snapshot-store grep -Fq 'TerminalSerializedSnapshotStore(TerminalContract.MAX_SERIALIZED_SNAPSHOT_BYTES)' app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSessionService.kt
check serialize-addon grep -Fq 'new window.SerializeAddon.SerializeAddon()' app/src/main/assets/terminal/bridge/terminal-bridge.js
check webgl-addon grep -Fq 'new WebglAddon.WebglAddon(false)' app/src/main/assets/terminal/bridge/terminal-renderer.js
check webgl-fallback grep -Fq "fallback('context-loss')" app/src/main/assets/terminal/bridge/terminal-renderer.js
check service-owns-session grep -Fq 'TerminalSession(' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSessionService.kt
check controller-does-not-own-session sh -c '! grep -Fq "TerminalSession(" app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalController.kt'
check platform-contract-v6 grep -Fq 'const val PROTOCOL_VERSION = 6' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check geometry-state grep -Fq 'class TerminalGeometryState' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalGeometry.kt
check geometry-signal grep -Fq 'requestGeometrySync()' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/MainActivity.kt
check geometry-native-capability grep -Fq 'android-window-geometry' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check platform-adapter grep -Fq 'class TerminalPlatformAdapter' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalPlatformAdapter.kt
check renderer-gone-handler grep -Fq 'override fun onRenderProcessGone' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/LocalAssetWebViewClient.kt
check renderer-recovery-state grep -Fq 'class TerminalFrontendRecoveryState' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalFrontendRecoveryState.kt
check renderer-same-service grep -Fq 'installFrontend(binder)' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/MainActivity.kt
check renderer-native-capability grep -Fq 'webview-renderer-recovery' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check platform-bridge-capability grep -Fq 'platform-bridge-v2' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check android-clipboard-capability grep -Fq 'android-clipboard' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check android-link-capability grep -Fq 'android-external-uri' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check android-accessibility-capability grep -Fq 'android-accessibility-state' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check android-document-capability grep -Fq 'android-document-transport' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check android-shared-storage-capability grep -Fq 'android-shared-storage-direct-path' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check manage-external-storage-permission grep -Fq 'android.permission.MANAGE_EXTERNAL_STORAGE' \
  app/src/main/AndroidManifest.xml
check legacy-external-storage grep -Fq 'android:requestLegacyExternalStorage="true"' \
  app/src/main/AndroidManifest.xml
check home-storage-link grep -Fq 'TerminalSharedStorage.prepareHomeLink(homeDirectory)' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSession.kt
check layer2-only-runtime grep -Fq 'layer2-only-runtime-v1' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check no-active-layer3 sh -c '! test -e app/src/main/assets/terminal/customization && ! test -e app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalCustomization.kt'
check saf-document-transport grep -Fq 'class TerminalDocumentTransport' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalDocumentTransport.kt
check private-home-document-policy grep -Fq 'resolvePrivateExportSource' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalDocumentPolicy.kt
check activity-document-result grep -Fq 'override fun onActivityResult' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/MainActivity.kt
check no-saf-virtual-mount "$ROOT/tools/verify-no-saf-virtual-mount.sh" "$ROOT"
check no-saf-virtual-mount-fixture "$ROOT/tools/test-no-saf-virtual-mount.sh"
check native-exec grep -Fq 'execve(shell_path, arguments, environment);' app/src/main/c/shell_bridge.c
check webview grep -Fq 'val view: WebView = WebView(activity)' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalController.kt
check web-message-port grep -Fq 'createWebMessageChannel()' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalController.kt
check local-origin grep -Fq 'const val ORIGIN = "https://app.local"' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check no-androidx sh -c '! grep -R --exclude-dir=.git --exclude-dir=out -E "androidx\.|com.android.support" app'
check no-rust sh -c '! find app/src/main -type f -name "*.rs" | grep .'
check no-java-source sh -c '! find app/src/main/java -type f 2>/dev/null | grep .'
check no-userland-payload sh -c '! find app/src/main -type f \( -name sh -o -name bash -o -name toybox -o -name busybox -o -name "libc.so*" -o -name "linker*" \) | grep .'
check manifest-no-network sh -c '! grep -Fq "android.permission.INTERNET" app/src/main/AndroidManifest.xml'

exit "$RC"
