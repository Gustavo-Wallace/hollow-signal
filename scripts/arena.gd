extends Node2D

const VIEWPORT_SIZE := Vector2(1280.0, 720.0)
const PULSE_SCRIPT := preload("res://scripts/pulse.gd")
const WRAITH_SCRIPT := preload("res://scripts/echo_wraith.gd")
const SHARD_SCRIPT := preload("res://scripts/echo_shard.gd")
const ECHO_TARGET := 8
const MAX_WRAITHS := 8

enum RunState { PLAYING, LOST, STABILIZED }

var stars: Array[Dictionary] = []
var drift := 0.0
var camera_shake_time := 0.0
var camera_shake_strength := 0.0
var exposure := 0.0
var run_state := RunState.PLAYING
var echoes_collected := 0
var spawn_timer := 3.2
var elapsed_time := 0.0
@onready var arena_camera: Camera2D = $ArenaCamera


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_generate_stars()
	_update_echo_counter()
	queue_redraw()


func _process(delta: float) -> void:
	drift += delta
	_update_exposure()
	if run_state == RunState.PLAYING:
		elapsed_time += delta
		_update_threat_spawner(delta)
	_update_camera_shake(delta)
	_update_final_echo_pulse()
	queue_redraw()


func emit_pulse(origin: Vector2) -> void:
	var pulse := Node2D.new()
	pulse.set_script(PULSE_SCRIPT)
	pulse.position = origin
	add_child(pulse)
	camera_shake_time = 0.15
	camera_shake_strength = 7.0


func player_damaged() -> void:
	camera_shake_time = 0.22
	camera_shake_strength = 13.0


func player_destroyed() -> void:
	if run_state != RunState.PLAYING:
		return
	run_state = RunState.LOST
	$Interface/GameOver/Title.text = "SIGNAL LOST"
	$Interface/GameOver/RestartHint.text = "Press R to restart"
	$Interface/GameOver.visible = true
	get_tree().paused = true


func _input(event: InputEvent) -> void:
	if run_state != RunState.PLAYING and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		get_tree().paused = false
		get_tree().reload_current_scene()


func spawn_echo_shard(origin: Vector2) -> void:
	if run_state != RunState.PLAYING:
		return
	var shard := Node2D.new()
	shard.set_script(SHARD_SCRIPT)
	shard.position = origin
	add_child(shard)


func collect_echo_shard(shard: Node2D) -> void:
	if run_state != RunState.PLAYING:
		return
	echoes_collected += 1
	_update_echo_counter()
	shard.call("begin_collection")
	if echoes_collected >= ECHO_TARGET:
		_stabilize_core()


func _stabilize_core() -> void:
	run_state = RunState.STABILIZED
	$Interface/GameOver/Title.text = "CORE STABILIZED"
	$Interface/GameOver/RestartHint.text = "Press R to run again"
	$Interface/GameOver.visible = true
	get_tree().paused = true


func _update_echo_counter() -> void:
	$Interface/EchoCounter.text = "ECHOES %d/%d" % [echoes_collected, ECHO_TARGET]


func _update_threat_spawner(delta: float) -> void:
	if get_tree().get_nodes_in_group("echo_wraith").size() >= MAX_WRAITHS:
		return
	spawn_timer -= delta
	if spawn_timer > 0.0:
		return
	_spawn_wraith_at_edge()
	var run_pressure := minf(elapsed_time / 90.0, 1.0)
	match get_exposure_band():
		0: spawn_timer = 5.4 - run_pressure * 0.6
		1: spawn_timer = 3.35 - run_pressure * 0.45
		_: spawn_timer = 1.65 - run_pressure * 0.25


func _spawn_wraith_at_edge() -> void:
	var player := get_tree().get_first_node_in_group("signal_player") as Node2D
	var spawn_position := Vector2(80.0, 80.0)
	for attempt in 8:
		var edge := randi_range(0, 3)
		match edge:
			0: spawn_position = Vector2(randf_range(82.0, 1198.0), 70.0)
			1: spawn_position = Vector2(1210.0, randf_range(70.0, 620.0))
			2: spawn_position = Vector2(randf_range(82.0, 1198.0), 630.0)
			_: spawn_position = Vector2(70.0, randf_range(70.0, 620.0))
		if player == null or spawn_position.distance_to(player.global_position) >= 290.0:
			break
	var wraith := Node2D.new()
	wraith.set_script(WRAITH_SCRIPT)
	wraith.position = spawn_position
	add_child(wraith)
	wraith.call("begin_emergence")
	if exposure >= 0.34:
		wraith.call("wake_for_exposure", exposure)


func get_exposure_band() -> int:
	if exposure >= 0.67:
		return 2
	if exposure >= 0.34:
		return 1
	return 0


func _update_final_echo_pulse() -> void:
	var remaining := ECHO_TARGET - echoes_collected
	if run_state == RunState.PLAYING and remaining <= 2:
		var pulse := 0.7 + sin(drift * 3.0) * 0.25
		$Interface/EchoCounter.modulate.a = pulse
	else:
		$Interface/EchoCounter.modulate.a = 1.0


func _update_exposure() -> void:
	var player := get_tree().get_first_node_in_group("signal_player")
	if player and player.has_method("get_exposure"):
		exposure = float(player.call("get_exposure"))


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
	var grid_color := Color(0.12, 0.4, 0.53, 0.075 + exposure * 0.075)
	for x in range(0, 1281, 64):
		draw_line(Vector2(x, 0), Vector2(x, 720), grid_color, 1.0)
	for y in range(0, 721, 64):
		draw_line(Vector2(0, y), Vector2(1280, y), grid_color, 1.0)


func _draw_machine_rings() -> void:
	var center := VIEWPORT_SIZE * 0.5
	var ring_color := Color(0.12, 0.7, 0.94, 0.11 + exposure * 0.1)
	for radius in [92.0, 156.0, 244.0, 350.0, 474.0]:
		draw_arc(center, radius, 0.0, TAU, 128, ring_color, 1.0, true)
	for angle in range(0, 360, 30):
		var direction := Vector2.RIGHT.rotated(deg_to_rad(float(angle)))
		draw_line(center + direction * 390.0, center + direction * 402.0, Color(0.22, 0.85, 1.0, 0.2), 1.0)
	var rotating_angle := drift * 0.16
	draw_arc(center, 292.0, rotating_angle, rotating_angle + 1.05, 48, Color(0.25, 0.92, 1.0, 0.32 + exposure * 0.16), 2.0, true)
	draw_arc(center, 292.0, rotating_angle + PI, rotating_angle + PI + 0.56, 32, Color(0.37, 0.42, 1.0, 0.22), 1.0, true)
	if get_exposure_band() == 2:
		var critical_pulse := 0.34 + sin(drift * 4.0) * 0.16
		draw_arc(center, 406.0, -rotating_angle * 1.8, -rotating_angle * 1.8 + 0.88, 42, Color(0.42, 0.9, 1.0, critical_pulse), 1.6, true)
		draw_arc(center, 214.0, rotating_angle * 2.3, rotating_angle * 2.3 + 0.52, 32, Color(0.42, 0.9, 1.0, critical_pulse * 0.7), 1.0, true)


func _draw_stars() -> void:
	for star in stars:
		var shimmer: float = 0.35 + sin(drift * 1.4 + star.phase) * 0.18 + exposure * 0.18
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
