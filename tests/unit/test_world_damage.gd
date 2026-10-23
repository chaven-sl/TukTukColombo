extends "res://tests/test_case.gd"
## v0.03A2 pure logic: crash tiers, damage state machine, surface tags, safe-area insets.

var _cfg: VehicleDamageConfig = load("res://resources/vehicles/vehicle_damage.tres")
var _bodies: Array[StaticBody3D] = []


func _free_bodies() -> void:
	for b in _bodies:
		b.free()
	_bodies.clear()


func _event(kind: CollisionEvent.Kind, kmh: float, surface: int) -> CollisionEvent:
	var e := CollisionEvent.new()
	e.kind = kind
	e.impact_speed = kmh / 3.6
	var body := StaticBody3D.new()
	_bodies.append(body)
	if surface >= 0:
		WorldSurface.tag(body, surface)
	e.other_body = body
	return e


func test_tiers_by_surface_and_speed() -> void:
	var T := VehicleDamageState.Tier
	var W := WorldSurface.Type
	check_eq(VehicleDamageState.tier_for(_event(CollisionEvent.Kind.WORLD, 10.0, W.BUILDING), _cfg), T.LIGHT, "10 km/h building scrape → LIGHT")
	check_eq(VehicleDamageState.tier_for(_event(CollisionEvent.Kind.WORLD, 25.0, W.BUILDING), _cfg), T.HARD, "25 km/h → HARD")
	check_eq(VehicleDamageState.tier_for(_event(CollisionEvent.Kind.WORLD, 40.0, W.WALL), _cfg), T.DISABLING, "40 km/h wall → DISABLING")
	check_eq(VehicleDamageState.tier_for(_event(CollisionEvent.Kind.WORLD, 50.0, W.KERB), _cfg), T.NONE, "kerb never damages")
	check_eq(VehicleDamageState.tier_for(_event(CollisionEvent.Kind.WORLD, 50.0, W.FORECOURT), _cfg), T.NONE, "ground never damages")
	check_eq(VehicleDamageState.tier_for(_event(CollisionEvent.Kind.TRAFFIC, 50.0, W.BUILDING), _cfg), T.NONE, "traffic handled by incidents, not damage")
	check_eq(VehicleDamageState.tier_for(_event(CollisionEvent.Kind.WORLD, 30.0, W.PROP), _cfg), T.HARD, "lamp post / tree is solid")
	check(_cfg.hard_min_kmh >= 12.0 and _cfg.disabling_min_kmh > _cfg.hard_min_kmh + 10.0, "thresholds sane (no resets from tiny bumps)")
	_free_bodies()


func test_state_machine() -> void:
	var T := VehicleDamageState.Tier
	var S := VehicleDamageState.State
	var d := VehicleDamageState.new(_cfg)
	check(not d.on_impact(T.LIGHT), "LIGHT changes nothing")
	check_eq(d.state, S.HEALTHY, "still HEALTHY")
	check(d.on_impact(T.HARD), "HARD → DAMAGED")
	check_eq(d.throttle_scale(), 0.0, "engine cut right after a hard crash")
	d.tick(_cfg.immobilised_seconds + 0.1)
	check_near(d.throttle_scale(), _cfg.limp_throttle, 0.001, "then limp")
	d.tick(_cfg.limp_seconds)
	check_eq(d.state, S.HEALTHY, "limp wears off")
	d.on_impact(T.HARD)
	check(d.on_impact(T.HARD), "second HARD while DAMAGED → DISABLED")
	check_eq(d.state, S.DISABLED, "DISABLED")
	check_eq(d.throttle_scale(), 0.0, "no drive while DISABLED")
	check(not d.on_impact(T.DISABLING), "already DISABLED")
	d.recovered()
	check_eq(d.state, S.HEALTHY, "recovered → HEALTHY")
	check(not d.on_impact(T.DISABLING), "post-reset grace prevents reset loops")
	d.tick(_cfg.post_reset_grace + 0.1)
	check(d.on_impact(T.DISABLING), "after grace a disabling crash counts again")


func test_surface_tags() -> void:
	var b := StaticBody3D.new()
	check_eq(WorldSurface.of_body(b), WorldSurface.Type.PROP, "untagged solid → PROP")
	b.set_meta(&"is_ground", true)
	check_eq(WorldSurface.of_body(b), WorldSurface.Type.FORECOURT, "ground → FORECOURT")
	WorldSurface.tag(b, WorldSurface.Type.WALL)
	check_eq(WorldSurface.of_body(b), WorldSurface.Type.WALL, "tag wins")
	check_eq(WorldSurface.of_body(null), WorldSurface.Type.VOID, "null → VOID")
	check(WorldSurface.is_solid_structure(WorldSurface.Type.BUILDING) and not WorldSurface.is_solid_structure(WorldSurface.Type.SIDEWALK), "solid set")
	b.free()


func test_safe_area_insets() -> void:
	var r := HudSafeArea.apply_insets(Rect2(0, 0, 1600, 720), Vector4(56, 10, 24, 30))
	check_eq(r, Rect2(56, 10, 1520, 680), "insets applied")
