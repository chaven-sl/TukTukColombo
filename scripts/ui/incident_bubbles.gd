class_name IncidentBubbles
extends Node3D
## Placeholder presentation for traffic incident hooks (v0.03A1): floating
## speech bubbles for driver shouts and horn text, until the audio sprint
## replaces them with Sri Lankan voice lines and horn samples. Listens to
## EventBus only; a small fixed pool of Label3D, no allocation per event.

const POOL := 5
const SHOUT_SECONDS := 1.8
const HORN_SECONDS := 0.9
const HORN_KEYS := ["SFX_HORN_ANGRY", "SFX_HORN_REPEATED", "SFX_HORN_NEARBY"]

var _labels: Array[Label3D] = []
var _timers := PackedFloat32Array()
var _next := 0
## Diagnostics (tests).
var shouts_shown := 0
var horns_shown := 0


func _ready() -> void:
	for i in POOL:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.001
		l.font_size = 30
		l.outline_size = 10
		l.render_priority = 9
		l.visible = false
		add_child(l)
		_labels.append(l)
		_timers.append(0.0)
	EventBus.driver_shout.connect(_on_shout)
	EventBus.traffic_horn.connect(_on_horn)


func _on_shout(at: Vector3, key: String) -> void:
	shouts_shown += 1
	_show("“%s”" % tr(key), at + Vector3.UP * 0.6, Color(1.0, 0.92, 0.85), SHOUT_SECONDS, 38)


func _on_horn(at: Vector3, pattern: int) -> void:
	horns_shown += 1
	var size := 24 if pattern == TrafficIncidentManager.Horn.NEARBY else 32
	_show(tr(HORN_KEYS[clampi(pattern, 0, 2)]), at, Color(1.0, 0.8, 0.25), HORN_SECONDS, size)


func _show(text: String, at: Vector3, color: Color, seconds: float, size: int) -> void:
	var l := _labels[_next]
	_timers[_next] = seconds
	_next = (_next + 1) % POOL
	l.text = text
	l.modulate = color
	l.font_size = size
	l.global_position = at
	l.visible = true


func _process(delta: float) -> void:
	var ps := PerfSections.begin()
	_process_body(delta)
	PerfSections.end(PerfSections.NOTIFICATIONS, ps)


func _process_body(delta: float) -> void:
	for i in POOL:
		if _timers[i] <= 0.0:
			continue
		_timers[i] -= delta
		var l := _labels[i]
		l.position.y += delta * 0.3
		if _timers[i] <= 0.0:
			l.visible = false
