# Mobile input (v0.03A, steering revised in v0.03A1)

```
MobileControls (CanvasLayer, raw ScreenTouch/Drag)
      │  fills
TouchControlState (pure logic, unit tested)
      │  copied each physics tick by
TouchInputSource ──► VehicleInputState ──► TukController   (unchanged physics)
PlayerInputSource (keyboard) ──┘   only ONE of the two is enabled
```

`InputMode.wants_touch()` decides once at startup: touch on Android/mobile,
keyboard elsewhere. Developer override: project setting
`tuktuk/dev/force_touch_controls=true` or `-- --force-touch-controls`.
`input_devices/pointing/emulate_touch_from_mouse` is on so forced touch can be
tried with a mouse on desktop (one finger only).

## Controls

| Control | Where | Behaviour |
|---|---|---|
| Steering pad | bottom-left (left thumb) | **floating origin** (v0.03A1): touch-down anywhere on the pad = exactly 0; analog −1…+1 from the horizontal offset to where the thumb landed; the finger that lands first owns steering until it lifts, even if it slides off the pad |
| GO (accelerator) | bottom-right | hold = full throttle |
| BRAKE / reverse | inboard of GO | hold = brake, then reverse (same as keyboard) |
| HORN | above GO | tap → `EventBus.horn_sounded` (same as H) |
| ACCEPT HIRE | right, above HORN | shown only while a hire is offered (card top-left names it); tap → `RideManager.request_accept()` (same as E) |
| II (pause) | top-left, away from thumbs | tap → pause |

Multitouch: every finger is tracked by index; steer + GO and steer + BRAKE
work together. Taps on horn/accept/pause never disturb held controls.

## Steering mapping (`TouchSteeringMapper`, tunables in `resources/input/touch_controls.tres`)

**v0.03A1 fix — owner playtest "steering drifts slightly right".** v0.03A
mapped the thumb's absolute x against the fixed pad centre, so a thumb resting
a few millimetres right of the visual centre steered right. Now:

```
touch-down        → origin = thumb x, steer = 0.0 exactly
drag              → offset = x − origin
                    n = clamp(offset / steer_full_lock_travel, −1, 1)
                    |n| ≤ dead_zone → 0, else sign · ((|n| − dz)/(1 − dz))^exponent
release / cancel  → steer = 0.0, offset = 0
```

| Tunable | Value | Why |
|---|---|---|
| `steer_full_lock_travel` | 120 logical units (≈ 1/6 of the screen height) | small movement = fine correction, ~half travel = urban steering (~0.45), full travel = full lock |
| `steer_dead_zone` | 0.10 of the travel (12 units) | thumb jitter while resting never steers |
| `steer_exponent` | 1.15 | mostly linear, mild centre softening |

Travel is measured from the origin, not limited by the pad edges, so it is
always symmetric left/right even when the thumb lands near an edge. The
visual travel guide + knob are drawn around the origin (nudged inside the pad
near its edges). No smoothing is added in the input layer: reversal is
instantaneous and release snaps the *input* to 0, exactly like the keyboard;
the wheels return at the vehicle's existing steering rate (locked baseline).

**Real-device check:** place your thumb naturally on the steering control and
hold it still for 10 seconds — the tuk should track straight unless the road
or physics genuinely disturbs it.

## Lifecycle

| Event | Result |
|---|---|
| Android Back in gameplay | pause |
| Android Back on pause screen | resume (`application/config/quit_on_go_back=false` — Back never quits) |
| Focus loss / app paused | pause, release all touches; **no auto-resume**; ride state and save untouched (GameState flushes stats on app pause as before) |
| Pause (any reason) | all held touches cancelled so nothing stays pressed on resume |

## Layout

`MobileLayout.compute(viewport, safe_area, config)` — pure, tested on
1920×1080, 2400×1080, 2340×1080, 2520×1080 and 1280×800, each with no
cutout, left/right cutouts and a gesture bar. Everything is placed relative
to `DisplayServer.get_display_safe_area()` converted to logical units. Checks:
inside the safe area, ≥ 60×56 units, no overlaps. Idle opacity 0.5, pressed
0.78. In touch mode the HUD moves the score right of the pause button and
lifts the speed readout above the steering pad.

Haptics: not implemented (hook point = `MobileControls._dispatch_taps` and
press handling; `Input.vibrate_handheld()` would need the VIBRATE permission,
deliberately not requested yet).
