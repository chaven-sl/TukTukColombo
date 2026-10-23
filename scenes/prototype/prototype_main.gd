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
@onready var pause: PauseController = $Pause
@onready var mobile_controls: MobileControls = $MobileControls
@onready var touch_input: TouchInputSource = $TouchInput
@onready var perf_monitor: SessionPerformanceMonitor = $PerformanceMonitor
@onready var perf_test: DevicePerfTest = $DevicePerfTest
@onready var guidance: RouteGuidance = $RouteGuidance
@onready var incidents: TrafficIncidentManager = $TrafficIncidentManager

## LOW, MEDIUM, HIGH (indexed by GraphicsProfile.Tier).
@export var graphics_profiles: Array[Resource] = []

## Fixed seeds for deterministic tests (0 = random).
var human_seed := 0
var offer_seed := 0
var incident_seed := 0
## Touch or keyboard, decided once at startup (InputMode).
var touch_mode := false
var graphics_tier: GraphicsProfile.Tier = GraphicsProfile.Tier.HIGH


func _ready() -> void:
	var perf_seconds := DevicePerfTest.requested_seconds()
	if perf_seconds > 0.0:
		_use_fixed_seeds()
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
	guidance.setup(rides, network, player)
	incidents.setup(traffic, humans, player, incident_seed)
	ride_hud.setup(rides, offers, self, guidance)
	debug_overlay.setup(player, traffic, network, scoring, near_miss)
	debug_overlay.setup_world(humans, rides, pedestrians)
	debug_overlay.setup_v003a1(guidance, incidents, mobile_controls.state)
	_setup_platform()
	GameState.reset_session()
	if perf_seconds > 0.0:
		start_perf_test(perf_seconds)


func _setup_platform() -> void:
	apply_graphics_tier(GraphicsProfile.default_tier_for_platform())
	set_touch_mode(InputMode.wants_touch())
	touch_input.vehicle = player
	touch_input.state = mobile_controls.state
	mobile_controls.setup(player, rides)
	perf_monitor.traffic = traffic
	perf_monitor.humans = humans
	perf_test.monitor = perf_monitor
	perf_test.player = player
	perf_test.network = network
	perf_test.traffic = traffic
	pause.perf_test_requested.connect(func() -> void: start_perf_test(DevicePerfTest.DEFAULT_SECONDS))


## Exactly one human input source drives the tuk: keyboard OR touch.
func set_touch_mode(on: bool) -> void:
	touch_mode = on
	var keyboard := player.get_node_or_null("PlayerInput") as PlayerInputSource
	if keyboard != null:
		keyboard.enabled = not on
	touch_input.enabled = on
	mobile_controls.set_active(on)
	hud.set_touch_layout(on)
	ride_hud.touch_mode = on
	pause.set_keyboard_hints(not on)


func apply_graphics_tier(tier: GraphicsProfile.Tier) -> void:
	if tier >= graphics_profiles.size():
		return
	var profile := graphics_profiles[tier] as GraphicsProfile
	var env := ($WorldEnvironment as WorldEnvironment).environment
	profile.apply(get_viewport(), $Sun as DirectionalLight3D, env)
	graphics_tier = tier


## Deterministic benchmark: the autopilot drives, so human input is off.
func start_perf_test(seconds: float) -> void:
	if perf_test.running:
		return
	touch_input.enabled = false
	var keyboard := player.get_node_or_null("PlayerInput") as PlayerInputSource
	if keyboard != null:
		keyboard.enabled = false
	mobile_controls.set_active(false)
	GameState.set_paused(false)
	perf_test.begin(seconds)


func _use_fixed_seeds() -> void:
	traffic.rng_seed = 7
	human_seed = 7
	offer_seed = 7
	incident_seed = 7
