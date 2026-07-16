extends Node

enum Phase { OPENING, HUNT, COMPRESSION, MACHINE_PANIC, ESCAPE }
enum Cycle { BUILD, PRESSURE, RELEASE }

const BASIC_COST := 1.0
const HARVESTER_COST := 2.5
const SENTRY_COST := 3.0

var phase := Phase.OPENING
var cycle := Cycle.BUILD
var threat_budget := 0.0
var target_pressure := 0.0
var director_intensity := 0.0
var cycle_time := 4.2
var spawn_interval := 1.2
var recovery_time := 0.0
var recovery_cooldown := 0.0
var harvester_cooldown := 0.0
var sentry_cooldown := 0.0
var special_separation := 0.0
var pocket_request_cooldown := 7.0
var time_since_damage := 0.0
var recent_kills := 0.0
var debug_visible := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func tick(delta: float) -> void:
	var arena := get_parent()
	if arena == null or not arena.is_playing():
		return
	_update_timers(delta)
	_update_phase(arena)
	_update_pressure(arena, delta)
	if phase == Phase.ESCAPE:
		_tick_escape(arena)
	else:
		_tick_normal_run(arena, delta)
	_update_debug(arena)


func note_player_damaged() -> void:
	time_since_damage = 0.0
	var arena := get_parent()
	if arena == null or phase == Phase.ESCAPE or recovery_cooldown > 0.0:
		return
	var player := get_tree().get_first_node_in_group("signal_player")
	var low_health := player != null and int(player.call("get_health")) <= 1
	_begin_recovery(3.5 if low_health else 2.35)


func note_threat_defeated(kind: String) -> void:
	recent_kills = minf(5.0, recent_kills + (1.4 if kind != "basic" else 0.7))
	if kind == "basic" and recent_kills >= 2.4:
		_begin_recovery(1.55)
	if kind == "harvester":
		harvester_cooldown = maxf(harvester_cooldown, 7.0)
		special_separation = maxf(special_separation, 2.8)
		_begin_recovery(2.0)
	elif kind == "sentry":
		sentry_cooldown = maxf(sentry_cooldown, 8.0)
		special_separation = maxf(special_separation, 2.8)
		_begin_recovery(2.0)


func note_null_pocket_resolved() -> void:
	pocket_request_cooldown = maxf(pocket_request_cooldown, 8.5)


func toggle_debug() -> void:
	debug_visible = not debug_visible
	_update_debug(get_parent())


func _update_timers(delta: float) -> void:
	spawn_interval = maxf(0.0, spawn_interval - delta)
	cycle_time = maxf(0.0, cycle_time - delta)
	recovery_time = maxf(0.0, recovery_time - delta)
	recovery_cooldown = maxf(0.0, recovery_cooldown - delta)
	harvester_cooldown = maxf(0.0, harvester_cooldown - delta)
	sentry_cooldown = maxf(0.0, sentry_cooldown - delta)
	special_separation = maxf(0.0, special_separation - delta)
	pocket_request_cooldown = maxf(0.0, pocket_request_cooldown - delta)
	time_since_damage += delta
	recent_kills = maxf(0.0, recent_kills - delta * 0.22)


func _update_phase(arena: Node) -> void:
	if arena.is_escape():
		phase = Phase.ESCAPE
		threat_budget = minf(threat_budget, 1.2)
		return
	var echoes := int(arena.get("echoes_collected"))
	if echoes <= 1:
		phase = Phase.OPENING
	elif echoes <= 4:
		phase = Phase.HUNT
	elif echoes <= 6:
		phase = Phase.COMPRESSION
	else:
		phase = Phase.MACHINE_PANIC


func _update_pressure(arena: Node, delta: float) -> void:
	var phase_base: float = [0.18, 0.42, 0.63, 0.8, 0.72][phase]
	var exposure := float(arena.get("exposure"))
	var elapsed := float(arena.get("elapsed_time"))
	var living := get_tree().get_nodes_in_group("echo_wraith").size()
	var overload := float(arena.call("get_visual_overload"))
	var trace_bonus := 0.16 if bool(arena.get("trace_lock")) else 0.0
	var efficiency := clampf(time_since_damage / 50.0 + recent_kills * 0.035 + float(arena.get("echoes_collected")) / maxf(1.0, elapsed) * 1.8, 0.0, 0.22)
	target_pressure = clampf(phase_base + exposure * 0.25 + trace_bonus + efficiency - maxf(0.0, float(living) - 3.0) * 0.055 - overload * 0.018, 0.08, 1.0)
	director_intensity = move_toward(director_intensity, target_pressure, delta * 0.22)


func _tick_normal_run(arena: Node, delta: float) -> void:
	if cycle_time <= 0.0:
		_advance_cycle()
	var max_budget: float = [3.1, 5.0, 6.5, 7.6][phase]
	var income := 0.34 + director_intensity * 0.38 + float(arena.get("exposure")) * 0.16
	if cycle == Cycle.PRESSURE:
		income *= 1.13
	elif cycle == Cycle.RELEASE:
		income *= 0.44
	threat_budget = minf(max_budget, threat_budget + income * delta)
	var player := get_tree().get_first_node_in_group("signal_player")
	var low_health := player != null and int(player.call("get_health")) <= 1
	var overload := float(arena.call("get_visual_overload"))
	var special_stack := not get_tree().get_nodes_in_group("echo_harvester").is_empty() and not get_tree().get_nodes_in_group("null_sentry").is_empty()
	if low_health and recovery_time <= 0.0 and recovery_cooldown <= 0.0:
		_begin_recovery(3.2)
	elif special_stack and recovery_time <= 0.0 and recovery_cooldown <= 0.0:
		_begin_recovery(2.1)
	if cycle != Cycle.RELEASE and recovery_time <= 0.0 and spawn_interval <= 0.0 and overload < 7.4:
		_try_spawn(arena)
	_request_null_pocket_if_needed(arena, overload)


func _tick_escape(arena: Node) -> void:
	cycle = Cycle.PRESSURE
	if spawn_interval > 0.0 or get_tree().get_nodes_in_group("echo_wraith").size() >= 8:
		return
	if float(arena.get("escape_timer")) <= 2.8:
		return
	if arena.call("spawn_directed_threat", "basic"):
		spawn_interval = 1.45
	else:
		spawn_interval = 0.7


func _try_spawn(arena: Node) -> void:
	var living := get_tree().get_nodes_in_group("echo_wraith").size()
	if living >= _living_limit() or threat_budget < BASIC_COST:
		return
	var kind := _choose_archetype(arena)
	var cost := BASIC_COST
	if kind == "harvester":
		cost = HARVESTER_COST
	elif kind == "sentry":
		cost = SENTRY_COST
	if threat_budget < cost:
		kind = "basic"
		cost = BASIC_COST
	if arena.call("spawn_directed_threat", kind):
		threat_budget = maxf(0.0, threat_budget - cost)
		spawn_interval = lerpf(1.7, 0.74, director_intensity)
		if cycle == Cycle.BUILD:
			spawn_interval += 0.35
		if kind != "basic":
			special_separation = 3.2
	else:
		spawn_interval = 0.55


func _choose_archetype(arena: Node) -> String:
	if phase == Phase.OPENING or special_separation > 0.0:
		return "basic"
	var harvesters := get_tree().get_nodes_in_group("echo_harvester").size()
	var sentries := get_tree().get_nodes_in_group("null_sentry").size()
	var shards := get_tree().get_nodes_in_group("echo_shard").size()
	var overload := float(arena.call("get_visual_overload"))
	var can_harvester := harvesters == 0 and harvester_cooldown <= 0.0 and shards > 0 and phase >= Phase.HUNT
	var player := get_tree().get_first_node_in_group("signal_player") as Node2D
	var center_bias := player != null and player.global_position.distance_to(Vector2(640.0, 360.0)) < 210.0
	var can_sentry := sentries == 0 and sentry_cooldown <= 0.0 and phase >= Phase.HUNT and float(arena.get("elapsed_time")) >= 30.0 and overload < 4.8 and (float(arena.get("exposure")) >= 0.42 or center_bias)
	var harvester_weight := 0.0
	var sentry_weight := 0.0
	if can_harvester:
		harvester_weight = 0.16 + minf(0.14, float(shards) * 0.045)
		if phase >= Phase.COMPRESSION:
			harvester_weight += 0.08
	if can_sentry:
		sentry_weight = 0.12 + float(arena.get("exposure")) * 0.13
		if phase >= Phase.COMPRESSION:
			sentry_weight += 0.06
	var roll := randf()
	if can_sentry and roll < sentry_weight:
		return "sentry"
	if can_harvester and roll < sentry_weight + harvester_weight:
		return "harvester"
	return "basic"


func _living_limit() -> int:
	return [4, 6, 7, 8][phase]


func _advance_cycle() -> void:
	match cycle:
		Cycle.BUILD:
			cycle = Cycle.PRESSURE
			cycle_time = lerpf(7.8, 5.0, director_intensity)
		Cycle.PRESSURE:
			cycle = Cycle.RELEASE
			cycle_time = lerpf(4.5, 2.4, director_intensity)
			_begin_recovery(minf(2.0, cycle_time))
		Cycle.RELEASE:
			cycle = Cycle.BUILD
			cycle_time = lerpf(5.4, 3.2, director_intensity)


func _begin_recovery(duration: float) -> void:
	if phase == Phase.ESCAPE or recovery_cooldown > 0.0:
		return
	var capped_duration := minf(duration, 2.0) if phase == Phase.MACHINE_PANIC else duration
	recovery_time = maxf(recovery_time, capped_duration)
	recovery_cooldown = 3.4


func _request_null_pocket_if_needed(arena: Node, overload: float) -> void:
	if phase == Phase.OPENING or cycle != Cycle.RELEASE or pocket_request_cooldown > 0.0:
		return
	if float(arena.get("exposure")) < 0.34 or overload > 5.6:
		return
	if not get_tree().get_nodes_in_group("null_pocket").is_empty():
		return
	if arena.call("request_directed_null_pocket"):
		pocket_request_cooldown = 12.0


func _update_debug(arena: Node) -> void:
	var label := arena.get_node_or_null("Interface/DirectorDebug") as Label
	if label == null:
		return
	label.visible = debug_visible
	if debug_visible:
		var state := "RECOVERY %.1f" % recovery_time if recovery_time > 0.0 else "ACTIVE"
		var player := get_tree().get_first_node_in_group("signal_player")
		var exposure := float(player.call("get_exposure")) if player else 0.0
		var band := "CRITICAL" if exposure >= 0.7 else ("RISING" if exposure >= 0.35 else "LOW")
		var saturated := bool(player.get("core_saturated")) if player else false
		var trace := float(player.get("trace_value")) if player else 0.0
		var charge_profile := String(player.call("get_charge_profile")) if player else "quick"
		var recovery := float(player.get("pulse_cooldown")) if player else 0.0
		label.text = "DIRECTOR  %s / %s\nBUDGET %.1f  INTENSITY %.2f\nENEMIES %d  %s\nEXPOSURE %d%% %s  SATURATED %s\nTRACE %.2f  CHARGE %s  RECOVERY %.2f" % [_phase_name(), _cycle_name(), threat_budget, director_intensity, get_tree().get_nodes_in_group("echo_wraith").size(), state, int(exposure * 100.0), band, "YES" if saturated else "NO", trace, charge_profile.to_upper(), recovery]


func _phase_name() -> String:
	return ["OPENING", "HUNT", "COMPRESSION", "MACHINE PANIC", "ESCAPE"][phase]


func _cycle_name() -> String:
	return ["BUILD", "PRESSURE", "RELEASE"][cycle]
