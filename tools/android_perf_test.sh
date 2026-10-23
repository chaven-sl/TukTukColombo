#!/usr/bin/env bash
# Runs the deterministic device performance test on the connected phone and
# pulls the JSON summary into builds/android/perf/ (git-ignored).
#   tools/android_perf_test.sh [seconds=300] [options]
# options (v0.03B1 A/B, comma-separated): audio_off rig_static humans_hidden
#   traffic_hidden hero_hidden ribbon_hidden signs_hidden shadows_off fog_off
#   sky_off art_hidden all_off
set -u
cd "$(dirname "$0")/.."
. tools/android_env.sh
secs="${1:-300}"
opts="${2:-}"
serial="$("$ADB" devices | awk 'NR>1 && $2=="device"{print $1; exit}')"
[ -n "$serial" ] || { echo "No adb device connected." >&2; exit 1; }
A="$ADB -s $serial"
$A shell am force-stop "$PACKAGE"
# Debug builds are debuggable, so run-as can write into the app's user:// dir.
$A shell "run-as $PACKAGE sh -c 'mkdir -p files && echo $secs $opts > files/perf_test.flag'" || { echo "run-as failed (is the debug build installed?)" >&2; exit 1; }
$A logcat -c
$A shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
echo "Running ${secs}s perf test on $serial — keep the screen on and the phone unplugged from chargers if possible …"
deadline=$(( $(date +%s) + secs + 120 ))
until $A logcat -d -s godot:V 2>/dev/null | grep -q "\[DevicePerfTest\] finished"; do
  [ "$(date +%s)" -lt "$deadline" ] || { echo "Timed out waiting for the result." >&2; exit 1; }
  $A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1  # screen timeout would stall the run
  sleep 10
done
mkdir -p builds/android/perf
tag="${opts//,/_}"
out="builds/android/perf/device_perf_test_$(date +%Y%m%d_%H%M%S)${tag:+_$tag}.json"
$A shell "run-as $PACKAGE cat files/perf/device_perf_test.json" > "$out"
$A logcat -d -s godot:V | grep -E "\[GraphicsRuntime\]|\[PerfMonitor\]"
$A shell dumpsys thermalservice | grep -m1 "Thermal Status"
echo "Saved $out"
