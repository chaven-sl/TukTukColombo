extends "res://tests/test_case.gd"
## Touch layout at the required device aspect ratios, with and without
## simulated cutouts / gesture bars. Logical sizes follow canvas_items/expand
## stretching from the 1280×720 base (height 720 unless the screen is taller
## than 16:9).

## device px -> logical viewport
const DEVICES := {
	"1920x1080": Vector2(1280, 720),
	"2400x1080": Vector2(1600, 720),
	"2340x1080": Vector2(1560, 720),
	"2520x1080": Vector2(1680, 720),
	"1280x800": Vector2(1280, 800),
}

var _cfg: TouchControlsConfig = load("res://resources/input/touch_controls.tres")


func _safe_variants(view: Vector2) -> Dictionary:
	return {
		"full": Rect2(Vector2.ZERO, view),
		"left cutout": Rect2(Vector2(48, 0), view - Vector2(48, 0)),
		"right cutout": Rect2(Vector2.ZERO, view - Vector2(48, 0)),
		"both + gesture bar": Rect2(Vector2(40, 0), view - Vector2(80, 24)),
	}


func test_layout_valid_on_all_devices_and_safe_areas() -> void:
	for device in DEVICES:
		var view: Vector2 = DEVICES[device]
		var variants := _safe_variants(view)
		for v in variants:
			var safe: Rect2 = variants[v]
			var rects := MobileLayout.compute(view, safe, _cfg)
			var problems := MobileLayout.problems(view, safe, rects)
			check(problems.is_empty(), "%s / %s: %s" % [device, v, ", ".join(problems)])


func test_thumb_zones() -> void:
	for device in DEVICES:
		var view: Vector2 = DEVICES[device]
		var rects := MobileLayout.compute(view, Rect2(Vector2.ZERO, view), _cfg)
		var steer: Rect2 = rects[TouchControlState.Pad.STEER]
		var acc: Rect2 = rects[TouchControlState.Pad.ACCELERATE]
		var brk: Rect2 = rects[TouchControlState.Pad.BRAKE]
		check(steer.end.x < view.x * 0.4, "%s steering pad on the left" % device)
		check(acc.position.x > view.x * 0.75 and brk.position.x > view.x * 0.6, "%s pedals on the right" % device)
		check(steer.end.y > view.y * 0.8 and acc.end.y > view.y * 0.8, "%s thumbs near the bottom" % device)
		check(acc.size.x >= 120.0 and acc.size.y >= 160.0, "%s accelerator is large (%s)" % [device, acc.size])
		check(brk.size.x >= 110.0 and brk.size.y >= 120.0, "%s brake is large (%s)" % [device, brk.size])
		check(steer.size.x >= 280.0, "%s steering pad wide enough (%.0f)" % [device, steer.size.x])
		var pause: Rect2 = rects[TouchControlState.Pad.PAUSE]
		check(pause.position.y < view.y * 0.2 and pause.position.x < view.x * 0.2, "%s pause top-left" % device)


func test_controls_move_with_cutouts() -> void:
	var view := Vector2(1600, 720)
	var full := MobileLayout.compute(view, Rect2(Vector2.ZERO, view), _cfg)
	var cut := MobileLayout.compute(view, Rect2(Vector2(60, 0), view - Vector2(120, 0)), _cfg)
	check_near((cut[TouchControlState.Pad.STEER] as Rect2).position.x - (full[TouchControlState.Pad.STEER] as Rect2).position.x, 60.0, 0.5, "steering pad shifts right of a left cutout")
	check_near((full[TouchControlState.Pad.ACCELERATE] as Rect2).end.x - (cut[TouchControlState.Pad.ACCELERATE] as Rect2).end.x, 60.0, 0.5, "accelerator shifts left of a right cutout")


func test_opacity_in_required_band() -> void:
	check(_cfg.idle_opacity >= 0.45 and _cfg.idle_opacity <= 0.65, "idle opacity 45–65%% (%.2f)" % _cfg.idle_opacity)
	check(_cfg.pressed_opacity > _cfg.idle_opacity, "pressed state is brighter")
