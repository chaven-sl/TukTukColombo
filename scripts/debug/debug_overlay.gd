class_name DebugOverlay
extends CanvasLayer
## Developer telemetry. F1 = text overlay, F2 = traffic debug (lanes,
## candidates, agent states), F3 = vehicle debug (suspension rays, tyre forces).
## Debug-only: strings here are not localised and the node can be removed
## from release builds without affecting gameplay.

const REFRESH_INTERVAL := 0.2

var _label: Label
var _panel: PanelContainer
var _refresh := 0.0
var _draw: MeshInstance3D
var _immediate: ImmediateMesh
var _draw_material: StandardMaterial3D

var _player: TukController
var _traffic: TrafficManager
var _network: RoadNetwork
var _scoring: ScoringSystem
var _near_miss: NearMissDetector


func setup(player: TukController, traffic: TrafficManager, network: RoadNetwork,
		scoring: ScoringSystem, near_miss: NearMissDetector) -> void:
	_player = player
	_traffic = traffic
	_network = network
	_scoring = scoring
	_near_miss = near_miss
	_immediate = ImmediateMesh.new()
	_draw = MeshInstance3D.new()
	_draw.name = "DebugDraw"
	_draw.mesh = _immediate
	_draw_material = StandardMaterial3D.new()
	_draw_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_draw_material.vertex_color_use_as_albedo = true
	_draw_material.no_depth_test = true
	_draw.material_override = _draw_material
	_draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	network.add_child(_draw)
	_apply_flags()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position = Vector2(16, 70)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	_panel.add_child(_label)
	GameState.debug_flags_changed.connect(_apply_flags)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle_hud"):
		GameState.toggle_debug_hud()
	elif event.is_action_pressed("debug_toggle_traffic"):
		GameState.toggle_traffic_debug()
	elif event.is_action_pressed("debug_toggle_vehicle"):
		GameState.toggle_vehicle_debug()


func _apply_flags() -> void:
	if _panel != null:
		_panel.visible = GameState.debug_hud_visible
	if _network != null and _network.debug_mesh_instance != null:
		_network.debug_mesh_instance.visible = GameState.traffic_debug_visible
	if _immediate != null and not (GameState.traffic_debug_visible or GameState.vehicle_debug_visible):
		_immediate.clear_surfaces()


func _process(delta: float) -> void:
	if _player == null:
		return
	if GameState.traffic_debug_visible or GameState.vehicle_debug_visible:
		_draw_3d()
	if not GameState.debug_hud_visible:
		return
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = REFRESH_INTERVAL
	_label.text = _compose_text()


func _compose_text() -> String:
	var fps := Engine.get_frames_per_second()
	var lines := PackedStringArray()
	lines.append("FPS %d   frame %.1f ms   draw calls %d" % [fps, 1000.0 / maxf(fps, 1.0),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	lines.append("")
	lines.append("VEHICLE")
	lines.append("  speed %.1f km/h  (fwd %.2f m/s)" % [_player.speed_kmh, _player.forward_speed])
	lines.append("  steer input %+.2f   angle %+.1f°   limit %.1f°" % [_player.steer_input, _player.steer_angle_deg,
			_player.tuning.steer_limit_deg(_player.speed_kmh)])
	lines.append("  roll %+.1f°  pitch %+.1f°  lat %.2f g  long %.2f g" % [_player.roll_deg, _player.pitch_deg,
			_player.lateral_accel / 9.81, _player.longitudinal_accel / 9.81])
	lines.append("  wheels grounded %d   compression F %.3f  RL %.3f  RR %.3f" % [_player.grounded_wheels,
			_player.wheel_compression[0], _player.wheel_compression[1], _player.wheel_compression[2]])
	lines.append("  velocity %s   tipped %s" % [_player.linear_velocity.snapped(Vector3(0.1, 0.1, 0.1)), _player.is_tipped])
	lines.append("")
	lines.append("SCORING")
	var combo := _scoring.combo
	lines.append("  score %d   combo x%d (chain %d)   timeout %.2f s" % [GameState.score, combo.multiplier(),
			combo.chain, combo.time_left])
	lines.append("  near-miss candidates %d   close calls %d   tight gaps %d" % [_near_miss.candidate_count,
			_near_miss.events_close_call, _near_miss.events_tight_gap])
	lines.append("  rejected: collision %d  clearance %d  speed %d  expired %d" % [_near_miss.rejected_collision,
			_near_miss.rejected_clearance, _near_miss.rejected_speed, _near_miss.expired])
	lines.append("")
	lines.append("TRAFFIC")
	var budget := _traffic.budget
	lines.append("  active %d / pool %d (free %d)   target %d" % [_traffic.active_agents.size(),
			_traffic.pool_capacity(), _traffic.pool.total_free(), _traffic.target_count()])
	lines.append("  performance ceiling %d   density target %d   window fps %.1f" % [budget.performance_ceiling,
			budget.gameplay_density_target, budget.window_fps])
	lines.append("  waiting at signals %d   spawned %d  despawned %d  stuck %d" % [_traffic.waiting_count(),
			_traffic.stats_spawned, _traffic.stats_despawned, _traffic.stats_stuck_despawns])
	for ix in _network.intersections:
		lines.append("  junction %s: %s  grants %d/%d" % [ix.name, ix.phase_description(), ix.grants_issued[0],
				ix.grants_issued[1]])
	lines.append("")
	lines.append("F1 overlay  F2 traffic  F3 vehicle  R reset  Esc pause")
	return "\n".join(lines)


func _draw_3d() -> void:
	_immediate.clear_surfaces()
	_immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	var lift := Vector3.UP * 0.3
	if GameState.vehicle_debug_visible:
		var xf := _player.global_transform
		for i in TukController.WHEEL_COUNT:
			var mount := xf * _player.mount_points_local[i]
			var grounded := _player.wheel_grounded[i] == 1
			var end := _player.wheel_contact[i] if grounded else mount - xf.basis.y * (_player.tuning.suspension_travel + _player.tuning.wheel_radius)
			_line(mount, end, Color(0.2, 1.0, 0.3) if grounded else Color(1.0, 0.3, 0.2))
			if grounded:
				_line(end, end + xf.basis.y * _player.wheel_load[i] / 3000.0, Color(0.3, 0.6, 1.0))
				_line(end + lift * 0.2, end + lift * 0.2 + _player.wheel_force[i] / 1500.0, Color(1.0, 0.9, 0.2))
		var com := xf * _player.tuning.center_of_mass
		_line(com, com + Vector3.UP * 0.6, Color(1, 0, 1))
	if GameState.traffic_debug_visible:
		for agent in _traffic.active_agents:
			var p := agent.global_position + Vector3.UP * (agent.vehicle_class.height + 0.4)
			var color := Color(0.3, 1.0, 0.3)
			if agent.waiting_for_signal:
				color = Color(1.0, 0.2, 0.2)
			elif agent.granted_connector != null:
				color = Color(1.0, 0.9, 0.2)
			elif agent.hold_timer > 0.0:
				color = Color(1.0, 0.0, 1.0)
			_line(p, p + Vector3.UP * 1.2, color)
			if _near_miss.is_candidate(agent.agent_id):
				_line(_player.global_position + lift, agent.global_position + lift, Color(1.0, 0.6, 0.1))
	_immediate.surface_end()


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_immediate.surface_set_color(color)
	_immediate.surface_add_vertex(a)
	_immediate.surface_set_color(color)
	_immediate.surface_add_vertex(b)
