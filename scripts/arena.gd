extends Node2D

const VIEWPORT_SIZE := Vector2(1280.0, 720.0)
const PULSE_SCRIPT := preload("res://scripts/pulse.gd")
const WRAITH_SCRIPT := preload("res://scripts/echo_wraith.gd")
const HARVESTER_SCRIPT := preload("res://scripts/echo_harvester.gd")
const SENTRY_SCRIPT := preload("res://scripts/null_sentry.gd")
const SHARD_SCRIPT := preload("res://scripts/echo_shard.gd")
const SCAR_SCRIPT := preload("res://scripts/resonance_scar.gd")
const NULL_GATE_SCRIPT := preload("res://scripts/null_gate.gd")
const NULL_POCKET_SCRIPT := preload("res://scripts/null_pocket.gd")
const ECHO_TARGET := 8
const MAX_WRAITHS := 8

enum RunState { PLAYING, ESCAPE, LOST, STABILIZED }

var stars: Array[Dictionary] = []
var drift := 0.0
var camera_shake_time := 0.0
var camera_shake_strength := 0.0
var exposure := 0.0
var run_state := RunState.PLAYING
var echoes_collected := 0
var elapsed_time := 0.0
var trace_lock := false
var trace_position := Vector2.ZERO
var trace_dash_timer := 0.0
var escape_timer := 14.0
var escape_intro_time := 0.0
var null_gate: Node2D
var null_pocket: Node2D
var status_message_time := 0.0
@onready var arena_camera: Camera2D = $ArenaCamera
@onready var threat_director: Node = $ThreatDirector
@onready var run_stats: Node = $RunStats


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_generate_stars()
	_update_echo_counter()
	queue_redraw()


func _process(delta: float) -> void:
	drift += delta
	_update_exposure()
	if is_playing():
		elapsed_time += delta
		var player_for_stats := get_tree().get_first_node_in_group("signal_player")
		var saturated := player_for_stats != null and bool(player_for_stats.get("core_saturated"))
		run_stats.call("tick", delta, exposure, saturated)
		_update_trace_lock(delta)
		_update_escape_state(delta)
		threat_director.call("tick", delta)
	_update_camera_shake(delta)
	_update_final_echo_pulse()
	_update_status_message(delta)
	queue_redraw()


func emit_pulse(origin: Vector2, signal_profile: String, charge_ratio: float) -> void:
	if not is_playing():
		return
	var pulse := Node2D.new()
	pulse.set_script(PULSE_SCRIPT)
	pulse.position = origin
	add_child(pulse)
	pulse.call("configure", signal_profile)
	run_stats.call("record_signal", signal_profile)
	audio_event("signal_%s" % signal_profile, charge_ratio)
	camera_shake_time = lerpf(0.08, 0.18, charge_ratio)
	camera_shake_strength = lerpf(2.0, 11.0, charge_ratio)
	_create_resonance_scar(origin, signal_profile, charge_ratio)


func audio_event(kind: String, value: float = 0.0) -> void:
	var audio := get_node_or_null("AudioDirector")
	if audio and audio.has_method("trigger"):
		audio.call("trigger", kind, value)


func _create_resonance_scar(origin: Vector2, signal_profile: String, charge_ratio: float) -> void:
	if signal_profile == "quick":
		return
	if signal_profile == "resonant" and exposure < 0.7:
		return
	var active_scars := get_tree().get_nodes_in_group("resonance_scar")
	if active_scars.size() >= 3:
		var oldest_scar := active_scars[0]
		if oldest_scar.has_method("expire"):
			oldest_scar.call("expire")
	var player := get_tree().get_first_node_in_group("signal_player")
	var exposure_at_signal := float(player.call("get_exposure")) if player else exposure
	var scar := Node2D.new()
	scar.set_script(SCAR_SCRIPT)
	scar.position = origin
	add_child(scar)
	var weak_scar := signal_profile == "resonant"
	scar.call("configure", charge_ratio, exposure_at_signal, trace_lock, weak_scar)
	audio_event("scar_imprint")


func player_damaged(source_type: String = "enemy_contact") -> void:
	camera_shake_time = 0.22
	camera_shake_strength = 13.0
	audio_event("damage")
	run_stats.call("record_damage", source_type)
	threat_director.call("note_player_damaged")


func is_playing() -> bool:
	return run_state == RunState.PLAYING or run_state == RunState.ESCAPE


func is_escape() -> bool:
	return run_state == RunState.ESCAPE


func is_player_in_null_pocket(player_position: Vector2) -> bool:
	return null_pocket != null and is_instance_valid(null_pocket) and bool(null_pocket.call("contains", player_position))


func get_null_pocket_silence_time() -> float:
	if null_pocket != null and is_instance_valid(null_pocket):
		return float(null_pocket.call("get_silence_time"))
	return 0.0


func get_progress_ratio() -> float:
	return float(echoes_collected) / float(ECHO_TARGET)


func is_machine_panic() -> bool:
	return run_state == RunState.PLAYING and ECHO_TARGET - echoes_collected <= 2


func activate_trace_lock(origin: Vector2) -> void:
	if not is_playing() or trace_lock:
		return
	trace_lock = true
	run_stats.call("record_trace_lock")
	trace_position = origin
	trace_dash_timer = 0.38
	$Interface/TraceLock.visible = true


func clear_trace_lock() -> void:
	trace_lock = false
	trace_dash_timer = 0.0
	$Interface/TraceLock.visible = false


func _update_trace_lock(delta: float) -> void:
	if not trace_lock:
		return
	var player := get_tree().get_first_node_in_group("signal_player") as Node2D
	if player:
		trace_position = player.global_position
	trace_dash_timer -= delta
	if trace_dash_timer <= 0.0:
		_request_trace_dashes()
		trace_dash_timer = 1.7


func _request_trace_dashes() -> void:
	var player := get_tree().get_first_node_in_group("signal_player") as Node2D
	if player == null:
		return
	var candidates := get_tree().get_nodes_in_group("echo_wraith")
	candidates.shuffle()
	var started := 0
	for wraith in candidates:
		if wraith is Node2D and wraith.global_position.distance_to(player.global_position) >= 125.0 and wraith.has_method("begin_trace_dash"):
			wraith.call("begin_trace_dash", player.global_position)
			started += 1
			if started >= 2:
				break


func player_destroyed() -> void:
	if not is_playing():
		return
	run_state = RunState.LOST
	run_stats.call("finish", "lost", "health_depleted", 0.0)
	audio_event("death")
	clear_trace_lock()
	$Interface/Containment.visible = false
	$Interface/GameOver/Title.text = "SIGNAL LOST"
	$Interface/GameOver/RestartHint.text = "Press R to restart"
	$Interface/GameOver.visible = true
	get_tree().paused = true


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		threat_director.call("toggle_debug")
	if (run_state == RunState.LOST or run_state == RunState.STABILIZED) and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		get_tree().paused = false
		get_tree().reload_current_scene()


func spawn_progress_echo_shard(origin: Vector2, opportunity_id: int) -> void:
	if run_state != RunState.PLAYING or opportunity_id <= 0:
		return
	var shard := Node2D.new()
	shard.set_script(SHARD_SCRIPT)
	shard.position = origin
	add_child(shard)
	shard.call("configure_progress", opportunity_id)
	audio_event("shard_spawn")


func carrier_destroyed(origin: Vector2, opportunity_id: int, kind: String) -> void:
	if run_state == RunState.PLAYING:
		threat_director.call("carrier_destroyed", origin, opportunity_id, kind)


func harvester_destroyed() -> void:
	run_stats.call("record_enemy_destroyed", "harvester")
	threat_director.call("note_threat_defeated", "harvester")


func sentry_destroyed() -> void:
	run_stats.call("record_enemy_destroyed", "sentry")
	threat_director.call("note_threat_defeated", "sentry")


func basic_enemy_destroyed() -> void:
	run_stats.call("record_enemy_destroyed", "basic")


func shard_intercepted() -> void:
	run_stats.call("record_shard_intercepted")


func shard_expired() -> void:
	run_stats.call("record_shard_expired")


func null_pocket_used() -> void:
	run_stats.call("record_null_pocket_used")


func break_attempt_blocked() -> void:
	run_stats.call("record_break_blocked")


func disruption_performed(kind: String) -> void:
	run_stats.call("record_disruption", kind)


func collect_echo_shard(shard: Node2D) -> void:
	if run_state != RunState.PLAYING:
		return
	var opportunity_id := int(shard.get("opportunity_id"))
	if opportunity_id <= 0 or not bool(threat_director.call("complete_opportunity", opportunity_id)):
		return
	echoes_collected = mini(ECHO_TARGET, echoes_collected + 1)
	run_stats.call("record_echoes", echoes_collected)
	audio_event("shard_collect", float(echoes_collected))
	_update_echo_counter()
	shard.call("begin_collection")
	if echoes_collected >= ECHO_TARGET:
		_begin_escape()


func progress_shard_expired(opportunity_id: int) -> void:
	threat_director.call("opportunity_expired", opportunity_id)


func progress_shard_stored(opportunity_id: int) -> void:
	threat_director.call("opportunity_stored", opportunity_id)


func progress_shard_released(opportunity_id: int) -> void:
	threat_director.call("opportunity_released", opportunity_id)


func _begin_escape() -> void:
	if run_state != RunState.PLAYING:
		return
	run_state = RunState.ESCAPE
	run_stats.call("begin_escape")
	audio_event("escape")
	escape_intro_time = 0.8
	escape_timer = 14.0
	clear_trace_lock()
	if null_pocket != null and is_instance_valid(null_pocket):
		null_pocket.call("force_expire")
	_show_status_message("CORE PRIMED", 0.8)
	for shard in get_tree().get_nodes_in_group("echo_shard"):
		if shard.has_method("expire"):
			shard.call("expire")
	for harvester in get_tree().get_nodes_in_group("echo_harvester"):
		if harvester.has_method("begin_escape_mode"):
			harvester.call("begin_escape_mode")


func _update_escape_state(delta: float) -> void:
	if run_state != RunState.ESCAPE:
		$Interface/Containment.visible = false
		return
	if escape_intro_time > 0.0:
		escape_intro_time = maxf(0.0, escape_intro_time - delta)
		if escape_intro_time <= 0.0:
			_spawn_null_gate()
			_show_status_message("REACH THE NULL GATE", 1.4)
		return
	escape_timer = maxf(0.0, escape_timer - delta)
	$Interface/Containment.visible = true
	$Interface/Containment.text = "CONTAINMENT %.1f" % escape_timer
	if escape_timer <= 0.0:
		_fail_escape()


func request_directed_null_pocket() -> bool:
	if run_state != RunState.PLAYING or (null_pocket != null and is_instance_valid(null_pocket)):
		return false
	return _spawn_null_pocket()


func _spawn_null_pocket() -> bool:
	var player := get_tree().get_first_node_in_group("signal_player") as Node2D
	if player == null:
		return false
	var pocket_position := Vector2.ZERO
	var found_position := false
	for attempt in 18:
		var candidate := Vector2(randf_range(176.0, 1104.0), randf_range(142.0, 578.0))
		if candidate.distance_to(VIEWPORT_SIZE * 0.5) < 175.0 or candidate.distance_to(player.global_position) < 280.0:
			continue
		if null_gate != null and is_instance_valid(null_gate) and candidate.distance_to(null_gate.global_position) < 160.0:
			continue
		var blocked := false
		for shard in get_tree().get_nodes_in_group("echo_shard"):
			if shard is Node2D and candidate.distance_to(shard.global_position) < 118.0:
				blocked = true
				break
		if not blocked:
			for scar in get_tree().get_nodes_in_group("resonance_scar"):
				if scar is Node2D and candidate.distance_to(scar.global_position) < 180.0:
					blocked = true
					break
		if not blocked:
			pocket_position = candidate
			found_position = true
			break
	if not found_position:
		return false
	null_pocket = Node2D.new()
	null_pocket.set_script(NULL_POCKET_SCRIPT)
	null_pocket.position = pocket_position
	add_child(null_pocket)
	run_stats.call("record_first_null_pocket")
	audio_event("pocket_spawn")
	return true


func null_pocket_collapsed(pocket: Node2D) -> void:
	if pocket == null_pocket:
		null_pocket = null
		threat_director.call("note_null_pocket_resolved")


func _spawn_null_gate() -> void:
	var player := get_tree().get_first_node_in_group("signal_player") as Node2D
	var candidates := [Vector2(112.0, 112.0), Vector2(1168.0, 112.0), Vector2(112.0, 590.0), Vector2(1168.0, 590.0), Vector2(112.0, 360.0), Vector2(1168.0, 360.0), Vector2(640.0, 112.0), Vector2(640.0, 590.0)]
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(player.global_position) > b.distance_to(player.global_position))
	var gate_position: Vector2 = candidates[0]
	for candidate in candidates:
		var safe := true
		for enemy in get_tree().get_nodes_in_group("echo_wraith"):
			if enemy is Node2D and candidate.distance_to(enemy.global_position) < 95.0:
				safe = false
				break
		if safe:
			gate_position = candidate
			break
	null_gate = Node2D.new()
	null_gate.set_script(NULL_GATE_SCRIPT)
	null_gate.position = gate_position
	add_child(null_gate)
	if player:
		run_stats.call("set_null_gate_distance", player.global_position.distance_to(gate_position))
	audio_event("gate_open")


func enter_null_gate() -> void:
	if run_state != RunState.ESCAPE:
		return
	run_state = RunState.STABILIZED
	run_stats.call("finish", "stabilized", "reached_null_gate", escape_timer)
	audio_event("gate_enter")
	audio_event("victory")
	clear_trace_lock()
	$Interface/Containment.visible = false
	for scar in get_tree().get_nodes_in_group("resonance_scar"):
		scar.queue_free()
	for harvester in get_tree().get_nodes_in_group("echo_harvester"):
		if harvester.has_method("cancel_channel"):
			harvester.call("cancel_channel")
	$Player.visible = false
	$Interface/GameOver/Title.text = "SIGNAL ESCAPED"
	$Interface/GameOver/RestartHint.text = "Press R to run again"
	$Interface/GameOver.visible = true
	get_tree().paused = true


func _fail_escape() -> void:
	if run_state != RunState.ESCAPE:
		return
	run_state = RunState.LOST
	run_stats.call("finish", "lost", "trace_complete", 0.0)
	audio_event("trace_fail")
	clear_trace_lock()
	$Interface/Containment.visible = false
	$Interface/GameOver/Title.text = "TRACE COMPLETE"
	$Interface/GameOver/RestartHint.text = "Press R to restart"
	$Interface/GameOver.visible = true
	get_tree().paused = true


func _show_status_message(message: String, duration: float) -> void:
	$Interface/StatusMessage.text = message
	$Interface/StatusMessage.visible = true
	status_message_time = duration


func _update_status_message(delta: float) -> void:
	if status_message_time <= 0.0:
		return
	status_message_time = maxf(0.0, status_message_time - delta)
	$Interface/StatusMessage.modulate.a = minf(1.0, status_message_time * 2.4)
	if status_message_time <= 0.0:
		$Interface/StatusMessage.visible = false


func _update_echo_counter() -> void:
	$Interface/EchoCounter.text = "ECHOES %d/%d" % [echoes_collected, ECHO_TARGET]


func spawn_directed_threat(kind: String) -> bool:
	return spawn_threat_node(kind) != null


func spawn_echo_carrier(kind: String, opportunity_id: int) -> Node2D:
	var threat := spawn_threat_node(kind)
	if threat and threat.has_method("set_echo_carrier"):
		threat.call("set_echo_carrier", opportunity_id)
	return threat


func spawn_threat_node(kind: String) -> Node2D:
	if not is_playing() or get_tree().get_nodes_in_group("echo_wraith").size() >= MAX_WRAITHS:
		return null
	var spawn_position := _find_safe_threat_spawn_position()
	if spawn_position == Vector2.ZERO:
		return null
	var threat := Node2D.new()
	match kind:
		"harvester": threat.set_script(HARVESTER_SCRIPT)
		"sentry": threat.set_script(SENTRY_SCRIPT)
		_: threat.set_script(WRAITH_SCRIPT)
	threat.position = spawn_position
	add_child(threat)
	if kind == "harvester" or kind == "sentry":
		run_stats.call("record_first_special", kind)
	threat.call("begin_emergence")
	if threat.has_method("wake_for_exposure") and (exposure >= 0.34 or is_machine_panic()):
		threat.call("wake_for_exposure", maxf(exposure, 0.5))
	return threat


func _find_safe_threat_spawn_position() -> Vector2:
	var player := get_tree().get_first_node_in_group("signal_player") as Node2D
	for attempt in 14:
		var spawn_position := Vector2.ZERO
		match randi_range(0, 3):
			0: spawn_position = Vector2(randf_range(92.0, 1188.0), 70.0)
			1: spawn_position = Vector2(1210.0, randf_range(82.0, 610.0))
			2: spawn_position = Vector2(randf_range(92.0, 1188.0), 630.0)
			_: spawn_position = Vector2(70.0, randf_range(82.0, 610.0))
		if player and spawn_position.distance_to(player.global_position) < 290.0:
			continue
		if null_pocket != null and is_instance_valid(null_pocket) and bool(null_pocket.call("contains", spawn_position)):
			continue
		if null_gate != null and is_instance_valid(null_gate) and spawn_position.distance_to(null_gate.global_position) < 112.0:
			continue
		var occupied := false
		for enemy in get_tree().get_nodes_in_group("echo_wraith"):
			if enemy is Node2D and spawn_position.distance_to(enemy.global_position) < 62.0:
				occupied = true
				break
		if not occupied:
			for scar in get_tree().get_nodes_in_group("resonance_scar"):
				if scar is Node2D and spawn_position.distance_to(scar.global_position) < 132.0:
					occupied = true
					break
		if not occupied:
			return spawn_position
	return Vector2.ZERO


func get_visual_overload() -> float:
	var all_enemies := get_tree().get_nodes_in_group("echo_wraith").size()
	var harvesters := get_tree().get_nodes_in_group("echo_harvester").size()
	var sentries := get_tree().get_nodes_in_group("null_sentry").size()
	var basics := maxi(0, all_enemies - harvesters - sentries)
	var scars := get_tree().get_nodes_in_group("resonance_scar").size()
	var shards := get_tree().get_nodes_in_group("echo_shard").size()
	var load := float(basics) + float(harvesters) * 1.45 + float(sentries) * 1.7 + float(scars) * 0.62 + minf(1.0, float(shards) * 0.12)
	if trace_lock:
		load += 0.8
	if null_pocket != null and is_instance_valid(null_pocket):
		load += 0.35
	return load


func get_exposure_band() -> int:
	if exposure >= 0.67:
		return 2
	if exposure >= 0.34:
		return 1
	return 0


func _update_final_echo_pulse() -> void:
	var remaining := ECHO_TARGET - echoes_collected
	if is_machine_panic():
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
	_draw_trace_lock()
	_draw_frame()


func _draw_trace_lock() -> void:
	if not trace_lock:
		return
	var pulse := 0.55 + sin(drift * 5.0) * 0.2
	draw_arc(trace_position, 46.0 + pulse * 10.0, 0.0, TAU, 48, Color(0.36, 0.9, 1.0, pulse * 0.4), 1.0, true)
	for angle in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
		var direction := Vector2.RIGHT.rotated(angle + drift * 0.22)
		draw_line(trace_position + direction * 118.0, trace_position + direction * 60.0, Color(0.36, 0.9, 1.0, pulse * 0.48), 1.2, true)


func _draw_grid() -> void:
	var panic_boost := 0.045 if is_machine_panic() else 0.0
	var grid_color := Color(0.12, 0.4, 0.53, 0.075 + exposure * 0.075 + panic_boost)
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
	if is_machine_panic():
		draw_arc(center, 356.0, rotating_angle * 1.4 + PI, rotating_angle * 1.4 + PI + 0.72, 40, Color(0.38, 0.88, 1.0, 0.28 + sin(drift * 3.0) * 0.1), 1.4, true)


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
