class_name EconomyConfig
extends Resource
## v0.04 progression tunables (cash, reputation, career, job tiers, payout
## bonuses). All values PROTOTYPE BASELINE — tuned by the offline economy
## simulation (tests/scenarios/economy_sim_test.gd), then by playtest.

@export_group("Start")
@export var starting_cash := 1500
@export var starting_reputation := 0

@export_group("Career (reputation thresholds, not spendable)")
@export var career_thresholds := PackedInt32Array([0, 50, 150, 350, 700])
@export var career_name_keys := PackedStringArray(["CAREER_1", "CAREER_2", "CAREER_3", "CAREER_4", "CAREER_5"])
## Fare multiplier per career level above 1 (+5 % per level).
@export var career_fare_bonus_per_level := 0.05

@export_group("Job tiers")
## Career level from which EXPRESS / PREMIUM offers can appear.
@export var express_from_level := 2
@export var premium_from_level := 3
## Chance an offer rolls EXPRESS / PREMIUM once unlocked (grows with level).
@export var express_chance := 0.3
@export var premium_chance := 0.2
@export var tier_chance_per_level := 0.05
@export var express_cash_multiplier := 1.35
@export var premium_cash_multiplier := 1.6
@export var express_reputation_bonus := 1
@export var premium_reputation_bonus := 2
## EXPRESS: the passenger expects this much faster progress.
@export var express_speed_factor := 1.25
## PREMIUM: higher service expectation (collisions hurt more, comfort counts more).
@export var premium_collision_multiplier := 1.35
@export var premium_comfort_weight_bonus := 0.12

@export_group("Payout bonuses (Rs.)")
@export var clean_ride_bonus := 40
@export var smooth_stop_bonus := 20
@export var fast_fare_bonus := 35
## Per close call / tight gap, scaled by the passenger's close_call_preference
## (only positive preferences pay: a Careful Aunty never rewards risk).
@export var close_call_bonus := 12
@export var tight_gap_bonus := 20
@export var combo_bonus_per_chain := 6
@export var skill_bonus_cap := 120
@export var minor_collision_penalty := 30
@export var major_collision_penalty := 60

@export_group("Reputation (★ per completed ride, from passenger rating %)")
## Rating breakpoints → stars: poor <40 → 1–2, average 40–65 → 3–5,
## good 65–85 → 6–8, excellent ≥85 → 9–12.
@export var rating_breaks := PackedFloat32Array([0.0, 40.0, 65.0, 85.0, 100.0])
@export var rating_stars := PackedInt32Array([1, 3, 6, 9, 12])
@export var max_ride_reputation := 12
