class_name SkillEvent
extends RefCounted
## A confirmed driving-skill event produced by NearMissDetector.
## The detector only describes what happened; ScoringSystem decides its value.

enum Type { CLOSE_CALL, TIGHT_GAP, ONCOMING }

var type: Type = Type.CLOSE_CALL
## Closest edge-to-edge clearance in metres (the smaller side for TIGHT_GAP).
var clearance := 0.0
## Relative speed in m/s at the moment the threat crossed the player.
var relative_speed := 0.0
## -1 = threat on the player's left, +1 = right, 0 = both sides (TIGHT_GAP).
var side := 0
var agent_ids := PackedInt32Array()
var timestamp := 0.0
## True when the threat was travelling against the player. ONCOMING is
## architected but not scored separately in v0.01.
var is_oncoming := false


static func type_key(t: int) -> String:
	match t:
		Type.CLOSE_CALL:
			return "UI_CLOSE_CALL"
		Type.TIGHT_GAP:
			return "UI_TIGHT_GAP"
		Type.ONCOMING:
			return "UI_ONCOMING"
	return "UI_CLOSE_CALL"
