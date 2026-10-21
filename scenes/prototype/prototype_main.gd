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
@onready var pedestrians: PedestrianNetwork = $TestTrack/Pedestrians
@onready var humans: HumanManager = $HumanManager
@onready var offers: PassengerOfferManager = $PassengerOfferManager
@onready var rides: RideManager = $RideManager
@onready var ride_hud: RideHud = $RideHud

## Fixed seeds for deterministic tests (0 = random).
var human_seed := 0
var offer_seed := 0


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
	pedestrians.build(network)
	humans.setup(pedestrians, traffic, player, camera, human_seed)
	offers.setup(pedestrians, network, humans, offer_seed)
	rides.setup(player, offers, humans, network, scoring)
	hud.setup(player, scoring)
	ride_hud.setup(rides, offers, self)
	debug_overlay.setup(player, traffic, network, scoring, near_miss)
	debug_overlay.setup_world(humans, rides, pedestrians)
	GameState.reset_session()
