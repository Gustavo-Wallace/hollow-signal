extends Node2D

const MAX_SPEED := 330.0
const ACCELERATION := 1250.0
const DECELERATION := 1650.0
const QUICK_COOLDOWN := 0.42
const BREAK_COOLDOWN := 1.05
const CHARGE_FULL_TIME := 0.86
const MAX_CHARGE_GRACE := 0.4
const MAX_CHARGE_EXPOSURE_RATE := 0.12
const MAX_CHARGE_TRACE_RATE := 0.55
const MAX_HEALTH := 3
const INVULNERABILITY_DURATION := 1.0
const EXPOSURE_DECAY := 0.05
const TRACE_MOVE_THRESHOLD := 72.0
const TRACE_WINDOW := 2.4
const ARENA_BOUNDS := Rect2(62.0, 62.0, 1156.0, 556.0)

var velocity := Vector2.ZERO
var trail_points: PackedVector2Array = []
var pulse_cooldown := 0.0
var health := MAX_HEALTH
var invulnerability_time := 0.0
var exposure := 0.0
var damage_flash := 0.0
var destroyed := false
var trace_anchor := Vector2.ZERO
var trace_time := 0.0
var trace_value := 0.0
var trace_locked := false
var is_charging := false
var charge_ratio := 0.0
var max_charge_hold_time := 0.0
var current_cooldown_length := QUICK_COOLDOWN
@onready var trail: Line2D = $Trail
@onready var signal_hint: Label = $"../Interface/SignalHint"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("signal_player")
	trail_points.append(global_position)
	trace_anchor = global_position
	queue_redraw()


func _process(delta: float) -> void:
	if destroyed or not get_parent().is_playing():
		_cancel_charge()
		return
	_move(delta)
	_update_trail()
	pulse_cooldown = maxf(0.0, pulse_cooldown - delta)
	invulnerability_time = maxf(0.0, invulnerability_time - delta)
	var progress_decay := lerpf(1.0, 0.62, get_parent().get_progress_ratio())
	if get_parent().is_escape():
		progress_decay = 0.2
	exposure = maxf(0.0, exposure - EXPOSURE_DECAY * progress_decay * delta)
	damage_flash = maxf(0.0, damage_flash - delta * 3.5)
	_update_signal_charge(delta)
	_update_stationary_trace(delta)
	signal_hint.modulate.a = 0.95 if is_charging else 0.28 + (1.0 - pulse_cooldown / current_cooldown_length) * 0.72
	queue_redraw()


func _move(delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var charge_speed_multiplier := lerpf(1.0, 0.6, charge_ratio) if is_charging else 1.0
	var current_max_speed := MAX_SPEED * charge_speed_multiplier
	if direction != Vector2.ZERO:
		velocity = velocity.move_toward(direction * current_max_speed, ACCELERATION * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, DECELERATION * delta)
	global_position += velocity * delta
	global_position = global_position.clamp(ARENA_BOUNDS.position, ARENA_BOUNDS.end)


func _update_trail() -> void:
	if trail_points.is_empty() or trail_points[0].distance_to(global_position) > 5.0:
		trail_points.insert(0, global_position)
	while trail_points.size() > 22:
		trail_points.remove_at(trail_points.size() - 1)
	trail.points = trail_points
	trail.default_color.a = 0.14 + minf(velocity.length() / MAX_SPEED, 1.0) * 0.28 + exposure * 0.18


func _update_signal_charge(delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept") and pulse_cooldown <= 0.0:
		is_charging = true
		charge_ratio = 0.0
		max_charge_hold_time = 0.0
	if not is_charging:
		return
	if Input.is_action_pressed("ui_accept"):
		charge_ratio = minf(1.0, charge_ratio + delta / CHARGE_FULL_TIME)
		if charge_ratio >= 1.0:
			max_charge_hold_time += delta
			if max_charge_hold_time > MAX_CHARGE_GRACE:
				exposure = minf(1.0, exposure + MAX_CHARGE_EXPOSURE_RATE * delta)
				trace_value += MAX_CHARGE_TRACE_RATE * delta
	elif Input.is_action_just_released("ui_accept"):
		_emit_charged_signal()


func _emit_charged_signal() -> void:
	var signal_strength := maxf(0.08, charge_ratio)
	exposure = minf(1.0, exposure + lerpf(0.1, 0.48, signal_strength))
	get_parent().emit_pulse(global_position, signal_strength)
	current_cooldown_length = lerpf(QUICK_COOLDOWN, BREAK_COOLDOWN, signal_strength)
	pulse_cooldown = current_cooldown_length
	trace_value += lerpf(0.28, 1.25, signal_strength)
	_cancel_charge()


func _cancel_charge() -> void:
	is_charging = false
	charge_ratio = 0.0
	max_charge_hold_time = 0.0


func _update_stationary_trace(delta: float) -> void:
	if global_position.distance_to(trace_anchor) >= TRACE_MOVE_THRESHOLD:
		trace_anchor = global_position
		trace_time = 0.0
		trace_value = 0.0
		if trace_locked:
			trace_locked = false
			get_parent().clear_trace_lock()
		return
	trace_time += delta
	if not trace_locked and trace_time >= TRACE_WINDOW and trace_value >= 1.45:
		trace_locked = true
		get_parent().activate_trace_lock(global_position)
	if not trace_locked and trace_time >= TRACE_WINDOW + 0.8:
		trace_time = 0.0
		trace_value = 0.0


func take_damage(source_position: Vector2) -> void:
	if invulnerability_time > 0.0 or destroyed or not get_parent().is_playing():
		return
	health -= 1
	invulnerability_time = INVULNERABILITY_DURATION
	damage_flash = 1.0
	velocity += source_position.direction_to(global_position) * 260.0
	get_parent().player_damaged()
	if health <= 0:
		destroyed = true
		get_parent().player_destroyed()
	queue_redraw()


func get_exposure() -> float:
	return exposure


func get_health() -> int:
	return health


func get_max_health() -> int:
	return MAX_HEALTH


func _draw() -> void:
	var pulse := sin(Time.get_ticks_msec() * 0.003) * 0.5 + 0.5
	var cooldown_progress := 1.0 - pulse_cooldown / current_cooldown_length
	var blink_alpha := 1.0 if invulnerability_time <= 0.0 else 0.38 + 0.62 * absf(sin(Time.get_ticks_msec() * 0.018))
	var charge_pulse := sin(Time.get_ticks_msec() * (0.004 + charge_ratio * 0.008)) * 0.5 + 0.5
	var aura_radius := 28.0 + pulse * 3.0 + exposure * 18.0 + charge_ratio * 12.0
	draw_circle(Vector2.ZERO, aura_radius, Color(0.05, 0.5, 0.82, (0.055 + exposure * 0.14 + charge_ratio * 0.08) * blink_alpha))
	draw_circle(Vector2.ZERO, 19.0 + pulse * 2.0 + exposure * 7.0, Color(0.1, 0.72, 1.0, (0.12 + exposure * 0.16) * blink_alpha))
	draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 48, Color(0.3, 0.9, 1.0, (0.72 + exposure * 0.2) * blink_alpha), 1.2, true)
	draw_arc(Vector2.ZERO, 22.0, -PI * 0.5, -PI * 0.5 + TAU * cooldown_progress, 32, Color(0.35, 0.93, 1.0, 0.52 * blink_alpha), 1.3, true)
	if is_charging:
		var charge_alpha := (0.42 + charge_ratio * 0.48) * blink_alpha
		draw_arc(Vector2.ZERO, 27.0, -PI * 0.5, -PI * 0.5 + TAU * charge_ratio, 44, Color(0.45, 0.95, 1.0, charge_alpha), 2.0, true)
		draw_arc(Vector2.ZERO, 32.0 + charge_pulse * 2.0, PI * 0.1, PI * 0.1 + TAU * charge_ratio * 0.55, 32, Color(0.3, 0.82, 1.0, charge_alpha * 0.56), 1.0, true)
		for angle in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
			var direction := Vector2.RIGHT.rotated(angle + Time.get_ticks_msec() * 0.0015)
			draw_line(direction * (42.0 - charge_ratio * 12.0), direction * 29.0, Color(0.42, 0.92, 1.0, charge_alpha * charge_ratio), 1.0, true)
	if exposure > 0.05:
		draw_arc(Vector2.ZERO, 34.0 + pulse * 5.0 + exposure * 12.0, 0.45, 2.35, 24, Color(0.3, 0.92, 1.0, exposure * 0.38 * blink_alpha), 1.0, true)
		draw_arc(Vector2.ZERO, 34.0 + pulse * 5.0 + exposure * 12.0, 3.6, 5.5, 24, Color(0.3, 0.92, 1.0, exposure * 0.38 * blink_alpha), 1.0, true)
	draw_circle(Vector2.ZERO, 10.0 + exposure * 1.5, Color(0.22, 0.83, 1.0, 0.92 * blink_alpha))
	draw_circle(Vector2.ZERO, 5.0 + damage_flash * 1.6, Color(0.8, 0.98, 1.0, blink_alpha))
	draw_line(Vector2(-17, 0), Vector2(17, 0), Color(0.35, 0.9, 1.0, 0.3 * blink_alpha), 1.0)
	draw_line(Vector2(0, -17), Vector2(0, 17), Color(0.35, 0.9, 1.0, 0.3 * blink_alpha), 1.0)
