class_name UiFonts
extends RefCounted
## Project typography (v0.03B): Noto Sans (Latin) with Noto Sans Sinhala and
## Noto Sans Tamil fallbacks — official Google Fonts releases under the SIL
## Open Font License (licences in assets/fonts/*/OFL.txt). Used by the HUD and
## the environment signage so English, Sinhala and Tamil all render.

static var _base: Font = null
static var _bold: Font = null
static var _heavy: Font = null


static func base() -> Font:
	if _base == null:
		var latin := load("res://assets/fonts/noto_sans/NotoSans.ttf") as FontFile
		var sinhala := load("res://assets/fonts/noto_sans_sinhala/NotoSansSinhala.ttf") as FontFile
		var tamil := load("res://assets/fonts/noto_sans_tamil/NotoSansTamil.ttf") as FontFile
		if latin == null:
			return ThemeDB.fallback_font
		var fb: Array[Font] = []
		if sinhala != null:
			fb.append(sinhala)
		if tamil != null:
			fb.append(tamil)
		latin.fallbacks = fb
		_base = latin
	return _base


## Variable-font weight instance (Regular 400 … Black 900).
static func weight(w: int) -> Font:
	var v := FontVariation.new()
	v.base_font = base()
	var ts := TextServerManager.get_primary_interface()
	v.variation_opentype = {ts.name_to_tag("wght"): w}
	return v


static func bold() -> Font:
	if _bold == null:
		_bold = weight(700)
	return _bold


static func heavy() -> Font:
	if _heavy == null:
		_heavy = weight(800)
	return _heavy
