class_name JobTiers
extends RefCounted
## Lightweight ride tiers (v0.04): STANDARD / EXPRESS / PREMIUM. Not a
## mission system — a tier is a label on an ordinary hire that changes the
## passenger's expectations (through PassengerProfile data, the existing
## single satisfaction model) and the payout. Personality stays separate.

enum Tier { STANDARD, EXPRESS, PREMIUM }

const KEYS := ["JOB_STANDARD", "JOB_EXPRESS", "JOB_PREMIUM"]


## Rolls a tier for a new offer at `career_level`.
static func roll(career_level: int, rng: RandomNumberGenerator, c: EconomyConfig) -> Tier:
	var extra := c.tier_chance_per_level * maxi(career_level - c.premium_from_level, 0)
	var r := rng.randf()
	if career_level >= c.premium_from_level and r < c.premium_chance + extra:
		return Tier.PREMIUM
	if career_level >= c.express_from_level and r < c.premium_chance + c.express_chance + extra * 2.0:
		return Tier.EXPRESS
	return Tier.STANDARD


## The profile this job's passenger rides with: the base personality with
## tier expectations layered on (a copy; shared resources are never edited).
static func profile_for(base: PassengerProfile, tier: Tier, c: EconomyConfig) -> PassengerProfile:
	if tier == Tier.STANDARD:
		return base
	var p := base.duplicate() as PassengerProfile
	match tier:
		Tier.EXPRESS:
			p.expected_speed_kmh = base.expected_speed_kmh * c.express_speed_factor
			p.time_weight = minf(base.time_weight + 0.1, 1.0)
		Tier.PREMIUM:
			p.collision_penalty_multiplier = base.collision_penalty_multiplier * c.premium_collision_multiplier
			p.comfort_weight = minf(base.comfort_weight + c.premium_comfort_weight_bonus, 1.0)
	return p


static func cash_multiplier(tier: Tier, c: EconomyConfig) -> float:
	match tier:
		Tier.EXPRESS:
			return c.express_cash_multiplier
		Tier.PREMIUM:
			return c.premium_cash_multiplier
	return 1.0


static func reputation_bonus(tier: Tier, c: EconomyConfig) -> int:
	match tier:
		Tier.EXPRESS:
			return c.express_reputation_bonus
		Tier.PREMIUM:
			return c.premium_reputation_bonus
	return 0
