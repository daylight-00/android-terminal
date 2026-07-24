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
check terminal-font-scale "$ROOT/tools/test-font-scale.sh"
check core-host-integration "$ROOT/tools/test-core-host-integration.sh"
check stable-addon-wave "$ROOT/tools/test-stable-addon-wave.sh"
check layer2-completion "$ROOT/tools/test-layer2-completion.sh"
check login-shell "$ROOT/tools/test-login-shell.sh"
check layer3-scaffold "$ROOT/tools/test-layer3-scaffold.sh"
check terminal-document-policy "$ROOT/tools/test-document-policy.sh"
check terminal-document-transport "$ROOT/tools/test-document-transport.sh"
check terminal-platform-adapter "$ROOT/tools/test-platform-adapter-compile.sh"
check shared-storage-access "$ROOT/tools/test-shared-storage-access.sh"
check session-environment "$ROOT/tools/test-session-environment.sh"
check session-directories "$ROOT/tools/test-session-directories.sh"
check frontend-recovery "$ROOT/tools/test-frontend-recovery.sh"
check renderer-recovery-api "$ROOT/tools/test-renderer-recovery-compile.sh"
check asset-provisioner "$ROOT/tools/test-asset-provisioner.sh"
check policy-verifier python3 "$ROOT/tools/verify_policy.py" "$ROOT"
check layer-boundaries python3 "$ROOT/tools/verify-layer-boundaries.py" "$ROOT"
check upstream-capabilities python3 "$ROOT/tools/verify-upstream-capabilities.py" "$ROOT"
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
  "$ROOT/tools/test-font-scale.sh" \
  "$ROOT/tools/test-core-host-integration.sh" \
  "$ROOT/tools/test-stable-addon-wave.sh" \
  "$ROOT/tools/test-layer2-completion.sh" \
  "$ROOT/tools/test-login-shell.sh" \
  "$ROOT/tools/test-layer3-scaffold.sh" \
  "$ROOT/tools/test-document-policy.sh" \
  "$ROOT/tools/test-document-transport.sh" \
  "$ROOT/tools/test-platform-adapter-compile.sh" \
  "$ROOT/tools/test-shared-storage-access.sh" \
  "$ROOT/tools/test-session-environment.sh" \
  "$ROOT/tools/test-session-directories.sh" \
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
  "$ROOT/tools/verify-upstream-capabilities.py" \
  "$ROOT/tools/verify-layer2-completion.py" \
  "$ROOT/tools/verify-web-assets.py"
check identity-name test "$(git config --local user.name)" = 'daylight-00'
check identity-email test "$(git config --local user.email)" = 'hwjang00@snu.ac.kr'
check main-branch test "$(git branch --show-current)" = 'main'
check project-name grep -Fxq "rootProject.name = 'android-terminal'" settings.gradle
check application-id grep -Fxq "        applicationId 'io.github.daylight00.androidterminal'" app/build.gradle
check app-label grep -Fq 'android:label="Terminal"' app/src/main/AndroidManifest.xml
check project-description grep -Fq 'A thin terminal frontend for Android’s native shell, powered by xterm.js.' README.md
check min-api grep -Fxq '        minSdk 29' app/build.gradle
check target-api grep -Fxq '        targetSdk 28' app/build.gradle
check version-code grep -Fxq '        versionCode 24' app/build.gradle
check version-name grep -Fxq "        versionName '0.23.3'" app/build.gradle
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
check login-shell-argv0 grep -Fq 'char *const arguments[] = {"-sh", NULL};' app/src/main/c/shell_bridge.c
check login-shell-direct-exec grep -Fq 'execve(shell_path, arguments, environment)' app/src/main/c/shell_bridge.c
check inherited-session-environment grep -Fq 'session_environment_merge(' app/src/main/c/shell_bridge.c
check environment-helper test -f app/src/main/c/session_environment.c
check no-fixed-path sh -c '! grep -Fq "PATH=/system/bin" app/src/main/c/shell_bridge.c app/src/main/c/session_environment.c'
check no-storage-env-synthesis sh -c '! grep -Eq "EXTERNAL_STORAGE=|ANDROID_STORAGE=/storage" app/src/main/c/shell_bridge.c app/src/main/c/session_environment.c'
check no-login-shell-wrapper sh -c '! grep -Eq "system\(|popen\(|\"-l\"" app/src/main/c/shell_bridge.c'
check session-service grep -Fq 'class TerminalSessionService : Service()' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSessionService.kt
check serialized-snapshot-store grep -Fq 'TerminalSerializedSnapshotStore(TerminalContract.MAX_SERIALIZED_SNAPSHOT_BYTES)' app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSessionService.kt
check serialize-addon grep -Fq 'new window.SerializeAddon.SerializeAddon()' app/src/main/assets/terminal/bridge/terminal-bridge.js
check clipboard-addon grep -Fq 'new window.ClipboardAddon.ClipboardAddon(undefined, clipboardProvider)' app/src/main/assets/terminal/bridge/terminal-bridge.js
check image-addon-defaults grep -Fq 'new window.ImageAddon.ImageAddon()' app/src/main/assets/terminal/bridge/terminal-bridge.js
check progress-addon grep -Fq 'new window.ProgressAddon.ProgressAddon()' app/src/main/assets/terminal/bridge/terminal-bridge.js
check search-addon grep -Fq 'new window.SearchAddon.SearchAddon()' app/src/main/assets/terminal/bridge/terminal-bridge.js
check unicode11-addon grep -Fq 'new window.Unicode11Addon.Unicode11Addon()' app/src/main/assets/terminal/bridge/terminal-bridge.js
check web-fonts-addon grep -Fq 'new window.WebFontsAddon.WebFontsAddon()' app/src/main/assets/terminal/bridge/terminal-bridge.js
check ligatures-addon grep -Fq 'new module.LigaturesAddon(options)' app/src/main/assets/terminal/bridge/terminal-bridge.js
check ligatures-esm-loader grep -Fq "import {LigaturesAddon} from '/terminal/vendor/addon-ligatures.mjs'" app/src/main/assets/terminal/bridge/terminal-ligatures.js
check ligatures-webgl-reactivation grep -Fq 'rendererController.reactivate()' app/src/main/assets/terminal/bridge/terminal-bridge.js
check unicode-proposed-api-opt-in sh -c '[ "$(grep -Fo allowProposedApi app/src/main/assets/terminal/bridge/terminal-bridge.js | wc -l)" -eq 1 ]'
check web-links-addon grep -Fq 'new window.WebLinksAddon.WebLinksAddon(' app/src/main/assets/terminal/bridge/terminal-bridge.js
check web-links-native-route grep -Fq 'platform.openExternalUri(uri)' app/src/main/assets/terminal/bridge/terminal-bridge.js
check web-links-capability grep -Fq 'web-links-v1' app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
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
check android-font-scale-capability grep -Fq 'android-font-scale-state' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check page-font-scale-capability grep -Fq 'android-font-scale-v1' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check page-title-capability grep -Fq 'session-title-state-v1' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check page-localized-strings-capability grep -Fq 'localized-xterm-strings-v1' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check page-safe-window-capability grep -Fq 'safe-window-reports-v1' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check native-localized-strings-capability grep -Fq 'android-localized-xterm-strings' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check service-title-state grep -Fq 'title = TerminalSessionTitle.sanitize(value)' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSessionService.kt
check xterm-title-event grep -Fq 'terminal.onTitleChange(' \
  app/src/main/assets/terminal/bridge/terminal-bridge.js
check xterm-localized-strings grep -Fq 'terminal.strings.promptLabel' \
  app/src/main/assets/terminal/bridge/terminal-platform.js
check safe-window-report grep -Fq 'getWinSizePixels: true' \
  app/src/main/assets/terminal/bridge/terminal-platform.js
check manifest-font-scale-config grep -Fq 'android:configChanges="fontScale|' app/src/main/AndroidManifest.xml
check android-document-capability grep -Fq 'android-document-transport' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check page-document-capability grep -Fq 'document-transport-v2' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check saf-import-destination grep -Fq 'destinationDirectory' \
  app/src/main/assets/terminal/bridge/terminal-bridge.js
check no-fixed-saf-inbox sh -c '! grep -Eq "IMPORT_DIRECTORY_NAME|File\(activity\.filesDir, \"imports\"\)" app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalDocumentPolicy.kt app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalDocumentTransport.kt'
check android-shared-storage-capability grep -Fq 'android-shared-storage-direct-path' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check native-account-capability grep -Fq 'android-native-account-session' app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check manage-external-storage-permission grep -Fq 'android.permission.MANAGE_EXTERNAL_STORAGE' \
  app/src/main/AndroidManifest.xml
check legacy-external-storage grep -Fq 'android:requestLegacyExternalStorage="true"' \
  app/src/main/AndroidManifest.xml
check no-home-storage-link sh -c '! grep -Eq "prepareHomeLink|Os.symlink" app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSharedStorage.kt app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSession.kt'
check startup-storage-request grep -Fq 'TerminalSharedStorage.requestAccess(this)' app/src/main/kotlin/io/github/daylight00/androidterminal/MainActivity.kt
check tmpdir-child grep -Fq 'java.io.File(cacheDir, "tmp")' app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSessionService.kt
check tmpdir-preparation grep -Fq 'TerminalSessionDirectories.prepareTemporaryDirectory(temporaryDirectory)' app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalSession.kt
check stable-addon-wave-capability grep -Fq 'stable-addon-wave-v1' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check login-shell-capability grep -Fq 'login-shell-v1' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check native-account-page-capability grep -Fq 'native-account-session-v1' app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check layer2-completion-capability grep -Fq 'layer2-completion-v1' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check image-wasm-csp grep -Fq "script-src 'self' 'wasm-unsafe-eval';" \
  app/src/main/kotlin/io/github/daylight00/androidterminal/LocalAssetWebViewClient.kt
check no-javascript-unsafe-eval sh -c '! grep -Fq "script-src '''self''' '''unsafe-eval''';" app/src/main/kotlin/io/github/daylight00/androidterminal/LocalAssetWebViewClient.kt'
check debug-webview-inspection grep -Fq 'if (BuildConfig.DEBUG) WebView.setWebContentsDebuggingEnabled(true)' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/MainActivity.kt
check layer3-scaffold grep -Fq 'layer3-scaffold-v1' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalContract.kt
check layer3-js-scaffold test -f app/src/main/assets/terminal/customization/customization.js
check layer3-css-scaffold test -f app/src/main/assets/terminal/customization/customization.css
check layer3-native-scaffold test -f app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalCustomization.kt
check layer2-does-not-depend-layer3 sh -c '! grep -Eq "AndroidTerminalCustomization|/terminal/customization/" app/src/main/assets/terminal/bridge/terminal-bridge.js'
check saf-document-transport grep -Fq 'class TerminalDocumentTransport' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalDocumentTransport.kt
check private-home-document-policy grep -Fq 'resolvePrivateExportSource' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalDocumentPolicy.kt
check activity-document-result grep -Fq 'override fun onActivityResult' \
  app/src/main/kotlin/io/github/daylight00/androidterminal/MainActivity.kt
check no-saf-virtual-mount "$ROOT/tools/verify-no-saf-virtual-mount.sh" "$ROOT"
check no-saf-virtual-mount-fixture "$ROOT/tools/test-no-saf-virtual-mount.sh"
check native-exec grep -Fq 'execve(shell_path, arguments, environment);' app/src/main/c/shell_bridge.c
check login-shell-argv0 grep -Fq 'char *const arguments[] = {"-sh", NULL};' app/src/main/c/shell_bridge.c
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
check manifest-native-network grep -Fq 'android.permission.INTERNET' app/src/main/AndroidManifest.xml
check webview-network-block grep -Fq 'blockNetworkLoads = true' app/src/main/kotlin/io/github/daylight00/androidterminal/TerminalController.kt
check webview-csp-no-connect grep -Fq "connect-src 'none'" app/src/main/kotlin/io/github/daylight00/androidterminal/LocalAssetWebViewClient.kt

exit "$RC"
