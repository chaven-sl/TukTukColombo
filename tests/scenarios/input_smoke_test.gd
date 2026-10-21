extends Node
## Drives the real prototype scene through InputMap actions (the same path a
## keyboard uses) and checks every control does what it should.
##
##   godot --headless --path . --fixed-fps 60 res://tests/scenarios/input_smoke_test.tscn

const MAIN := preload("res://scenes/prototype/prototype_main.tscn")

var main: Node3D
var player: TukController
var _t := 0.0
var _step := 0
var _failures := 0
var _resets := 0
var _horns := 0
var _speed_before_brake := 0.0
var _debug_initial := false
var _brake_checked := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	main = MAIN.instantiate()
	main.get_node("TrafficManager").set("rng_seed", 99)
	add_child(main)
	player = main.get_node("PlayerTuk")
	EventBus.player_reset.connect(func() -> void: _resets += 1)
	EventBus.horn_sounded.connect(func(_p: Vector3) -> void: _horns += 1)
	_debug_initial = GameState.debug_hud_visible


func _check(name: String, ok: bool, detail: String) -> void:
	print("[%s] %s  %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		_failures += 1


func _send(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _process(delta: float) -> void:
	_t += delta
	match _step:
		0:
			Input.action_press("accelerate")
			if _t > 4.0:
				_check("W accelerates", player.speed_kmh > 20.0, "%.1f km/h" % player.speed_kmh)
				Input.action_press("steer_left")
				_step = 1
				_t = 0.0
		1:
			if _t > 0.6:
				_check("A steers left", player.steer_input < -0.5 and player.steer_angle_deg < 0.0, "input %.2f" % player.steer_input)
				Input.action_release("steer_left")
				Input.action_press("steer_right")
				_step = 2
				_t = 0.0
		2:
			if _t > 0.6:
				_check("D steers right", player.steer_input > 0.5, "input %.2f" % player.steer_input)
				Input.action_release("steer_right")
				Input.action_release("accelerate")
				_speed_before_brake = player.speed_kmh
				Input.action_press("brake_reverse")
				_step = 3
				_t = 0.0
		3:
			if _t > 1.5 and not _brake_checked:
				_brake_checked = true
				_check("S brakes", player.speed_kmh < _speed_before_brake - 10.0, "%.1f -> %.1f" % [_speed_before_brake, player.speed_kmh])
			if _t > 6.0:
				_check("S reverses when stopped", player.forward_speed < -1.0, "%.1f km/h backwards" % (-player.forward_speed * 3.6))
				Input.action_release("brake_reverse")
				_send("reset_vehicle")
				_send("horn")
				_step = 4
				_t = 0.0
		4:
			if _t > 0.5:
				_check("R resets the tuk", _resets >= 1 and absf(player.forward_speed) < 1.0, "resets %d" % _resets)
				_check("H sounds horn event", _horns == 1, "horns %d" % _horns)
				_send("debug_toggle_hud")
				_send("debug_toggle_traffic")
				_send("debug_toggle_vehicle")
				_step = 5
				_t = 0.0
		5:
			if _t > 0.3:
				_check("F1 toggles overlay", GameState.debug_hud_visible != _debug_initial, "")
				_check("F2 toggles traffic debug", GameState.traffic_debug_visible, "")
				_check("F3 toggles vehicle debug", GameState.vehicle_debug_visible, "")
				_send("debug_toggle_hud")
				_send("debug_toggle_traffic")
				_send("debug_toggle_vehicle")
				_send("pause")
				_step = 6
				_t = 0.0
		6:
			if _t > 0.3:
				_check("Esc pauses", get_tree().paused, "")
				_send("pause")
				_step = 7
				_t = 0.0
		7:
			if _t > 0.3:
				_check("Esc resumes", not get_tree().paused, "")
				_check("debug flags restored", GameState.debug_hud_visible == _debug_initial, "")
				print("=== INPUT SMOKE: %s (%d failed) ===" % ["PASS" if _failures == 0 else "FAIL", _failures])
				get_tree().quit(1 if _failures > 0 else 0)
