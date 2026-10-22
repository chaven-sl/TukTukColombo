class_name InputMode
extends RefCounted
## Decides which human input source drives the tuk. Gameplay never asks
## "am I on Android?" — it asks this once and wires keyboard OR touch.
##
## Touch when: forced (developer override) or the platform is mobile. Overrides, any of:
##   project setting  tuktuk/dev/force_touch_controls = true
##   command line     -- --force-touch-controls

const SETTING := "tuktuk/dev/force_touch_controls"
const CLI_FLAG := "--force-touch-controls"


static func is_forced() -> bool:
	if ProjectSettings.has_setting(SETTING) and bool(ProjectSettings.get_setting(SETTING)):
		return true
	if OS.get_cmdline_user_args().has(CLI_FLAG):
		return true
	return false


static func wants_touch(forced: bool = is_forced()) -> bool:
	if forced:
		return true
	# Not DisplayServer.is_touchscreen_available(): it reports true whenever
	# emulate_touch_from_mouse is on, and touchscreen laptops keep the keyboard.
	return OS.has_feature("mobile") or OS.has_feature("android")
