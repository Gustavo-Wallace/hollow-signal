extends Node2D

const DORMANT_SPEED := 52.0
const ALERT_SPEED := 132.0
const REVEAL_DURATION := 2.6
const ALERT_DURATION := 2.0
const DEATH_DURATION := 0.52
const ARENA_BOUNDS := Rect2(64.0, 64.0, 1152.0, 552.0)

var health := 3
var velocity := Vector2.ZERO
var reveal_time := 0.0
var alert_time := 0.0
var reveal_amount := 0.08
var flash_amount := 0.0
var target_position := Vector2.ZERO
var phase := 0.0
var dying := false
var death_time := 0.0
var emergence := 1.0


func _ready() -> void:
	add_to_group("echo_wraith")
	target_position = global_position
	phase = fmod(global_position.x * 0.021 + global_position.y * 0.013, TAU)
	queue_redraw()


func _process(delta: float) -> void:
	if dying:
		_process_death(delta)
		return
	_process_movement(delta)
	reveal_time = maxf(0.0, reveal_time - delta)
	alert_time = maxf(0.0, alert_time - delta)
	flash_amount = maxf(0.0, flash_amount - delta * 3.8)
	emergence = move_toward(emergence, 1.0, delta * 2.2)
	var target_reveal := 1.0 if reveal_time > 0.0 else 0.08
	reveal_amount = move_toward(reveal_amount, target_reveal, delta * 1.45)
	rotation += delta * (0.16 + alert_time * 0.14)
	queue_redraw()


func _process_movement(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("signal_player") as Node2D
	var player_exposure := 0.0
	if player and player.has_method("get_exposure"):
		player_exposure = float(player.call("get_exposure"))
	var has_target := false
	if player:
		var awareness_radius := lerpf(140.0, 620.0, player_exposure)
		if alert_time > 0.0 or global_position.distance_to(player.global_position) <= awareness_radius:
			target_position = player.global_position
			has_target = true
	if has_target:
		var direction := global_position.direction_to(target_position)
		var speed := ALERT_SPEED if alert_time > 0.0 else DORMANT_SPEED
		velocity = velocity.move_toward(direction * speed * (1.0 + player_exposure * 1.15), delta * 128.0)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, delta * 52.0)
	global_position += velocity * delta
	global_position = global_position.clamp(ARENA_BOUNDS.position, ARENA_BOUNDS.end)
	if player and global_position.distance_to(player.global_position) <= 27.0:
		player.call("take_damage", global_position)


func receive_signal_pulse(origin: Vector2, force: float, damage: int) -> void:
	if dying:
		return
	var push_direction := origin.direction_to(global_position)
	if push_direction == Vector2.ZERO:
		push_direction = Vector2.RIGHT.rotated(phase)
	velocity += push_direction * force
	target_position = origin
	var player := get_tree().get_first_node_in_group("signal_player")
	var player_exposure := float(player.call("get_exposure")) if player else 0.0
	reveal_time = maxf(reveal_time, REVEAL_DURATION + player_exposure * 0.8)
	alert_time = maxf(alert_time, lerpf(ALERT_DURATION, 4.1, player_exposure))
	flash_amount = 1.0
	health -= damage
	if health <= 0:
		_begin_death()
	queue_redraw()


func begin_emergence() -> void:
	emergence = 0.0
	reveal_amount = 0.02
	queue_redraw()


func wake_for_exposure(exposure_level: float) -> void:
	if exposure_level < 0.34:
		return
	reveal_time = lerpf(0.7, 2.0, exposure_level)
	alert_time = lerpf(0.9, 3.2, exposure_level)
	flash_amount = 0.45
	queue_redraw()


func _begin_death() -> void:
	dying = true
	death_time = 0.0
	velocity = Vector2.ZERO
	remove_from_group("echo_wraith")
	get_parent().spawn_echo_shard(global_position)


func _process_death(delta: float) -> void:
	death_time += delta
	queue_redraw()
	if death_time >= DEATH_DURATION:
		queue_free()


func _draw() -> void:
	if dying:
		_draw_fragments()
		return
	var pulse := sin(Time.get_ticks_msec() * 0.002 + phase) * 0.5 + 0.5
	var alpha := lerpf(0.09, 0.82, reveal_amount) * emergence
	var glow_alpha := alpha * (0.28 + flash_amount * 0.72)
	var cold := Color(0.22, 0.78, 1.0, alpha)
	var shadow := Color(0.04, 0.12, 0.19, alpha * 0.8)
	var diamond := PackedVector2Array([Vector2(0, -17), Vector2(15, 0), Vector2(0, 17), Vector2(-15, 0)])
	draw_colored_polygon(diamond, shadow)
	draw_line(diamond[0], diamond[1], cold, 1.3, true)
	draw_line(diamond[1], diamond[2], cold, 1.3, true)
	draw_line(diamond[2], diamond[3], cold, 1.3, true)
	draw_line(diamond[3], diamond[0], cold, 1.3, true)
	draw_arc(Vector2.ZERO, 24.0 + pulse * 2.0, 0.18, 2.25, 24, Color(0.3, 0.9, 1.0, glow_alpha), 1.3, true)
	draw_arc(Vector2.ZERO, 24.0 + pulse * 2.0, 3.35, 5.48, 24, Color(0.3, 0.9, 1.0, glow_alpha), 1.3, true)
	draw_circle(Vector2.ZERO, 3.4 + flash_amount * 1.8, Color(0.62, 0.96, 1.0, alpha * (0.52 + flash_amount * 0.48)))
	if emergence < 1.0:
		draw_line(Vector2(0, -42.0 * (1.0 - emergence)), Vector2.ZERO, Color(0.25, 0.85, 1.0, (1.0 - emergence) * 0.55), 1.0, true)
	if reveal_amount > 0.2:
		for index in health:
			draw_circle(Vector2(-6.0 + index * 6.0, 29.0), 1.6, Color(0.34, 0.9, 1.0, alpha * 0.7))


func _draw_fragments() -> void:
	var progress := clampf(death_time / DEATH_DURATION, 0.0, 1.0)
	var alpha := (1.0 - progress) * 0.9
	var directions := [Vector2(1, 0), Vector2(0.2, 1), Vector2(-0.8, 0.54), Vector2(-0.35, -0.94), Vector2(0.72, -0.7)]
	for index in directions.size():
		var direction: Vector2 = directions[index].normalized()
		var offset := direction * (12.0 + progress * 52.0)
		var tangent := direction.rotated(PI * 0.5) * (6.0 + progress * 9.0)
		draw_line(offset - tangent, offset + tangent, Color(0.32, 0.9, 1.0, alpha), 2.0 - progress, true)
	draw_circle(Vector2.ZERO, 13.0 * (1.0 - progress), Color(0.3, 0.85, 1.0, alpha * 0.24))
