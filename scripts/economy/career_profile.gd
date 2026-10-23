class_name CareerProfile
extends RefCounted
## Persistent career state (v0.04): cash, reputation, career level, upgrade
## levels and career stats, stored in the save document's "career" section.
## Pure logic over a Dictionary so it is unit-testable without autoloads.
##
## Invariants: cash never goes below 0; a purchase is all-or-nothing (cash
## and level change together, or neither does); a purchase must name the
## level it expects to buy, so a second rapid tap with the same stale
## level is rejected (no double purchase).

enum Purchase { OK, MAX_LEVEL, INSUFFICIENT_FUNDS, STALE_REQUEST, UNKNOWN }

var data: Dictionary
var config: EconomyConfig


func _init(p_data: Dictionary, p_config: EconomyConfig) -> void:
	data = p_data
	config = p_config
	ensure_defaults(data, config)


static func default_section(c: EconomyConfig) -> Dictionary:
	return {
		"cash": c.starting_cash,
		"reputation": c.starting_reputation,
		"career_level": 1,
		"upgrades": UpgradeCatalog.empty_levels(),
		"total_rides": 0,
		"successful_rides": 0,
		"failed_rides": 0,
		"total_earned": 0,
		"total_spent": 0,
		"upgrades_bought": 0,
		"best_ride_payout": 0,
		"express_completed": 0,
		"premium_completed": 0,
	}


static func ensure_defaults(d: Dictionary, c: EconomyConfig) -> void:
	var defaults := default_section(c)
	for k in defaults.keys():
		if not d.has(k):
			d[k] = defaults[k]
	var ups: Dictionary = d["upgrades"]
	for id in UpgradeCatalog.IDS:
		if not ups.has(String(id)):
			ups[String(id)] = 0


func cash() -> int:
	return int(data["cash"])


func reputation() -> int:
	return int(data["reputation"])


func upgrade_levels() -> Dictionary:
	return data["upgrades"]


func level_of(id: StringName) -> int:
	return int(upgrade_levels().get(String(id), 0))


## Career level 1..N from reputation (cached in the save for display/hooks).
func career_level() -> int:
	return CareerProfile.level_for(reputation(), config)


static func level_for(rep: int, c: EconomyConfig) -> int:
	var level := 1
	for i in c.career_thresholds.size():
		if rep >= c.career_thresholds[i]:
			level = i + 1
	return level


## Reputation needed for the next level (-1 at the top).
func next_level_reputation() -> int:
	var lvl := career_level()
	return config.career_thresholds[lvl] if lvl < config.career_thresholds.size() else -1


func next_cost(id: StringName) -> int:
	var def := UpgradeCatalog.get_def(id)
	var lvl := level_of(id)
	return def.cost_for_level(lvl + 1) if lvl < def.max_level else -1


## Atomic purchase of level `expected_level + 1` of `id`.
func purchase(id: StringName, expected_level: int) -> Purchase:
	var def := UpgradeCatalog.get_def(id)
	if def == null:
		return Purchase.UNKNOWN
	var lvl := level_of(id)
	if lvl != expected_level:
		return Purchase.STALE_REQUEST
	if lvl >= def.max_level:
		return Purchase.MAX_LEVEL
	var cost := def.cost_for_level(lvl + 1)
	if cost < 0 or cost > cash():
		return Purchase.INSUFFICIENT_FUNDS
	# All-or-nothing: compute the new state, then commit both values.
	var new_cash := cash() - cost
	assert(new_cash >= 0)
	upgrade_levels()[String(id)] = lvl + 1
	data["cash"] = new_cash
	data["total_spent"] = int(data["total_spent"]) + cost
	data["upgrades_bought"] = int(data["upgrades_bought"]) + 1
	return Purchase.OK


## Applies a finished ride's payout (RidePayout already ran on `result`).
func apply_ride(result: RideResult) -> void:
	data["total_rides"] = int(data["total_rides"]) + 1
	if result.outcome != RideResult.Outcome.COMPLETED:
		data["failed_rides"] = int(data["failed_rides"]) + 1
		return
	data["successful_rides"] = int(data["successful_rides"]) + 1
	data["cash"] = maxi(cash() + maxi(result.cash_earned, 0), 0)
	data["reputation"] = reputation() + maxi(result.reputation_earned, 0)
	data["total_earned"] = int(data["total_earned"]) + maxi(result.cash_earned, 0)
	data["best_ride_payout"] = maxi(int(data["best_ride_payout"]), result.cash_earned)
	match result.job_tier:
		JobTiers.Tier.EXPRESS:
			data["express_completed"] = int(data["express_completed"]) + 1
		JobTiers.Tier.PREMIUM:
			data["premium_completed"] = int(data["premium_completed"]) + 1
	data["career_level"] = career_level()


## Debug/balancing: average earnings per successful ride and rides needed
## for the cheapest next upgrade at that rate.
func average_earnings() -> float:
	var n := int(data["successful_rides"])
	return float(data["total_earned"]) / float(n) if n > 0 else 0.0


func rides_to_next_upgrade() -> int:
	var cheapest := -1
	for id in UpgradeCatalog.IDS:
		var c := next_cost(id)
		if c > 0 and (cheapest < 0 or c < cheapest):
			cheapest = c
	if cheapest < 0:
		return 0
	var avg := average_earnings()
	if cheapest <= cash():
		return 0
	return ceili(float(cheapest - cash()) / avg) if avg > 0.0 else -1
