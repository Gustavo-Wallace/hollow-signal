extends Node2D

const SEEK_SPEED := 104.0
const CHARGED_SPEED := 162.0
const ACCELERATION := 170.0
const CHANNEL_DISTANCE := 27.0
const CHANNEL_DURATION_LOW := 0.64
const CHANNEL_DURATION_CRITICAL := 0.44
const CHANNEL_INTERRUPTION := 0.62
const STAGGER_DURATION := 0.32
const DEATH_DURATION := 0.48
const ARENA_BOUNDS := Rect2(64.0, 64.0, 1152.0, 552.0)

var health := 4
var stored_echoes := 0
var velocity := Vector2.ZERO
var target_shard: Node2D
var channeling := false
var channel_time := 0.0
var channel_pause := 0.0
var reveal_time := 0.0
var reveal_amount := 0.12
var flash_amount := 0.0
var stagger_time := 0.0
var stagger_brake := 0.0
var pulse_resistance := 0.0
var resistance_hold := 0.0
var phase := 0.0
var emergence := 1.0
var dying := false
var death_time := 0.0
var wander_target := Vector2.ZERO
var last_player_position := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("echo_wraith")
	add_to_group("echo_harvester")
	phase = fmod(global_position.x * 0.017 + global_position.y * 0.027, TAU)
	wander_target = _next_wander_target()
	queue_redraw()


func _process(delta: float) -> void:
	if not get_parent().is_playing():
		return
	if dying:
		_process_death(delta)
		return
	channel_pause = maxf(0.0, channel_pause - delta)
	reveal_time = maxf(0.0, reveal_time - delta)
	flash_amount = maxf(0.0, flash_amount - delta * 3.4)
	stagger_time = maxf(0.0, stagger_time - delta)
	resistance_hold = maxf(0.0, resistance_hold - delta)
	if resistance_hold <= 0.0:
		pulse_resistance = move_toward(pulse_resistance, 0.0, delta * 0.7)
	emergence = move_toward(emergence, 1.0, delta * 2.1)
	if get_parent().is_escape() and channeling:
		_cancel_channel(false)
	if channeling:
		_process_channel(delta)
	else:
		_process_movement(delta)
	var target_reveal := 1.0 if reveal_time > 0.0 or channeling or stored_echoes >= 2 else 0.12
	reveal_amount = move_toward(reveal_amount, target_reveal, delta * 1.5)
	rotation += delta * (0.24 + stored_echoes * 0.18)
	queue_redraw()


func _process_movement(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("signal_player") as Node2D
	var player_exposure := float(player.call("get_exposure")) if player else 0.0
	var signal_hidden: bool = player != null and get_parent().is_player_in_null_pocket(player.global_position) and get_parent().get_null_pocket_silence_time() >= 0.72
	if player and not signal_hidden:
		last_player_position = player.global_position
	if stagger_time > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, delta * 440.0 * stagger_brake)
	elif get_parent().is_escape() and player:
		var escape_direction := global_position.direction_to(player.global_position)
		velocity = velocity.move_toward(escape_direction * CHARGED_SPEED * (1.0 + player_exposure * 0.45), delta * ACCELERATION)
	elif stored_echoes >= 2 and player:
		var pursuit_target := last_player_position if signal_hidden else player.global_position
		var charged_direction := global_position.direction_to(pursuit_target)
		var tracking_multiplier := 0.68 if signal_hidden else 1.0
		velocity = velocity.move_toward(charged_direction * CHARGED_SPEED * tracking_multiplier * (1.0 + player_exposure * 0.35), delta * ACCELERATION)
	elif channel_pause <= 0.0:
		if not _valid_target_shard():
			target_shard = _find_nearest_shard()
		if target_shard:
			var shard_direction := global_position.direction_to(target_shard.global_position)
			velocity = velocity.move_toward(shard_direction * SEEK_SPEED * (1.0 + player_exposure * 0.22), delta * ACCELERATION)
			if global_position.distance_to(target_shard.global_position) <= CHANNEL_DISTANCE:
				channeling = true
				channel_time = 0.0
				get_parent().audio_event("wraith_wake")
		else:
			if global_position.distance_to(wander_target) <= 16.0:
				wander_target = _next_wander_target()
			var wander_direction := global_position.direction_to(wander_target)
			velocity = velocity.move_toward(wander_direction * 44.0, delta * 72.0)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, delta * 130.0)
	global_position += velocity * delta
	global_position = global_position.clamp(ARENA_BOUNDS.position, ARENA_BOUNDS.end)
	if (stored_echoes >= 2 or get_parent().is_escape()) and player and global_position.distance_to(player.global_position) <= 28.0:
		player.call("take_damage", global_position)


func _process_channel(delta: float) -> void:
	if not _valid_target_shard():
		_cancel_channel(false)
		return
	velocity = velocity.move_toward(Vector2.ZERO, delta * 360.0)
	channel_time += delta
	var player := get_tree().get_first_node_in_group("signal_player")
	var player_exposure := float(player.call("get_exposure")) if player else 0.0
	var channel_duration := lerpf(CHANNEL_DURATION_LOW, CHANNEL_DURATION_CRITICAL, player_exposure)
	var pull_strength := clampf(channel_time / channel_duration, 0.0, 1.0)
	target_shard.global_position = target_shard.global_position.lerp(global_position, delta * (0.5 + pull_strength * 1.5))
	if channel_time >= channel_duration:
		get_parent().shard_intercepted()
		target_shard.queue_free()
		target_shard = null
		channeling = false
		stored_echoes = mini(2, stored_echoes + 1)
		get_parent().audio_event("harvester_absorb")
		if stored_echoes >= 2:
			get_parent().audio_event("harvester_charged")
		flash_amount = 1.0
		reveal_time = 1.4
		queue_redraw()


func _valid_target_shard() -> bool:
	return target_shard != null and is_instance_valid(target_shard) and target_shard.is_in_group("echo_shard")


func _find_nearest_shard() -> Node2D:
	var nearest: Node2D = null
	var nearest_distance := INF
	for shard in get_tree().get_nodes_in_group("echo_shard"):
		if shard is Node2D:
			var distance := global_position.distance_to(shard.global_position)
			if distance < nearest_distance:
				nearest = shard
				nearest_distance = distance
	return nearest


func _next_wander_target() -> Vector2:
	var center := Vector2(640.0, 350.0)
	var direction := Vector2.RIGHT.rotated(phase + randf_range(-1.2, 1.2))
	return center + direction * randf_range(130.0, 250.0)


func _cancel_channel(interrupted: bool) -> void:
	channeling = false
	channel_time = 0.0
	target_shard = null
	if interrupted:
		channel_pause = CHANNEL_INTERRUPTION


func cancel_channel() -> void:
	_cancel_channel(false)


func begin_escape_mode() -> void:
	_cancel_channel(false)
	reveal_time = maxf(reveal_time, 1.3)
	flash_amount = 0.55


func receive_signal_pulse(origin: Vector2, force: float, damage: int, signal_stagger_scale: float = 1.0) -> void:
	if dying:
		return
	var push_direction := origin.direction_to(global_position)
	if push_direction == Vector2.ZERO:
		push_direction = Vector2.RIGHT.rotated(phase)
	var player := get_tree().get_first_node_in_group("signal_player")
	var player_exposure := float(player.call("get_exposure")) if player else 0.0
	var exposure_control := 0.82
	if player_exposure >= 0.67:
		exposure_control = 0.44
	elif player_exposure >= 0.34:
		exposure_control = 0.64
	var stored_resistance := 0.72 if stored_echoes >= 2 else 1.0
	var resistance_control := maxf(0.26, 1.0 - pulse_resistance * 0.64)
	var control_factor := exposure_control * stored_resistance * resistance_control * signal_stagger_scale
	var was_channeling := channeling
	_cancel_channel(true)
	if was_channeling:
		get_parent().audio_event("sentry_interrupt")
	reveal_time = maxf(reveal_time, 2.5)
	flash_amount = 1.0
	stagger_time = maxf(stagger_time, STAGGER_DURATION * control_factor)
	stagger_brake = control_factor
	velocity = velocity * lerpf(0.84, 0.34, control_factor) + push_direction * force * control_factor * 0.78
	pulse_resistance = minf(1.0, pulse_resistance + 0.36)
	resistance_hold = 1.1
	var applied_damage := damage if signal_stagger_scale >= 0.52 else 0
	health -= applied_damage
	if health <= 0:
		_begin_death()
	queue_redraw()


func begin_emergence() -> void:
	emergence = 0.0
	reveal_amount = 0.03
	queue_redraw()


func wake_for_exposure(exposure_level: float) -> void:
	reveal_time = lerpf(0.6, 1.6, exposure_level)
	queue_redraw()


func _begin_death() -> void:
	dying = true
	death_time = 0.0
	velocity = Vector2.ZERO
	remove_from_group("echo_wraith")
	remove_from_group("echo_harvester")
	get_parent().audio_event("harvester_death")
	if not get_parent().is_escape():
		for index in stored_echoes:
			var direction := Vector2.RIGHT.rotated(phase + float(index) * PI)
			get_parent().spawn_echo_shard(global_position + direction * 19.0)
	get_parent().harvester_destroyed()


func _process_death(delta: float) -> void:
	death_time += delta
	queue_redraw()
	if death_time >= DEATH_DURATION:
		queue_free()


func _draw() -> void:
	if dying:
		_draw_fragments()
		return
	var pulse := sin(Time.get_ticks_msec() * 0.0025 + phase) * 0.5 + 0.5
	var alpha := lerpf(0.12, 0.86, reveal_amount) * emergence
	var core_alpha := alpha * (0.38 + flash_amount * 0.62)
	var points := PackedVector2Array([Vector2(0, -20), Vector2(9, -10), Vector2(9, 10), Vector2(0, 20), Vector2(-9, 10), Vector2(-9, -10)])
	for index in points.size():
		draw_line(points[index], points[(index + 1) % points.size()], Color(0.25, 0.82, 1.0, alpha), 1.25, true)
	draw_arc(Vector2.ZERO, 16.0 + pulse * 2.0, 0.35, PI - 0.35, 28, Color(0.35, 0.9, 1.0, core_alpha), 1.2, true)
	draw_arc(Vector2.ZERO, 16.0 + pulse * 2.0, PI + 0.35, TAU - 0.35, 28, Color(0.35, 0.9, 1.0, core_alpha), 1.2, true)
	draw_circle(Vector2.ZERO, 3.5 + flash_amount * 1.6, Color(0.58, 0.96, 1.0, core_alpha))
	if channeling and _valid_target_shard():
		var local_target := to_local(target_shard.global_position)
		var channel_alpha := alpha * (0.45 + sin(Time.get_ticks_msec() * 0.014) * 0.2)
		draw_line(Vector2.ZERO, local_target, Color(0.45, 0.94, 1.0, channel_alpha), 1.0, true)
		draw_arc(Vector2.ZERO, 24.0, 0.0, TAU, 32, Color(0.38, 0.86, 1.0, channel_alpha), 1.0, true)
	for index in stored_echoes:
		var orbit_angle := phase + Time.get_ticks_msec() * (0.0018 + stored_echoes * 0.0015) + float(index) * PI
		var orbit_position := Vector2.RIGHT.rotated(orbit_angle) * 25.0
		draw_circle(orbit_position, 3.2, Color(0.58, 0.98, 1.0, alpha * 0.9))
	if stored_echoes >= 2:
		draw_arc(Vector2.ZERO, 30.0 + pulse * 3.0, 0.0, TAU, 40, Color(0.46, 0.94, 1.0, alpha * 0.55), 1.5, true)
	if emergence < 1.0:
		draw_line(Vector2(0, -38.0 * (1.0 - emergence)), Vector2.ZERO, Color(0.3, 0.88, 1.0, alpha * 0.5), 1.0, true)


func _draw_fragments() -> void:
	var progress := clampf(death_time / DEATH_DURATION, 0.0, 1.0)
	var alpha := (1.0 - progress) * 0.82
	for angle in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
		var direction := Vector2.RIGHT.rotated(angle + phase)
		draw_line(direction * (8.0 + progress * 34.0), direction * (20.0 + progress * 48.0), Color(0.38, 0.9, 1.0, alpha), 1.8, true)
	draw_circle(Vector2.ZERO, 11.0 * (1.0 - progress), Color(0.48, 0.94, 1.0, alpha * 0.35))
