class_name SignAtlas
extends Node
## All environment signage text in ONE 1024² texture (v0.03B art budget:
## "signage: 1 × 1024 atlas"). Signs are registered as specs, packed into
## shelves, rendered once by a SubViewport with UiFonts (Sinhala/Tamil
## fallbacks), then copied into a mipmapped ImageTexture. Sign quads in the
## district chunks sample this one material.
##
## Spec: {"lines": [[text, size_px, Color]...], "bg": Color, "border": Color,
##        "px": Vector2i (cell size)}

const SIZE := 1024

var material: StandardMaterial3D
var _specs: Array = []
var _rects: Array[Rect2i] = []
var _shelf_x := 0
var _shelf_y := 0
var _shelf_h := 0
var _viewport: SubViewport


func _init() -> void:
	material = StandardMaterial3D.new()
	material.roughness = 0.75
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## Returns the UV rect for the sign (call before build()).
func add(spec: Dictionary) -> Rect2:
	var px: Vector2i = spec.get("px", Vector2i(256, 64))
	if _shelf_x + px.x > SIZE:
		_shelf_x = 0
		_shelf_y += _shelf_h + 2
		_shelf_h = 0
	if _shelf_y + px.y > SIZE:
		push_warning("[SignAtlas] full; reusing the first cell")
		return Rect2(Vector2.ZERO, Vector2(_rects[0].size) / SIZE) if not _rects.is_empty() else Rect2()
	var r := Rect2i(_shelf_x, _shelf_y, px.x, px.y)
	_shelf_x += px.x + 2
	_shelf_h = maxi(_shelf_h, px.y)
	_specs.append(spec)
	_rects.append(r)
	# Inset half a texel against bleeding.
	return Rect2((Vector2(r.position) + Vector2(0.5, 0.5)) / SIZE, (Vector2(r.size) - Vector2.ONE) / SIZE)


func used_fraction() -> float:
	return float(_shelf_y + _shelf_h) / float(SIZE)


func build() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.transparent_bg = false
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	var root := ColorRect.new()
	root.color = Color(0.5, 0.5, 0.5)
	root.size = Vector2(SIZE, SIZE)
	_viewport.add_child(root)
	for i in _specs.size():
		_draw_sign(root, _specs[i], _rects[i])
	material.albedo_texture = _viewport.get_texture()
	if DisplayServer.get_name() != "headless":
		_bake.call_deferred()


func _draw_sign(root: Control, spec: Dictionary, r: Rect2i) -> void:
	var panel := Panel.new()
	panel.position = Vector2(r.position)
	panel.size = Vector2(r.size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = spec.get("bg", Color(0.95, 0.92, 0.85))
	var border: Color = spec.get("border", sb.bg_color.darkened(0.3))
	sb.border_color = border
	sb.set_border_width_all(maxi(2, r.size.y / 24))
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.position = Vector2(r.position) + Vector2(4, 2)
	box.size = Vector2(r.size) - Vector2(8, 4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	root.add_child(box)
	for line: Array in spec.get("lines", []):
		var l := Label.new()
		l.text = line[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", UiFonts.heavy() if line.size() < 4 or line[3] else UiFonts.base())
		l.add_theme_font_size_override("font_size", line[1])
		l.add_theme_color_override("font_color", line[2])
		l.clip_text = true
		box.add_child(l)


## Copy the one-off render into a mipmapped texture (crisper at distance).
func _bake() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _viewport.get_texture().get_image()
	if img == null or img.is_empty():
		return
	img.generate_mipmaps()
	material.albedo_texture = ImageTexture.create_from_image(img)
	_viewport.queue_free()
	_viewport = null
