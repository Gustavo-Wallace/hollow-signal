extends Node2D


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var player := get_tree().get_first_node_in_group("signal_player")
	if player == null:
		return
	var health := int(player.call("get_health"))
	var max_health := int(player.call("get_max_health"))
	var exposure := float(player.call("get_exposure"))
	_draw_health(health, max_health)
	_draw_exposure(exposure)


func _draw_health(health: int, max_health: int) -> void:
	for index in max_health:
		var filled := index < health
		var color := Color(0.42, 0.91, 1.0, 0.9) if filled else Color(0.13, 0.31, 0.4, 0.55)
		draw_circle(Vector2(57.0 + index * 17.0, 72.0), 4.4, color)
		draw_arc(Vector2(57.0 + index * 17.0, 72.0), 7.2, 0.0, TAU, 24, Color(0.3, 0.78, 0.92, 0.35), 1.0, true)


func _draw_exposure(exposure: float) -> void:
	var origin := Vector2(984.0, 71.0)
	var length := 210.0
	draw_line(origin, origin + Vector2(length, 0.0), Color(0.14, 0.36, 0.46, 0.52), 2.0, true)
	draw_line(origin, origin + Vector2(length * exposure, 0.0), Color(0.35, 0.92, 1.0, 0.58 + exposure * 0.35), 2.0, true)
	draw_circle(origin, 2.6, Color(0.37, 0.9, 1.0, 0.68))
	draw_circle(origin + Vector2(length, 0.0), 2.6, Color(0.37, 0.9, 1.0, 0.45))
