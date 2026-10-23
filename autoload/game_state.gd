extends Node
## Session-level state shared across systems: score, run stats, pause and
## debug flags. Owns no gameplay rules — ScoringSystem decides points and
## GameState records them and persists bests through SaveManager.

signal pause_changed(paused: bool)
signal debug_flags_changed()
## v0.04: cash / reputation / upgrades changed (HUD wallet, garage).
signal career_changed()
signal career_level_up(level: int)

const AUTOSAVE_INTERVAL := 20.0

var score := 0
var session_close_calls := 0
var session_tight_gaps := 0
var session_best_chain := 0

var debug_hud_visible := false
var traffic_debug_visible := false
var vehicle_debug_visible := false
var human_debug_visible := false

var _unflushed_close_calls := 0
var _unflushed_tight_gaps := 0
var _dirty := false
var _autosave_timer := 0.0


## v0.04 career progression (persistent, in the save's "career" section).
var economy: EconomyConfig = preload("res://resources/economy/economy_config.tres")
var career: CareerProfile
## Session totals for the garage summary.
var session_cash := 0
var session_reputation := 0
var session_collisions := 0
var session_upgrades := 0
## Set when the player returns from the street; the garage shows it once.
var has_session_summary := false
var session_rides_completed := 0
var session_rides_failed := 0
var session_fares := 0
var session_pedestrian_impacts := 0
var _unflushed_rides: Array[RideResult] = []
var _unflushed_impacts := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.ride_finished.connect(_on_ride_finished)
	EventBus.pedestrian_impact.connect(_on_pedestrian_impact)
	debug_hud_visible = bool(SaveManager.get_setting("show_debug_hud", false))
	career = CareerProfile.new(SaveManager.career_section(), economy)
	EventBus.collision_event.connect(func(e: CollisionEvent) -> void:
		if e.kind != CollisionEvent.Kind.ROLLOVER:
			session_collisions += 1)
	TranslationServer.set_locale(str(SaveManager.get_setting("locale", "en")))


func reset_session() -> void:
	session_cash = 0
	session_reputation = 0
	session_collisions = 0
	session_upgrades = 0
	session_rides_completed = 0
	session_rides_failed = 0
	session_fares = 0
	session_pedestrian_impacts = 0
	score = 0
	session_close_calls = 0
	session_tight_gaps = 0
	session_best_chain = 0


func add_score(points: int) -> void:
	score += points
	_dirty = true


func record_skill(event_type: int) -> void:
	match event_type:
		SkillEvent.Type.CLOSE_CALL:
			session_close_calls += 1
			_unflushed_close_calls += 1
		SkillEvent.Type.TIGHT_GAP:
			session_tight_gaps += 1
			_unflushed_tight_gaps += 1
	_dirty = true


func record_chain(chain: int) -> void:
	if chain > session_best_chain:
		session_best_chain = chain
		_dirty = true


func set_paused(paused: bool) -> void:
	if get_tree().paused == paused:
		return
	get_tree().paused = paused
	if paused:
		flush_stats()
	pause_changed.emit(paused)


func toggle_debug_hud() -> void:
	debug_hud_visible = not debug_hud_visible
	SaveManager.set_setting("show_debug_hud", debug_hud_visible)
	debug_flags_changed.emit()


func toggle_traffic_debug() -> void:
	traffic_debug_visible = not traffic_debug_visible
	debug_flags_changed.emit()


func toggle_human_debug() -> void:
	human_debug_visible = not human_debug_visible
	debug_flags_changed.emit()


func toggle_vehicle_debug() -> void:
	vehicle_debug_visible = not vehicle_debug_visible
	debug_flags_changed.emit()


## Merges session bests/totals into the persistent prototype stats and saves.
func flush_stats() -> void:
	var best_combo := int(SaveManager.get_stat("best_combo", 0))
	var highest := int(SaveManager.get_stat("highest_score", 0))
	SaveManager.set_stat("best_combo", maxi(best_combo, session_best_chain))
	SaveManager.set_stat("highest_score", maxi(highest, score))
	SaveManager.set_stat("total_close_calls", int(SaveManager.get_stat("total_close_calls", 0)) + _unflushed_close_calls)
	SaveManager.set_stat("total_tight_gaps", int(SaveManager.get_stat("total_tight_gaps", 0)) + _unflushed_tight_gaps)
	_unflushed_close_calls = 0
	_unflushed_tight_gaps = 0
	for result in _unflushed_rides:
		_persist_ride(result)
	_unflushed_rides.clear()
	SaveManager.set_stat("pedestrian_impacts", int(SaveManager.get_stat("pedestrian_impacts", 0)) + _unflushed_impacts)
	_unflushed_impacts = 0
	_dirty = false
	_autosave_timer = 0.0
	SaveManager.save_now()


## Atomic upgrade purchase, persisted immediately. `expected_level` guards
## against double purchases from rapid taps.
func purchase_upgrade(id: StringName, expected_level: int) -> CareerProfile.Purchase:
	var r := career.purchase(id, expected_level)
	if r == CareerProfile.Purchase.OK:
		session_upgrades += 1
		print("[Economy] bought %s level %d → cash Rs. %d" % [id, career.level_of(id), career.cash()])
		SaveManager.save_now()
		career_changed.emit()
	return r


## Leaving the street for the garage: persist everything, keep a summary.
func prepare_garage_return() -> void:
	flush_stats()
	has_session_summary = true


## Unsafe-driving incident. Recorded even when no ride is active.
func _on_pedestrian_impact(_event: PedestrianEvent) -> void:
	session_pedestrian_impacts += 1
	_unflushed_impacts += 1
	_dirty = true


func _on_ride_finished(result: RideResult) -> void:
	if result.outcome == RideResult.Outcome.COMPLETED:
		session_rides_completed += 1
		session_fares += result.final_fare
	else:
		session_rides_failed += 1
	_unflushed_rides.append(result)
	# v0.04: the career is credited immediately and saved right away — money
	# and reputation are never lost to a crash or a killed app.
	var level_before := career.career_level()
	career.apply_ride(result)
	session_cash += result.cash_earned
	session_reputation += result.reputation_earned
	print("[Economy] ride %s tier %s: Rs. %d, +%d ★ → cash Rs. %d, ★ %d, level %d, avg Rs. %.0f/ride, ~%d rides to next upgrade" % [
		RideResult.Outcome.keys()[result.outcome], JobTiers.Tier.keys()[result.job_tier], result.cash_earned, result.reputation_earned,
		career.cash(), career.reputation(), career.career_level(), career.average_earnings(), career.rides_to_next_upgrade()])
	if career.career_level() > level_before:
		career_level_up.emit(career.career_level())
	career_changed.emit()
	flush_stats()


func _persist_ride(result: RideResult) -> void:
	if result.outcome != RideResult.Outcome.COMPLETED:
		SaveManager.set_stat("rides_failed", int(SaveManager.get_stat("rides_failed", 0)) + 1)
		return
	SaveManager.set_stat("rides_completed", int(SaveManager.get_stat("rides_completed", 0)) + 1)
	SaveManager.set_stat("prototype_fares_total", int(SaveManager.get_stat("prototype_fares_total", 0)) + result.final_fare)
	var best := int(SaveManager.get_stat("best_passenger_satisfaction", 0))
	SaveManager.set_stat("best_passenger_satisfaction", maxi(best, roundi(result.satisfaction.final_score)))
	var per_type: Variant = SaveManager.get_stat("passenger_type_completions", {})
	if typeof(per_type) == TYPE_DICTIONARY:
		var counts: Dictionary = per_type
		var id := String(result.profile.id)
		counts[id] = int(counts.get(id, 0)) + 1
		SaveManager.set_stat("passenger_type_completions", counts)


func _process(delta: float) -> void:
	if not _dirty:
		return
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		flush_stats()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if _dirty:
			flush_stats()
