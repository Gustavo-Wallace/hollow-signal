extends Node2D

const QUICK := "quick"
const RESONANT := "resonant"
const BREAK := "break"

var age := 0.0
var affected_targets: Array[Node2D] = []
var profile := RESONANT
var lifetime := 0.52
var max_radius := 248.0
var signal_force := 92.0
var signal_damage := 2
var stagger_scale := 0.68


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func configure(signal_profile: String) -> void:
	profile = signal_profile
	match profile:
		QUICK:
			lifetime = 0.3
			max_radius = 480.0
			signal_force = 12.0
			signal_damage = 0
			stagger_scale = 0.22
		BREAK:
			lifetime = 0.78
			max_radius = 340.0
			signal_force = 154.0
			signal_damage = 2
			stagger_scale = 1.0
		_:
			lifetime = 0.52
			max_radius = 248.0
			signal_force = 92.0
			signal_damage = 2
			stagger_scale = 0.68


func _process(delta: float) -> void:
	if not get_parent().is_playing():
		queue_free()
		return
	age += delta
	_apply_signal_to_reached_targets()
	queue_redraw()
	if age >= lifetime:
		queue_free()


func _apply_signal_to_reached_targets() -> void:
	var radius := ease(clampf(age / lifetime, 0.0, 1.0), 0.72) * max_radius
	for target in get_tree().get_nodes_in_group("echo_wraith"):
		if target is Node2D and target not in affected_targets and global_position.distance_to(target.global_position) <= radius:
			affected_targets.append(target)
			var distance_ratio := global_position.distance_to(target.global_position) / max_radius
			var force_falloff := lerpf(0.94, 0.48, distance_ratio)
			target.receive_signal_pulse(global_position, signal_force * force_falloff, signal_damage, stagger_scale, profile)


func _draw() -> void:
	var progress := clampf(age / lifetime, 0.0, 1.0)
	var radius := ease(progress, 0.72) * max_radius
	var color := Color(0.22, 0.88, 1.0, (1.0 - progress) * 0.58)
	var width := 1.5
	if profile == QUICK:
		color = Color(0.4, 0.94, 1.0, (1.0 - progress) * 0.5)
		width = 1.0
	elif profile == BREAK:
		color = Color(0.36, 0.92, 1.0, (1.0 - progress) * 0.74)
		width = 3.0
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 80, color, width, true)
	if profile != QUICK:
		draw_arc(Vector2.ZERO, maxf(0.0, radius - 9.0), 0.0, TAU, 80, Color(0.34, 0.45, 1.0, color.a * 0.48), 1.0, true)
	if profile == BREAK:
		draw_arc(Vector2.ZERO, radius + 10.0, 0.0, TAU, 80, Color(0.46, 0.94, 1.0, color.a * 0.64), 1.2, true)
