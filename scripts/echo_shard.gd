extends Node2D

const COLLECTION_RADIUS := 28.0
const COLLECTION_DURATION := 0.38
const LIFETIME := 13.0
const INSTABILITY_DURATION := 3.0

var phase := 0.0
var collected := false
var collection_time := 0.0
var lifetime := 0.0
var expiring := false
var expire_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	phase = fmod(global_position.x * 0.031 + global_position.y * 0.017, TAU)
	add_to_group("echo_shard")
	queue_redraw()


func _process(delta: float) -> void:
	if expiring:
		expire_time += delta
		queue_redraw()
		if expire_time >= 0.45:
			queue_free()
		return
	if collected:
		collection_time += delta
		queue_redraw()
		if collection_time >= COLLECTION_DURATION:
			queue_free()
		return
	lifetime += delta
	if lifetime >= LIFETIME:
		get_parent().shard_expired()
		queue_free()
		return
	phase += delta * 2.2
	var player := get_tree().get_first_node_in_group("signal_player") as Node2D
	if player and global_position.distance_to(player.global_position) <= COLLECTION_RADIUS:
		get_parent().collect_echo_shard(self)
	queue_redraw()


func begin_collection() -> void:
	if collected:
		return
	collected = true
	remove_from_group("echo_shard")
	queue_redraw()


func expire() -> void:
	if collected or expiring:
		return
	expiring = true
	remove_from_group("echo_shard")
	queue_redraw()


func _draw() -> void:
	if collected:
		_draw_collection_echo()
		return
	var bob := sin(phase) * 2.0
	var pulse := 0.7 + sin(phase * 1.7) * 0.3
	var instability := clampf((lifetime - (LIFETIME - INSTABILITY_DURATION)) / INSTABILITY_DURATION, 0.0, 1.0)
	var flicker := 1.0 if instability <= 0.0 else 0.38 + absf(sin(Time.get_ticks_msec() * 0.018)) * 0.62
	var dissolve := 1.0 - clampf(expire_time / 0.45, 0.0, 1.0)
	var alpha := (1.0 - instability * 0.5) * flicker * dissolve
	draw_circle(Vector2(0, bob), 13.0 + pulse * 3.0, Color(0.12, 0.72, 1.0, 0.065 * alpha))
	draw_circle(Vector2(0, bob), 6.0 + pulse * 1.2, Color(0.25, 0.85, 1.0, 0.22 * alpha))
	var diamond := PackedVector2Array([Vector2(0, bob - 5), Vector2(4, bob), Vector2(0, bob + 5), Vector2(-4, bob)])
	draw_colored_polygon(diamond, Color(0.55, 0.96, 1.0, 0.94 * alpha))
	draw_arc(Vector2(0, bob), 10.0, phase, phase + 1.65, 18, Color(0.34, 0.9, 1.0, 0.48 * alpha), 1.0, true)


func _draw_collection_echo() -> void:
	var progress := clampf(collection_time / COLLECTION_DURATION, 0.0, 1.0)
	var alpha := (1.0 - progress) * 0.85
	var radius := 8.0 + progress * 34.0
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, Color(0.4, 0.94, 1.0, alpha), 1.5, true)
	draw_circle(Vector2.ZERO, 7.0 * (1.0 - progress), Color(0.6, 0.98, 1.0, alpha))
