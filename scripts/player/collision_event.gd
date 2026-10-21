class_name CollisionEvent
extends RefCounted
## A player impact classified by severity. Emitted by TukController.

enum Severity { MINOR, MAJOR }
enum Kind { TRAFFIC, WORLD, ROLLOVER }

var severity: Severity = Severity.MINOR
var kind: Kind = Kind.WORLD
## Change in player velocity across the impact (horizontal), stored in
## internal m/s. Use impact_speed_kmh() for anything human-readable.
var impact_speed := 0.0
var position := Vector3.ZERO
## Direction of the impulse the player received (horizontal, normalised).
var impulse_direction := Vector3.ZERO
var other_agent_id := -1
var timestamp := 0.0


func impact_speed_kmh() -> float:
	return impact_speed * 3.6
