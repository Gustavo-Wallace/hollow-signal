extends Node

const HISTORY_PATH := "user://run_history.json"
const HISTORY_LIMIT := 20

var stats: Dictionary = {}
var finalized := false
var summary_delay := -1.0
var summary_fade := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset()


func _process(delta: float) -> void:
	if summary_delay > 0.0:
		summary_delay = maxf(0.0, summary_delay - delta)
		return
	if summary_delay == 0.0:
		summary_delay = -1.0
		_show_summary()
	if summary_fade > 0.0 and summary_fade < 1.0:
		summary_fade = minf(1.0, summary_fade + delta * 3.2)
		_get_summary_label().modulate.a = summary_fade


func reset() -> void:
	stats = {"run_time": 0.0, "echoes_collected": 0, "quick_signals": 0, "resonant_signals": 0, "break_signals": 0, "damage_taken": 0, "max_exposure": 0.0, "trace_locks_triggered": 0, "null_pockets_used": 0, "enemies_destroyed": 0, "basic_enemies_destroyed": 0, "harvesters_destroyed": 0, "sentries_destroyed": 0, "shards_intercepted": 0, "shards_expired": 0, "resonance_scar_hits": 0, "sentry_hits": 0, "contact_hits": 0, "escape_started_at": -1.0, "escape_duration": 0.0, "escape_time_remaining": 0.0, "null_gate_distance_initial": 0.0, "outcome": "", "end_reason": ""}
	finalized = false
	summary_delay = -1.0
	summary_fade = 0.0
	var summary := _get_summary_label()
	if summary:
		summary.visible = false


func tick(delta: float, exposure: float) -> void:
	if finalized:
		return
	stats["run_time"] = float(stats["run_time"]) + delta
	stats["max_exposure"] = maxf(float(stats["max_exposure"]), exposure)


func record_signal(charge_ratio: float) -> void:
	if finalized:
		return
	if charge_ratio < 0.35:
		_increment("quick_signals")
	elif charge_ratio < 0.75:
		_increment("resonant_signals")
	else:
		_increment("break_signals")


func record_echoes(total: int) -> void:
	if not finalized:
		stats["echoes_collected"] = mini(8, total)


func record_damage(source_type: String, amount: int = 1) -> void:
	if finalized:
		return
	stats["damage_taken"] = int(stats["damage_taken"]) + amount
	match source_type:
		"resonance_scar": _increment("resonance_scar_hits")
		"sentry_beam": _increment("sentry_hits")
		_: _increment("contact_hits")


func record_trace_lock() -> void:
	if not finalized:
		_increment("trace_locks_triggered")


func record_null_pocket_used() -> void:
	if not finalized:
		_increment("null_pockets_used")


func record_enemy_destroyed(kind: String) -> void:
	if finalized:
		return
	_increment("enemies_destroyed")
	match kind:
		"harvester": _increment("harvesters_destroyed")
		"sentry": _increment("sentries_destroyed")
		_: _increment("basic_enemies_destroyed")


func record_shard_intercepted() -> void:
	if not finalized:
		_increment("shards_intercepted")


func record_shard_expired() -> void:
	if not finalized:
		_increment("shards_expired")


func begin_escape() -> void:
	if not finalized and float(stats["escape_started_at"]) < 0.0:
		stats["escape_started_at"] = stats["run_time"]


func set_null_gate_distance(distance: float) -> void:
	if not finalized:
		stats["null_gate_distance_initial"] = distance


func finish(outcome: String, reason: String, escape_remaining: float = 0.0) -> void:
	if finalized:
		return
	finalized = true
	stats["outcome"] = outcome
	stats["end_reason"] = reason
	stats["escape_time_remaining"] = maxf(0.0, escape_remaining)
	if float(stats["escape_started_at"]) >= 0.0:
		stats["escape_duration"] = maxf(0.0, float(stats["run_time"]) - float(stats["escape_started_at"]))
	_save_history()
	summary_delay = 0.55


func _increment(key: String) -> void:
	stats[key] = int(stats[key]) + 1


func _show_summary() -> void:
	var summary := _get_summary_label()
	if summary == null:
		return
	var lines := ["TIME                 %s" % _format_time(float(stats["run_time"])), "ECHOES               %d / 8" % int(stats["echoes_collected"]), "SIGNALS  Q / R / B   %d / %d / %d" % [int(stats["quick_signals"]), int(stats["resonant_signals"]), int(stats["break_signals"])], "DAMAGE               %d" % int(stats["damage_taken"]), "MAX EXPOSURE         %d%%" % int(round(float(stats["max_exposure"]) * 100.0)), "TRACE LOCKS          %d" % int(stats["trace_locks_triggered"]), "DESTROYED            %d" % int(stats["enemies_destroyed"])]
	if String(stats["outcome"]) == "stabilized":
		lines.append("ESCAPE REMAINING     %.1fs" % float(stats["escape_time_remaining"]))
	else:
		lines.append("CAUSE                %s" % _reason_label(String(stats["end_reason"])))
	summary.text = "\n".join(lines)
	summary.modulate.a = 0.0
	summary.visible = true
	summary_fade = 0.01
	get_parent().audio_event("summary")


func _get_summary_label() -> Label:
	return get_parent().get_node_or_null("Interface/GameOver/Summary") as Label


func _format_time(seconds: float) -> String:
	var whole := int(seconds)
	return "%02d:%04.1f" % [whole / 60, fmod(seconds, 60.0)]


func _reason_label(reason: String) -> String:
	match reason:
		"health_depleted": return "CORE COLLAPSE"
		"trace_complete": return "TRACE COMPLETE"
		"containment_complete": return "CONTAINED"
		_: return "SIGNAL LOST"


func _save_history() -> void:
	var history: Array = []
	var file := FileAccess.open(HISTORY_PATH, FileAccess.READ)
	if file:
		var json := JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Array:
			history = json.data
	var entry := stats.duplicate(true)
	entry["timestamp"] = Time.get_unix_time_from_system()
	history.append(entry)
	while history.size() > HISTORY_LIMIT:
		history.pop_front()
	var output := FileAccess.open(HISTORY_PATH, FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify(history))
