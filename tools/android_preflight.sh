#!/usr/bin/env bash
# Checks the Android debug-export toolchain. Prints PASS/FAIL per item; exit 1 if any FAIL.
#   tools/android_preflight.sh
set -u
cd "$(dirname "$0")/.."
. tools/android_env.sh
fails=0
check() { if eval "$2" >/dev/null 2>&1; then echo "PASS  $1"; else echo "FAIL  $1${3:+  → $3}"; fails=$((fails+1)); fi; }

check "Godot executable ($GODOT)" '[ -n "$GODOT" ] && "$GODOT" --version | grep -q "^4\.7\.2\.stable"' "install Godot 4.7.2 stable or set GODOT="
check "Java 17 (JAVA_HOME=$JAVA_HOME)" '"$JAVA_HOME/bin/java" -version 2>&1 | grep -q "version \"17"' "brew install openjdk@17"
check "Android SDK ($ANDROID_HOME)" '[ -d "$ANDROID_HOME" ]' "see docs/android_setup.md"
check "cmdline-tools;latest" '[ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]'
check "platform-tools (adb)" '[ -x "$ADB" ]'
check "build-tools;35.0.1" '[ -x "$BUILD_TOOLS/apksigner" ] && [ -x "$BUILD_TOOLS/aapt2" ]'
check "platforms;android-35" '[ -f "$ANDROID_HOME/platforms/android-35/android.jar" ]'
check "cmake;3.10.2.4988404" '[ -d "$ANDROID_HOME/cmake/3.10.2.4988404" ]'
check "ndk;28.1.13356709" '[ -d "$ANDROID_HOME/ndk/28.1.13356709" ]'
check "SDK licences accepted" '[ -f "$ANDROID_HOME/licenses/android-sdk-license" ]' "yes | sdkmanager --licenses"
check "Export templates $GODOT_VERSION" 'grep -qx "$GODOT_VERSION" "$TEMPLATES_DIR/version.txt" && [ -f "$TEMPLATES_DIR/android_debug.apk" ] && [ -f "$TEMPLATES_DIR/android_source.zip" ]' "Editor → Manage Export Templates"
check "Debug keystore" '[ -f "$HOME/Library/Application Support/Godot/keystores/debug.keystore" ] || grep -q "export/android/debug_keystore = \"/" "$HOME/Library/Application Support/Godot/editor_settings-4.7.tres"' "see docs/android_setup.md"
check "Export preset \"Android Debug\"" 'grep -q "name=\"Android Debug\"" export_presets.cfg'
check "Output dir builds/android/" '[ -d builds/android ]'
echo ""
if [ "$fails" -eq 0 ]; then echo "PREFLIGHT: PASS"; else echo "PREFLIGHT: FAIL ($fails)"; exit 1; fi
