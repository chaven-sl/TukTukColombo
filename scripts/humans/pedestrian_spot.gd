class_name PedestrianSpot
extends Marker3D
## Level-authored point of interest for people: a waiting area, a group spot,
## a passenger pickup or a ride destination. Snapped to the nearest sidewalk
## node when the PedestrianNetwork builds.

enum Kind { WAIT, GROUP, PICKUP, DROPOFF }

@export var kind: Kind = Kind.WAIT
@export var spot_id: StringName = &""
## Translation key for destinations / pickups shown to the player.
@export var display_name_key := ""
## Placeholder dressing: 0 none, 1 bus shelter, 2 shop front.
@export_range(0, 2) var dressing := 0

var node_id := -1
