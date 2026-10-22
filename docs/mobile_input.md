# Mobile input (v0.03A)

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
| Steering pad | bottom-left (left thumb) | analog −1…+1 from horizontal thumb offset to the pad centre; the finger that lands first owns steering until it lifts, even if it slides off the pad |
| GO (accelerator) | bottom-right | hold = full throttle |
| BRAKE / reverse | inboard of GO | hold = brake, then reverse (same as keyboard) |
| HORN | above GO | tap → `EventBus.horn_sounded` (same as H) |
| ACCEPT RIDE | right, above HORN | shown only while a passenger offer is in range; tap → `RideManager.request_accept()` (same as E) |
| II (pause) | top-left, away from thumbs | tap → pause |

Multitouch: every finger is tracked by index; steer + GO and steer + BRAKE
work together. Taps on horn/accept/pause never disturb held controls.

## Steering mapping (`TouchSteeringMapper`, tunables in `resources/input/touch_controls.tres`)

`n = clamp(offset / (half_width × full_lock_fraction), −1, 1)`;
`|n| < dead_zone → 0`; otherwise `sign · ((|n| − dz)/(1 − dz))^exponent`.

| Tunable | Value | Why |
|---|---|---|
| `steer_dead_zone` | 0.08 | resting thumb jitter doesn't steer |
| `steer_exponent` | 1.15 | mostly linear, mild centre softening for lane corrections |
| `full_lock_fraction` | 0.85 | full lock before the pad edge, so quick countersteer isn't limited by thumb travel |

No smoothing is added in the input layer: release snaps the *input* to 0 and
reversal is instantaneous, exactly like the keyboard. The return of the
wheels is the vehicle's existing steering rate (locked MVP handling baseline).

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
