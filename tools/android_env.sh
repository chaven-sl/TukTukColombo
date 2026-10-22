#!/usr/bin/env bash
# Shared Android environment for the tools/android_*.sh scripts (sourced, not run).
# Every path can be overridden from the environment; nothing machine-specific
# is stored in the project.
GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
  for candidate in godot godot4 /Applications/Godot.app/Contents/MacOS/Godot; do
    if command -v "$candidate" >/dev/null 2>&1 || [ -x "$candidate" ]; then GODOT="$candidate"; break; fi
  done
fi
if [ -z "${JAVA_HOME:-}" ]; then
  for candidate in /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
                   /usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home; do
    if [ -x "$candidate/bin/java" ]; then JAVA_HOME="$candidate"; break; fi
  done
  if [ -z "${JAVA_HOME:-}" ] && [ -x /usr/libexec/java_home ]; then
    JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
  fi
fi
export JAVA_HOME
ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
export ANDROID_HOME ANDROID_SDK_ROOT="$ANDROID_HOME"
ADB="$ANDROID_HOME/platform-tools/adb"
BUILD_TOOLS="$ANDROID_HOME/build-tools/35.0.1"
GODOT_VERSION="4.7.2.stable"
TEMPLATES_DIR="${TEMPLATES_DIR:-$HOME/Library/Application Support/Godot/export_templates/$GODOT_VERSION}"
PACKAGE="com.chavensl.tuktukcolombo"
APK="builds/android/tuktukcolombo-debug.apk"
