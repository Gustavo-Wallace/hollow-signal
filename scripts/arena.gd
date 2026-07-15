extends Node2D

const VIEWPORT_SIZE := Vector2(1280.0, 720.0)
const PULSE_SCRIPT := preload("res://scripts/pulse.gd")

var stars: Array[Dictionary] = []
var drift := 0.0
var camera_shake_time := 0.0
var camera_shake_strength := 0.0
@onready var arena_camera: Camera2D = $ArenaCamera


func _ready() -> void:
	_generate_stars()
	queue_redraw()


func _process(delta: float) -> void:
	drift += delta
	_update_camera_shake(delta)
	queue_redraw()


func emit_pulse(origin: Vector2) -> void:
	var pulse := Node2D.new()
	pulse.set_script(PULSE_SCRIPT)
	pulse.position = origin
	add_child(pulse)
	camera_shake_time = 0.15
	camera_shake_strength = 7.0


func _update_camera_shake(delta: float) -> void:
	if camera_shake_time <= 0.0:
		arena_camera.offset = Vector2.ZERO
		return
	camera_shake_time = maxf(0.0, camera_shake_time - delta)
	var intensity := camera_shake_strength * (camera_shake_time / 0.15)
	arena_camera.offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))


func _generate_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 711942
	for i in 80:
		stars.append({
			"position": Vector2(rng.randf_range(28.0, 1252.0), rng.randf_range(24.0, 660.0)),
			"size": rng.randf_range(0.6, 1.8),
			"phase": rng.randf_range(0.0, TAU),
			"tone": rng.randf_range(0.25, 0.7)
		})


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEWPORT_SIZE), Color("050914"))
	_draw_grid()
	_draw_machine_rings()
	_draw_stars()
	_draw_frame()


func _draw_grid() -> void:
	var grid_color := Color(0.12, 0.4, 0.53, 0.075)
	for x in range(0, 1281, 64):
		draw_line(Vector2(x, 0), Vector2(x, 720), grid_color, 1.0)
	for y in range(0, 721, 64):
		draw_line(Vector2(0, y), Vector2(1280, y), grid_color, 1.0)


func _draw_machine_rings() -> void:
	var center := VIEWPORT_SIZE * 0.5
	var ring_color := Color(0.12, 0.7, 0.94, 0.11)
	for radius in [92.0, 156.0, 244.0, 350.0, 474.0]:
		draw_arc(center, radius, 0.0, TAU, 128, ring_color, 1.0, true)
	for angle in range(0, 360, 30):
		var direction := Vector2.RIGHT.rotated(deg_to_rad(float(angle)))
		draw_line(center + direction * 390.0, center + direction * 402.0, Color(0.22, 0.85, 1.0, 0.2), 1.0)
	var rotating_angle := drift * 0.16
	draw_arc(center, 292.0, rotating_angle, rotating_angle + 1.05, 48, Color(0.25, 0.92, 1.0, 0.32), 2.0, true)
	draw_arc(center, 292.0, rotating_angle + PI, rotating_angle + PI + 0.56, 32, Color(0.37, 0.42, 1.0, 0.22), 1.0, true)


func _draw_stars() -> void:
	for star in stars:
		var shimmer: float = 0.35 + sin(drift * 1.4 + star.phase) * 0.18
		var tint: float = star.tone
		draw_circle(star.position, star.size, Color(0.22 * tint, 0.7 * tint, tint, shimmer))


func _draw_frame() -> void:
	var frame_color := Color(0.18, 0.65, 0.82, 0.24)
	draw_line(Vector2(40, 40), Vector2(1240, 40), frame_color, 1.0)
	draw_line(Vector2(40, 40), Vector2(40, 640), frame_color, 1.0)
	draw_line(Vector2(1240, 40), Vector2(1240, 640), frame_color, 1.0)
	draw_line(Vector2(40, 640), Vector2(1240, 640), frame_color, 1.0)
	for corner in [Vector2(40, 40), Vector2(1240, 40), Vector2(40, 640), Vector2(1240, 640)]:
		draw_circle(corner, 3.0, Color(0.35, 0.93, 1.0, 0.55))
