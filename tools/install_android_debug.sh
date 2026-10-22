#!/usr/bin/env bash
# Installs (replaces) the debug APK on the connected device and launches it.
# Never uninstalls anything. If an existing install was signed with a
# different key, it stops and explains instead of removing it.
#   tools/install_android_debug.sh [device-serial]
set -u
cd "$(dirname "$0")/.."
. tools/android_env.sh
[ -f "$APK" ] || { echo "No APK at $APK — run tools/export_android_debug.sh first." >&2; exit 1; }
serial="${1:-$("$ADB" devices | awk 'NR>1 && $2=="device"{print $1; exit}')}"
[ -n "$serial" ] || { echo "No adb device connected (see docs/android_setup.md → Device)." >&2; exit 1; }
echo "Installing on $serial …"
out="$("$ADB" -s "$serial" install -r "$APK" 2>&1)"
echo "$out"
if echo "$out" | grep -q "INSTALL_FAILED_UPDATE_INCOMPATIBLE"; then
  echo ""
  echo "An older $PACKAGE signed with a different key is installed. Not removing it automatically."
  echo "If you are happy to lose its local save data, remove it yourself:"
  echo "  $ADB -s $serial uninstall $PACKAGE"
  exit 1
fi
echo "$out" | grep -q "^Success" || exit 1
"$ADB" -s "$serial" shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
echo "Launched $PACKAGE. Logs: $ADB -s $serial logcat -s godot:V"
