extends Node2D

const HEALTH := 3
const OBSERVE_SPEED := 72.0
const ACCELERATION := 118.0
const MIN_DISTANCE := 290.0
const MAX_DISTANCE := 500.0
const LOCK_LOW_DURATION := 0.96
const LOCK_CRITICAL_DURATION := 0.76
const FIRE_DURATION := 0.14
const RECOVER_DURATION := 0.78
const BEAM_HALF_WIDTH := 10.0
const STAGGER_DURATION := 0.3
const ARENA_BOUNDS := Rect2(64.0, 64.0, 1152.0, 552.0)

enum AttackState { OBSERVE, LOCK, FIRE, RECOVER }

var health := HEALTH
var velocity := Vector2.ZERO
var attack_state := AttackState.OBSERVE
var attack_timer := 2.6
var state_time := 0.0
var lock_target := Vector2.ZERO
var beam_end := Vector2.ZERO
var aim_locked := false
var reveal_time := 0.0
var reveal_amount := 0.16
var flash_amount := 0.0
var stagger_time := 0.0
var stagger_brake := 0.0
var pulse_resistance := 0.0
var resistance_hold := 0.0
var phase := 0.0
var emergence := 1.0
var dying := false
var death_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("echo_wraith")
	add_to_group("null_sentry")
	phase = fmod(global_position.x * 0.023 + global_position.y * 0.011, TAU)
	attack_timer += randf_range(0.2, 1.1)
	queue_redraw()


func _process(delta: float) -> void:
	if not get_parent().is_playing():
		return
	if dying:
		_process_death(delta)
		return
	reveal_time = maxf(0.0, reveal_time - delta)
	flash_amount = maxf(0.0, flash_amount - delta * 3.3)
	stagger_time = maxf(0.0, stagger_time - delta)
	resistance_hold = maxf(0.0, resistance_hold - delta)
	if resistance_hold <= 0.0:
		pulse_resistance = move_toward(pulse_resistance, 0.0, delta * 0.72)
	emergence = move_toward(emergence, 1.0, delta * 2.0)
	_update_attack_cycle(delta)
	var target_reveal := 1.0 if reveal_time > 0.0 or attack_state != AttackState.OBSERVE else 0.16
	reveal_amount = move_toward(reveal_amount, target_reveal, delta * 1.4)
	rotation += delta * 0.14
	queue_redraw()


func _update_attack_cycle(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("signal_player") as Node2D
	if player == null:
		return
	if attack_state == AttackState.OBSERVE:
		_update_observe_movement(delta, player)
		attack_timer -= delta
		if attack_timer <= 0.0:
			if _can_begin_lock(player):
				_begin_lock(player.global_position)
			else:
				attack_timer = 0.35
	elif attack_state == AttackState.LOCK:
		velocity = velocity.move_toward(Vector2.ZERO, delta * 230.0)
		global_position += velocity * delta
		state_time += delta
		var lock_duration := _get_lock_duration(player)
		if state_time < lock_duration * 0.55:
			lock_target = player.global_position
			beam_end = _get_beam_endpoint(lock_target)
		else:
			if not aim_locked:
				aim_locked = true
				get_parent().audio_event("sentry_lock")
		if state_time >= lock_duration:
			_fire_beam(player)
	elif attack_state == AttackState.FIRE:
		state_time += delta
		if state_time >= FIRE_DURATION:
			attack_state = AttackState.RECOVER
			state_time = 0.0
	elif attack_state == AttackState.RECOVER:
		_update_observe_movement(delta, player)
		state_time += delta
		if state_time >= RECOVER_DURATION:
			attack_state = AttackState.OBSERVE
			attack_timer = _get_attack_interval(player)
	global_position = global_position.clamp(ARENA_BOUNDS.position, ARENA_BOUNDS.end)


func _update_observe_movement(delta: float, player: Node2D) -> void:
	if stagger_time > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, delta * 390.0 * stagger_brake)
		global_position += velocity * delta
		return
	var distance := global_position.distance_to(player.global_position)
	var direction := Vector2.ZERO
	if distance < MIN_DISTANCE:
		direction = player.global_position.direction_to(global_position)
	elif distance > MAX_DISTANCE:
		direction = global_position.direction_to(player.global_position)
	else:
		direction = player.global_position.direction_to(global_position).rotated(PI * 0.5 + sin(phase) * 0.35)
	var exposure := float(player.call("get_exposure"))
	velocity = velocity.move_toward(direction * OBSERVE_SPEED * (1.0 + exposure * 0.22), delta * ACCELERATION)
	global_position += velocity * delta


func _begin_lock(target: Vector2) -> void:
	attack_state = AttackState.LOCK
	state_time = 0.0
	lock_target = target
	beam_end = _get_beam_endpoint(target)
	aim_locked = false
	reveal_time = maxf(reveal_time, 1.2)
	flash_amount = 0.65
	get_parent().audio_event("sentry_lock")


func _can_begin_lock(player: Node2D) -> bool:
	return not (get_parent().is_player_in_null_pocket(player.global_position) and get_parent().get_null_pocket_silence_time() >= 0.5)


func _fire_beam(player: Node2D) -> void:
	attack_state = AttackState.FIRE
	state_time = 0.0
	flash_amount = 1.0
	get_parent().audio_event("sentry_fire")
	var closest := Geometry2D.get_closest_point_to_segment(player.global_position, global_position, beam_end)
	if player.global_position.distance_to(closest) <= BEAM_HALF_WIDTH:
		player.call("take_damage", global_position)


func _get_lock_duration(player: Node2D) -> float:
	var exposure := float(player.call("get_exposure"))
	return lerpf(LOCK_LOW_DURATION, LOCK_CRITICAL_DURATION, exposure)


func _get_attack_interval(player: Node2D) -> float:
	var exposure := float(player.call("get_exposure"))
	var interval := lerpf(3.8, 2.7, exposure)
	if get_parent().is_escape():
		interval *= 0.86
	return interval


func _get_beam_endpoint(target: Vector2) -> Vector2:
	var direction := global_position.direction_to(target)
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	var distances: Array[float] = []
	if absf(direction.x) > 0.001:
		distances.append((ARENA_BOUNDS.position.x - global_position.x) / direction.x)
		distances.append((ARENA_BOUNDS.end.x - global_position.x) / direction.x)
	if absf(direction.y) > 0.001:
		distances.append((ARENA_BOUNDS.position.y - global_position.y) / direction.y)
		distances.append((ARENA_BOUNDS.end.y - global_position.y) / direction.y)
	var distance_to_edge := 1400.0
	for distance in distances:
		if distance > 0.0:
			distance_to_edge = minf(distance_to_edge, distance)
	return global_position + direction * distance_to_edge


func receive_signal_pulse(origin: Vector2, force: float, damage: int, signal_stagger_scale: float = 1.0) -> void:
	if dying:
		return
	var push_direction := origin.direction_to(global_position)
	if push_direction == Vector2.ZERO:
		push_direction = Vector2.RIGHT.rotated(phase)
	var player := get_tree().get_first_node_in_group("signal_player")
	var player_exposure := float(player.call("get_exposure")) if player else 0.0
	var exposure_control := 0.85
	if player_exposure >= 0.67:
		exposure_control = 0.48
	elif player_exposure >= 0.34:
		exposure_control = 0.68
	var resistance_control := maxf(0.25, 1.0 - pulse_resistance * 0.62)
	var control_factor := exposure_control * resistance_control * signal_stagger_scale
	if attack_state == AttackState.LOCK:
		attack_state = AttackState.RECOVER
		state_time = 0.0
		attack_timer = 1.2
		flash_amount = 1.0
		get_parent().audio_event("sentry_interrupt")
	reveal_time = maxf(reveal_time, 2.2)
	stagger_time = maxf(stagger_time, STAGGER_DURATION * control_factor)
	stagger_brake = control_factor
	velocity = velocity * lerpf(0.84, 0.36, control_factor) + push_direction * force * control_factor * 0.62
	pulse_resistance = minf(1.0, pulse_resistance + 0.34)
	resistance_hold = 1.15
	var applied_damage := damage if signal_stagger_scale >= 0.52 else 0
	health -= applied_damage
	if health <= 0:
		_begin_death()
	queue_redraw()


func begin_emergence() -> void:
	emergence = 0.0
	reveal_amount = 0.04


func wake_for_exposure(exposure_level: float) -> void:
	reveal_time = lerpf(0.5, 1.3, exposure_level)


func _begin_death() -> void:
	dying = true
	attack_state = AttackState.RECOVER
	velocity = Vector2.ZERO
	remove_from_group("echo_wraith")
	remove_from_group("null_sentry")
	get_parent().audio_event("sentry_death")
	if not get_parent().is_escape():
		get_parent().spawn_echo_shard(global_position)
	get_parent().sentry_destroyed()


func _process_death(delta: float) -> void:
	death_time += delta
	queue_redraw()
	if death_time >= 0.5:
		queue_free()


func _draw() -> void:
	if dying:
		_draw_fragments()
		return
	var pulse := sin(Time.get_ticks_msec() * 0.002 + phase) * 0.5 + 0.5
	var alpha := lerpf(0.12, 0.84, reveal_amount) * emergence
	var eye_alpha := alpha * (0.46 + flash_amount * 0.54)
	draw_circle(Vector2.ZERO, 17.0, Color(0.02, 0.08, 0.14, alpha * 0.86))
	draw_arc(Vector2.ZERO, 25.0 + pulse * 2.0, 0.1, 1.55, 24, Color(0.34, 0.86, 1.0, alpha), 1.4, true)
	draw_arc(Vector2.ZERO, 25.0 + pulse * 2.0, 2.2, 3.75, 24, Color(0.34, 0.86, 1.0, alpha), 1.4, true)
	draw_arc(Vector2.ZERO, 25.0 + pulse * 2.0, 4.3, 5.85, 24, Color(0.34, 0.86, 1.0, alpha), 1.4, true)
	draw_circle(Vector2.ZERO, 4.2 + flash_amount * 1.8, Color(0.64, 0.97, 1.0, eye_alpha))
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var direction := Vector2.RIGHT.rotated(angle + phase)
		draw_line(direction * 29.0, direction * 38.0, Color(0.4, 0.9, 1.0, alpha * 0.72), 1.2, true)
	if attack_state == AttackState.LOCK:
		var lock_duration := _get_lock_duration(get_tree().get_first_node_in_group("signal_player") as Node2D)
		var lock_progress := clampf(state_time / lock_duration, 0.0, 1.0)
		var local_end := to_local(beam_end)
		var line_alpha := alpha * (0.16 + lock_progress * 0.72)
		draw_line(Vector2.ZERO, local_end, Color(0.42, 0.9, 1.0, line_alpha), 1.0 + lock_progress, true)
		for step in [0.2, 0.4, 0.6, 0.8]:
			var marker: Vector2 = local_end * step
			draw_circle(marker, 1.5 + lock_progress * 1.2, Color(0.58, 0.96, 1.0, line_alpha), true)
	if attack_state == AttackState.FIRE:
		var local_beam_end := to_local(beam_end)
		draw_line(Vector2.ZERO, local_beam_end, Color(0.66, 0.98, 1.0, alpha * 0.9), BEAM_HALF_WIDTH * 2.0, true)


func _draw_fragments() -> void:
	var progress := clampf(death_time / 0.5, 0.0, 1.0)
	var alpha := (1.0 - progress) * 0.86
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var direction := Vector2.RIGHT.rotated(angle + phase)
		draw_line(direction * (9.0 + progress * 28.0), direction * (22.0 + progress * 48.0), Color(0.42, 0.92, 1.0, alpha), 1.6, true)
	draw_circle(Vector2.ZERO, 12.0 * (1.0 - progress), Color(0.56, 0.96, 1.0, alpha * 0.42))
