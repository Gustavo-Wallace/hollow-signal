extends Node2D

const MIN_RADIUS := 55.0
const MAX_RADIUS := 125.0
const COLLAPSE_DURATION := 0.24

var charge_ratio := 0.5
var radius := 72.0
var warning_duration := 1.5
var age := 0.0
var collapse_age := 0.0
var collapsed := false
var trace_intensity := 0.0
var phase_offset := 0.0
var convergence_announced := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("resonance_scar")
	phase_offset = fmod(global_position.x * 0.013 + global_position.y * 0.019, TAU)
	queue_redraw()


func configure(charge: float, exposure: float, trace_locked: bool) -> void:
	charge_ratio = clampf(charge, 0.35, 1.0)
	var normalized_charge := inverse_lerp(0.35, 1.0, charge_ratio)
	radius = lerpf(MIN_RADIUS, MAX_RADIUS, normalized_charge)
	if trace_locked:
		radius += 8.0
	trace_intensity = 1.0 if trace_locked else 0.0
	warning_duration = lerpf(1.7, 1.25, clampf(exposure, 0.0, 1.0))
	queue_redraw()


func _process(delta: float) -> void:
	if not get_parent().is_playing():
		queue_free()
		return
	if collapsed:
		collapse_age += delta
		queue_redraw()
		if collapse_age >= COLLAPSE_DURATION:
			queue_free()
		return
	age += delta
	if not convergence_announced and age >= warning_duration * 0.38:
		convergence_announced = true
		get_parent().audio_event("scar_converge")
	if age >= warning_duration:
		_collapse()
	queue_redraw()


func expire() -> void:
	queue_free()


func _collapse() -> void:
	if collapsed:
		return
	collapsed = true
	get_parent().audio_event("scar_collapse")
	var player := get_tree().get_first_node_in_group("signal_player") as Node2D
	if player and global_position.distance_to(player.global_position) <= radius:
		player.call("take_damage", global_position)


func _draw() -> void:
	if collapsed:
		_draw_collapse()
		return
	var progress := clampf(age / warning_duration, 0.0, 1.0)
	var imprint_end := 0.38
	var pulse := 0.55 + sin(Time.get_ticks_msec() * (0.004 + progress * 0.009) + phase_offset) * 0.22
	var alpha := 0.2 + progress * 0.4 + trace_intensity * 0.12
	if progress < imprint_end:
		var imprint := progress / imprint_end
		draw_arc(Vector2.ZERO, radius, phase_offset, phase_offset + TAU * (0.45 + imprint * 0.4), 48, Color(0.25, 0.75, 1.0, alpha * imprint), 1.0, true)
		draw_arc(Vector2.ZERO, radius * 0.68, phase_offset + PI, phase_offset + PI + TAU * 0.25, 28, Color(0.38, 0.42, 1.0, alpha * 0.45), 1.0, true)
	else:
		var convergence := inverse_lerp(imprint_end, 1.0, progress)
		var inner_radius := lerpf(radius * 0.78, radius * 0.2, convergence)
		draw_arc(Vector2.ZERO, radius + pulse * 3.0, 0.0, TAU, 64, Color(0.3, 0.86, 1.0, alpha), 1.4 + convergence, true)
		draw_arc(Vector2.ZERO, inner_radius, phase_offset, phase_offset + TAU * 0.72, 44, Color(0.42, 0.5, 1.0, alpha * 0.72), 1.2, true)
		for angle in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
			var direction := Vector2.RIGHT.rotated(angle + phase_offset + progress * 1.5)
			draw_line(direction * radius * 0.9, direction * inner_radius, Color(0.38, 0.9, 1.0, alpha * (0.48 + convergence * 0.32)), 1.0, true)
	draw_circle(Vector2.ZERO, 3.0 + progress * 2.0, Color(0.58, 0.96, 1.0, alpha * 0.72))


func _draw_collapse() -> void:
	var progress := clampf(collapse_age / COLLAPSE_DURATION, 0.0, 1.0)
	var alpha := (1.0 - progress) * (0.72 + trace_intensity * 0.18)
	var collapsing_radius := radius * (1.0 - progress * 0.82)
	draw_arc(Vector2.ZERO, collapsing_radius, 0.0, TAU, 64, Color(0.5, 0.95, 1.0, alpha), 2.4, true)
	draw_arc(Vector2.ZERO, radius + progress * 12.0, 0.0, TAU, 64, Color(0.36, 0.56, 1.0, alpha * 0.48), 1.0, true)
	draw_circle(Vector2.ZERO, maxf(0.0, 11.0 * (1.0 - progress)), Color(0.68, 0.98, 1.0, alpha * 0.72))
