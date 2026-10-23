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
@onready var recovery: WorldRecoveryManager = $WorldRecovery
@onready var damage: VehicleDamageManager = $VehicleDamage
@onready var crash_effects: CrashEffects = $CrashEffects
@onready var props: ImpactPropManager = $ImpactProps
@onready var notifications: NotificationPresenter = $Notifications

## v0.03B: district content to play in (null = the greybox test track, kept
## for regression tests). The district replaces TestTrack under the same node
## name so every system and test wiring stays identical.
@export var district_scene: PackedScene
## Presentation style: greybox test track, or the Fort–Pettah art pass
## (district lighting + DistrictArt dresser + audio).
@export_enum("Greybox", "FortPettah") var art_style := 0

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
	if district_scene != null:
		_swap_district()
	if art_style == 1:
		_apply_district_lighting()
		_apply_ui_theme()
	var perf_seconds := DevicePerfTest.requested_seconds()
	if perf_seconds > 0.0:
		_use_fixed_seeds()
	network.build()
	player.reset_pose_provider = network.find_reset_transform  # replaced by WorldRecoveryManager below
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
	var art := get_node_or_null("DistrictArt")
	if art != null and art.has_method("dress"):
		art.call("dress", network, pedestrians)
	humans.setup(pedestrians, traffic, player, camera, human_seed)
	offers.setup(pedestrians, network, humans, offer_seed)
	rides.setup(player, offers, humans, network, scoring)
	hud.setup(player, scoring)
	recovery.setup(network, player, traffic, humans)
	damage.setup(player, recovery, crash_effects)
	props.setup(network, player, camera, network.scenery_seed + 2)
	hud.notifications = notifications
	guidance.setup(rides, network, player)
	incidents.setup(traffic, humans, player, incident_seed)
	ride_hud.setup(rides, offers, self, guidance)
	debug_overlay.setup(player, traffic, network, scoring, near_miss)
	debug_overlay.setup_world(humans, rides, pedestrians)
	debug_overlay.setup_v003a1(guidance, incidents, mobile_controls.state)
	debug_overlay.setup_v003a2(damage, recovery, props, humans)
	var audio := get_node_or_null("DistrictAudio") as DistrictAudio
	if audio != null:
		audio.setup(player, traffic, network)
	_setup_platform()
	GameState.reset_session()
	if perf_seconds > 0.0:
		start_perf_test(perf_seconds)


func _swap_district() -> void:
	var old := get_node("TestTrack")
	var idx := old.get_index()
	remove_child(old)
	old.free()
	var district := district_scene.instantiate()
	district.name = "TestTrack"
	add_child(district)
	move_child(district, idx)
	network = district as RoadNetwork
	pedestrians = district.get_node("Pedestrians") as PedestrianNetwork


## v0.03B restrained UI pass: project typography (Noto + Sinhala/Tamil
## fallbacks) for every Control; layout and safe-area logic are unchanged.
func _apply_ui_theme() -> void:
	var t := Theme.new()
	t.default_font = UiFonts.weight(600)
	get_window().theme = t


## Hot tropical late morning (DistrictLighting) instead of the greybox sky.
func _apply_district_lighting() -> void:
	($WorldEnvironment as WorldEnvironment).environment = DistrictLighting.make_environment()
	var sun := $Sun as DirectionalLight3D
	var ref := DistrictLighting.make_sun()
	sun.rotation = ref.rotation
	sun.light_color = ref.light_color
	sun.light_energy = ref.light_energy
	sun.shadow_blur = ref.shadow_blur
	sun.directional_shadow_max_distance = ref.directional_shadow_max_distance
	ref.free()


func _setup_platform() -> void:
	apply_graphics_tier(GraphicsProfile.default_tier_for_platform())
	set_touch_mode(InputMode.wants_touch())
	touch_input.vehicle = player
	touch_input.state = mobile_controls.state
	mobile_controls.layout_changed.connect(hud.on_touch_controls_layout)
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
