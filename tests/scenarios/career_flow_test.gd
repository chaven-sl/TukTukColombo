extends Node
## v0.04 core-loop flow test, real scenes end to end:
## garage → DRIVE → complete hires → cash / reputation credited → return to
## garage (summary) → buy an upgrade → DRIVE again with the upgraded tuk →
## reload the save from disk ("close and reopen") → progression retained.
##
##   godot --headless --path . --fixed-fps 60 res://tests/scenarios/career_flow_test.tscn
##
## Headless runs use their own save slot (never the player's progression);
## this test also starts that slot from a clean career.

const GARAGE := "res://scenes/garage/garage.tscn"

var _failures := 0
var _results: Array[RideResult] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Survive scene changes: park the test on the root, let a placeholder be
	# the "current scene" that change_scene_to_file replaces.
	var holder := Node.new()
	holder.name = "Holder"
	_park.call_deferred(holder)


func _park(holder: Node) -> void:
	var tree := get_tree()
	tree.root.add_child(holder)
	reparent(tree.root)
	tree.current_scene = holder
	EventBus.ride_finished.connect(func(r: RideResult) -> void: _results.append(r))
	_run.call_deferred()


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("  [%s] %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait_scene(script_class: String, max_frames := 900) -> Node:
	for i in max_frames:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs != null and cs.get_script() != null and (cs.get_class() == script_class or cs.name == script_class):
			return cs
	return null


func _run() -> void:
	print("\n=== v0.04 CAREER FLOW ===")
	# Clean career on the headless slot.
	SaveManager.store.data = SaveStore.default_document()
	GameState.career = CareerProfile.new(SaveManager.career_section(), GameState.economy)
	GameState.reset_session()
	SaveManager.save_now()
	var start_cash := GameState.career.cash()
	_check("clean career: Rs. 1,500, ★ 0, level 1", start_cash == 1500 and GameState.career.reputation() == 0 and GameState.career.career_level() == 1)
	# 1. Garage.
	get_tree().change_scene_to_file(GARAGE)
	var garage := await _wait_scene("Garage") as Garage
	_check("boots into the garage", garage != null)
	if garage == null:
		return _finish()
	await _frames(10)
	_check("garage shows cash and level", garage._cash.text == EconomyFormat.rupees(start_cash) and garage._level.text.contains("1"), garage._cash.text)
	var cost := GameState.career.next_cost(&"engine")
	_check("first upgrade not yet affordable (needs rides)", cost > start_cash, "%s vs %s" % [EconomyFormat.rupees(cost), EconomyFormat.rupees(start_cash)])
	# 2. DRIVE.
	garage.drive()
	var main := await _wait_scene("FortPettahSlice") as Node3D
	_check("DRIVE enters Fort–Pettah", main != null)
	if main == null:
		return _finish()
	await _frames(60)
	var player: TukController = main.get_node("PlayerTuk")
	var base_top: float = (main.get("base_tuning") as VehicleTuning).top_speed_kmh
	_check("stock tuk drives with base tuning", is_equal_approx(player.tuning.top_speed_kmh, base_top), "%.1f km/h" % player.tuning.top_speed_kmh)
	player.get_node("PlayerInput").set("enabled", false)
	# 3. Hires until the first upgrade is affordable (2–4 expected).
	var rides: RideManager = main.get_node("RideManager")
	var offers: PassengerOfferManager = main.get_node("PassengerOfferManager")
	var net: PedestrianNetwork = main.get_node("TestTrack/Pedestrians")
	var completed := 0
	var attempts := 0
	while GameState.career.cash() < cost and attempts < 6:
		attempts += 1
		var cash_before := GameState.career.cash()
		var rep_before := GameState.career.reputation()
		var r := await _do_hire(main, player, rides, offers, net)
		if r == null:
			_check("hire %d completes" % attempts, false)
			continue
		if r.outcome == RideResult.Outcome.COMPLETED:
			completed += 1
			_check("hire %d: Rs. %d and +%d ★ credited" % [attempts, r.cash_earned, r.reputation_earned],
					GameState.career.cash() == cash_before + r.cash_earned and GameState.career.reputation() == rep_before + r.reputation_earned and r.cash_earned > 0)
			var sum := 0
			for l: Array in r.payout_lines:
				sum += int(l[1])
			_check("hire %d: result explains every rupee" % attempts, sum == r.cash_earned and r.payout_lines.size() >= 1, "%d lines" % r.payout_lines.size())
	_check("first upgrade affordable after %d completed hires (target 2–4)" % completed, GameState.career.cash() >= cost and completed >= 1 and completed <= 4)
	# 4. Return to garage (safe moment only).
	await _wait_idle(rides, player)
	_check("return allowed: no hire, tuk stopped", main.call("can_return_to_garage"))
	var session_cash := GameState.session_cash
	main.call("return_to_garage")
	garage = await _wait_scene("Garage") as Garage
	_check("back in the garage", garage != null)
	if garage == null:
		return _finish()
	await _frames(10)
	_check("session summary shown", garage._summary != null and is_instance_valid(garage._summary), "session %s" % EconomyFormat.rupees(session_cash))
	# 5. Buy an upgrade (and a rapid double tap).
	var cash_before_buy := GameState.career.cash()
	var r1 := garage.buy(&"engine")
	var r2 := garage.buy(&"engine")
	_check("upgrade purchased", r1 == CareerProfile.Purchase.OK and GameState.career.level_of(&"engine") == 1)
	_check("rapid second tap does not double-buy", r2 != CareerProfile.Purchase.OK and GameState.career.level_of(&"engine") == 1)
	_check("cash deducted exactly once", GameState.career.cash() == cash_before_buy - cost, "%s → %s" % [EconomyFormat.rupees(cash_before_buy), EconomyFormat.rupees(GameState.career.cash())])
	await _frames(50)
	# 6. Drive again: upgraded tuning present, base untouched.
	garage.drive()
	main = await _wait_scene("FortPettahSlice") as Node3D
	await _frames(30)
	player = main.get_node("PlayerTuk")
	var expected := EffectiveVehicleConfig.build(main.get("base_tuning"), {"engine": 1})
	_check("driving again with ENGINE 1 (top speed +2.5 km/h)", is_equal_approx(player.tuning.top_speed_kmh, expected.top_speed_kmh) and player.tuning.top_speed_kmh > base_top,
			"%.1f km/h" % player.tuning.top_speed_kmh)
	_check("base tuning resource unchanged", is_equal_approx((main.get("base_tuning") as VehicleTuning).top_speed_kmh, base_top))
	# 7. "Close and reopen": a fresh SaveStore reads the same file.
	GameState.flush_stats()
	var reopened := SaveStore.new(SaveManager.store.directory, SaveManager.store.base_name)
	reopened.load_document()
	var c: Dictionary = reopened.data["career"]
	_check("reopened save keeps cash, reputation and upgrades",
			int(c["cash"]) == GameState.career.cash() and int(c["reputation"]) == GameState.career.reputation() and int(c["upgrades"]["engine"]) == 1,
			"%s, ★ %d, engine %d" % [EconomyFormat.rupees(int(c["cash"])), int(c["reputation"]), int(c["upgrades"]["engine"])])
	_check("career ride stats persisted", int(c["successful_rides"]) == completed and int(c["total_earned"]) > 0)
	_finish()


func _wait_idle(rides: RideManager, player: TukController) -> void:
	player.input.throttle = 0.0
	player.input.brake = 1.0
	player.input.handbrake = true
	for i in 1200:
		await get_tree().physics_frame
		if rides.state == RideManager.RideState.NO_RIDE and player.speed_kmh < 3.0:
			return


func _do_hire(main: Node3D, player: TukController, rides: RideManager, offers: PassengerOfferManager, net: PedestrianNetwork) -> RideResult:
	await _wait_idle(rides, player)
	var offer: PassengerOffer = null
	for i in 900:
		for o in offers.offers:
			if o.state == PassengerOffer.State.AVAILABLE and o.passenger != null:
				offer = o
		if offer != null:
			break
		await get_tree().physics_frame
	if offer == null:
		return null
	var out := net.node_out[offer.pickup.node_id]
	player.teleport(Transform3D(MathUtil.basis_from_forward(out.cross(Vector3.UP)), offer.pickup.global_position - out * 4.0 + Vector3.UP * 0.3))
	var before := _results.size()
	for i in 1200:
		await get_tree().physics_frame
		if rides.state == RideManager.RideState.NO_RIDE and rides.nearby_offer == offer:
			rides.request_accept()
		if rides.state == RideManager.RideState.ACTIVE:
			break
	if rides.state != RideManager.RideState.ACTIVE:
		return null
	# A calm, clean ride: let the clock run a little, then arrive and stop.
	await _frames(240)
	var dest := offer.destination
	var dout := net.node_out[dest.node_id]
	player.teleport(Transform3D(MathUtil.basis_from_forward(dout.cross(Vector3.UP)), dest.global_position - dout * 4.0 + Vector3.UP * 0.3))
	for i in 1200:
		await get_tree().physics_frame
		if _results.size() > before:
			return _results[_results.size() - 1]
	return null


func _finish() -> void:
	print("\nCAREER FLOW: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)
