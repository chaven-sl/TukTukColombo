class_name HudSafeArea
extends Control
## Root container for HUD content (v0.03A2). Sits exactly on the device's
## usable safe rectangle (cutouts, rounded corners, gesture bars removed),
## inset by an inner margin, so every child anchored to it is automatically
## inside the safe area at any aspect ratio. The touch controls use the same
## safe rect (safe_rect()) so the whole HUD shares one alignment.
##
## Testing / screenshots: simulated insets via HudSafeArea.simulated_insets
## (logical units: left, top, right, bottom) or `-- --simulate-safe-area=L,T,R,B`.

const MARGIN := 24.0

## Logical-unit insets added on top of the display safe area (tests, CLI).
static var simulated_insets := Vector4.ZERO
static var _cli_checked := false

var margin := MARGIN


static func _check_cli() -> void:
	if _cli_checked:
		return
	_cli_checked = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--simulate-safe-area="):
			var parts := arg.get_slice("=", 1).split(",")
			if parts.size() == 4:
				simulated_insets = Vector4(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]))


## Usable rectangle in logical viewport units (display safe area ∩ simulation).
static func safe_rect(viewport: Viewport) -> Rect2:
	_check_cli()
	var r := MobileLayout.safe_rect_for(viewport)
	return apply_insets(r, simulated_insets)


static func apply_insets(r: Rect2, insets: Vector4) -> Rect2:
	return Rect2(r.position + Vector2(insets.x, insets.y), r.size - Vector2(insets.x + insets.z, insets.y + insets.w))


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	get_viewport().size_changed.connect(refresh)
	refresh()


func refresh() -> void:
	apply_safe_rect(safe_rect(get_viewport()))


## Separate so tests can lay the HUD out for any safe rect.
func apply_safe_rect(safe: Rect2) -> void:
	var inner := safe.grow(-margin)
	position = inner.position
	size = inner.size
