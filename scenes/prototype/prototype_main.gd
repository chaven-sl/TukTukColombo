extends Node3D
## Prototype v0.01 composition root. Wires systems together explicitly;
## systems themselves never look each other up by scene path.

@onready var network: RoadNetwork = $TestTrack
@onready var player: TukController = $PlayerTuk
@onready var camera: ChaseCamera = $ChaseCamera
@onready var traffic: TrafficManager = $TrafficManager
@onready var near_miss: NearMissDetector = $NearMissDetector
@onready var scoring: ScoringSystem = $ScoringSystem
@onready var hud: PrototypeHud = $HUD
@onready var debug_overlay: DebugOverlay = $DebugOverlay


func _ready() -> void:
	network.build()
	player.reset_pose_provider = network.find_reset_transform
	var spawn := network.get_node_or_null("PlayerSpawn") as Marker3D
	if spawn != null:
		player.teleport(spawn.global_transform)
	else:
		player.teleport(network.find_reset_transform(Vector3.ZERO))
	camera.set_target(player)
	player.impacted.connect(camera.on_vehicle_impact)
	player.was_reset.connect(camera.snap_to_target)
	traffic.setup(network, player, camera)
	near_miss.setup(player, traffic)
	hud.setup(player, scoring)
	debug_overlay.setup(player, traffic, network, scoring, near_miss)
	GameState.reset_session()
