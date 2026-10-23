class_name Garage
extends Node3D
## v0.04 HOME / GARAGE — the first non-driving screen. Cheap by design: a
## dim Colombo workshop impression built from a few boxes, the hero tuk
## (the same HeroTukVisual, no physics body) on a slowly turning floor, and
## the upgrade UI around it. Shows cash, reputation, career level, the four
## upgrade categories with relative bars, and DRIVE.
##
## Purchases go through GameState.purchase_upgrade (atomic, saved at once,
## guarded against double taps by the expected level).

const DRIVE_SCENE := "res://scenes/districts/fort_pettah/fort_pettah_slice.tscn"
const WALL := Color(0.2, 0.19, 0.18)
const SHEET := Color(0.27, 0.28, 0.29)

var selected: StringName = &"engine"
var tuk_root: Node3D
var hero: HeroTukVisual
var camera: Camera3D
var _cards: Dictionary = {}  # id -> {"button", "pips", "cost"}
var _stat_bars: Dictionary = {}  # id -> HBoxContainer of segment ColorRects
var _cash: Label
var _rep: Label
var _level: Label
var _level_bar: ProgressBar
var _title: Label
var _desc: Label
var _current: Label
var _next: Label
var _improve: Label
var _cost: Label
var _buy: Button
var _need: Label
var _debug: Label
var _summary: PanelContainer
var _drive: Button
var _pulse := 0.0
var _busy := false
var _sfx: AudioStreamPlayer
var _spin := 0.0


func _ready() -> void:
	_build_world()
	_build_ui()
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = &"UI"
	add_child(_sfx)
	GameState.career_changed.connect(_refresh)
	_refresh()
	if GameState.has_session_summary:
		_show_summary()


# --- world ---

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.045, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.48, 0.4)
	e.ambient_light_energy = 0.22
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.1
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.86, 0.66)
	key.light_energy = 0.75
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 14.0
	key.rotation = Vector3(deg_to_rad(-62.0), deg_to_rad(28.0), 0.0)
	add_child(key)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.55, 0.7, 0.8)
	fill.light_energy = 0.8
	fill.omni_range = 9.0
	fill.position = Vector3(-3.5, 2.6, 2.5)
	add_child(fill)
	var bulb := OmniLight3D.new()  # warm work light over the tuk
	bulb.light_color = Color(1.0, 0.78, 0.45)
	bulb.light_energy = 2.6
	bulb.omni_range = 6.0
	bulb.omni_attenuation = 1.6
	bulb.position = Vector3(0.6, 3.2, -0.5)
	add_child(bulb)
	var m := ArtMesh.new()
	var g := ArtMesh.new()
	var I := Transform3D.IDENTITY
	m.box(I, Vector3(0, -0.05, 0), Vector3(14, 0.1, 12), Color(0.17, 0.165, 0.16))  # concrete floor
	for k in 6:  # oil stains / patches
		m.box(I, Vector3(-4.0 + k * 1.7, 0.003, -1.0 + (k % 3) * 1.4), Vector3(1.1, 0.002, 0.8), Color(0.11, 0.105, 0.1), 4)
	m.cylinder(I, Vector3(0, 0.03, 0), 2.1, 0.06, 40, Color(0.12, 0.12, 0.13))  # turntable
	m.lathe(I, PackedVector2Array([Vector2(2.12, 0.064), Vector2(2.0, 0.064)]), 48, Color(0.75, 0.6, 0.2))  # painted rim ring
	m.box(I, Vector3(0, 2.5, -4.5), Vector3(14, 5, 0.2), WALL)  # back wall
	for k in 28:  # corrugated sheet ribs
		m.box(I, Vector3(-6.75 + k * 0.5, 2.5, -4.38), Vector3(0.08, 5, 0.06), SHEET)
	m.box(I, Vector3(-6.0, 2.5, 0.0), Vector3(0.2, 5, 9), WALL.darkened(0.15))  # side wall
	m.box(I, Vector3(-3.6, 0.9, -3.8), Vector3(3.0, 0.08, 1.0), Color(0.42, 0.3, 0.2))  # workbench
	for sx: float in [-4.9, -2.3]:
		m.box(I, Vector3(sx, 0.45, -3.8), Vector3(0.08, 0.9, 0.9), Color(0.25, 0.2, 0.15))
	m.box(I, Vector3(-3.6, 2.2, -4.35), Vector3(2.6, 1.4, 0.05), Color(0.55, 0.45, 0.3))  # tool board
	for k in 7:
		m.box(I, Vector3(-4.6 + k * 0.33, 2.2, -4.3), Vector3(0.05, 0.6 + (k % 3) * 0.2, 0.04), Color(0.6, 0.62, 0.64))
	for k in 4:  # tyre stack
		g.lathe(Transform3D(Basis.IDENTITY, Vector3(4.4, 0.12 + k * 0.24, -3.4)), PackedVector2Array([Vector2(0.14, -0.1), Vector2(0.3, -0.12),
				Vector2(0.34, 0.0), Vector2(0.3, 0.12), Vector2(0.14, 0.1)]), 16, Color(0.07, 0.07, 0.075))
	m.cylinder(I, Vector3(5.2, 0.45, -2.2), 0.3, 0.9, 14, Color(0.15, 0.32, 0.55))  # oil drum
	m.cylinder(I, Vector3(0.6, 3.6, -0.5), 0.12, 0.2, 10, Color(0.15, 0.15, 0.15))  # lamp shade
	var mesh := ArrayMesh.new()
	m.commit(ArtMaterials.get_material(&"plaster"), mesh)
	g.commit(ArtMaterials.get_material(&"rubber"), mesh)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	var sign := Label3D.new()  # fictional workshop name
	sign.text = "PERERA TUK WORKS"
	sign.font = UiFonts.heavy()
	sign.font_size = 96
	sign.pixel_size = 0.006
	sign.modulate = Color(1.0, 0.82, 0.3)
	sign.outline_size = 0
	sign.font_size = 72
	sign.position = Vector3(-0.4, 3.2, -4.3)
	add_child(sign)
	_build_tuk()
	camera = Camera3D.new()
	camera.fov = 50.0
	add_child(camera)
	camera.look_at_from_position(Vector3(3.3, 2.1, 4.6), Vector3(0.6, 0.85, 0.0))
	camera.current = true


## The hero tuk without a physics body: the same art on the same wheel
## hook layout (FrontSteer / RearLeft / RearRight) as player_tuk.tscn.
func _build_tuk() -> void:
	tuk_root = Node3D.new()
	tuk_root.name = "TukDisplay"
	add_child(tuk_root)
	var visual := Node3D.new()
	visual.name = "Visual"
	tuk_root.add_child(visual)
	for spec: Array in [["FrontSteer", Vector3(0, 0.21, -1.0)], ["RearLeft", Vector3(-0.575, 0.21, 1.0)], ["RearRight", Vector3(0.575, 0.21, 1.0)]]:
		var mount := Node3D.new()
		mount.name = spec[0]
		mount.position = spec[1]
		visual.add_child(mount)
		var spin := Node3D.new()
		spin.name = "Spin"
		mount.add_child(spin)
	hero = HeroTukVisual.new()
	hero.name = "HeroArt"
	visual.add_child(hero)
	tuk_root.rotation.y = deg_to_rad(-30.0)


func _process(delta: float) -> void:
	_spin += delta * 0.18
	tuk_root.rotation.y = deg_to_rad(-30.0) + sin(_spin) * 0.35
	if _pulse > 0.0:  # mechanical pulse after a purchase
		_pulse = maxf(_pulse - delta, 0.0)
		var k := sin((1.0 - _pulse / 0.6) * PI) * 0.035
		tuk_root.scale = Vector3.ONE * (1.0 + k)
		tuk_root.position.y = k * 1.5
	(hero.get_parent().get_node("FrontSteer") as Node3D).rotation.y = sin(_spin * 2.2) * 0.25


# --- UI ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var t := Theme.new()
	t.default_font = UiFonts.weight(600)
	var root := HudSafeArea.new()
	root.theme = t
	layer.add_child(root)
	# Top bar: cash, reputation, career level + progress.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 26)
	PrototypeHud.place(top, Vector2(0, 0), Rect2(0, 0, 900, 54))
	root.add_child(top)
	_cash = _label(top, 30, Color(1.0, 0.9, 0.55))
	_rep = _label(top, 30, Color(1.0, 0.8, 0.3))
	var lv := VBoxContainer.new()
	top.add_child(lv)
	_level = _label(lv, 18, Color(0.9, 0.92, 0.95))
	_level_bar = ProgressBar.new()
	_level_bar.custom_minimum_size = Vector2(260, 8)
	_level_bar.show_percentage = false
	lv.add_child(_level_bar)
	# Left: the four upgrade cards.
	var cards := VBoxContainer.new()
	cards.add_theme_constant_override("separation", 10)
	PrototypeHud.place(cards, Vector2(0, 0), Rect2(0, 76, 300, 430))
	root.add_child(cards)
	for def in UpgradeCatalog.all():
		var b := Button.new()
		b.custom_minimum_size = Vector2(300, 92)
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.position = Vector2(14, 8)
		b.add_child(v)
		var name := _label(v, 20, Color(1, 1, 1))
		name.text = tr(def.display_key)
		var pips := _label(v, 18, Color(0.35, 0.85, 0.85))
		var cost := _label(v, 15, Color(0.85, 0.85, 0.8))
		var id := def.id
		b.pressed.connect(func() -> void: _select(id))
		cards.add_child(b)
		_cards[id] = {"button": b, "pips": pips, "cost": cost}
	# Right: detail panel for the selected upgrade.
	var panel := _panel(root, Vector2(1, 0), Rect2(-380, 76, 380, 380))
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 6)
	panel.add_child(dv)
	_title = _label(dv, 26, Color(1.0, 0.86, 0.4))
	_desc = _label(dv, 15, Color(0.82, 0.84, 0.86))
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(340, 0)
	_current = _label(dv, 18, Color(1, 1, 1))
	_next = _label(dv, 18, Color(0.55, 0.95, 0.8))
	_improve = _label(dv, 16, Color(0.75, 0.95, 0.75))
	_improve.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_improve.custom_minimum_size = Vector2(340, 0)
	_cost = _label(dv, 18, Color(1.0, 0.9, 0.55))
	_buy = Button.new()
	_buy.custom_minimum_size = Vector2(340, 64)
	_buy.add_theme_font_size_override("font_size", 22)
	_buy.pressed.connect(func() -> void: buy(selected))
	_style_button(_buy, Color(0.1, 0.55, 0.5))
	dv.add_child(_buy)
	_need = _label(dv, 16, Color(1.0, 0.6, 0.45))
	# Bottom left: relative stat bars (never raw physics values).
	var stats := VBoxContainer.new()
	PrototypeHud.place(stats, Vector2(0, 1), Rect2(0, -150, 380, 150))
	root.add_child(stats)
	for def in UpgradeCatalog.all():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		stats.add_child(row)
		var name := _label(row, 18, Color(0.92, 0.94, 0.96))
		name.text = tr(def.stat_key)
		name.custom_minimum_size = Vector2(150, 0)
		var cells := HBoxContainer.new()
		cells.add_theme_constant_override("separation", 4)
		cells.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cells)
		for k in def.max_level + 1:
			var cell := ColorRect.new()
			cell.custom_minimum_size = Vector2(26, 12)
			cells.add_child(cell)
		_stat_bars[def.id] = cells
	# Bottom right: DRIVE.
	_drive = Button.new()
	_drive.text = tr("UI_DRIVE")
	_drive.add_theme_font_size_override("font_size", 34)
	PrototypeHud.place(_drive, Vector2(1, 1), Rect2(-300, -96, 300, 96))
	_drive.pressed.connect(drive)
	_style_button(_drive, Color(0.85, 0.55, 0.08))
	root.add_child(_drive)
	_debug = _label(root, 13, Color(0.6, 0.62, 0.65))
	PrototypeHud.place(_debug, Vector2(1, 1), Rect2(-560, -126, 540, 24))
	_debug.visible = OS.is_debug_build()


func _style_button(b: Button, color: Color) -> void:
	for state: Array in [["normal", color], ["hover", color.lightened(0.12)], ["pressed", color.darkened(0.15)],
			["disabled", Color(0.22, 0.23, 0.24, 0.9)], ["focus", color]]:
		var st := StyleBoxFlat.new()
		st.bg_color = state[1]
		st.set_corner_radius_all(12)
		b.add_theme_stylebox_override(state[0], st)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_disabled_color", Color(0.6, 0.62, 0.64))


func _label(parent: Node, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _panel(parent: Control, anchor: Vector2, r: Rect2) -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.07, 0.72)
	st.set_corner_radius_all(12)
	st.border_width_bottom = 2
	st.border_color = Color(0.1, 0.62, 0.62, 0.85)
	st.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", st)
	PrototypeHud.place(p, anchor, r)
	parent.add_child(p)
	return p


static func bar(fraction: float, cells := 6) -> String:
	var n := roundi(clampf(fraction, 0.0, 1.0) * cells)
	return "■".repeat(n) + "□".repeat(cells - n)


func _select(id: StringName) -> void:
	selected = id
	_refresh()


func _refresh() -> void:
	var c := GameState.career
	var econ := GameState.economy
	_cash.text = EconomyFormat.rupees(c.cash())
	_rep.text = EconomyFormat.stars(c.reputation())
	var lvl := c.career_level()
	_level.text = "%s %d — %s" % [tr("UI_LEVEL"), lvl, tr(econ.career_name_keys[lvl - 1])]
	var lo := econ.career_thresholds[lvl - 1]
	var hi := c.next_level_reputation()
	_level_bar.value = 100.0 if hi < 0 else 100.0 * float(c.reputation() - lo) / float(maxi(hi - lo, 1))
	for def in UpgradeCatalog.all():
		var card: Dictionary = _cards[def.id]
		var level := c.level_of(def.id)
		(card["button"] as Button).button_pressed = def.id == selected
		(card["pips"] as Label).text = "%s  %s %d/%d" % ["●".repeat(level) + "○".repeat(def.max_level - level), tr("UI_LV"), level, def.max_level]
		var nc := c.next_cost(def.id)
		(card["cost"] as Label).text = tr("UI_MAX_LEVEL") if nc < 0 else EconomyFormat.rupees(nc)
		var cells: HBoxContainer = _stat_bars[def.id]
		var filled := roundi(EffectiveVehicleConfig.stat_fraction(c.upgrade_levels(), def.id) * cells.get_child_count())
		for k in cells.get_child_count():
			(cells.get_child(k) as ColorRect).color = Color(0.2, 0.75, 0.75) if k < filled else Color(0.18, 0.19, 0.2, 0.85)
	var d := UpgradeCatalog.get_def(selected)
	var cur := c.level_of(selected)
	var cost := c.next_cost(selected)
	_title.text = tr(d.display_key)
	_desc.text = tr(d.description_key)
	_current.text = "%s  %s %d" % [tr("UI_CURRENT"), tr("UI_LV"), cur]
	if cost < 0:
		_next.text = tr("UI_MAX_LEVEL")
		_improve.text = ""
		_cost.text = ""
		_buy.text = tr("UI_MAX_LEVEL")
		_buy.disabled = true
		_need.text = ""
	else:
		_next.text = "%s  %s %d" % [tr("UI_NEXT_LEVEL"), tr("UI_LV"), cur + 1]
		_improve.text = "%s  %s" % [tr("UI_IMPROVEMENT"), tr(d.improvement_key)]
		_cost.text = "%s  %s" % [tr("UI_COST"), EconomyFormat.rupees(cost)]
		_buy.text = tr("UI_UPGRADE_FOR") % EconomyFormat.rupees(cost)
		_buy.disabled = cost > c.cash() or _busy
		_need.text = "" if cost <= c.cash() else tr("UI_NEED_MORE") % EconomyFormat.rupees(cost - c.cash())
	_debug.text = "avg %s / ride · ~%d rides to next upgrade · %d rides" % [EconomyFormat.rupees(roundi(c.average_earnings())), c.rides_to_next_upgrade(), int(c.data["successful_rides"])]


## Buys the next level of `id` (UI and tests). Returns the purchase result.
func buy(id: StringName) -> CareerProfile.Purchase:
	if _busy:
		return CareerProfile.Purchase.STALE_REQUEST
	var r := GameState.purchase_upgrade(id, GameState.career.level_of(id))
	if r == CareerProfile.Purchase.OK:
		_busy = true  # one purchase per pulse: no double taps
		_pulse = 0.6
		_sfx.stream = AudioLibrary.get_stream("upgrade_clunk")
		_sfx.play()
		var bar_cells: HBoxContainer = _stat_bars[id]
		var tw := create_tween()
		bar_cells.modulate = Color(2.2, 2.2, 1.4)  # the new segment flashes in
		tw.tween_property(bar_cells, "modulate", Color.WHITE, 0.6)
		tw.tween_callback(func() -> void:
			_busy = false
			_refresh())
	_refresh()
	return r


func drive() -> void:
	_drive.disabled = true
	GameState.has_session_summary = false
	GameState.reset_session()
	get_tree().change_scene_to_file(DRIVE_SCENE)


func _show_summary() -> void:
	var gs := GameState
	_summary = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.04, 0.05, 0.06, 0.92)
	st.set_corner_radius_all(14)
	st.set_content_margin_all(24)
	_summary.add_theme_stylebox_override("panel", st)
	var root := _cash.get_parent().get_parent() as Control
	PrototypeHud.place(_summary, Vector2(0.5, 0.5), Rect2(-230, -190, 460, 380))
	root.add_child(_summary)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_summary.add_child(v)
	_label(v, 26, Color(1.0, 0.86, 0.4)).text = tr("UI_SESSION_SUMMARY")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	v.add_child(grid)
	for row: Array in [["UI_SESSION_CASH", EconomyFormat.rupees(gs.session_cash)], ["UI_RIDES_COMPLETED", str(gs.session_rides_completed)],
			["UI_REPUTATION_EARNED", "+" + EconomyFormat.stars(gs.session_reputation)], ["UI_BEST_COMBO", "x%d" % gs.session_best_chain],
			["UI_COLLISIONS", str(gs.session_collisions)], ["UI_PEDESTRIAN_INCIDENTS", str(gs.session_pedestrian_impacts)]]:
		_label(grid, 19, Color(0.82, 0.85, 0.88)).text = tr(row[0])
		_label(grid, 19, Color(1, 1, 1)).text = row[1]
	var ok := Button.new()
	ok.text = tr("UI_CONTINUE")
	ok.custom_minimum_size = Vector2(0, 58)
	_style_button(ok, Color(0.1, 0.55, 0.5))
	ok.pressed.connect(func() -> void:
		_summary.queue_free()
		GameState.has_session_summary = false)
	v.add_child(ok)
