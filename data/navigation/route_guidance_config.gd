class_name RouteGuidanceConfig
extends Resource
## GPS guidance tunables. PROTOTYPE BASELINE v0.03A1. Distances in m, speeds km/h.

@export_group("Off-route")
## Player farther than this from the route line counts as off-route...
@export var off_route_distance := 9.0
## ...after this long (s).
@export var off_route_seconds := 1.2
## Driving against the route direction (dot below this) above wrong_way_min_speed_kmh...
@export var wrong_way_dot := -0.5
@export var wrong_way_min_speed_kmh := 8.0
## ...for this long (s) also counts as off-route.
@export var wrong_way_seconds := 2.5
## Minimum time between recalculations (s) — never spam the search.
@export var recalc_cooldown := 3.0

@export_group("Instructions")
## A turn closer than this is announced as LEFT/RIGHT; farther shows STRAIGHT.
@export var turn_announce_distance := 250.0
## Straight-line distance to the waiting passenger that shows STOP TO PICK UP.
@export var pickup_stop_distance := 12.0
## Progress tracking interval (s).
@export var update_interval := 0.1

@export_group("Ribbon")
@export var ribbon_width := 1.2
@export var ribbon_height := 0.07
@export var ribbon_color := Color(0.15, 0.85, 1.0)
