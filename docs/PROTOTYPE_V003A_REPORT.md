# Prototype v0.03A — Android + Touch + Production Readiness

## STATUS

**PARTIAL.** Everything that can be done without a phone is done and verified: the Android toolchain is installed, the debug APK exports, touch controls and lifecycle work in automated tests, and all earlier tests pass. **No Android device was connected**, so the real-device test and device performance baseline are **PENDING**. Vehicle physics, camera, traffic, passenger weights and satisfaction formulas were **not retuned**.

`REAL DEVICE BASELINE: PENDING — no adb device connected` (owner steps are under *Real device* below).

## TOOLCHAIN

| Item | Value |
|---|---|
| Godot | 4.7.2.stable.official.ed1daf0bf (standard, not .NET) |
| JDK | OpenJDK 17.0.21 (Homebrew `openjdk@17`) — `/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home` |
| SDK location | `~/Library/Android/sdk` (command-line tools only; no Android Studio) |
| SDK packages | cmdline-tools;latest 23.0.0 · platform-tools 37.0.1 (adb 1.0.41) · build-tools;35.0.1 · platforms;android-35 · cmake;3.10.2.4988404 · ndk;28.1.13356709 · *platforms;android-36 (fetched automatically by Godot's Gradle template, which compiles against SDK 36; the target stays 35)* |
| Export templates | 4.7.2.stable, official, SHA-512 verified, in `~/Library/Application Support/Godot/export_templates/4.7.2.stable/` |
| Debug keystore | Godot's standard debug keystore (`androiddebugkey`), per-machine editor setting; no release keystore was created |
| Preflight | `tools/android_preflight.sh` — **14/14 PASS** |

Every download came from an official source (Homebrew, dl.google.com via `sdkmanager`, Godot's GitHub release), and checksums were verified where published. Reproduction steps are in `docs/android_setup.md`.

## ANDROID EXPORT CONFIGURATION

| | |
|---|---|
| Preset | "Android Debug" (`export_presets.cfg`, committed; it contains no secrets) |
| Package ID | `com.chavensl.tuktukcolombo` — **provisional development ID** |
| Minimum API | 28 (Android 9) |
| Target API | 35 |
| Renderer | Mobile (Vulkan) |
| ABI | arm64-v8a only |
| Orientation | landscape: project `orientation=4` (sensor landscape) → manifest `screenOrientation=11` (userLandscape) |
| Build | Gradle build (needed to set the SDK levels). The template is generated into the git-ignored `android/` |
| Other | immersive mode; **no permissions** requested; `tests/ docs/ tools/ builds/` excluded from the package; version 0.0.3a (code 3) |

## TOUCH ARCHITECTURE

`MobileControls` (CanvasLayer 15, raw `InputEventScreenTouch`/`ScreenDrag`) → `TouchControlState` (pure, unit-tested) → `TouchInputSource` (physics priority −10) → `VehicleInputState` → `TukController`. Keyboard input stays in `PlayerInputSource`.

`InputMode` decides once at startup, and only one source is ever enabled: touch on Android/mobile, keyboard on desktop. The touch HUD is hidden on desktop by default. Overrides: `tuktuk/dev/force_touch_controls` or `-- --force-touch-controls`. No plugins or joystick packages are used.

## TOUCH CONTROL LAYOUT

- Bottom-left: analog **steering pad** (left thumb) with a knob showing the current input.
- Bottom-right: large **GO** (accelerator), with **BRAKE/reverse** inboard of it.
- Above GO: small **HORN**.
- Top-left: small **II** pause button, away from both thumbs.
- Above HORN on the right: **ACCEPT RIDE**, shown only when a passenger is in range.
- Opacity is 0.50 idle and 0.78 when pressed.
- In touch mode the score moves right of the pause button, and the speed readout sits above the steering pad.
- Screenshots: `user://test_results/screens/touch_<w>x<h>.png`, made with `tests/scenarios/touch_layout_screens.tscn`.

## STEERING MAPPING

`TouchSteeringMapper`:
- dead zone 0.08;
- exponent 1.15, so it is mostly linear (half travel gives about 0.45 lock);
- full lock at 85% of the pad half-width;
- clamped to −1…+1;
- symmetric and monotonic, with no hysteresis.

The input layer adds no smoothing. Reversal is instantaneous and release returns the input to 0, exactly like the keyboard. The wheels return at the vehicle's existing steering rate (locked baseline). Tunables are in `resources/input/touch_controls.tres`.

## MULTITOUCH

Every finger is tracked by its touch index:
- The first control a finger lands on owns that finger until it lifts. A steering thumb that slides onto BRAKE keeps steering and never brakes.
- Only one finger can steer, so a second finger cannot steal steering.
- Steer + GO and steer + BRAKE work together.
- Taps never release held controls.

This is verified with injected touch events in the real scene: steer + GO turns and accelerates the real tuk (18 km/h, Δyaw −1.18 rad); steer + BRAKE slows it from 18.6 to 0.8 km/h.

## PASSENGER INTERACTION

- **ACCEPT RIDE** calls the same `RideManager.request_accept()` as the E key. The automated test confirms the ride moves into the pickup/boarding flow.
- The live mood **percentage was removed**. The ride panel now shows a qualitative mood: HAPPY / IMPATIENT / NERVOUS / EXCITED / BORED / UPSET.
  - It comes from `PassengerMood`, which projects the finish time and reuses the existing subscore functions unchanged.
  - Any pedestrian danger → UPSET.
  - The final numeric rating on the result card is unchanged.

## ANDROID BACK / APP LIFECYCLE

| Event | Behaviour (tested) |
|---|---|
| Back during gameplay | pause |
| Back on pause screen | resume; `quit_on_go_back=false`, so Back never quits |
| Pause button | pause |
| Focus loss / app paused | pause and release all held touches. **No auto-resume.** Ride state is unchanged. Stats are flushed by GameState as before. |
| Any pause | all touches are cancelled, so nothing is stuck pressed on resume |

The pause screen hides the keyboard shortcut hints in touch mode. The developer telemetry and performance-test buttons appear in debug builds only.

## RESPONSIVE UI / SAFE AREA

`MobileLayout.compute()` places every control relative to the display safe area, converted to logical units.

Verified at 1920×1080, 2400×1080, 2340×1080, 2520×1080 and 1280×800, each under four safe-area cases:
- no cutout;
- a left cutout;
- a right cutout;
- both cutouts plus a gesture bar.

In every case, all controls are inside the safe area, at least 60×56 units, and nothing overlaps. Windowed screenshots at all five aspect ratios report no problems.

## ROUTE FIX

**Fixed.** `RoadNetwork.route(from, to, heading)` is now direction-aware:
- The start lanes follow the tuk's heading. At a pickup, they follow the kerb lane the passenger stands beside.
- The destination snaps to its kerb lane.
- The undirected search is used only when no legal route exists.

Quoted offer distances use the kerb direction. The in-ride remaining distance uses the tuk's heading.

Two pickups faced a direction with no legal way to the destinations, which is where the U-turn quotes came from. **PickupThrill** moved from x 120.2 to 131.8, and **PickupAunty** moved from x 9.2 to −9.2 (the opposite kerb).

The regression test checks all 3 offers × 4 destinations: each route is direction-restricted and stable when the tuk drives off along the kerb. All 12 pass.

Side effect: some quoted routes are now honest long laps. For example, the careful passenger's routes are now 0.27–1.16 km.

## GRAPHICS PROFILE FOUNDATION

`GraphicsProfile` Resources LOW / MEDIUM / HIGH (`docs/graphics_profiles.md`):
- LOW: no shadows, render scale 0.85, 30 FPS cap.
- MEDIUM: shadows to 60 m, 60 FPS cap.
- HIGH: the v0.02 look, uncapped.

Defaults: MEDIUM on mobile, HIGH on desktop. There is no settings menu yet.

## APK

| | |
|---|---|
| Path | `builds/android/tuktukcolombo-debug.apk` (git-ignored; not committed) |
| Size | 80 MB (84 216 197 bytes); 76 MB of it is the debug engine library `libgodot_android.so` |
| SHA-256 | `585b014bebf43c957581b29d20d3e0c2b268002d9a577aff200330f52d1a67ad` |
| Verified with aapt2 / apksigner | package `com.chavensl.tuktukcolombo` · versionName 0.0.3a / code 3 · minSdk 28 · targetSdk 35 · native-code arm64-v8a · landscape · no `uses-permission` · debuggable · signed `CN=Android Debug` |

## REAL DEVICE

**Not tested — no adb device connected** (`adb devices` returned an empty list).

## DEVICE PERFORMANCE RESULTS

**PENDING.** The 5-minute deterministic test is ready. It runs the normal world with fixed seeds, driven by the autopilot. Start it with `tools/android_perf_test.sh`, or from the pause menu → *Performance test (5 min)*.

A desktop smoke run (`-- --perf-test=20`, M2) wrote a complete summary:
- 59.3 FPS average, p5 59.4, worst second 49.5 (start-up);
- frame time 16.9 ms average;
- 12–14 traffic and 9–11 people;
- 151 draw calls on average;
- 97 MB peak static memory.

## ADB / LOGCAT FINDINGS

None yet (no device). On a device, use `adb logcat -s godot:V`. The perf test logs one `[PerfMonitor]` JSON line.

## DESKTOP REGRESSION PERFORMANCE

Measured with a windowed 60 s soak (`--perf`, Apple M2). Both versions were measured on the same machine, the same day, with the editor open:

| Build | FPS | gameplay CPU (physics) mean | human AI mean |
|---|---|---|---|
| v0.02 HEAD (re-measured today) | 60.3 / 60.0 | 3.03 / 3.24 ms | 0.136 / 0.142 ms |
| v0.03A | 60.4 / 60.2 / 60.1 | 2.99 / 3.43 / 3.35 ms | 0.121–0.135 ms |

There is **no material change** from v0.03A: it is within run-to-run noise of v0.02 measured today. Today's absolute numbers are higher than the 1.74 ms in the v0.02 report because of the machine's current load (the Godot editor and Gradle daemons were running), not the code. Draw calls were 209.

## AUTOMATED TEST RESULTS

`tools/run_tests.sh`: **ALL 10 STAGES PASS.**

| Stage | Result |
|---|---|
| Unit | PASS — **80 tests / 765 assertions** (was 61 / 545) |
| Vehicle handling | PASS (unchanged) |
| Vehicle dynamics v0.01a | PASS (unchanged) |
| Scoring scenarios | PASS |
| Human world + passengers | PASS |
| Input smoke (keyboard) | PASS |
| Mobile touch + lifecycle | PASS — new |
| Mobile touch (forced) | PASS — new |
| Traffic + humans soak (driving, 6 min) | PASS |
| Traffic + humans soak (junction, 6 min) | PASS |

New coverage:
- Touch mapper: dead zone, clamp, symmetry, quick reversal.
- Multitouch: steer + GO, steer + BRAKE, slide-off, no stolen steering, taps, cancel_all, ignoring touches outside controls.
- Layout: 5 resolutions × 4 safe areas, thumb zones, cutout shifting, opacity band.
- Export preset: package, SDKs, ABIs, no permissions, no release signing.
- Project settings: Back never quits, landscape, touch override off by default.
- Input-mode selection and graphics-profile loading.
- Qualitative mood.
- Real-scene scenarios: desktop default, touch-mode swap, driving by touch, horn, pause, Back ×2, focus loss, accept by touch, and the route-direction regression.

## MANUAL TEST RESULTS

Desktop only:
- Forced-touch screenshots at all 5 aspect ratios: controls clear of each other and of the road ahead; speed and score readable.
- One capture showed the focus-loss pause triggering correctly when the test window was unfocused.
- Desktop keyboard play is unchanged: the input smoke test passes, and the touch HUD is hidden.
- **Phone handling, thumb comfort, readability on a real screen and heat have not been judged** — they need the owner's playtest.

## KNOWN ISSUES

- No real-device test or performance baseline yet.
- The debug APK is 80 MB, almost all of it the debug engine. A release build will be much smaller (out of scope).
- The graphics tier is not yet chosen per device, and there is no settings menu.
- No haptics. The hook point is documented; it would need the VIBRATE permission, which was deliberately not requested.
- Sinhala/Tamil still fall back to English for the new strings. No Sinhala/Tamil font is shipped.
- The pause button glyph is the text "II", a placeholder.
- Some quoted routes are long laps now that pickups face legal directions. The test track has few turn-around options.
- Zebra-crossing yield improvement was not attempted (it was secondary, and not clearly safe without changing traffic behaviour).
- With `emulate_touch_from_mouse` on, desktop mouse clicks also generate touch events. They are ignored unless touch mode is forced.

## OWNER ANDROID PLAYTEST QUESTIONS

1. Does steering feel as precise on touch as it did with keyboard?
2. Can you instantly swerve left-right without fighting the virtual control?
3. Is the steering control comfortable for several minutes?
4. Are accelerator and brake easy to hold while steering?
5. Can you recover a two-wheel moment reliably using touch?
6. Are any controls blocking important traffic visibility?
7. Is ACCEPT RIDE obvious and easy to use?
8. Is passenger information readable on the phone?
9. Does the game feel responsive or is there noticeable input latency?
10. Does the phone become obviously hot or performance degrade during 10–15 minutes?
11. Do pedestrians and traffic remain smooth?
12. Would you personally prefer the steering control larger, smaller or unchanged?

## NEXT RECOMMENDED STEP

Connect an Android phone with USB debugging enabled, then run:

```bash
tools/install_android_debug.sh
tools/android_perf_test.sh
```

Then play for 10–15 minutes and answer the 12 questions. v0.03B (device-tuned touch feel, per-device graphics tier) should be planned from those answers and the device numbers. **Not started.**
