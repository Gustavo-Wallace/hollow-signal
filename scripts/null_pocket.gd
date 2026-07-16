extends Node2D

const RADIUS := 102.0
const WORLD_LIFETIME := 16.0
const SILENCE_CAPACITY := 4.0
const TRACE_BREAK_DELAY := 0.75
const FORMATION_SPEED := 1.65
const COLLAPSE_DURATION := 0.42

var formation := 0.0
var world_age := 0.0
var remaining_capacity := SILENCE_CAPACITY
var player_silence_time := 0.0
var collapsing := false
var collapse_time := 0.0
var phase := 0.0
var player_was_inside := false
var instability_announced := false
var use_recorded := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("null_pocket")
	phase = fmod(global_position.x * 0.017 + global_position.y * 0.029, TAU)
	queue_redraw()


func _process(delta: float) -> void:
	if not get_parent().is_playing() or get_parent().is_escape():
		_begin_collapse()
	if collapsing:
		collapse_time += delta
		queue_redraw()
		if collapse_time >= COLLAPSE_DURATION:
			get_parent().null_pocket_collapsed(self)
			queue_free()
		return
	formation = move_toward(formation, 1.0, delta * FORMATION_SPEED)
	world_age += delta
	phase += delta
	var player := get_tree().get_first_node_in_group("signal_player") as Node2D
	var inside := player != null and contains(player.global_position)
	if inside:
		if not use_recorded:
			use_recorded = true
			get_parent().null_pocket_used()
		player_silence_time += delta
		remaining_capacity = maxf(0.0, remaining_capacity - delta)
		if not instability_announced and remaining_capacity <= SILENCE_CAPACITY * 0.2:
			instability_announced = true
			get_parent().audio_event("pocket_unstable")
		if player_silence_time >= TRACE_BREAK_DELAY and player.has_method("break_trace_from_null"):
			player.call("break_trace_from_null")
	else:
		player_silence_time = 0.0
	if inside != player_was_inside:
		get_parent().audio_event("pocket_enter" if inside else "pocket_exit")
	player_was_inside = inside
	if world_age >= WORLD_LIFETIME or remaining_capacity <= 0.0:
		_begin_collapse()
	queue_redraw()


func contains(point: Vector2) -> bool:
	return not collapsing and formation >= 0.72 and global_position.distance_to(point) <= RADIUS


func get_silence_time() -> float:
	return player_silence_time


func force_expire() -> void:
	_begin_collapse()


func _begin_collapse() -> void:
	if collapsing:
		return
	collapsing = true
	player_was_inside = false
	get_parent().audio_event("pocket_collapse")


func _draw() -> void:
	var dissolve := 1.0 - clampf(collapse_time / COLLAPSE_DURATION, 0.0, 1.0)
	var active_radius := RADIUS * lerpf(0.42, 1.0, formation) * dissolve
	var capacity_ratio := remaining_capacity / SILENCE_CAPACITY
	var unstable := capacity_ratio <= 0.2
	var flicker := 0.72 + sin(phase * (8.0 if unstable else 2.0)) * (0.18 if unstable else 0.06)
	var boundary_alpha := (0.18 + formation * 0.18) * flicker * dissolve
	draw_circle(Vector2.ZERO, active_radius, Color(0.008, 0.022, 0.048, 0.43 * formation * dissolve))
	draw_circle(Vector2.ZERO, active_radius * 0.66, Color(0.006, 0.014, 0.032, 0.32 * formation * dissolve))
	var segment_count := maxi(2, int(7.0 * capacity_ratio + 0.8))
	for index in segment_count:
		var angle := phase * 0.18 + float(index) * TAU / 7.0
		draw_arc(Vector2.ZERO, active_radius, angle, angle + 0.48, 18, Color(0.25, 0.52, 0.68, boundary_alpha), 1.1, true)
		draw_arc(Vector2.ZERO, active_radius * 0.72, angle + 0.2, angle + 0.43, 12, Color(0.17, 0.36, 0.52, boundary_alpha * 0.62), 1.0, true)
	for index in 10:
		var angle := phase * 0.34 + float(index) * TAU / 10.0
		var point := Vector2.RIGHT.rotated(angle) * (active_radius * (0.22 + float(index % 4) * 0.12))
		draw_circle(point, 1.0 + float(index % 2) * 0.45, Color(0.25, 0.57, 0.7, boundary_alpha * 0.68))
	if unstable:
		draw_arc(Vector2.ZERO, active_radius + 5.0, phase * 2.4, phase * 2.4 + PI * 0.86, 24, Color(0.38, 0.68, 0.8, boundary_alpha * 1.35), 1.3, true)
