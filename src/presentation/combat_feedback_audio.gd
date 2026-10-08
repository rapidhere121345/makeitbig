class_name CombatFeedbackAudio
extends Node

## Event-bound, locally synthesized combat cues. The arena feeds this node only
## after CombatEventStream has resolved an event; windup and generic impact
## boundaries are deliberately not cues. Playback is bounded by a small player
## pool plus a per-cue presentation-time throttle.

const SAMPLE_RATE := 22050
const PLAYER_COUNT := 6
const CUE_THROTTLE_MILLISECONDS := 45
const DEFAULT_VOLUME := 0.45

const CUE_PROJECTILE := "projectile"
const CUE_ENEMY_DAMAGE := "enemy_damage"
const CUE_PLAYER_DAMAGE := "player_damage"
const CUE_DODGE := "dodge"
const CUE_BLOCKED := "blocked"
const CUE_DEATH := "death"

var _volume: float = DEFAULT_VOLUME
var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _last_cue_milliseconds: Dictionary = {}
var _last_event_id: int = 0
var _counts: Dictionary = {}
var _throttled: int = 0
var _polyphony_rejected: int = 0
var _playback_enabled := true

func _ready() -> void:
	_playback_enabled = not DisplayServer.get_name().to_lower().begins_with("headless")
	if not _playback_enabled:
		return
	_streams = {
		CUE_PROJECTILE: _projectile_stream(),
		CUE_ENEMY_DAMAGE: _enemy_damage_stream(),
		CUE_PLAYER_DAMAGE: _player_damage_stream(),
		CUE_DODGE: _dodge_stream(),
		CUE_BLOCKED: _blocked_stream(),
		CUE_DEATH: _death_stream(),
	}
	for _index in PLAYER_COUNT:
		var player := AudioStreamPlayer.new()
		player.volume_db = linear_to_db(_volume)
		add_child(player)
		_players.append(player)


func set_volume(value: float) -> void:
	_volume = clampf(value, 0.0, 1.0)
	var decibels := linear_to_db(_volume)
	for player in _players:
		player.volume_db = decibels


func get_volume() -> float:
	return _volume


func handle_event(event: Dictionary) -> void:
	var event_id := int(event.get("event_id", 0))
	if event_id <= 0 or event_id <= _last_event_id:
		return
	_last_event_id = event_id
	if not _playback_enabled:
		return
	var cue := _cue_for_event(event)
	if cue.is_empty():
		return
	var now := Time.get_ticks_msec()
	var last := int(_last_cue_milliseconds.get(cue, -CUE_THROTTLE_MILLISECONDS))
	if now - last < CUE_THROTTLE_MILLISECONDS:
		_throttled += 1
		return
	var player := _available_player()
	if player == null:
		_polyphony_rejected += 1
		return
	player.stream = _streams.get(cue)
	player.play()
	_last_cue_milliseconds[cue] = now
	_counts[cue] = int(_counts.get(cue, 0)) + 1


func reset_audio() -> void:
	for player in _players:
		player.stop()
		player.stream = null
	_last_cue_milliseconds.clear()
	_counts.clear()
	_last_event_id = 0
	_throttled = 0
	_polyphony_rejected = 0


func report() -> Dictionary:
	return {
		"volume": _volume,
		"playback_enabled": _playback_enabled,
		"player_count": _players.size(),
		"maximum_polyphony": PLAYER_COUNT,
		"cue_throttle_ms": CUE_THROTTLE_MILLISECONDS,
		"played": _counts.duplicate(true),
		"throttled": _throttled,
		"polyphony_rejected": _polyphony_rejected,
		"last_event_id": _last_event_id,
	}


func _exit_tree() -> void:
	reset_audio()


func _available_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	return null


func _cue_for_event(event: Dictionary) -> String:
	match String(event.get("type", "")):
		"projectile_spawned":
			return CUE_PROJECTILE
		"damage_applied":
			return CUE_PLAYER_DAMAGE if String(event.get("target_id", "")) == "ranger" else CUE_ENEMY_DAMAGE
		"attack_resolved":
			var outcome := String(event.get("outcome", ""))
			if outcome == "avoided" and String(event.get("target_id", "")) == "ranger":
				return CUE_DODGE
			if outcome == "blocked":
				return CUE_BLOCKED
		"death_applied":
			return CUE_DEATH
	return ""


func _projectile_stream() -> AudioStreamWAV:
	var samples := PackedByteArray()
	for index in range(1470):
		var time := float(index) / float(SAMPLE_RATE)
		var frequency := 740.0 - 260.0 * time / 0.065
		samples.append_array(_sample_bytes(sin(TAU * frequency * time) * exp(-time * 34.0) * 0.52))
	return _stream(samples)


func _enemy_damage_stream() -> AudioStreamWAV:
	var samples := PackedByteArray()
	for index in range(1850):
		var time := float(index) / float(SAMPLE_RATE)
		var value := (sin(TAU * 172.0 * time) * 0.48 + sin(TAU * 940.0 * time) * 0.16) * exp(-time * 43.0)
		samples.append_array(_sample_bytes(value))
	return _stream(samples)


func _player_damage_stream() -> AudioStreamWAV:
	var samples := PackedByteArray()
	for index in range(2646):
		var time := float(index) / float(SAMPLE_RATE)
		var value := (sin(TAU * 118.0 * time) * 0.56 + sin(TAU * 331.0 * time) * 0.18) * exp(-time * 29.0)
		samples.append_array(_sample_bytes(value))
	return _stream(samples)


func _dodge_stream() -> AudioStreamWAV:
	var samples := PackedByteArray()
	for index in range(2204):
		var time := float(index) / float(SAMPLE_RATE)
		var noise := sin(float(index) * 12.9898) * 43758.5453
		noise = (noise - floor(noise)) * 2.0 - 1.0
		var band := sin(TAU * (430.0 + 900.0 * time) * time)
		var value := (noise * 0.24 + band * 0.24) * sin(PI * minf(1.0, time / 0.08)) * exp(-time * 19.0)
		samples.append_array(_sample_bytes(value))
	return _stream(samples)


func _blocked_stream() -> AudioStreamWAV:
	var samples := PackedByteArray()
	for index in range(1984):
		var time := float(index) / float(SAMPLE_RATE)
		var value := (signf(sin(TAU * 243.0 * time)) * 0.18 + sin(TAU * 727.0 * time) * 0.25) * exp(-time * 39.0)
		samples.append_array(_sample_bytes(value))
	return _stream(samples)


func _death_stream() -> AudioStreamWAV:
	var samples := PackedByteArray()
	for index in range(6616):
		var time := float(index) / float(SAMPLE_RATE)
		var frequency := 430.0 - 250.0 * minf(1.0, time / 0.24)
		var value := (sin(TAU * frequency * time) * 0.42 + sin(TAU * frequency * 1.5 * time) * 0.14) * exp(-time * 11.0)
		samples.append_array(_sample_bytes(value))
	return _stream(samples)


func _sample_bytes(value: float) -> PackedByteArray:
	var quantized := clampi(roundi(clampf(value, -1.0, 1.0) * 32767.0), -32768, 32767)
	var bytes := PackedByteArray()
	bytes.append(quantized & 0xff)
	bytes.append((quantized >> 8) & 0xff)
	return bytes


func _stream(samples: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = samples
	return stream
