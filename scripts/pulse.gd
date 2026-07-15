extends Node2D

const LIFETIME := 0.8
const MAX_RADIUS := 175.0

var age := 0.0


func _process(delta: float) -> void:
	age += delta
	queue_redraw()
	if age >= LIFETIME:
		queue_free()


func _draw() -> void:
	var progress := clampf(age / LIFETIME, 0.0, 1.0)
	var radius := ease(progress, 0.72) * MAX_RADIUS
	var alpha := (1.0 - progress) * 0.72
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 80, Color(0.22, 0.88, 1.0, alpha), 2.0, true)
	draw_arc(Vector2.ZERO, maxf(0.0, radius - 8.0), 0.0, TAU, 80, Color(0.34, 0.45, 1.0, alpha * 0.35), 1.0, true)
