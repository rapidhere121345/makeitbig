extends SceneTree

const CombatFeedbackAudioScript := preload("res://src/presentation/combat_feedback_audio.gd")
const Assert := preload("res://tests/helpers/assert.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var audio := CombatFeedbackAudioScript.new()
	root.add_child(audio)

	var streams := [
		audio._projectile_stream(),
		audio._enemy_damage_stream(),
		audio._player_damage_stream(),
		audio._dodge_stream(),
		audio._blocked_stream(),
		audio._death_stream(),
	]
	for stream in streams:
		_expect(stream is AudioStreamWAV, "synthesis did not return a WAV stream", failures)
		_expect(stream.data.size() % 2 == 0 and stream.data.size() > 1, "PCM byte length is not a complete sample sequence", failures)
		_expect(stream.mix_rate == audio.SAMPLE_RATE and stream.stereo == false, "PCM stream metadata is invalid", failures)

		var onset_peak := 0
		for index in mini(220, stream.data.size() / 2):
			onset_peak = maxi(onset_peak, absi(stream.data.decode_s16(index * 2)))
		_expect(onset_peak > 100, "cue starts with an audible-latency block of silence", failures)
		_expect(stream.get_length() <= 0.31, "combat cue exceeds short feedback duration", failures)

	var before: Dictionary = audio.report().duplicate(true)
	audio.handle_event({"event_id": 2, "type": "action_accepted"})
	var after_non_cue: Dictionary = audio.report()
	_expect(int(after_non_cue.get("last_event_id", 0)) == 2, "non-cue authority event did not advance the cursor", failures)
	_expect(after_non_cue.get("played", {}) == before.get("played", {}) and int(after_non_cue.get("throttled", -1)) == int(before.get("throttled", -2)) and int(after_non_cue.get("polyphony_rejected", -1)) == int(before.get("polyphony_rejected", -2)), "non-cue authority event changed audio playback state", failures)
	audio.handle_event({"event_id": 1, "type": "damage_applied", "target_id": "enemy/1"})
	_expect(int(audio.report().get("last_event_id", 0)) == 2, "stale event id regressed the audio cursor", failures)
	audio.reset_audio()
	_expect(int(audio.report().get("last_event_id", -1)) == 0 and audio.report().get("played", {}).is_empty(), "audio reset retained event or playback counters", failures)

	root.remove_child(audio)
	audio.free()
	if failures.is_empty():
		print("PASS  test_combat_feedback_audio.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void: Assert.expect(condition, message, failures)
