extends Node2D

const ENTRY_RADIUS := 36.0

var phase := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("null_gate")
	queue_redraw()


func _process(delta: float) -> void:
	if not get_parent().is_escape():
		queue_free()
		return
	phase += delta
	var player := get_tree().get_first_node_in_group("signal_player") as Node2D
	if player and global_position.distance_to(player.global_position) <= ENTRY_RADIUS:
		get_parent().enter_null_gate()
	queue_redraw()


func _draw() -> void:
	var slow_pulse := 0.6 + sin(phase * 2.3) * 0.18
	draw_circle(Vector2.ZERO, 31.0 + slow_pulse * 3.0, Color(0.01, 0.05, 0.11, 0.94))
	draw_arc(Vector2.ZERO, 38.0, phase * 0.7, phase * 0.7 + PI * 1.35, 44, Color(0.52, 0.94, 1.0, 0.78), 1.8, true)
	draw_arc(Vector2.ZERO, 38.0, phase * 0.7 + PI, phase * 0.7 + TAU * 0.82, 36, Color(0.43, 0.46, 1.0, 0.58), 1.2, true)
	draw_arc(Vector2.ZERO, 25.0, -phase * 1.15, -phase * 1.15 + PI * 1.25, 36, Color(0.6, 0.96, 1.0, 0.7), 1.2, true)
	draw_arc(Vector2.ZERO, 50.0 + slow_pulse * 4.0, 0.0, TAU, 64, Color(0.32, 0.82, 1.0, 0.22), 1.0, true)
	for angle in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
		var direction := Vector2.RIGHT.rotated(angle - phase * 0.4)
		draw_line(direction * 57.0, direction * 43.0, Color(0.58, 0.95, 1.0, 0.72), 1.5, true)
	draw_line(Vector2(0.0, -69.0), Vector2(0.0, -43.0), Color(0.44, 0.9, 1.0, 0.28), 1.0, true)
	draw_line(Vector2(0.0, 69.0), Vector2(0.0, 43.0), Color(0.44, 0.9, 1.0, 0.28), 1.0, true)
