#!/usr/bin/env bash
# Runs every automated check for TukTuk Colombo headless.
#   tools/run_tests.sh            # full suite (~1 min)
#   GODOT=/path/to/Godot tools/run_tests.sh
# Exit code is non-zero if any stage fails.
set -u
cd "$(dirname "$0")/.."

GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
  for candidate in godot godot4 /Applications/Godot.app/Contents/MacOS/Godot; do
    if command -v "$candidate" >/dev/null 2>&1 || [ -x "$candidate" ]; then
      GODOT="$candidate"
      break
    fi
  done
fi
if [ -z "$GODOT" ]; then
  echo "Godot executable not found. Set GODOT=/path/to/godot" >&2
  exit 2
fi

status=0
# Portable timeout (macOS has no `timeout`): perl alarm kills a hung stage.
with_timeout() { local secs="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$secs" "$@"; }
run() {
  local label="$1"; shift
  echo ""
  echo "##### $label"
  # A script parse error can leave Godot waiting forever; cap each stage.
  if ! with_timeout 900 "$GODOT" --headless --path . "$@" 2>&1 | grep -v -E "^\s*$|^Godot Engine"; then :; fi
  local code=${PIPESTATUS[0]}
  if [ "$code" -ne 0 ]; then
    echo "##### $label FAILED (exit $code)"
    status=1
  fi
}

echo "##### Import (refresh class cache)"
"$GODOT" --headless --path . --import >/dev/null 2>&1

run "Unit tests" --script res://tests/run_tests.gd
run "Vehicle handling scenarios" --fixed-fps 60 res://tests/scenarios/vehicle_handling_test.tscn
run "Vehicle dynamics v0.01a (swerve / rollover / recovery)" --fixed-fps 60 res://tests/scenarios/vehicle_dynamics_test.tscn
run "Scoring scenarios" --fixed-fps 60 res://tests/scenarios/scoring_scenarios_test.tscn
run "Human world + passengers (real scene)" --fixed-fps 60 res://tests/scenarios/human_world_test.tscn
run "Input smoke (real scene, InputMap actions)" --fixed-fps 60 res://tests/scenarios/input_smoke_test.tscn
run "Mobile touch + lifecycle (real scene)" --fixed-fps 60 res://tests/scenarios/mobile_touch_test.tscn
run "GPS + hire UX + traffic incidents (real scene)" --fixed-fps 60 res://tests/scenarios/gps_incident_test.tscn
run "HUD safe-area matrix (5 aspect ratios x 6 safe areas)" --fixed-fps 60 res://tests/scenarios/hud_safe_area_test.tscn
run "World containment + crash damage + recovery + props" --fixed-fps 60 res://tests/scenarios/world_containment_test.tscn
run "Pavement safety: pedestrian emergency evasion" --fixed-fps 60 res://tests/scenarios/pavement_safety_test.tscn
run "Fort–Pettah slice: art / presentation / audio (v0.03B)" --fixed-fps 60 res://tests/scenarios/fort_pettah_test.tscn
run "Pettah compression: narrowed market road, routing, traffic (v0.03B1.1)" --fixed-fps 60 res://tests/scenarios/market_compression_test.tscn
run "Mobile touch (forced touch controls)" --fixed-fps 60 res://tests/scenarios/mobile_touch_test.tscn -- --force-touch-controls
run "Traffic + humans soak (6 min, driving)" --fixed-fps 60 res://tests/scenarios/traffic_soak_test.tscn -- --duration=360
run "Traffic + humans + incidents soak (4 min, scripted collisions)" --fixed-fps 60 res://tests/scenarios/traffic_soak_test.tscn -- --duration=240 --incidents
run "Traffic + humans + off-road soak (4 min, pavement / props / crashes)" --fixed-fps 60 res://tests/scenarios/traffic_soak_test.tscn -- --duration=240 --offroad
run "Fort–Pettah soak (6 min: traffic, people, hires, GPS, incidents, off-road, damage)" --fixed-fps 60 res://tests/scenarios/traffic_soak_test.tscn -- --duration=360 --fort-pettah
run "Traffic + humans soak (6 min, junction stress)" --fixed-fps 60 res://tests/scenarios/traffic_soak_test.tscn -- --duration=360 --park-near-junction

echo ""
if [ "$status" -eq 0 ]; then echo "ALL TEST STAGES PASSED"; else echo "SOME TEST STAGES FAILED"; fi
exit $status
