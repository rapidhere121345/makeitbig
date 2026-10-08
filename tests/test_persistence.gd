extends RefCounted

const DeterministicRng = preload("res://src/core/deterministic_rng.gd")
const SaveStore = preload("res://src/persistence/save_store.gd")
const TEST_DIRECTORY: String = "user://makeitbig-persistence-tests"


func run() -> Array[String]:
	var failures: Array[String] = []
	_cleanup_test_directory()
	_test_fixed_vectors(failures)
	_test_stream_isolation(failures)
	_test_state_restore(failures)
	_test_canonical_encoding(failures)
	_test_corrupt_slot_fallback(failures)
	_test_exit_time_has_no_offline_progress(failures)
	_cleanup_test_directory()
	_test_load_latest_no_valid_save_slot(failures)
	_test_delete_all_removes_only_its_own_targets(failures)
	_test_delete_all_spares_unrelated_files(failures)
	_test_delete_all_is_idempotent(failures)
	_cleanup_test_directory()
	return failures


func _test_fixed_vectors(failures: Array[String]) -> void:
	var rng := DeterministicRng.create(123456789, "loot")
	var actual: Array[int] = []
	for _index in 5:
		actual.append(rng.next_u32())
	var expected: Array[int] = [19545934, 2662881743, 633311983, 731986654, 2477091011]
	_expect(actual == expected, "PRNG fixed vector changed: %s" % [actual], failures)


func _test_stream_isolation(failures: Array[String]) -> void:
	var loot_a := DeterministicRng.create(77, "loot")
	var combat := DeterministicRng.create(77, "combat")
	var loot_b := DeterministicRng.create(77, "loot")
	var loot_expected: Array[int] = []
	var loot_interleaved: Array[int] = []
	for _index in 6:
		loot_expected.append(loot_a.next_u32())
	for _index in 6:
		combat.next_u32()
		loot_interleaved.append(loot_b.next_u32())
	_expect(loot_interleaved == loot_expected, "advancing another named stream changed loot", failures)
	_expect(combat.export_state() != loot_b.export_state(), "different stream names derived the same observed state", failures)


func _test_state_restore(failures: Array[String]) -> void:
	var original := DeterministicRng.create(-42, "forge/affix")
	for _index in 4:
		original.next_u32()
	var snapshot: Dictionary = original.export_state()
	var expected: Array[int] = []
	for _index in 8:
		expected.append(original.next_u32())
	var restored := DeterministicRng.new()
	_expect(restored.restore_state(snapshot), "valid PRNG state was rejected", failures)
	var actual: Array[int] = []
	for _index in 8:
		actual.append(restored.next_u32())
	_expect(actual == expected, "restored PRNG did not continue at the exact position", failures)
	var wrong_version: Dictionary = snapshot.duplicate(true)
	wrong_version.version = 999
	_expect(not restored.restore_state(wrong_version), "unknown PRNG state version was accepted", failures)


func _test_canonical_encoding(failures: Array[String]) -> void:
	var first := {"z": [3, true], "a": {"y": 2.0, "x": "line\n"}}
	var second := {"a": {"x": "line\n", "y": 2}, "z": [3.0, true]}
	var expected := "{\"a\":{\"x\":\"line\\n\",\"y\":2},\"z\":[3,true]}"
	_expect(SaveStore.canonical_json(first) == expected, "canonical JSON ordering/escaping changed", failures)
	_expect(SaveStore.canonical_json(first) == SaveStore.canonical_json(second), "equivalent JSON values encoded differently", failures)


func _test_corrupt_slot_fallback(failures: Array[String]) -> void:
	var store := SaveStore.new(TEST_DIRECTORY)
	var first_save: Dictionary = store.save({"progress": 10, "label": "older"})
	var second_save: Dictionary = store.save({"progress": 20, "label": "newer"})
	_expect(bool(first_save.get("ok", false)) and bool(second_save.get("ok", false)), "A/B saves failed", failures)
	if not bool(second_save.get("ok", false)):
		return
	var newest_path: String = ProjectSettings.globalize_path(TEST_DIRECTORY).path_join("save_%s.json" % second_save.slot)
	var original_contents: String = FileAccess.get_file_as_string(newest_path)
	var tampered_contents: String = original_contents.replace("\"progress\":20", "\"progress\":999")
	_expect(tampered_contents != original_contents, "could not prepare checksum tampering test", failures)
	var file := FileAccess.open(newest_path, FileAccess.WRITE)
	_expect(file != null, "could not open newest slot for corruption test", failures)
	if file == null:
		return
	file.store_string(tampered_contents)
	file.close()
	var loaded: Dictionary = store.load_latest()
	_expect(bool(loaded.get("ok", false)), "one corrupt slot prevented fallback", failures)
	if bool(loaded.get("ok", false)):
		_expect(int(loaded.payload.progress) == 10, "fallback did not choose the older valid slot", failures)
		_expect(int(loaded.generation) == int(first_save.generation), "fallback returned the wrong generation", failures)


func _test_exit_time_has_no_offline_progress(failures: Array[String]) -> void:
	var store := SaveStore.new(TEST_DIRECTORY)
	var payload := {"progress": 37, "exit_time": 1, "offline_progress": 0}
	var saved: Dictionary = store.save(payload)
	_expect(bool(saved.get("ok", false)), "save with exit_time field failed", failures)
	var loaded: Dictionary = store.load_latest()
	_expect(bool(loaded.get("ok", false)), "save with exit_time field could not be loaded", failures)
	if bool(loaded.get("ok", false)):
		_expect(int(loaded.payload.progress) == 37, "exit_time changed stored progress", failures)
		_expect(int(loaded.payload.offline_progress) == 0, "persistence computed offline progress", failures)
		_expect(int(loaded.payload.exit_time) == 1, "exit_time was interpreted instead of preserved", failures)


func _test_load_latest_no_valid_save_slot(failures: Array[String]) -> void:
	var store := SaveStore.new(TEST_DIRECTORY)
	var loaded: Dictionary = store.load_latest()
	_expect(not bool(loaded.get("ok", false)), "load_latest accepted an empty directory", failures)
	_expect(str(loaded.get("error", "")) == "no valid save slot", "load_latest returned the wrong error for an empty directory: %s" % [loaded], failures)


func _test_delete_all_removes_only_its_own_targets(failures: Array[String]) -> void:
	var store := SaveStore.new(TEST_DIRECTORY)
	_expect(bool(store.save({"progress": 1}).get("ok", false)), "could not prepare first save for delete_all", failures)
	_expect(bool(store.save({"progress": 2}).get("ok", false)), "could not prepare second save for delete_all", failures)
	var absolute_directory: String = ProjectSettings.globalize_path(TEST_DIRECTORY)
	for temporary_name in ["save_a.json.tmp", "save_b.json.tmp"]:
		_expect(_write_test_file(absolute_directory.path_join(temporary_name), "partial"), "could not prepare %s for delete_all" % temporary_name, failures)
	var result: Dictionary = store.delete_all()
	_expect(bool(result.get("ok", false)), "delete_all failed: %s" % [result], failures)
	var removed: Array = result.get("removed", [])
	removed.sort()
	var expected: Array[String] = ["save_a.json", "save_a.json.tmp", "save_b.json", "save_b.json.tmp"]
	_expect(removed == expected, "delete_all removed the wrong files: %s" % [removed], failures)
	var loaded: Dictionary = store.load_latest()
	_expect(not bool(loaded.get("ok", false)), "delete_all left a loadable save slot", failures)


func _test_delete_all_spares_unrelated_files(failures: Array[String]) -> void:
	var store := SaveStore.new(TEST_DIRECTORY)
	var absolute_directory: String = ProjectSettings.globalize_path(TEST_DIRECTORY)
	_expect(DirAccess.make_dir_recursive_absolute(absolute_directory) == OK, "could not create test directory", failures)
	_expect(_write_test_file(absolute_directory.path_join("save_a.json"), "slot"), "could not prepare save_a.json", failures)
	_expect(_write_test_file(absolute_directory.path_join("save_c.json"), "foreign slot"), "could not prepare save_c.json", failures)
	_expect(_write_test_file(absolute_directory.path_join("notes.txt"), "keep me"), "could not prepare notes.txt", failures)
	var nested_directory: String = absolute_directory.path_join("nested")
	_expect(DirAccess.make_dir_recursive_absolute(nested_directory) == OK, "could not create nested directory", failures)
	_expect(_write_test_file(nested_directory.path_join("save_a.json"), "nested slot"), "could not prepare nested save_a.json", failures)
	var result: Dictionary = store.delete_all()
	_expect(bool(result.get("ok", false)), "delete_all failed: %s" % [result], failures)
	_expect(result.get("removed", []) == ["save_a.json"], "delete_all removed unexpected files: %s" % [result], failures)
	_expect(FileAccess.file_exists(absolute_directory.path_join("save_c.json")), "delete_all removed an unrelated slot file", failures)
	_expect(FileAccess.file_exists(absolute_directory.path_join("notes.txt")), "delete_all removed an unrelated file", failures)
	_expect(FileAccess.file_exists(nested_directory.path_join("save_a.json")), "delete_all recursed into subdirectories", failures)
	_expect(DirAccess.dir_exists_absolute(nested_directory), "delete_all removed the directory itself", failures)
	for path in [nested_directory.path_join("save_a.json"), absolute_directory.path_join("save_c.json"), absolute_directory.path_join("notes.txt")]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(nested_directory):
		DirAccess.remove_absolute(nested_directory)


func _test_delete_all_is_idempotent(failures: Array[String]) -> void:
	var store := SaveStore.new(TEST_DIRECTORY)
	var first: Dictionary = store.delete_all()
	_expect(bool(first.get("ok", false)), "delete_all on an empty directory failed: %s" % [first], failures)
	_expect(first.get("removed", []) == [], "delete_all on an empty directory reported removals: %s" % [first], failures)
	var second: Dictionary = store.delete_all()
	_expect(bool(second.get("ok", false)), "repeated delete_all failed: %s" % [second], failures)
	_expect(second.get("removed", []) == [], "repeated delete_all was not idempotent: %s" % [second], failures)


func _write_test_file(path: String, contents: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(contents)
	file.close()
	return true


func _cleanup_test_directory() -> void:
	var absolute_directory: String = ProjectSettings.globalize_path(TEST_DIRECTORY)
	for file_name in ["save_a.json", "save_b.json", "save_a.json.tmp", "save_b.json.tmp"]:
		var path: String = absolute_directory.path_join(file_name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(absolute_directory):
		DirAccess.remove_absolute(absolute_directory)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
