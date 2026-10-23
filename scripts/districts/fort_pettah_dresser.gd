class_name FortPettahDresser
extends Node3D
## FORT–PETTAH GATEWAY district content (v0.03B). Dresses the RoadNetwork
## after it is built — art and collision proxies only; gameplay systems are
## untouched and never read this node.
##
## Five beats, chosen by RoadSegment.zone:
##   station  Fort Railway Station-inspired frontage + colonial arcades
##   olcott   bus corridor: bus stand, shelters, railings, mixed commercial
##   market   Pettah: narrow 2–4 storey shop-houses, awnings, stalls, carts,
##            umbrellas, hanging goods, wires — the densest beat
##   junction compact signalised junction: corner blocks, gantry signs
##   service  warehouses, rear façades, walls, delivery clutter
## Plus implied city: blocked side streets, gateway buildings over the traffic
## portals, boundary façades and a skyline. Collision is separate simple boxes
## (BUILDING / PROP) — never derived from the art meshes.

const BUILDING_SETBACK := 0.15

var network: RoadNetwork
var pedestrians: PedestrianNetwork
var chunks: DistrictChunks
## Skyline / beyond-the-ring massing: long view range, no shadows.
var far_chunks: DistrictChunks
var atlas: SignAtlas
var rng := RandomNumberGenerator.new()
var building_body: StaticBody3D
var prop_body: StaticBody3D
var forecourt_body: StaticBody3D
## Stats (report / tests).
var stats := {"buildings": 0, "props": 0, "signs": 0, "parked_vehicles": 0, "side_streets": 0}
var _shop_signs: Array = []  # [Rect2 uv, Color bg]
var _sign_index := 0
var _spot_positions := PackedVector3Array()
var _parked: Array = []


func dress(p_network: RoadNetwork, p_pedestrians: PedestrianNetwork) -> void:
	network = p_network
	pedestrians = p_pedestrians
	rng.seed = 20261023
	chunks = DistrictChunks.new()
	far_chunks = DistrictChunks.new()
	far_chunks.arch_range = 700.0
	far_chunks.cast_shadows = false
	atlas = SignAtlas.new()
	atlas.name = "SignAtlas"
	add_child(atlas)
	building_body = _body("BuildingProxies", WorldSurface.Type.BUILDING)
	prop_body = _body("PropProxies", WorldSurface.Type.PROP)
	forecourt_body = _body("ForecourtProxies", WorldSurface.Type.SIDEWALK)
	for c in pedestrians.get_children():
		if c is PedestrianSpot:
			_spot_positions.append((c as Node3D).global_position)
	_register_shop_signs()
	for seg in network.segments:
		_dress_segment(seg)
	_dress_station()
	_dress_junction_gantry()
	_dress_portals()
	_dress_boundary_and_skyline()
	atlas.build()
	chunks.commit(self, atlas.material)
	far_chunks.commit(self, null)
	_spawn_parked()
	print("[FortPettah] %d buildings, %d props, %d signs, %d parked, %d side streets, %d art meshes, %d triangles, sign atlas %.0f%%" % [
		stats["buildings"], stats["props"], stats["signs"], stats["parked_vehicles"], stats["side_streets"],
		chunks.mesh_instances, chunks.triangles, atlas.used_fraction() * 100.0])


func _body(n: String, surface: WorldSurface.Type) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = n
	b.collision_layer = 1
	b.collision_mask = 0
	WorldSurface.tag(b, surface)
	add_child(b)
	return b


func _proxy(body: StaticBody3D, xf: Transform3D, centre: Vector3, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.transform = Transform3D(xf.basis.orthonormalized(), xf * centre)
	body.add_child(shape)


# --- frames along a segment ---

## Module frame at distance s on `side` (−1 left, +1 right), `off` metres
## from the centre line; −Z faces the road, +X runs along the street.
func _frame(seg: RoadSegment, s: float, side: float, off: float) -> Transform3D:
	var xf := seg.global_transform
	var p := xf * (seg.local_center(s) + seg.local_right(s) * (side * off))
	var to_road := -(xf.basis * seg.local_right(s)) * side
	to_road.y = 0.0
	return Transform3D(MathUtil.basis_from_forward(to_road.normalized()), Vector3(p.x, 0.0, p.z))


func _near_spot(p: Vector3, r: float) -> bool:
	for sp in _spot_positions:
		if Vector2(sp.x - p.x, sp.z - p.z).length() < r:
			return true
	return false


func _junction_clear(p: Vector3) -> bool:
	for ix in network.intersections:
		var d := Vector2(p.x - ix.global_position.x, p.z - ix.global_position.z)
		if absf(d.x) < ix.size * 0.5 + 9.0 and absf(d.y) < ix.size * 0.5 + 9.0:
			return false
	return true


# --- signs ---

const SHOPS := [
	["SUNRISE TEXTILES", "රෙදි", "துணிக்கடை"],
	["KUMARA ELECTRICALS", "විදුලි උපකරණ", "மின்சாதனங்கள்"],
	["NEW RUBY HARDWARE", "දෘඪාංග", "வன்பொருள்"],
	["PETTAH LUGGAGE HOUSE", "ගමන් මලු", "பயணப் பைகள்"],
	["CEYLON TEA & BITES", "තේ කඩේ", "தேநீர் கடை"],
	["RAJAH WHOLESALE", "තොග වෙළඳසැල", "மொத்த விற்பனை"],
	["CITY CARE PHARMACY", "ඖෂධ", "மருந்தகம்"],
	["STAR PRINTERS", "මුද්‍රණ", "அச்சகம்"],
	["LUCKY MOBILE CENTRE", "ජංගම දුරකථන", "கைபேசி நிலையம்"],
	["SILVA & SONS TRADERS", "වෙළඳසැල", "வியாபாரம்"],
	["FATHIMA FABRICS", "රෙදි", "துணிகள்"],
	["GANESH STORES", "සාප්පුව", "கடை"],
	["GOLDEN SPICE CO.", "කුළුබඩු", "மசாலா பொருட்கள்"],
	["METRO FANCY GOODS", "සෙල්ලම් බඩු", "அலங்கார பொருட்கள்"],
	["PERERA BOOKSHOP", "පොත් හල", "புத்தகக் கடை"],
	["HOTEL NEW LAKSHMI", "ආපන ශාලාව", "உணவகம்"],
]
const SIGN_COLOURS := [
	[Color(0.95, 0.78, 0.15), Color(0.12, 0.1, 0.08)], [Color(0.12, 0.35, 0.65), Color(1, 1, 1)],
	[Color(0.8, 0.12, 0.1), Color(1, 0.95, 0.85)], [Color(0.95, 0.94, 0.9), Color(0.1, 0.25, 0.55)],
	[Color(0.15, 0.5, 0.3), Color(1, 0.98, 0.9)], [Color(0.98, 0.55, 0.12), Color(0.1, 0.08, 0.08)],
	[Color(0.35, 0.18, 0.45), Color(1, 0.92, 0.6)],
]


func _register_shop_signs() -> void:
	for i in SHOPS.size():
		var pal: Array = SIGN_COLOURS[i % SIGN_COLOURS.size()]
		var fg: Color = pal[1]
		var uv := atlas.add({"px": Vector2i(252, 80), "bg": pal[0], "border": fg,
				"lines": [[SHOPS[i][0], 21, fg], [SHOPS[i][1] + "  •  " + SHOPS[i][2], 16, fg, false]]})
		_shop_signs.append(uv)


func _next_shop_sign() -> Rect2:
	_sign_index += 1
	return _shop_signs[_sign_index % _shop_signs.size()]


## A sign quad facing −Z in `xf` (local), sampling `uv` of the atlas.
func _sign_quad(xf: Transform3D, size: Vector2, uv: Rect2) -> void:
	var c := chunks.at(xf.origin)
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	c.signs.quad(xf * Vector3(hx, -hy, -0.02), xf * Vector3(-hx, -hy, -0.02), xf * Vector3(-hx, hy, -0.02), xf * Vector3(hx, hy, -0.02),
			Color.WHITE, Rect2(uv.position + Vector2(0, uv.size.y), Vector2(uv.size.x, -uv.size.y)))
	stats["signs"] += 1


func _place_signs(slots: Array) -> void:
	for slot: Dictionary in slots:
		_sign_quad(slot["xf"], slot["size"], _next_shop_sign())


# --- segment dressing ---

func _dress_segment(seg: RoadSegment) -> void:
	for side: float in [-1.0, 1.0]:
		match seg.zone:
			&"station":
				if side > 0.0 or seg.is_curved():
					_row(seg, side, "fort")
				# The station itself (side −1 of the straight) is _dress_station().
			&"olcott":
				_row(seg, side, "olcott")
			&"market":
				_row(seg, side, "market")
			&"junction":
				_row(seg, side, "junction")
			&"service":
				_row(seg, side, "service")
		_street_furniture(seg, side)


func _row(seg: RoadSegment, side: float, style: String) -> void:
	var c := chunks.at(_frame(seg, seg.length * 0.5, side, 0).origin)
	var s := 3.0
	var side_street_at := -1.0
	if seg.length > 60.0 and style != "station":
		side_street_at = seg.length * rng.randf_range(0.35, 0.65)
	while s < seg.length - 3.0:
		var w := _module_width(style)
		var mid := s + w * 0.5
		if mid > seg.length - 2.0:
			break
		var front := seg.outer_extent(mid, side) + BUILDING_SETBACK
		var xf := _frame(seg, mid, side, front)
		if not _junction_clear(xf.origin):
			s += w
			continue
		if side_street_at > 0.0 and absf(mid - side_street_at) < w * 0.5 + 1.0:
			_side_street(seg, mid, side, front, style)
			side_street_at = -1.0
			s += 9.0
			continue
		c = chunks.at(xf.origin)
		_building(c, xf, style, w)
		s += w + (0.0 if style == "market" else rng.randf_range(0.0, 0.6))


func _module_width(style: String) -> float:
	match style:
		"market":
			return rng.randf_range(4.0, 6.5)
		"fort":
			return rng.randf_range(9.0, 14.0)
		"service":
			return rng.randf_range(10.0, 18.0)
		_:
			return rng.randf_range(5.5, 9.0)


func _building(c: DistrictChunks.Builders, xf: Transform3D, style: String, w: float) -> void:
	var p := {"width": w}
	var depth := 9.0
	var height := 0.0
	match style:
		"fort":
			var wall: Color = [ArtPalette.STATION_WHITE, ArtPalette.CREAM, ArtPalette.OFF_WHITE, Color(0.86, 0.82, 0.72)][rng.randi() % 4]
			BuildingKit.arcade(c, xf, w, maxi(2, int(w / 4.0)), ArtPalette.weather(wall, 0.12), rng.randi_range(2, 3), rng)
			height = 3 * BuildingKit.STOREY + 0.6
			depth = 12.4
			_sign_quad(xf * Transform3D(Basis.IDENTITY, Vector3(0, 2.9, 1.1)), Vector2(minf(w * 0.6, 4.5), 0.55), _next_shop_sign())
		"service":
			if rng.randf() < 0.35:
				BuildingKit.boundary_wall(c, xf, w, 2.8, ArtPalette.pick(ArtPalette.WALLS, rng), rng.randf() < 0.5)
				_proxy(building_body, xf, Vector3(0, 1.4, 0.15), Vector3(w, 2.8, 0.3))
				stats["buildings"] += 1
				return
			height = rng.randf_range(5.0, 8.0)
			depth = rng.randf_range(10.0, 16.0)
			_place_signs(BuildingKit.warehouse(c, xf, w, depth, height, ArtPalette.pick(ArtPalette.WALLS, rng).darkened(0.05), rng))
			if rng.randf() < 0.6:
				StreetKit.boxes(c, xf * Transform3D(Basis.IDENTITY, Vector3(w * 0.3, 0.6, -0.6)), 4, rng)
		_:
			var storeys := rng.randi_range(2, 4) if style != "olcott" else rng.randi_range(3, 4)
			p["storeys"] = storeys
			p["depth"] = depth
			p["wall"] = ArtPalette.pick(ArtPalette.WALLS, rng)
			p["grime"] = rng.randf_range(0.05, 0.35)
			p["roof"] = [BuildingKit.Roof.PARAPET, BuildingKit.Roof.PARAPET, BuildingKit.Roof.PITCHED_SHEET, BuildingKit.Roof.STEPPED, BuildingKit.Roof.PITCHED_TILE][rng.randi() % 5]
			p["balcony"] = rng.randf() < 0.35
			var market := style == "market"
			p["ground"] = [BuildingKit.Ground.SHOP_OPEN, BuildingKit.Ground.SHOP_OPEN, BuildingKit.Ground.HALF_SHUTTER,
					BuildingKit.Ground.SHUTTERED, BuildingKit.Ground.GLAZED][rng.randi() % (3 if market else 5)]
			if market or rng.randf() < 0.6:
				p["awning"] = ArtPalette.pick(ArtPalette.ACCENTS, rng)
				if rng.randf() < 0.5:
					p["awning_stripe"] = ArtPalette.OFF_WHITE
			height = storeys * BuildingKit.STOREY
			_place_signs(BuildingKit.shop_house(c, xf, p, rng))
			if market:
				_market_spill(c, xf, w)
			elif rng.randf() < 0.3:
				StreetKit.stools(c, xf * Transform3D(Basis.IDENTITY, Vector3(-w * 0.3, 0.15, -0.8)), 3, ArtPalette.pick(ArtPalette.ACCENTS, rng))
	_proxy(building_body, xf, Vector3(0, height * 0.5, depth * 0.5), Vector3(w - 0.1, height, depth))
	stats["buildings"] += 1


## Goods spilling onto the pavement in front of a Pettah shop (on the
## building side of the pavement — the walking line stays usable).
func _market_spill(c: DistrictChunks.Builders, xf: Transform3D, w: float) -> void:
	var roll := rng.randf()
	var local := xf * Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-w * 0.25, w * 0.25), 0.15, -0.75))
	if roll < 0.25:
		StreetKit.sacks(c, local, rng.randi_range(3, 6), rng)
		_proxy(prop_body, local, Vector3(0, 0.4, 0), Vector3(1.6, 0.8, 0.7))
	elif roll < 0.45:
		StreetKit.boxes(c, local, rng.randi_range(2, 5), rng)
	elif roll < 0.6:
		StreetKit.hanging_goods(c, xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.15, 0)), w * 0.8, rng)
	elif roll < 0.75:
		StreetKit.stall(c, local * Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.3)), rng.randi() % 3, rng)
		_proxy(prop_body, local, Vector3(0, 0.45, -0.3), Vector3(1.9, 0.9, 0.9))
	stats["props"] += 1


## Blocked side street: a paved stub, a believable termination (barrier,
## construction or market activity) and a façade beyond — implies the city
## continues without building the road. Collision across the stub.
func _side_street(seg: RoadSegment, s: float, side: float, front: float, style: String) -> void:
	var xf := _frame(seg, s, side, front)
	var c := chunks.at(xf.origin)
	c.plaster.box(xf, Vector3(0, 0.08, 9.0), Vector3(7.5, 0.16, 18.0), ArtPalette.ASPHALT.lightened(0.08), 4)
	var kind := rng.randi() % 3
	var stop := xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 4.0))
	match kind:
		0:
			StreetKit.barrier(c, stop, 7.0)
		1:
			StreetKit.construction(c, stop, rng)
		_:
			StreetKit.handcart(c, stop * Transform3D(Basis(Vector3.UP, 0.6), Vector3(-1.5, 0, 1.0)), 1, rng)
			StreetKit.stall(c, stop * Transform3D(Basis.IDENTITY, Vector3(1.6, 0, 0.5)), rng.randi() % 3, rng)
			StreetKit.barrier(c, stop * Transform3D(Basis.IDENTITY, Vector3(0, 0, 2.0)), 7.0)
	_proxy(prop_body, stop, Vector3(0, 0.6, 0.0), Vector3(7.5, 1.2, 0.5))
	# Something parked in the side street beyond the termination.
	var kind_parked: String = ["tuk", "van", "tuk"][rng.randi() % 3]
	_parked.append([kind_parked, xf * Transform3D(Basis(Vector3.UP, 0.15), Vector3(1.6, 0, 8.5)), rng.randi() % 4])
	# The street "continues" to façades further back.
	var far := xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 19.0))
	BuildingKit.background_block(c, far, 14.0, 10.0, rng.randf_range(9.0, 15.0), ArtPalette.pick(ArtPalette.WALLS, rng))
	_proxy(building_body, far, Vector3(0, 6, 5), Vector3(14, 12, 10))
	for sx: float in [-1.0, 1.0]:  # flanking walls so the stub reads as a street
		BuildingKit.boundary_wall(c, xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(sx * 3.9, 0, 9.0)), 18.0, 3.0, ArtPalette.pick(ArtPalette.WALLS, rng), false)
		_proxy(building_body, xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(sx * 3.9, 0, 9.0)), Vector3(0, 1.5, 0.15), Vector3(18.0, 3.0, 0.3))
	stats["side_streets"] += 1


func _street_furniture(seg: RoadSegment, side: float) -> void:
	var zone := seg.zone
	var s := 8.0 + rng.randf() * 6.0
	var prev_pole := PackedVector3Array()
	var pole_spacing := 26.0 if zone == &"market" else 32.0
	while s < seg.length - 6.0:
		var xf := _frame(seg, s, side, seg.half_width(s) + 0.55)
		if not _junction_clear(xf.origin) or _near_spot(xf.origin, 3.0):
			s += pole_spacing
			prev_pole = PackedVector3Array()
			continue
		var c := chunks.at(xf.origin)
		var to_road := -xf.basis.z
		var along := xf.basis.x
		if side > 0.0 or zone == &"market" or zone == &"service":
			var pts := StreetKit.utility_pole(c, xf.origin + Vector3(0, 0.15, 0), along, rng.randf() < 0.3)
			_proxy(prop_body, Transform3D(Basis.IDENTITY, xf.origin), Vector3(0, 4.5, 0), Vector3(0.3, 9.0, 0.3))
			if not prev_pole.is_empty():
				StreetKit.wires(c, prev_pole, pts)
			# Across-the-street wires in the market (the Pettah tangle).
			if zone == &"market" and side > 0.0:
				var opposite := _frame(seg, s, -side, seg.half_width(s) + 0.55).origin + Vector3(0, 8.0, 0)
				c.detail.wire(pts[2], opposite, 1.2, 0.04, Color(0.05, 0.05, 0.05), 8)
			prev_pole = pts
		else:
			StreetKit.street_lamp(c, xf.origin + Vector3(0, 0.15, 0), to_road)
			_proxy(prop_body, Transform3D(Basis.IDENTITY, xf.origin), Vector3(0, 3.6, 0), Vector3(0.2, 7.2, 0.2))
		stats["props"] += 1
		# Zone extras on the pavement.
		var extra := _frame(seg, s + pole_spacing * 0.5, side, seg.outer_extent(s, side) - 0.9)
		if s + pole_spacing * 0.5 < seg.length - 4.0 and _junction_clear(extra.origin) and not _near_spot(extra.origin, 4.0):
			var ec := chunks.at(extra.origin)
			match zone:
				&"market":
					if rng.randf() < 0.55:
						StreetKit.handcart(ec, extra * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0.15, 0)), rng.randi() % 3, rng)
						_proxy(prop_body, extra, Vector3(0, 0.9, 0), Vector3(2.4, 1.6, 1.3))
					else:
						StreetKit.umbrella(ec, extra.origin + Vector3(0, 0.15, 0), ArtPalette.pick(ArtPalette.ACCENTS, rng), 1.4)
						StreetKit.stools(ec, extra * Transform3D(Basis.IDENTITY, Vector3(-0.5, 0.15, 0.2)), 2, ArtPalette.pick(ArtPalette.ACCENTS, rng))
				&"olcott":
					if side < 0.0:
						StreetKit.bus_shelter(ec, extra * Transform3D(Basis.IDENTITY, Vector3(0, 0.15, 0.3)))
						_proxy(prop_body, extra, Vector3(0, 1.3, 1.25), Vector3(4.8, 2.6, 0.2))
					else:
						StreetKit.railing(ec, extra.origin + extra.basis.x * -6.0 + Vector3(0, 0.15, 0) - extra.basis.z * 0.6,
								extra.origin + extra.basis.x * 6.0 + Vector3(0, 0.15, 0) - extra.basis.z * 0.6, Color(0.85, 0.75, 0.15))
				&"station":
					StreetKit.shade_tree(ec, extra.origin + Vector3(0, 0.15, 0), rng)
					_proxy(prop_body, Transform3D(Basis.IDENTITY, extra.origin), Vector3(0, 1.6, 0), Vector3(0.4, 3.2, 0.4))
				&"service":
					if rng.randf() < 0.5:
						StreetKit.boxes(ec, extra * Transform3D(Basis.IDENTITY, Vector3(0, 0.15, 0)), 4, rng)
				_:
					for k in 3:
						StreetKit.bollard(ec, (extra * Vector3(-1.2 + k * 1.2, 0.15, -0.5)), true)
		s += pole_spacing
	# Kerb drains and road patches.
	if zone == &"market" or zone == &"service" or zone == &"junction":
		var a := _frame(seg, 2.0, side, seg.half_width(2.0) + 0.1).origin
		var b := _frame(seg, seg.length - 2.0, side, seg.half_width(seg.length - 2.0) + 0.1).origin
		if not seg.is_curved():
			StreetKit.drain(chunks.at(a), a + Vector3(0, -0.15, 0), b + Vector3(0, -0.15, 0))
	if side > 0.0:
		var n := int(seg.length / 25.0)
		for k in n:
			var ss := rng.randf_range(2.0, seg.length - 2.0)
			var off := rng.randf_range(-seg.carriageway_half(ss) * 0.8, seg.carriageway_half(ss) * 0.8)
			var pxf := _frame(seg, ss, 1.0, off)
			StreetKit.road_patch(chunks.at(pxf.origin), pxf, Vector2(rng.randf_range(1.2, 3.5), rng.randf_range(0.8, 2.5)), rng.randi() % 3)
	if seg.zone == &"olcott" and not seg.is_curved() and side < 0.0 and seg.length > 50.0:
		# Painted bus bay on the corridor's kerb-side shoulder.
		var bay := _frame(seg, seg.length * 0.4, side, seg.carriageway_half(seg.length * 0.4) + 1.3)
		var bc := chunks.at(bay.origin)
		bc.detail.box(bay, Vector3(0, 0.013, 0), Vector3(30.0, 0.005, 0.12), ArtPalette.AWNING_YELLOW, 4)
		bc.detail.box(bay, Vector3(0, 0.013, -1.25), Vector3(30.0, 0.005, 0.12), ArtPalette.AWNING_YELLOW, 4)


# --- the Fort station landmark ---

func _dress_station() -> void:
	var seg: RoadSegment = null
	for sg in network.segments:
		if sg.name == "StationFrontage":
			seg = sg
	if seg == null:
		return
	var side := -1.0
	var forecourt := 5.0
	var front := seg.outer_extent(90.0, side) + forecourt
	var centre := _frame(seg, 90.0, side, front)
	var c := chunks.at(centre.origin)
	var white := ArtPalette.STATION_WHITE
	var roof := ArtPalette.ROOF_DARK
	# Forecourt plaza (raised to pavement level, driveable like a pavement).
	var plaza := _frame(seg, 90.0, side, seg.outer_extent(90.0, side) + forecourt * 0.5)
	c.plaster.box(plaza, Vector3(0, 0.075, 0), Vector3(150.0, 0.15, forecourt + 0.2), Color(0.74, 0.72, 0.68), 4 | 32)
	_proxy(forecourt_body, plaza, Vector3(0, 0.075, 0), Vector3(150.0, 0.15, forecourt + 0.2))
	for k in 14:  # paving joints
		c.detail.box(plaza, Vector3(-70.0 + k * 10.8, 0.152, 0), Vector3(0.06, 0.004, forecourt), Color(0.6, 0.58, 0.55))
	# Long two-storey arcaded frontage either side of the central pavilion.
	for half: float in [-1.0, 1.0]:
		for b in 6:
			var x := half * (9.0 + 5.0 + b * 10.0)
			var bxf := centre * Transform3D(Basis.IDENTITY, Vector3(x, 0, 0))
			var bc := chunks.at(bxf.origin)
			BuildingKit.arcade(bc, bxf, 10.0, 2, white, 2, rng)
			# Dark tiled hip roof behind the parapet.
			bc.plaster.quad(bxf * Vector3(-5.0, 7.0, 1.0), bxf * Vector3(5.0, 7.0, 1.0), bxf * Vector3(5.0, 9.6, 7.5), bxf * Vector3(-5.0, 9.6, 7.5), roof)
			bc.plaster.quad(bxf * Vector3(-5.0, 9.6, 7.5), bxf * Vector3(5.0, 9.6, 7.5), bxf * Vector3(5.0, 7.0, 14.0), bxf * Vector3(-5.0, 7.0, 14.0), roof.darkened(0.1))
			_proxy(building_body, bxf, Vector3(0, 3.5, 7.4), Vector3(10.0, 7.0, 10.0))
			stats["buildings"] += 1
		# End pavilions (slightly projecting, taller).
		var exf := centre * Transform3D(Basis.IDENTITY, Vector3(half * 74.0, 0, -0.8))
		var ec := chunks.at(exf.origin)
		ec.plaster.box(exf, Vector3(0, 5.2, 6.0), Vector3(8.0, 10.4, 12.0), white)
		for k in 2:
			ec.glass.box(exf, Vector3(-1.8 + k * 3.6, 6.8, -0.03), Vector3(1.4, 2.4, 0.04), ArtPalette.WINDOW_DARK)
			ec.plaster.arch_panel(exf * Transform3D(Basis.IDENTITY, Vector3(-1.8 + k * 3.6, 0, -0.02)), 3.6, 3.8, 2.4, 2.4, white, 7, Color(0.18, 0.16, 0.15))
		ec.plaster.box(exf, Vector3(0, 10.8, 0.2), Vector3(8.4, 0.8, 0.5), white.darkened(0.03))
		_proxy(building_body, exf, Vector3(0, 5.2, 6.0), Vector3(8.0, 10.4, 12.0))
	# Central entrance pavilion: big arch, three storeys, pediment, canopy.
	c.plaster.box(centre, Vector3(0, 6.5, 7.0), Vector3(18.0, 13.0, 14.0), white, 63 & ~32)
	c.plaster.arch_panel(centre * Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.01)), 18.0, 7.5, 7.0, 4.2, white, 9, Color(0.16, 0.14, 0.13))
	c.plaster.box(centre, Vector3(0, 10.25, 0.05), Vector3(18.0, 5.5, 0.1), white)
	for k in 3:
		c.glass.box(centre, Vector3(-5.0 + k * 5.0, 9.6, -0.04), Vector3(2.0, 2.6, 0.04), ArtPalette.WINDOW_DARK)
		c.plaster.box(centre, Vector3(-5.0 + k * 5.0, 11.1, -0.12), Vector3(2.5, 0.25, 0.25), white.darkened(0.04))
	for k in 4:  # pilasters
		c.plaster.box(centre, Vector3(-8.6 + k * 5.73, 6.5, -0.15), Vector3(0.6, 13.0, 0.3), white.lightened(0.05))
	c.plaster.quad(centre * Vector3(-9.5, 13.0, -0.2), centre * Vector3(9.5, 13.0, -0.2), centre * Vector3(0.0, 15.8, -0.2), centre * Vector3(0.0, 15.8, -0.2), white)  # pediment
	c.plaster.quad(centre * Vector3(-9.5, 13.0, -0.2), centre * Vector3(0.0, 15.8, -0.2), centre * Vector3(0.0, 15.8, 8.0), centre * Vector3(-9.5, 13.0, 8.0), roof)
	c.plaster.quad(centre * Vector3(0.0, 15.8, -0.2), centre * Vector3(9.5, 13.0, -0.2), centre * Vector3(9.5, 13.0, 8.0), centre * Vector3(0.0, 15.8, 8.0), roof.darkened(0.08))
	# Entrance canopy (concrete cantilever) over the steps.
	c.plaster.box(centre, Vector3(0, 4.6, -2.2), Vector3(14.0, 0.3, 4.6), white.darkened(0.05))
	for sx: float in [-6.5, 6.5]:
		c.metal.cylinder(centre, Vector3(sx, 2.3, -4.2), 0.12, 4.6, 8, ArtPalette.CONCRETE)
	c.plaster.box(centre, Vector3(0, 0.25, -1.0), Vector3(12.0, 0.2, 2.0), ArtPalette.CONCRETE)  # steps
	_proxy(building_body, centre, Vector3(0, 6.5, 7.0), Vector3(18.0, 13.0, 14.0))
	stats["buildings"] += 1
	# Station identity sign (location identifiers, not commercial branding).
	var uv := atlas.add({"px": Vector2i(640, 176), "bg": Color(0.1, 0.22, 0.45), "border": Color(0.95, 0.85, 0.4),
			"lines": [["COLOMBO FORT", 56, Color(1, 1, 1)], ["කොළඹ කොටුව", 40, Color(1, 0.92, 0.6), false], ["கொழும்பு கோட்டை", 36, Color(1, 0.92, 0.6), false]]})
	_sign_quad(centre * Transform3D(Basis.IDENTITY, Vector3(0, 6.2, -4.55)), Vector2(9.0, 2.5), uv)
	var uv2 := atlas.add({"px": Vector2i(320, 72), "bg": Color(0.95, 0.94, 0.9), "border": Color(0.1, 0.22, 0.45),
			"lines": [["TICKETS • ප්‍රවේශපත් • பயணச்சீட்டு", 22, Color(0.1, 0.22, 0.45), false]]})
	for half: float in [-1.0, 1.0]:
		_sign_quad(centre * Transform3D(Basis.IDENTITY, Vector3(half * 24.0, 3.0, 1.0)), Vector2(4.0, 0.9), uv2)
	# Depth cheats behind the façade: platform canopies, rail catenary, carriages.
	var back := centre * Transform3D(Basis.IDENTITY, Vector3(0, 0, 22.0))
	var bc2 := chunks.at(back.origin)
	for k in 3:
		bc2.metal.box(back, Vector3(0, 4.8, k * 9.0), Vector3(140.0, 0.25, 6.0), Color(0.45, 0.47, 0.48))
		for j in 12:
			bc2.metal.box(back, Vector3(-66.0 + j * 12.0, 2.4, k * 9.0), Vector3(0.25, 4.8, 0.25), Color(0.3, 0.32, 0.33))
	for k in 5:  # train carriages glimpsed between the canopies
		var col: Color = [Color(0.15, 0.3, 0.6), Color(0.62, 0.12, 0.1)][k % 2]
		bc2.plaster.box(back, Vector3(-48.0 + k * 21.0, 2.0, 4.5), Vector3(20.0, 3.4, 3.0), col)
		bc2.glass.box(back, Vector3(-48.0 + k * 21.0, 2.6, 2.98), Vector3(18.0, 0.9, 0.02), ArtPalette.WINDOW_DARK)
	# Tuk rank at the station kerb and a vendor near the entrance.
	for k in 3:
		_parked.append(["tuk", _frame(seg, 104.0 + k * 3.2, side, seg.outer_extent(104.0, side) + 1.6) * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO), k + 1])
	var vend := _frame(seg, 76.0, side, seg.outer_extent(76.0, side) + 1.2)
	StreetKit.stall(chunks.at(vend.origin), vend * Transform3D(Basis.IDENTITY, Vector3(0, 0.15, 0)), 0, rng)
	_proxy(prop_body, vend, Vector3(0, 0.6, 0), Vector3(1.9, 1.2, 0.9))


# --- junction gantry & traffic portals ---

func _dress_junction_gantry() -> void:
	for seg in network.segments:
		if seg.name != "JunctionApproach":
			continue
		var s := 14.0
		var left := _frame(seg, s, -1.0, seg.half_width(s) + 0.4)
		var right := _frame(seg, s, 1.0, seg.half_width(s) + 0.4)
		var c := chunks.at(left.origin)
		for p: Vector3 in [left.origin, right.origin]:
			c.metal.cylinder(Transform3D.IDENTITY, p + Vector3(0, 3.4, 0), 0.14, 6.8, 8, StreetKit.POLE_GREY)
			_proxy(prop_body, Transform3D(Basis.IDENTITY, p), Vector3(0, 3.4, 0), Vector3(0.35, 6.8, 0.35))
		var mid := (left.origin + right.origin) * 0.5 + Vector3(0, 6.3, 0)
		var dir := (right.origin - left.origin).normalized()
		var beam := Transform3D(MathUtil.basis_from_forward(dir), mid)
		c.metal.box(beam, Vector3.ZERO, Vector3(0.25, 0.25, left.origin.distance_to(right.origin)), StreetKit.POLE_GREY)
		var sign_xf := Transform3D(left.basis.rotated(Vector3.UP, PI * 0.5).orthonormalized(), mid + Vector3(0, -1.0, 0))
		var uv := atlas.add({"px": Vector2i(512, 160), "bg": Color(0.1, 0.42, 0.25), "border": Color(1, 1, 1),
				"lines": [["← FORT     PETTAH ↑     KOTAHENA →", 30, Color(1, 1, 1)],
						["← කොටුව     පිටකොටුව ↑     කොටහේන →", 24, Color(1, 1, 1), false],
						["← கோட்டை     புறக்கோட்டை ↑     கொட்டாஞ்சேனை →", 22, Color(1, 1, 1), false]]})
		_sign_quad(sign_xf, Vector2(7.5, 2.2), uv)


func _dress_portals() -> void:
	var labels := {
		"MarketLaneArm": ["PETTAH MARKET ARCADE", "පිටකොටුව වෙළඳපොළ", "புறக்கோட்டை சந்தை"],
		"BusStandArm": ["CENTRAL BUS STAND", "මධ්‍යම බස් නැවතුම්පොළ", "மத்திய பேருந்து நிலையம்"],
	}
	for chain in network.chains:
		var portal := chain.get_node_or_null("TunnelPortal") as Node3D
		if portal == null:
			continue
		var seg := chain.last_segment()
		var half := seg.half_width(seg.length) + 0.6 if seg != null else 5.0
		var mouth := portal.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, chain.tunnel_depth + 0.7))
		var toward_road := mouth.basis.z
		toward_road.y = 0.0
		var xf := Transform3D(MathUtil.basis_from_forward(toward_road.normalized()), Vector3(mouth.origin.x, 0, mouth.origin.z))
		var c := chunks.at(xf.origin)
		var w := half * 2.0 + 10.0
		var wall := ArtPalette.pick(ArtPalette.WALLS, rng)
		# Gateway building straddling the passage the traffic disappears into.
		c.plaster.box(xf, Vector3(0, 10.0, 11.0), Vector3(w, 7.0, 22.0), wall)
		for sx: float in [-1.0, 1.0]:
			c.plaster.box(xf, Vector3(sx * (half + 3.0), 3.25, 11.0), Vector3(5.0, 6.5, 22.0), wall.darkened(0.05))
			_proxy(building_body, xf, Vector3(sx * (half + 3.0), 3.25, 11.0), Vector3(5.0, 6.5, 22.0))
		for k in int(w / 3.0):
			c.glass.box(xf, Vector3(-w * 0.5 + 1.5 + k * 3.0, 10.4, -0.03), Vector3(1.2, 1.8, 0.04), ArtPalette.WINDOW_DARK)
		var lab: Array = labels.get(String(chain.name), ["PETTAH", "පිටකොටුව", "புறக்கோட்டை"])
		var uv := atlas.add({"px": Vector2i(512, 128), "bg": Color(0.8, 0.12, 0.1), "border": Color(1, 0.9, 0.5),
				"lines": [[lab[0], 34, Color(1, 1, 1)], [lab[1] + "  •  " + lab[2], 22, Color(1, 0.93, 0.7), false]]})
		_sign_quad(xf * Transform3D(Basis.IDENTITY, Vector3(0, 7.4, 0)), Vector2(minf(w - 2.0, 10.0), 2.4), uv)


# --- boundary façades & skyline ---

func _dress_boundary_and_skyline() -> void:
	for bxf: Transform3D in network.boundary_blocks:
		var size := bxf.basis.get_scale()
		var xf := Transform3D(bxf.basis.orthonormalized(), Vector3(bxf.origin.x, 0, bxf.origin.z))
		var c := chunks.at(xf.origin)
		if size.z < 2.0:
			BuildingKit.boundary_wall(c, xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, -size.z * 0.5)), size.x, size.y, ArtPalette.pick(ArtPalette.WALLS, rng), rng.randf() < 0.3)
		else:
			# Boundary blocks face inward (their −Z points outward in the ring).
			var inward := xf * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, size.z * 0.5))
			BuildingKit.background_block(c, inward, size.x, size.z, size.y, ArtPalette.vary(ArtPalette.pick(ArtPalette.WALLS, rng), rng, 0.04))
	# Skyline: office slabs and towers beyond the ring (no collision, far away).
	var r := network.district_rect.grow(60.0)
	for k in 26:
		var t := float(k) / 26.0
		var p := Vector2.ZERO
		match k % 4:
			0: p = Vector2(lerpf(r.position.x, r.end.x, t), r.position.y - rng.randf_range(0, 40))
			1: p = Vector2(r.end.x + rng.randf_range(0, 40), lerpf(r.position.y, r.end.y, t))
			2: p = Vector2(lerpf(r.position.x, r.end.x, t), r.end.y + rng.randf_range(0, 40))
			_: p = Vector2(r.position.x - rng.randf_range(0, 40), lerpf(r.position.y, r.end.y, t))
		var h := rng.randf_range(18.0, 46.0) if k % 5 != 0 else rng.randf_range(60.0, 95.0)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, 0, p.y))
		BuildingKit.background_block(far_chunks.at(xf.origin), xf, rng.randf_range(14.0, 30.0), rng.randf_range(14.0, 26.0), h,
				ArtPalette.vary([ArtPalette.CONCRETE, ArtPalette.OFF_WHITE, Color(0.62, 0.68, 0.74)][k % 3], rng, 0.05))
		if k % 3 == 0:
			StreetKit.palm(far_chunks.at(xf.origin), Vector3(p.x + 18.0, 0, p.y), rng)


# --- parked vehicles (shared TrafficArt meshes + PROP collision) ---

func _spawn_parked() -> void:
	var classes := {}
	for path in ["tuk", "van", "motorcycle", "car"]:
		classes[path] = load("res://resources/traffic/%s.tres" % path)
	# Market loading: a delivery van and a couple of tuks; junction: bikes.
	for seg in network.segments:
		# Never on the carriageway (no collider may block a legal lane): parked
		# vehicles live on the station forecourt, in side-street stubs and at the
		# back edge of wide pavements only.
		if seg.name == "JunctionApproach":
			for k in 4:
				_parked.append(["motorcycle", _frame(seg, 30.0 + k * 1.0, -1.0, seg.outer_extent(30.0, -1.0) - 0.8) * Transform3D(Basis(Vector3.UP, PI * 0.5 + 0.3), Vector3(0, 0.15, 0)), k])
	for entry: Array in _parked:
		var cls: TrafficVehicleClass = classes[entry[0]]
		var xf: Transform3D = entry[1]
		var mi := MeshInstance3D.new()
		mi.name = "Parked_%s" % entry[0]
		mi.mesh = TrafficArt.mesh_for(cls, entry[2])
		mi.transform = xf
		mi.visibility_range_end = 110.0
		add_child(mi)
		_proxy(prop_body, xf, Vector3(0, cls.height * 0.5, 0), Vector3(cls.width, cls.height, cls.length))
		stats["parked_vehicles"] += 1
