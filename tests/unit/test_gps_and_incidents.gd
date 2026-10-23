extends "res://tests/test_case.gd"
## v0.03A1 pure logic: RoutePlan geometry/instructions and incident rules.

var _incident_cfg: IncidentConfig = load("res://resources/traffic/incident_config.tres")
var _gps_cfg: RouteGuidanceConfig = load("res://resources/navigation/route_guidance.tres")


## An L-shaped route: 200 m north (-Z), then a right turn, 100 m east (+X).
func _l_route() -> RoutePlan:
	var p := RoutePlan.new()
	for i in 21:
		p.add_point(Vector3(0, 0, -i * 10.0))
	p.add_turn(p.length(), Vector3(0, 0, -1), Vector3(1, 0, 0))
	for i in range(1, 11):
		p.add_point(Vector3(i * 10.0, 0, -200.0))
	return p


func test_route_plan_geometry() -> void:
	var p := _l_route()
	check_near(p.length(), 300.0, 0.01, "length")
	check(p.position_at(250.0).distance_to(Vector3(50, 0, -200)) < 0.01, "position along")
	check(p.tangent_at(50.0).distance_to(Vector3(0, 0, -1)) < 0.01, "tangent first leg")
	var pr := p.project(Vector3(3, 0, -120))
	check_near(pr.x, 120.0, 0.01, "projection along")
	check_near(pr.y, 3.0, 0.01, "projection lateral")
	var windowed := p.project(Vector3(3, 0, -120), 110.0)
	check_near(windowed.x, 120.0, 0.01, "windowed projection agrees")


func test_turn_detection_ignores_gentle_bends() -> void:
	var p := RoutePlan.new()
	p.add_point(Vector3.ZERO)
	p.add_point(Vector3(0, 0, -10))
	p.add_turn(10.0, Vector3(0, 0, -1), Vector3(0.3, 0, -1).normalized())  # ~17°
	p.add_turn(10.0, Vector3(0, 0, -1), Vector3(-1, 0, 0))  # left 90°
	check_eq(p.turn_along.size(), 1, "only the real turn is kept")
	check_eq(p.turn_dir[0], -1, "turning from north to west is LEFT")
	check_eq(_l_route().turn_dir[0], 1, "north to east is RIGHT")


func test_instructions() -> void:
	var p := _l_route()
	var far := p.next_instruction(0.0, true, false, _gps_cfg.turn_announce_distance)
	check_eq(int(far.x), RoutePlan.Kind.RIGHT, "turn within announce distance → RIGHT")
	check_near(far.y, 200.0, 0.01, "RIGHT — 200 m")
	var short_announce := p.next_instruction(0.0, true, false, 120.0)
	check_eq(int(short_announce.x), RoutePlan.Kind.STRAIGHT, "turn beyond announce distance → STRAIGHT")
	var after := p.next_instruction(230.0, true, false, 250.0)
	check_eq(int(after.x), RoutePlan.Kind.PICKUP, "after the last turn → PICKUP")
	check_near(after.y, 70.0, 0.01, "PICKUP — remaining")
	check_eq(int(p.next_instruction(230.0, false, false, 250.0).x), RoutePlan.Kind.DESTINATION, "DESTINATION wording")
	check_eq(int(p.next_instruction(295.0, true, true, 250.0).x), RoutePlan.Kind.STOP_TO_PICK_UP, "STOP TO PICK UP")
	check_eq(int(p.next_instruction(295.0, false, true, 250.0).x), RoutePlan.Kind.STOP_HERE, "STOP HERE")
	check_eq(RoutePlan.display_distance(243.0), 240, "rounded to 10 m above 100 m")
	check_eq(RoutePlan.display_distance(37.0), 35, "rounded to 5 m below 100 m")


func _event(kind: CollisionEvent.Kind, severity: CollisionEvent.Severity, kmh: float, agent: int) -> CollisionEvent:
	var e := CollisionEvent.new()
	e.kind = kind
	e.severity = severity
	e.impact_speed = kmh / 3.6
	e.other_agent_id = agent
	return e


func test_incident_tiers() -> void:
	var C := CollisionEvent
	var T := IncidentRules.Tier
	check_eq(IncidentRules.tier_for(_event(C.Kind.WORLD, C.Severity.MAJOR, 50.0, -1), _incident_cfg), T.NONE, "world collision → none")
	check_eq(IncidentRules.tier_for(_event(C.Kind.ROLLOVER, C.Severity.MAJOR, 50.0, -1), _incident_cfg), T.NONE, "rollover → none")
	check_eq(IncidentRules.tier_for(_event(C.Kind.TRAFFIC, C.Severity.MINOR, 8.0, -1), _incident_cfg), T.NONE, "no agent id → none")
	check_eq(IncidentRules.tier_for(_event(C.Kind.TRAFFIC, C.Severity.MINOR, 8.0, 3), _incident_cfg), T.LIGHT, "scrape → LIGHT")
	check_eq(IncidentRules.tier_for(_event(C.Kind.TRAFFIC, C.Severity.MINOR, 20.0, 3), _incident_cfg), T.MODERATE, "harder → MODERATE")
	check_eq(IncidentRules.tier_for(_event(C.Kind.TRAFFIC, C.Severity.MAJOR, 40.0, 3), _incident_cfg), T.MAJOR, "major → MAJOR")


func test_temperaments_load_and_differ() -> void:
	check_eq(_incident_cfg.temperaments.size(), 3, "calm / impatient / hothead")
	var ids := []
	for t in _incident_cfg.temperaments:
		ids.append(String(t.id))
		check(not t.argue_keys.is_empty(), "%s has lines" % t.id)
		for k in t.argue_keys:
			check(TranslationServer.translate(k) != k, "%s line %s translated" % [t.id, k])
	check(ids == ["calm", "impatient", "hothead"], "ids %s" % str(ids))
	var calm: DriverTemperament = _incident_cfg.temperaments[0]
	var hot: DriverTemperament = _incident_cfg.temperaments[2]
	check(hot.exit_chance_moderate > calm.exit_chance_moderate and hot.argue_seconds.y > calm.argue_seconds.y, "hothead escalates more and argues longer")


func test_severity_dominates_temperament() -> void:
	var T := IncidentRules.Tier
	var R := IncidentRules.Response
	var calm: DriverTemperament = _incident_cfg.temperaments[0]
	var hot: DriverTemperament = _incident_cfg.temperaments[2]
	# Minor scrape + calm driver → never stops.
	for i in 20:
		var r := IncidentRules.response(T.LIGHT, calm, _incident_cfg, i / 20.0, i / 20.0)
		check(r == R.HORN_ONLY or r == R.SHOUT_ONLY, "calm LIGHT never stops (roll %.2f)" % (i / 20.0))
	# Minor scrape + hothead → may stop and yell.
	check_eq(IncidentRules.response(T.LIGHT, hot, _incident_cfg, 0.5, 0.1), R.STOP_AND_HONK, "hothead may escalate a scrape")
	# Major → (almost) anyone gets out.
	var exits := 0
	for i in 100:
		if IncidentRules.response(T.MAJOR, calm, _incident_cfg, i / 100.0, 0.5) == R.STOP_AND_EXIT:
			exits += 1
	check(exits >= 85, "major + calm: driver gets out ≥ 85%% (%d%%)" % exits)
	check(IncidentRules.argue_seconds(T.MAJOR, calm, _incident_cfg, 0.5) > IncidentRules.argue_seconds(T.MODERATE, calm, _incident_cfg, 0.5), "major argues longer")
	var counts := {}
	for i in 1000:
		var t := IncidentRules.pick_temperament(_incident_cfg, i / 1000.0)
		counts[t.id] = int(counts.get(t.id, 0)) + 1
	check(int(counts[&"calm"]) > int(counts[&"hothead"]), "calm drivers more common than hotheads %s" % str(counts))


func test_passenger_collision_lines_are_profile_specific() -> void:
	var cfg: RideConfig = load("res://resources/rides/ride_config.tres")
	var keys := {}
	for name in ["rushed", "careful", "thrill_seeker"]:
		var p: PassengerProfile = load("res://resources/passengers/%s.tres" % name)
		var r := PassengerReactionSystem.new(p, cfg)
		r.on_collision()
		var said := r.tick(0.016, 30.0, 10.0)
		keys[name] = said
		check(said.begins_with("REACT_COLLISION"), "%s reacts to a collision (%s)" % [name, said])
		check(TranslationServer.translate(said) != said, "%s line translated" % name)
		check(not p.incident_reaction_key.is_empty(), "%s has an incident line" % name)
	check(keys["rushed"] != keys["careful"] and keys["careful"] != keys["thrill_seeker"], "lines differ by passenger")
