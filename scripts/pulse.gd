extends Node2D

const QUICK_RADIUS := 150.0
const BREAK_RADIUS := 275.0
const QUICK_LIFETIME := 0.46
const BREAK_LIFETIME := 0.82
const QUICK_FORCE := 52.0
const BREAK_FORCE := 170.0

var age := 0.0
var affected_targets: Array[Node2D] = []
var charge_ratio := 0.5
var lifetime := 0.65
var max_radius := 215.0
var signal_force := 110.0
var signal_damage := 1
var stagger_scale := 0.7


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func configure(charge: float) -> void:
	charge_ratio = clampf(charge, 0.0, 1.0)
	lifetime = lerpf(QUICK_LIFETIME, BREAK_LIFETIME, charge_ratio)
	max_radius = lerpf(QUICK_RADIUS, BREAK_RADIUS, charge_ratio)
	signal_force = lerpf(QUICK_FORCE, BREAK_FORCE, charge_ratio)
	signal_damage = 2 if charge_ratio >= 0.75 else 1
	stagger_scale = lerpf(0.3, 1.0, charge_ratio)


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
			var force_falloff := lerpf(0.92, 0.42, distance_ratio)
			target.receive_signal_pulse(global_position, signal_force * force_falloff, signal_damage, stagger_scale)


func _draw() -> void:
	var progress := clampf(age / lifetime, 0.0, 1.0)
	var radius := ease(progress, 0.72) * max_radius
	var alpha := (1.0 - progress) * (0.42 + charge_ratio * 0.34)
	var width := lerpf(1.0, 3.0, charge_ratio)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 80, Color(0.22, 0.88, 1.0, alpha), width, true)
	draw_arc(Vector2.ZERO, maxf(0.0, radius - 8.0 - charge_ratio * 5.0), 0.0, TAU, 80, Color(0.34, 0.45, 1.0, alpha * 0.35), 1.0 + charge_ratio, true)
	if charge_ratio >= 0.75:
		draw_arc(Vector2.ZERO, radius + 9.0, 0.0, TAU, 80, Color(0.46, 0.94, 1.0, alpha * 0.5), 1.2, true)
