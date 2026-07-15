extends Node2D

const MAX_SPEED := 330.0
const ACCELERATION := 1250.0
const DECELERATION := 1650.0
const PULSE_COOLDOWN := 0.65
const ARENA_BOUNDS := Rect2(62.0, 62.0, 1156.0, 556.0)

var velocity := Vector2.ZERO
var trail_points: PackedVector2Array = []
var pulse_cooldown := 0.0
@onready var trail: Line2D = $Trail


func _ready() -> void:
	add_to_group("signal_player")
	trail_points.append(global_position)
	queue_redraw()


func _process(delta: float) -> void:
	_move(delta)
	_update_trail()
	pulse_cooldown = maxf(0.0, pulse_cooldown - delta)
	if Input.is_action_just_pressed("ui_accept") and pulse_cooldown <= 0.0:
		get_parent().emit_pulse(global_position)
		pulse_cooldown = PULSE_COOLDOWN
	queue_redraw()


func _move(delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction != Vector2.ZERO:
		velocity = velocity.move_toward(direction * MAX_SPEED, ACCELERATION * delta)
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
	trail.default_color.a = 0.14 + minf(velocity.length() / MAX_SPEED, 1.0) * 0.28


func _draw() -> void:
	var pulse := sin(Time.get_ticks_msec() * 0.003) * 0.5 + 0.5
	var cooldown_progress := 1.0 - pulse_cooldown / PULSE_COOLDOWN
	draw_circle(Vector2.ZERO, 28.0 + pulse * 3.0, Color(0.05, 0.5, 0.82, 0.055))
	draw_circle(Vector2.ZERO, 19.0 + pulse * 2.0, Color(0.1, 0.72, 1.0, 0.12))
	draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 48, Color(0.3, 0.9, 1.0, 0.72), 1.2, true)
	draw_arc(Vector2.ZERO, 22.0, -PI * 0.5, -PI * 0.5 + TAU * cooldown_progress, 32, Color(0.35, 0.93, 1.0, 0.52), 1.3, true)
	draw_circle(Vector2.ZERO, 10.0, Color(0.22, 0.83, 1.0, 0.92))
	draw_circle(Vector2.ZERO, 5.0, Color(0.8, 0.98, 1.0, 1.0))
	draw_line(Vector2(-17, 0), Vector2(17, 0), Color(0.35, 0.9, 1.0, 0.3), 1.0)
	draw_line(Vector2(0, -17), Vector2(0, 17), Color(0.35, 0.9, 1.0, 0.3), 1.0)
