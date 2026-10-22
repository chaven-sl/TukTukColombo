#!/usr/bin/env bash
# Exports the DEBUG APK (preset "Android Debug") to builds/android/ and prints
# its path, size and SHA-256. Release builds / store signing are out of scope.
#   tools/export_android_debug.sh
set -u
cd "$(dirname "$0")/.."
. tools/android_env.sh
tools/android_preflight.sh || { echo "Fix the FAIL items above first." >&2; exit 1; }
rm -f "$APK"
echo ""
echo "##### Import"
perl -e 'alarm shift; exec @ARGV' 600 "$GODOT" --headless --path . --import >/dev/null 2>&1
echo "##### Export (gradle build; first run downloads Gradle dependencies)"
# --install-android-build-template creates the git-ignored android/ build
# project from the 4.7.2 templates when it is missing.
perl -e 'alarm shift; exec @ARGV' 1800 "$GODOT" --headless --path . --install-android-build-template \
  --export-debug "Android Debug" "$APK" 2>&1 | grep -v -E "^\s*$|^Godot Engine" | tail -40
if [ ! -f "$APK" ]; then echo "EXPORT: FAIL (no APK produced)"; exit 1; fi
echo ""
echo "APK:     $(pwd)/$APK"
echo "Size:    $(du -h "$APK" | cut -f1) ($(stat -f%z "$APK" 2>/dev/null || stat -c%s "$APK") bytes)"
echo "SHA-256: $(shasum -a 256 "$APK" | cut -d' ' -f1)"
"$BUILD_TOOLS/aapt2" dump badging "$APK" 2>/dev/null | grep -E "^package:|minSdkVersion|sdkVersion|targetSdkVersion|uses-permission|native-code|launchable-activity" | sed 's/^/         /'
"$BUILD_TOOLS/apksigner" verify --print-certs "$APK" 2>/dev/null | grep -E "Signer #1 certificate DN" | sed 's/^/         /'
echo "EXPORT: PASS"
