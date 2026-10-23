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
const GARAGE_SCENE := "res://scenes/garage/garage.tscn"
var _greybox_environment: Environment = null

## LOW, MEDIUM, HIGH (indexed by GraphicsProfile.Tier).
@export var graphics_profiles: Array[Resource] = []

## Fixed seeds for deterministic tests (0 = random).
var human_seed := 0
var offer_seed := 0
var incident_seed := 0
## Touch or keyboard, decided once at startup (InputMode).
var touch_mode := false
var graphics_tier: GraphicsProfile.Tier = GraphicsProfile.Tier.HIGH


## v0.03B1 startup analysis: [Startup] phase marks, ms since engine start.
var _startup_marks := PackedStringArray()


func _mark(label: String) -> void:
	_startup_marks.append("%s=%d" % [label, Time.get_ticks_msec()])


func _enter_tree() -> void:
	if Engine.has_meta("startup_boot_ms"):
		_startup_marks.append("boot=%d" % int(Engine.get_meta("startup_boot_ms")))
	_mark("scene_loaded")


func _ready() -> void:
	_mark("ready")
	if district_scene != null:
		_swap_district()
	if art_style == 1:
		_apply_district_lighting()
		_apply_ui_theme()
	var perf_seconds := DevicePerfTest.requested_seconds()
	if perf_seconds > 0.0:
		_use_fixed_seeds()
	network.build()
	_mark("road_built")
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
	_mark("traffic_pool")
	near_miss.setup(player, traffic)
	pedestrians.build(network)
	_mark("pedestrian_net")
	var art := get_node_or_null("DistrictArt")
	if art != null and art.has_method("dress"):
		art.call("dress", network, pedestrians)
		_mark("district_art")
	humans.setup(pedestrians, traffic, player, camera, human_seed)
	_mark("humans_pool")
	_apply_career()
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
		_mark("audio")
	_setup_platform()
	_log_runtime_settings()
	GameState.reset_session()
	_mark("setup_done")
	if perf_seconds > 0.0:
		start_perf_test(perf_seconds)
	_log_startup.call_deferred()


func _log_startup() -> void:
	await RenderingServer.frame_post_draw
	_mark("first_frame")
	for i in 30:
		await RenderingServer.frame_post_draw
	_mark("frame_30")
	print("[Startup] %s" % " ".join(_startup_marks))


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
	_greybox_environment = ($WorldEnvironment as WorldEnvironment).environment
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
	pause.garage_check = can_return_to_garage
	pause.garage_requested.connect(return_to_garage)


## v0.04: the tuk drives with its upgrades (EffectiveVehicleConfig: a copy
## of the base tuning — the base resource is never modified) and the ride
## system knows the career level for job tiers and payouts.
var base_tuning: VehicleTuning


func _apply_career() -> void:
	var career := GameState.career
	if base_tuning == null:
		base_tuning = player.tuning if player.tuning != null else VehicleTuning.new()
	player.tuning = EffectiveVehicleConfig.build(base_tuning, career.upgrade_levels())
	rides.economy = GameState.economy
	rides.career_level = career.career_level()
	offers.economy = GameState.economy
	offers.career_level = career.career_level()
	if not GameState.career_level_up.is_connected(_on_career_level_up):
		GameState.career_level_up.connect(_on_career_level_up)
	print("[Career] level %d, Rs. %d, ★ %d, upgrades %s, top speed %.1f km/h, brakes %.0f N" % [career.career_level(), career.cash(),
			career.reputation(), career.upgrade_levels(), player.tuning.top_speed_kmh, player.tuning.brake_force])


func _on_career_level_up(level: int) -> void:
	rides.career_level = level
	offers.career_level = level
	notifications.notify(tr("UI_CAREER_LEVEL_UP") % [level, tr(GameState.economy.career_name_keys[level - 1])],
			NotificationPresenter.Category.RIDE, NotificationPresenter.Priority.HIGH, 4.0)


## Safe moment to leave for the garage: no hire in progress, tuk (nearly) stopped.
func can_return_to_garage() -> bool:
	return rides.state == RideManager.RideState.NO_RIDE and player.speed_kmh < 6.0


func return_to_garage() -> void:
	if not can_return_to_garage():
		return
	GameState.set_paused(false)
	GameState.prepare_garage_return()
	get_tree().change_scene_to_file(GARAGE_SCENE)


## v0.03B1: one line describing what the device is ACTUALLY running.
func _log_runtime_settings() -> void:
	var profile := graphics_profiles[graphics_tier] as GraphicsProfile
	var sun := $Sun as DirectionalLight3D
	var env := ($WorldEnvironment as WorldEnvironment).environment
	var vp := get_viewport()
	var win := DisplayServer.window_get_size()
	var refresh := DisplayServer.screen_get_refresh_rate()
	var vsync_names := ["DISABLED", "ENABLED", "ADAPTIVE", "MAILBOX"]
	var vsync := DisplayServer.window_get_vsync_mode()
	var cap := Engine.max_fps if Engine.max_fps > 0 else int(refresh)
	print("[GraphicsRuntime] tier=%s profile_shadow_distance=%.0f max_fps=%d render_scale=%.2f scaling_mode=%s shadow_distance=%.0f sun_shadows=%s fog=%s sky=%s ambient=%s reflections=%s viewport=%dx%d render_3d=%dx%d window=%dx%d screen_refresh_hz=%.1f vsync=%s renderer=%s physics_ticks=%d process_mode=%d effective_cap=%d" % [
		GraphicsProfile.Tier.keys()[graphics_tier], profile.shadow_max_distance, Engine.max_fps, vp.scaling_3d_scale, ["BILINEAR", "FSR", "FSR2", "METALFX_SPATIAL", "METALFX_TEMPORAL"][vp.scaling_3d_mode],
		sun.directional_shadow_max_distance, sun.shadow_enabled, env.fog_enabled,
		env.background_mode == Environment.BG_SKY, ["BG", "DISABLED", "COLOR", "SKY"][env.ambient_light_source],
		["BG", "DISABLED", "SKY"][env.reflected_light_source],
		vp.get_visible_rect().size.x, vp.get_visible_rect().size.y,
		int(vp.size.x * vp.scaling_3d_scale), int(vp.size.y * vp.scaling_3d_scale), win.x, win.y, refresh,
		vsync_names[vsync] if vsync < vsync_names.size() else str(vsync),
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		Engine.physics_ticks_per_second, process_mode, cap])


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
	_apply_perf_options(DevicePerfTest.options)
	perf_monitor.options = DevicePerfTest.options
	perf_test.begin(seconds)


## v0.03B1 device A/B switches (debug/perf runs only; never shipped states).
## Each turns off ONE presentation layer while gameplay keeps running.
func _apply_perf_options(opts: PackedStringArray) -> void:
	var all := opts.has("all_off")
	var audio := get_node_or_null("DistrictAudio")
	if audio != null and (all or opts.has("audio_off")):
		audio.process_mode = Node.PROCESS_MODE_DISABLED
		for c in audio.get_children():
			if c is AudioStreamPlayer:
				(c as AudioStreamPlayer).stop()
			elif c is AudioStreamPlayer3D:
				(c as AudioStreamPlayer3D).stop()
	for a in humans.all_agents:
		if a.rig == null:
			continue
		if all or opts.has("humans_hidden"):
			a.rig.visible = false
		elif opts.has("rig_static"):
			a.rig.animate_distance = 0.0
	if all or opts.has("traffic_hidden"):
		for a in traffic.agents_by_id:
			for mi in a.body_meshes:
				mi.visible = false
	var hero := player.get_node_or_null("Visual/HeroArt") as Node3D
	if hero != null and (all or opts.has("hero_hidden")):
		hero.visible = false
		hero.process_mode = Node.PROCESS_MODE_DISABLED
	if all or opts.has("ribbon_hidden"):
		guidance.set_ribbon_hidden(true)
	var art := get_node_or_null("DistrictArt") as Node3D
	if art != null:
		if all or opts.has("art_hidden"):
			art.visible = false
		elif opts.has("signs_hidden"):
			for c in art.get_children():
				if c.name.begins_with("Signs_"):
					(c as Node3D).visible = false
	if all or opts.has("shadows_off"):
		($Sun as DirectionalLight3D).shadow_enabled = false
	var env := ($WorldEnvironment as WorldEnvironment).environment
	if all or opts.has("fog_off"):
		env.fog_enabled = false
	for o in opts:
		if o.begins_with("scale="):
			get_viewport().scaling_3d_scale = float(o.get_slice("=", 1))
		elif o == "fsr":
			get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	if opts.has("sky_off"):
		env.background_mode = Environment.BG_COLOR
		env.background_color = DistrictLighting.SKY_HORIZON
	if all and _greybox_environment != null:
		($WorldEnvironment as WorldEnvironment).environment = _greybox_environment
		get_window().theme = null


func _use_fixed_seeds() -> void:
	traffic.rng_seed = 7
	human_seed = 7
	offer_seed = 7
	incident_seed = 7
