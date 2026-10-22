#!/usr/bin/env bash
# Prints connected Android device details useful for the playtest report.
#   tools/android_device_info.sh
set -u
cd "$(dirname "$0")/.."
. tools/android_env.sh
devices="$("$ADB" devices | awk 'NR>1 && $2=="device"{print $1}')"
if [ -z "$devices" ]; then
  echo "No adb device connected."
  "$ADB" devices | sed -n '2,$p' | grep -E "unauthorized|offline" && echo "Accept the USB-debugging prompt on the phone, then retry."
  exit 1
fi
for d in $devices; do
  p() { "$ADB" -s "$d" shell getprop "$1" | tr -d '\r'; }
  echo "Device:      $d"
  echo "Model:       $(p ro.product.manufacturer) $(p ro.product.model)"
  echo "Android:     $(p ro.build.version.release) (API $(p ro.build.version.sdk))"
  echo "ABI:         $(p ro.product.cpu.abi)"
  echo "SoC:         $(p ro.soc.manufacturer) $(p ro.soc.model)"
  echo "Screen:      $("$ADB" -s "$d" shell wm size | tr -d '\r' | tail -1)  $("$ADB" -s "$d" shell wm density | tr -d '\r' | tail -1)"
  echo "RAM:         $("$ADB" -s "$d" shell cat /proc/meminfo | tr -d '\r' | head -1)"
  installed="$("$ADB" -s "$d" shell pm list packages "$PACKAGE" | tr -d '\r')"
  echo "Installed:   ${installed:-no}"
done
