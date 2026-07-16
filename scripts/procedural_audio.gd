extends Node

const SAMPLE_RATE := 22050
const SILENT_DB := -56.0

var streams: Dictionary = {}
var sound_pool: Array[AudioStreamPlayer] = []
var pool_index := 0
var event_times: Dictionary = {}
var ambience: AudioStreamPlayer
var charge_voice: AudioStreamPlayer
var trace_voice: AudioStreamPlayer
var harvester_voice: AudioStreamPlayer
var sentry_voice: AudioStreamPlayer
var gate_voice: AudioStreamPlayer
var run_finished := false
var trace_was_active := false
var escape_was_active := false
var escape_pulse_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_streams()
	ambience = _make_voice()
	charge_voice = _make_voice()
	trace_voice = _make_voice()
	harvester_voice = _make_voice()
	sentry_voice = _make_voice()
	gate_voice = _make_voice()
	for index in 8:
		sound_pool.append(_make_voice())
	_start_loop(ambience, "ambience", -31.5, 1.0)


func _process(delta: float) -> void:
	var arena := get_parent()
	if arena == null:
		return
	var playing := arena.has_method("is_playing") and bool(arena.call("is_playing"))
	if not playing:
		_stop_live_layers(delta)
		return
	var player := get_tree().get_first_node_in_group("signal_player")
	var exposure := 0.0
	if player and player.has_method("get_exposure"):
		exposure = float(player.call("get_exposure"))
	var escape_active := arena.has_method("is_escape") and bool(arena.call("is_escape"))
	var ambience_target := -31.5 + exposure * 5.0 + (2.0 if escape_active else 0.0)
	_set_loop(ambience, "ambience", true, ambience_target, 0.96 + exposure * 0.1 + (0.035 if escape_active else 0.0), delta)
	_update_charge(player, delta)
	_update_trace(arena, exposure, delta)
	_update_enemy_layers(delta)
	_update_gate_layer(delta)
	_update_escape_pulse(arena, escape_active, delta)
	if escape_active and not escape_was_active:
		trigger("escape")
	escape_was_active = escape_active


func trigger(kind: String, value: float = 0.0) -> void:
	if run_finished and kind not in ["restart"]:
		return
	match kind:
		"signal":
			if value < 0.35:
				_play("signal_quick", lerpf(0.94, 1.12, value), -8.0)
			elif value < 0.75:
				_play("signal_resonant", lerpf(0.92, 1.08, value), -6.5)
			else:
				_play("signal_break", lerpf(0.88, 1.04, value), -4.5)
		"damage": _play("damage", 0.94 + randf() * 0.1, -5.0)
		"death":
			run_finished = true
			_play("death", 1.0, -3.5)
		"trace_fail":
			run_finished = true
			_play("trace_fail", 1.0, -4.0)
		"victory":
			run_finished = true
			_play("victory", 1.0, -5.0)
		"wraith_wake": _play_limited("wraith_wake", 0.18, 0.94 + randf() * 0.12, -16.0)
		"wraith_dash": _play_limited("wraith_dash", 0.18, 0.92 + randf() * 0.1, -11.0)
		"wraith_death": _play_limited("wraith_death", 0.08, 0.9 + randf() * 0.14, -10.0)
		"shard_spawn": _play_limited("shard_spawn", 0.12, 0.96 + randf() * 0.1, -19.0)
		"shard_collect":
			_play_limited("shard_collect", 0.06, 0.9 + minf(value, 8.0) * 0.025, -10.5 if value < 8.0 else -6.0)
		"harvester_absorb": _play("harvester_absorb", 0.95 + randf() * 0.08, -11.0)
		"harvester_charged": _play("harvester_charged", 1.0, -8.0)
		"harvester_death": _play("harvester_death", 0.94 + randf() * 0.1, -9.0)
		"sentry_lock": _play_limited("sentry_lock", 0.32, 1.0, -13.0)
		"sentry_fire": _play("sentry_fire", 0.98 + randf() * 0.06, -7.0)
		"sentry_interrupt": _play("sentry_interrupt", 1.0, -10.0)
		"sentry_death": _play("sentry_death", 1.0, -9.0)
		"scar_imprint": _play_limited("scar_imprint", 0.2, 0.94 + randf() * 0.1, -15.0)
		"scar_converge": _play_limited("scar_converge", 0.24, 1.0, -17.0)
		"scar_collapse": _play_limited("scar_collapse", 0.12, 0.96 + randf() * 0.08, -9.0)
		"trace_start": _play("trace_start", 1.0, -9.0)
		"trace_clear": _play("trace_clear", 1.0, -13.0)
		"escape": _play("escape", 1.0, -6.5)
		"gate_open": _play("gate_open", 1.0, -7.0)
		"gate_enter": _play("gate_enter", 1.0, -5.5)
		"restart": run_finished = false


func _build_streams() -> void:
	streams["ambience"] = _make_loop([43.0, 49.0, 86.0], [0.22, 0.15, 0.045])
	streams["charge"] = _make_loop([126.0, 189.0], [0.16, 0.06])
	streams["trace"] = _make_loop([92.0, 184.0], [0.11, 0.035])
	streams["harvester"] = _make_loop([156.0, 234.0], [0.12, 0.045])
	streams["sentry"] = _make_loop([188.0, 282.0], [0.1, 0.04])
	streams["gate"] = _make_loop([57.0, 114.0, 228.0], [0.14, 0.055, 0.018])
	streams["signal_quick"] = _make_tone(0.22, 640.0, 1.9, 0.0, true)
	streams["signal_resonant"] = _make_tone(0.44, 166.0, 2.04, 0.04, false)
	streams["signal_break"] = _make_tone(0.62, 76.0, 4.2, 0.12, false)
	streams["damage"] = _make_tone(0.25, 72.0, 1.4, 0.2, true)
	streams["death"] = _make_tone(0.8, 168.0, 0.48, 0.14, true)
	streams["trace_fail"] = _make_tone(0.76, 212.0, 0.4, 0.18, true)
	streams["victory"] = _make_tone(0.72, 118.0, 1.48, 0.02, false)
	streams["wraith_wake"] = _make_tone(0.16, 285.0, 0.72, 0.08, true)
	streams["wraith_dash"] = _make_tone(0.19, 190.0, 2.1, 0.05, false)
	streams["wraith_death"] = _make_tone(0.28, 246.0, 0.53, 0.16, true)
	streams["shard_spawn"] = _make_tone(0.18, 520.0, 1.48, 0.0, false)
	streams["shard_collect"] = _make_tone(0.26, 390.0, 1.62, 0.0, false)
	streams["harvester_absorb"] = _make_tone(0.2, 130.0, 1.25, 0.08, true)
	streams["harvester_charged"] = _make_tone(0.32, 108.0, 2.0, 0.06, false)
	streams["harvester_death"] = _make_tone(0.4, 154.0, 0.5, 0.18, true)
	streams["sentry_lock"] = _make_tone(0.15, 334.0, 1.32, 0.0, false)
	streams["sentry_fire"] = _make_tone(0.24, 312.0, 0.72, 0.12, true)
	streams["sentry_interrupt"] = _make_tone(0.22, 270.0, 0.44, 0.1, true)
	streams["sentry_death"] = _make_tone(0.36, 210.0, 0.48, 0.16, true)
	streams["scar_imprint"] = _make_tone(0.32, 104.0, 0.72, 0.04, true)
	streams["scar_converge"] = _make_tone(0.24, 138.0, 1.22, 0.03, false)
	streams["scar_collapse"] = _make_tone(0.3, 82.0, 1.92, 0.12, true)
	streams["trace_start"] = _make_tone(0.34, 236.0, 1.42, 0.04, false)
	streams["trace_clear"] = _make_tone(0.3, 248.0, 0.48, 0.02, true)
	streams["escape"] = _make_tone(0.64, 96.0, 2.0, 0.08, false)
	streams["escape_tick"] = _make_tone(0.16, 86.0, 1.55, 0.02, false)
	streams["gate_open"] = _make_tone(0.58, 64.0, 3.8, 0.05, false)
	streams["gate_enter"] = _make_tone(0.5, 118.0, 2.35, 0.04, false)


func _make_tone(duration: float, frequency: float, overtone_ratio: float, noise_amount: float, descends: bool) -> AudioStreamWAV:
	var sample_count := maxi(1, int(duration * SAMPLE_RATE))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase := 0.0
	for index in sample_count:
		var time := float(index) / float(SAMPLE_RATE)
		var progress := float(index) / float(sample_count - 1)
		var envelope := minf(1.0, time / 0.018) * minf(1.0, (duration - time) / 0.065)
		var pitch_factor := lerpf(1.0, 0.48 if descends else 1.42, progress)
		phase += TAU * frequency * pitch_factor / float(SAMPLE_RATE)
		var tone := sin(phase) * 0.7 + sin(phase * overtone_ratio + 0.3) * 0.22
		var grain := sin(float(index) * 0.734) * sin(float(index) * 0.173) * noise_amount
		var value := clampf((tone + grain) * envelope * (0.43 + noise_amount * 0.1), -0.88, 0.88)
		data.encode_s16(index * 2, int(value * 32767.0))
	return _make_wav(data, false)


func _make_loop(frequencies: Array[float], amplitudes: Array[float]) -> AudioStreamWAV:
	var sample_count := SAMPLE_RATE * 4
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for index in sample_count:
		var time := float(index) / float(SAMPLE_RATE)
		var value := 0.0
		for tone_index in frequencies.size():
			value += sin(TAU * frequencies[tone_index] * time) * amplitudes[tone_index]
		var machine_motion := 0.82 + sin(TAU * 0.25 * time) * 0.12
		value = clampf(value * machine_motion, -0.72, 0.72)
		data.encode_s16(index * 2, int(value * 32767.0))
	return _make_wav(data, true)


func _make_wav(data: PackedByteArray, looping: bool) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	if looping:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = data.size() / 2
	return wav


func _make_voice() -> AudioStreamPlayer:
	var voice := AudioStreamPlayer.new()
	voice.volume_db = SILENT_DB
	add_child(voice)
	return voice


func _play(sound_name: String, pitch: float = 1.0, volume: float = -12.0) -> void:
	var voice := sound_pool[pool_index]
	pool_index = (pool_index + 1) % sound_pool.size()
	voice.stop()
	voice.stream = streams[sound_name]
	voice.pitch_scale = pitch
	voice.volume_db = volume
	voice.play()


func _play_limited(sound_name: String, interval: float, pitch: float = 1.0, volume: float = -12.0) -> void:
	var now := Time.get_ticks_msec() * 0.001
	var last_time: float = float(event_times.get(sound_name, -100.0))
	if now - last_time < interval:
		return
	event_times[sound_name] = now
	_play(sound_name, pitch, volume)


func _start_loop(voice: AudioStreamPlayer, stream_name: String, volume: float, pitch: float) -> void:
	voice.stream = streams[stream_name]
	voice.pitch_scale = pitch
	voice.volume_db = volume
	voice.play()


func _set_loop(voice: AudioStreamPlayer, stream_name: String, active: bool, target_volume: float, target_pitch: float, delta: float) -> void:
	if active and not voice.playing:
		_start_loop(voice, stream_name, SILENT_DB, target_pitch)
	var goal := target_volume if active else SILENT_DB
	voice.volume_db = lerpf(voice.volume_db, goal, minf(1.0, delta * 9.0))
	voice.pitch_scale = lerpf(voice.pitch_scale, target_pitch, minf(1.0, delta * 7.0))
	if not active and voice.playing and voice.volume_db <= SILENT_DB + 0.3:
		voice.stop()


func _update_charge(player: Node, delta: float) -> void:
	var active := player != null and bool(player.get("is_charging"))
	var ratio := float(player.get("charge_ratio")) if player else 0.0
	_set_loop(charge_voice, "charge", active, -27.0 + ratio * 8.0, 0.72 + ratio * 1.15, delta)


func _update_trace(arena: Node, exposure: float, delta: float) -> void:
	var active := bool(arena.get("trace_lock"))
	_set_loop(trace_voice, "trace", active, -32.0 + exposure * 4.0, 0.72 + exposure * 0.34, delta)
	if active and not trace_was_active:
		trigger("trace_start")
	elif not active and trace_was_active:
		trigger("trace_clear")
	trace_was_active = active


func _update_enemy_layers(delta: float) -> void:
	var harvester_active := false
	for harvester in get_tree().get_nodes_in_group("echo_harvester"):
		if bool(harvester.get("channeling")):
			harvester_active = true
			break
	_set_loop(harvester_voice, "harvester", harvester_active, -32.0, 0.92, delta)
	var sentry_active := false
	for sentry in get_tree().get_nodes_in_group("null_sentry"):
		if int(sentry.get("attack_state")) == 1:
			sentry_active = true
			break
	_set_loop(sentry_voice, "sentry", sentry_active, -31.0, 0.92, delta)


func _update_gate_layer(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("signal_player") as Node2D
	var gate := get_tree().get_first_node_in_group("null_gate") as Node2D
	var active := player != null and gate != null
	var near := 0.0
	if active:
		near = 1.0 - clampf(player.global_position.distance_to(gate.global_position) / 680.0, 0.0, 1.0)
	_set_loop(gate_voice, "gate", active, -42.0 + near * 14.0, 0.92 + near * 0.15, delta)


func _update_escape_pulse(arena: Node, active: bool, delta: float) -> void:
	if not active:
		escape_pulse_timer = 0.0
		return
	escape_pulse_timer -= delta
	if escape_pulse_timer > 0.0:
		return
	var escape_time := float(arena.get("escape_timer"))
	var pressure := 1.0 - clampf(escape_time / 14.0, 0.0, 1.0)
	_play("escape_tick", 0.76 + pressure * 0.38, -25.0 + pressure * 7.0)
	escape_pulse_timer = lerpf(1.15, 0.32, pressure)


func _stop_live_layers(delta: float) -> void:
	_set_loop(ambience, "ambience", false, SILENT_DB, 1.0, delta)
	_set_loop(charge_voice, "charge", false, SILENT_DB, 1.0, delta)
	_set_loop(trace_voice, "trace", false, SILENT_DB, 1.0, delta)
	_set_loop(harvester_voice, "harvester", false, SILENT_DB, 1.0, delta)
	_set_loop(sentry_voice, "sentry", false, SILENT_DB, 1.0, delta)
	_set_loop(gate_voice, "gate", false, SILENT_DB, 1.0, delta)
