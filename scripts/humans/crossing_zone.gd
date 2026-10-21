class_name CrossingZone
extends RefCounted
## A place where pedestrians cross a road segment. Knows the lanes it crosses
## (and where on each lane the conflict point is) so it can answer "how soon
## will a vehicle reach me?" without any per-pedestrian physics queries.
##
## Traffic only reads `occupied_count` (via Lane.crossings) to yield; it never
## depends on HumanAgent.

enum Style { DESIGNATED, UNCONTROLLED }
enum Level { SAFE, QUESTIONABLE, DANGER }

var id := -1
var style: Style = Style.DESIGNATED
var segment: RoadSegment
var s := 0.0
## Sidewalk walking-line endpoints (side −1 = A, side +1 = B).
var point_a := Vector3.ZERO
var point_b := Vector3.ZERO
var node_a := -1
var node_b := -1
var center := Vector3.ZERO
## Unit direction along the road (segment travel direction) and across it.
var road_dir := Vector3.FORWARD
var across_dir := Vector3.RIGHT
## Half the distance between the two sidewalk walking lines (m).
var half_span := 8.0
## Half width of the drivable surface between kerb faces (m).
var road_half_width := 7.6
var lanes: Array[Lane] = []
var lane_conflict_s := PackedFloat32Array()

## People currently on the carriageway (traffic yields while > 0).
var occupied_count := 0
var waiting_count := 0

# Assessment outputs (last call).
var last_min_ttc := INF
var last_threat_is_player := false


func length() -> float:
	return point_a.distance_to(point_b)


## Danger assessment for someone who needs `time_to_clear` seconds and wants
## an extra `margin` seconds of gap. Considers lane traffic and the player.
func assess(time_to_clear: float, margin: float, traffic: TrafficManager, player_pos: Vector3,
		player_vel: Vector3, awareness_range: float) -> Level:
	var min_ttc := INF
	var blocked := false
	last_threat_is_player = false
	if traffic != null:
		for i in lanes.size():
			var lane := lanes[i]
			var conflict := lane_conflict_s[i]
			for agent in lane.agents:
				var r := _agent_ttc(agent, agent.s, conflict, awareness_range)
				if r < 0.0:
					blocked = true
				else:
					min_ttc = minf(min_ttc, r)
			for pred in lane.predecessors:
				for agent in pred.agents:
					var r2 := _agent_ttc(agent, agent.s - pred.length, conflict, awareness_range)
					if r2 < 0.0:
						blocked = true
					else:
						min_ttc = minf(min_ttc, r2)
	var player_ttc := player_time_to_conflict(player_pos, player_vel, awareness_range)
	if player_ttc < 0.0:
		blocked = true
		last_threat_is_player = true
	elif player_ttc < min_ttc:
		min_ttc = player_ttc
		last_threat_is_player = true
	last_min_ttc = min_ttc
	if blocked or min_ttc < time_to_clear + 0.3:
		return Level.DANGER
	if min_ttc < time_to_clear + margin:
		return Level.QUESTIONABLE
	return Level.SAFE


## Seconds until the agent's front reaches the crossing band; −1 when the
## vehicle body already occupies the band; INF when irrelevant.
func _agent_ttc(agent: TrafficAgent, s_on_lane: float, conflict: float, awareness_range: float) -> float:
	var front := s_on_lane + agent.half_length
	var rear := s_on_lane - agent.half_length
	if front > conflict - 1.8 and rear < conflict + 1.8:
		return -1.0
	var distance := conflict - 1.8 - front
	if distance < 0.0 or distance > awareness_range:
		return INF
	return distance / maxf(agent.speed, 0.1)


## Player tuk time to reach the crossing band (s): −1 = on it, INF = not coming.
func player_time_to_conflict(player_pos: Vector3, player_vel: Vector3, awareness_range: float) -> float:
	var rel := player_pos - center
	var along := rel.dot(road_dir)
	var lateral := rel.dot(across_dir)
	if absf(lateral) > half_span + 1.5:
		return INF
	if absf(along) < 1.8 + 1.4:
		return -1.0
	var closing := -signf(along) * player_vel.dot(road_dir)
	if closing < 0.5:
		return INF
	var distance := absf(along) - 1.8 - 1.4
	if distance > awareness_range:
		return INF
	return distance / closing
