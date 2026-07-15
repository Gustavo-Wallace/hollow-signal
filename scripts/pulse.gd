extends Node2D

const LIFETIME := 0.72
const MAX_RADIUS := 230.0
const SIGNAL_FORCE := 105.0
const SIGNAL_DAMAGE := 1

var age := 0.0
var affected_targets: Array[Node2D] = []


func _process(delta: float) -> void:
	age += delta
	_apply_signal_to_reached_targets()
	queue_redraw()
	if age >= LIFETIME:
		queue_free()


func _apply_signal_to_reached_targets() -> void:
	var radius := ease(clampf(age / LIFETIME, 0.0, 1.0), 0.72) * MAX_RADIUS
	for target in get_tree().get_nodes_in_group("echo_wraith"):
		if target is Node2D and target not in affected_targets and global_position.distance_to(target.global_position) <= radius:
			affected_targets.append(target)
			var distance_ratio := global_position.distance_to(target.global_position) / MAX_RADIUS
			var force_falloff := lerpf(0.9, 0.32, distance_ratio)
			target.receive_signal_pulse(global_position, SIGNAL_FORCE * force_falloff, SIGNAL_DAMAGE)


func _draw() -> void:
	var progress := clampf(age / LIFETIME, 0.0, 1.0)
	var radius := ease(progress, 0.72) * MAX_RADIUS
	var alpha := (1.0 - progress) * 0.72
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 80, Color(0.22, 0.88, 1.0, alpha), 2.0, true)
	draw_arc(Vector2.ZERO, maxf(0.0, radius - 8.0), 0.0, TAU, 80, Color(0.34, 0.45, 1.0, alpha * 0.35), 1.0, true)
