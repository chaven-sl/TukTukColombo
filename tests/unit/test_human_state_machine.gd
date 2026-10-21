extends "res://tests/test_case.gd"

const S := HumanAgent.State


func _agent() -> HumanAgent:
	var a := HumanAgent.new()
	a.human_id = 1
	return a


func test_ambient_lifecycle_transitions() -> void:
	var a := _agent()
	var before := HumanAgent.invalid_transitions
	for to in [S.IDLE, S.WALKING, S.WAITING_TO_CROSS, S.CROSSING, S.WALKING, S.REACTING, S.WALKING, S.IDLE,
			S.RETURNING_TO_POOL, S.INACTIVE]:
		check(a.set_state(to), "allowed: -> %s" % S.keys()[to])
	check_eq(HumanAgent.invalid_transitions, before, "no invalid transitions")
	a.free()


func test_passenger_lifecycle_transitions() -> void:
	var a := _agent()
	var before := HumanAgent.invalid_transitions
	for to in [S.WAITING_FOR_PICKUP, S.APPROACHING_TUK, S.BOARDING, S.RIDING, S.EXITING, S.RETURNING_TO_POOL, S.INACTIVE]:
		check(a.set_state(to), "allowed: -> %s" % S.keys()[to])
	check_eq(HumanAgent.invalid_transitions, before, "no invalid transitions")
	a.free()


func test_invalid_transitions_are_rejected_and_counted() -> void:
	var a := _agent()
	var before := HumanAgent.invalid_transitions
	check(not a.set_state(S.RIDING), "INACTIVE -> RIDING rejected")
	check_eq(a.state, S.INACTIVE, "state unchanged")
	a.set_state(S.IDLE)
	check(not a.set_state(S.BOARDING), "IDLE -> BOARDING rejected (ambient people never board)")
	check(not a.set_state(S.CROSSING), "IDLE -> CROSSING rejected (must wait at the kerb first)")
	check_eq(HumanAgent.invalid_transitions, before + 3, "three rejections counted")
	a.free()


func test_crossing_counters_released_on_leave() -> void:
	var a := _agent()
	var zone := CrossingZone.new()
	a.set_state(S.IDLE)
	a.set_state(S.WALKING)
	a.crossing = zone
	zone.waiting_count = 1
	a.set_state(S.WAITING_TO_CROSS)
	check_eq(zone.waiting_count, 1, "still waiting")
	zone.occupied_count += 1
	a.set_state(S.CROSSING)
	check_eq(zone.waiting_count, 0, "waiting released when crossing starts")
	a.set_state(S.RETURNING_TO_POOL)
	check_eq(zone.occupied_count, 0, "occupancy released even when pulled back to the pool mid-crossing")
	a.free()


func test_every_state_has_a_route_back_to_the_pool() -> void:
	for st in HumanAgent.TRANSITIONS.keys():
		if st == S.INACTIVE or st == S.RETURNING_TO_POOL:
			continue
		var allowed: Array = HumanAgent.TRANSITIONS[st]
		check(allowed.has(S.RETURNING_TO_POOL), "%s can return to the pool" % S.keys()[st])


func test_ride_manager_transition_table() -> void:
	var R := RideManager.RideState
	var t: Dictionary = RideManager.TRANSITIONS
	var path := [R.NO_RIDE, R.OFFER_SELECTED, R.EN_ROUTE_TO_PICKUP, R.BOARDING, R.ACTIVE, R.ARRIVED, R.COMPLETED,
			R.EXITING, R.RETURN_TO_IDLE, R.NO_RIDE]
	for i in path.size() - 1:
		check((t[path[i]] as Array).has(path[i + 1]), "%s -> %s" % [R.keys()[path[i]], R.keys()[path[i + 1]]])
	check((t[R.ACTIVE] as Array).has(R.FAILED), "ACTIVE -> FAILED")
	check((t[R.FAILED] as Array).has(R.EXITING), "FAILED -> EXITING")
	check(not (t[R.ACTIVE] as Array).has(R.NO_RIDE), "an active ride cannot silently vanish")
	check(not (t[R.NO_RIDE] as Array).has(R.ACTIVE), "cannot start riding without pickup")
