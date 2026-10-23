class_name WorldSurface
extends RefCounted
## Lightweight world surface semantics (v0.03A2). The world/environment layer
## owns this — TukController never needs to know what it hit beyond a body.
##
##   ROAD      normal driving space (asphalt, junctions)
##   SIDEWALK  raised pavement: physically accessible, dangerous (pedestrians)
##   FORECOURT open ground off the road inside the district: accessible
##   KERB      kerb face (scrapes, never a damaging crash)
##   BUILDING  buildings, shopfronts, district boundary blocks: solid
##   WALL      walls, jersey barriers, tunnel walls: solid
##   PROP      solid street furniture (poles, trees, shelters) / impact props
##   VOID      outside the playable district or below the world: failsafe only
##
## Static bodies are tagged once at build time (meta "surface"); points are
## classified on demand (rare: evasion targets, recovery, tests).

enum Type { ROAD, SIDEWALK, FORECOURT, KERB, BUILDING, WALL, PROP, VOID }

const META := &"surface"


static func tag(body: Object, type: Type) -> void:
	body.set_meta(META, type)


static func of_body(body: Object) -> Type:
	if body == null:
		return Type.VOID
	if body.has_meta(META):
		return body.get_meta(META) as Type
	if body.has_meta(&"is_ground"):
		return Type.FORECOURT
	return Type.PROP


## Solid structures that can damage the tuk in a hard crash.
static func is_solid_structure(type: Type) -> bool:
	return type == Type.BUILDING or type == Type.WALL or type == Type.PROP


## Classifies a point: VOID outside the district or below the world; ROAD on
## a lane (or junction); SIDEWALK when raised next to a road; else FORECOURT.
static func classify_point(network: RoadNetwork, pos: Vector3) -> Type:
	if pos.y < -2.0 or not network.district_rect.has_point(Vector2(pos.x, pos.z)):
		return Type.VOID
	if is_on_carriageway(network, pos, 0.2):
		return Type.ROAD
	if pos.y > 0.08 and network.distance_to_road(pos) < 8.0:
		return Type.SIDEWALK
	return Type.FORECOURT


## True if `pos` lies on a traffic lane (within half a lane width + margin).
static func is_on_carriageway(network: RoadNetwork, pos: Vector3, margin: float = 0.4) -> bool:
	for ix in network.intersections:
		var d := Vector2(pos.x - ix.global_position.x, pos.z - ix.global_position.z)
		if absf(d.x) < ix.size * 0.5 + margin and absf(d.y) < ix.size * 0.5 + margin:
			return true
	for lane in network.lanes:
		if lane.is_connector:
			continue
		var s := lane.closest_s(pos)
		var p := lane.sample_position(s)
		if Vector2(p.x - pos.x, p.z - pos.z).length() < lane.width * 0.5 + margin:
			return true
	return false
