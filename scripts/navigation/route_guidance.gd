class_name RouteGuidance
extends Node3D
## v0.03A1 GPS. Follows the RideManager lifecycle and keeps one cached
## RoutePlan along the real lane graph:
##
##   NO_RIDE ............................ no route
##   EN_ROUTE_TO_PICKUP ................. tuk → selected passenger
##   BOARDING ........................... route hidden ("boarding")
##   ACTIVE ............................. tuk → destination (automatic)
##   ARRIVED / FAILED / cancel / reset .. route cleared
##
## Route searches run only on accept, boarding, meaningful off-route deviation
## (rate limited by recalc_cooldown) and invalidation — never every frame.
## Progress along the cached route is a cheap windowed projection.

signal route_changed(plan: RoutePlan)
signal instruction_changed(kind: RoutePlan.Kind, distance_m: float)

enum Phase { NONE, TO_PICKUP, BOARDING, TO_DESTINATION }

@export var config: RouteGuidanceConfig

var rides: RideManager
var road: RoadNetwork
var player: TukController

var phase: Phase = Phase.NONE
var plan: RoutePlan = null
var progress := 0.0
var lateral := 0.0
var remaining_m := 0.0
var instruction_kind: RoutePlan.Kind = RoutePlan.Kind.NONE
var instruction_distance := 0.0
var off_route := false

# Diagnostics (debug HUD, tests).
var recalc_count := 0
var off_route_events := 0
var suppressed_recalcs := 0

var _ribbon: RouteRibbon
## Debug/perf A/B only: keep the ribbon hidden.
var _ribbon_hidden := false
var _update_timer := 0.0
var _off_timer := 0.0
var _wrong_timer := 0.0
var _since_recalc := 1000.0


func _ready() -> void:
	if config == null:
		config = RouteGuidanceConfig.new()
	_ribbon = RouteRibbon.new()
	_ribbon.name = "RouteRibbon"
	add_child(_ribbon)


func setup(p_rides: RideManager, p_road: RoadNetwork, p_player: TukController) -> void:
	rides = p_rides
	road = p_road
	player = p_player
	rides.state_changed.connect(_on_ride_state)
	EventBus.player_reset.connect(func() -> void:
		if phase == Phase.TO_PICKUP or phase == Phase.TO_DESTINATION:
			recalculate(true))


func target_position() -> Vector3:
	match phase:
		Phase.TO_PICKUP:
			var agent := rides.passenger_agent()
			return agent.global_position if agent != null else rides.offer.pickup.global_position
		Phase.TO_DESTINATION:
			return rides.offer.destination.global_position
	return Vector3.ZERO


func phase_name() -> String:
	return Phase.keys()[phase]


func _on_ride_state(state: RideManager.RideState) -> void:
	match state:
		RideManager.RideState.EN_ROUTE_TO_PICKUP:
			_set_phase(Phase.TO_PICKUP)
		RideManager.RideState.BOARDING:
			_set_phase(Phase.BOARDING)
		RideManager.RideState.ACTIVE:
			_set_phase(Phase.TO_DESTINATION)
		_:
			_set_phase(Phase.NONE)


func _set_phase(p: Phase) -> void:
	if p == phase and p != Phase.TO_PICKUP:
		return
	phase = p
	if phase == Phase.TO_PICKUP or phase == Phase.TO_DESTINATION:
		recalculate(true)
	else:
		_clear()


func _clear() -> void:
	plan = null
	progress = 0.0
	remaining_m = 0.0
	off_route = false
	_off_timer = 0.0
	_wrong_timer = 0.0
	_ribbon.clear()
	_set_instruction(RoutePlan.Kind.NONE, 0.0)
	route_changed.emit(null)


## Full route search from the tuk's position and heading. `force` bypasses the
## cooldown (accept, boarding, reset); off-route requests respect it.
func recalculate(force: bool = false) -> bool:
	if not force and _since_recalc < config.recalc_cooldown:
		suppressed_recalcs += 1
		return false
	_since_recalc = 0.0
	recalc_count += 1
	var heading := -player.global_transform.basis.z
	plan = road.route_path(player.global_position, target_position(), heading)
	off_route = false
	_off_timer = 0.0
	_wrong_timer = 0.0
	if plan.is_empty():
		_ribbon.clear()
	else:
		var pr := plan.project(player.global_position)
		progress = pr.x
		lateral = pr.y
		_ribbon.show_plan(plan, config)
		if _ribbon_hidden:
			_ribbon.visible = false
		_ribbon.set_progress(progress)
	_update_instruction()
	route_changed.emit(plan)
	return true


func _physics_process(delta: float) -> void:
	var ps := PerfSections.begin()
	_physics_process_body(delta)
	PerfSections.end(PerfSections.GPS, ps)


func _physics_process_body(delta: float) -> void:
	_since_recalc += delta
	if plan == null or plan.is_empty() or player == null:
		if phase == Phase.BOARDING:
			_set_instruction(RoutePlan.Kind.NONE, 0.0)
		return
	_update_timer -= delta
	if _update_timer > 0.0:
		return
	var dt := config.update_interval - _update_timer
	_update_timer = config.update_interval
	var pr := plan.project(player.global_position, progress)
	# Only move forward along the route unless the window search says we are
	# genuinely back (prevents flicker on loops).
	progress = pr.x
	lateral = pr.y
	_ribbon.set_progress(progress)
	_check_off_route(dt)
	_update_instruction()


func _check_off_route(dt: float) -> void:
	var was := off_route
	_off_timer = _off_timer + dt if lateral > config.off_route_distance else 0.0
	var v := player.linear_velocity
	v.y = 0.0
	var wrong := v.length() * 3.6 > config.wrong_way_min_speed_kmh \
			and v.normalized().dot(plan.tangent_at(progress)) < config.wrong_way_dot
	_wrong_timer = _wrong_timer + dt if wrong else 0.0
	off_route = _off_timer >= config.off_route_seconds or _wrong_timer >= config.wrong_way_seconds
	if off_route and not was:
		off_route_events += 1
	if off_route:
		recalculate(false)


func _update_instruction() -> void:
	if plan == null or plan.is_empty():
		_set_instruction(RoutePlan.Kind.NONE, 0.0)
		return
	var target := target_position()
	remaining_m = maxf(plan.length() - progress, 0.0)
	var to_pickup := phase == Phase.TO_PICKUP
	var straight := Vector2(target.x - player.global_position.x, target.z - player.global_position.z).length()
	var stop_radius := config.pickup_stop_distance if to_pickup else rides.config.arrive_radius
	var stop_now := straight <= stop_radius
	var ins := plan.next_instruction(progress, to_pickup, stop_now, config.turn_announce_distance)
	_set_instruction(int(ins.x) as RoutePlan.Kind, ins.y)


func _set_instruction(kind: RoutePlan.Kind, distance_m: float) -> void:
	var changed := kind != instruction_kind or RoutePlan.display_distance(distance_m) != RoutePlan.display_distance(instruction_distance)
	instruction_kind = kind
	instruction_distance = distance_m
	if changed:
		instruction_changed.emit(kind, distance_m)


## "LEFT — 80 m" etc. (presentation helper shared by HUD and debug).
func instruction_text() -> String:
	if instruction_kind == RoutePlan.Kind.NONE:
		return ""
	var word := tr(String(RoutePlan.KEYS[instruction_kind]))
	if instruction_kind == RoutePlan.Kind.STOP_TO_PICK_UP or instruction_kind == RoutePlan.Kind.STOP_HERE:
		return word
	return "%s — %d m" % [word, RoutePlan.display_distance(instruction_distance)]


func set_ribbon_hidden(hidden: bool) -> void:
	_ribbon_hidden = hidden
	if hidden:
		_ribbon.visible = false
