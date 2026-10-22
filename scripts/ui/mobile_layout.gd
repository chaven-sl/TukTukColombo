class_name MobileLayout
extends RefCounted
## Pure responsive layout for the touch controls. Given the logical viewport
## size and the safe area (cutouts/gesture bars removed), returns one Rect2
## per control. All anchoring is relative to the safe rect — never raw screen
## corners — and sizes scale gently with available height.
##
##   left thumb:  steering pad (bottom-left)
##   right thumb: accelerator (bottom-right), brake inboard of it, horn above
##   top-left:    pause (small, away from the driving thumbs)
##   right-mid:   contextual ACCEPT RIDE (only shown when available)


static func compute(viewport: Vector2, safe: Rect2, cfg: TouchControlsConfig) -> Dictionary:
	var pad := cfg.edge_padding
	var area := Rect2(safe.position + Vector2(pad, pad), safe.size - Vector2(pad, pad) * 2.0)
	var s := clampf(area.size.y / (720.0 - pad * 2.0), 0.8, 1.25)
	var r := {}
	var C := TouchControlState.Pad

	var steer_w := clampf(viewport.x * cfg.steer_pad_width_fraction, cfg.steer_pad_min_width, cfg.steer_pad_max_width) * s
	steer_w = minf(steer_w, area.size.x * 0.34)
	var steer_h := cfg.steer_pad_height * s
	r[C.STEER] = Rect2(Vector2(area.position.x, area.end.y - steer_h), Vector2(steer_w, steer_h))

	var acc := cfg.accelerator_size * s
	var acc_rect := Rect2(Vector2(area.end.x - acc.x, area.end.y - acc.y), acc)
	r[C.ACCELERATE] = acc_rect
	var brk := cfg.brake_size * s
	r[C.BRAKE] = Rect2(Vector2(acc_rect.position.x - cfg.control_gap * s - brk.x, area.end.y - brk.y), brk)
	var horn := cfg.horn_size * s
	r[C.HORN] = Rect2(Vector2(acc_rect.end.x - horn.x, acc_rect.position.y - cfg.control_gap * s - horn.y), horn)
	var pause := cfg.pause_size * s
	r[C.PAUSE] = Rect2(area.position, pause)
	var accept := cfg.accept_size * s
	var accept_bottom: float = (r[C.HORN] as Rect2).position.y - cfg.control_gap * s
	r[C.ACCEPT] = Rect2(Vector2(area.end.x - accept.x, accept_bottom - accept.y), accept)
	return r


## Safe area from the display, converted into logical viewport units.
static func safe_rect_for(viewport: Viewport) -> Rect2:
	var visible := viewport.get_visible_rect()
	var screen_safe := DisplayServer.get_display_safe_area()
	var window_size := Vector2(DisplayServer.window_get_size())
	if window_size.x <= 0.0 or window_size.y <= 0.0 or screen_safe.size.x <= 0:
		return visible
	var window_pos := Vector2(DisplayServer.window_get_position())
	var scale := visible.size / window_size
	var local := Rect2((Vector2(screen_safe.position) - window_pos) * scale, Vector2(screen_safe.size) * scale)
	var clipped := local.intersection(visible)
	return clipped if clipped.has_area() else visible


## Validation used by tests: every rect inside the safe rect, minimum sizes,
## and no overlaps between any two controls.
static func problems(viewport: Vector2, safe: Rect2, rects: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var keys := rects.keys()
	for k in keys:
		var rect: Rect2 = rects[k]
		var name: String = TouchControlState.Pad.keys()[k]
		if not safe.encloses(rect):
			out.append("%s outside safe area" % name)
		if rect.size.x < 60.0 or rect.size.y < 56.0:
			out.append("%s too small (%s)" % [name, rect.size])
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: Rect2 = rects[keys[i]]
			var b: Rect2 = rects[keys[j]]
			if a.intersects(b):
				out.append("%s overlaps %s" % [TouchControlState.Pad.keys()[keys[i]], TouchControlState.Pad.keys()[keys[j]]])
	return out
