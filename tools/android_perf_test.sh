#!/usr/bin/env bash
# Runs the deterministic device performance test on the connected phone and
# pulls the JSON summary into builds/android/perf/ (git-ignored).
#   tools/android_perf_test.sh [seconds=300]
set -u
cd "$(dirname "$0")/.."
. tools/android_env.sh
secs="${1:-300}"
serial="$("$ADB" devices | awk 'NR>1 && $2=="device"{print $1; exit}')"
[ -n "$serial" ] || { echo "No adb device connected." >&2; exit 1; }
A="$ADB -s $serial"
$A shell am force-stop "$PACKAGE"
# Debug builds are debuggable, so run-as can write into the app's user:// dir.
$A shell "run-as $PACKAGE sh -c 'mkdir -p files && echo $secs > files/perf_test.flag'" || { echo "run-as failed (is the debug build installed?)" >&2; exit 1; }
$A logcat -c
$A shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
echo "Running ${secs}s perf test on $serial — keep the screen on and the phone unplugged from chargers if possible …"
deadline=$(( $(date +%s) + secs + 120 ))
until $A logcat -d -s godot:V 2>/dev/null | grep -q "\[DevicePerfTest\] finished"; do
  [ "$(date +%s)" -lt "$deadline" ] || { echo "Timed out waiting for the result." >&2; exit 1; }
  sleep 10
done
mkdir -p builds/android/perf
out="builds/android/perf/device_perf_test_$(date +%Y%m%d_%H%M%S).json"
$A shell "run-as $PACKAGE cat files/perf/device_perf_test.json" > "$out"
$A logcat -d -s godot:V | grep "\[PerfMonitor\]"
echo "Saved $out"
