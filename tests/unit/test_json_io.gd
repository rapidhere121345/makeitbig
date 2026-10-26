extends SceneTree
## Shared JSON reader gate (src/core/json_io.gd).
##   godot --headless --path . --script res://tests/unit/test_json_io.gd

const JsonIO := preload("res://src/core/json_io.gd")
const TEMP_DIR := "user://json_io_test"

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	var object_path := _write("object.json", '{"a": 1, "b": [2, 3]}')
	var array_path := _write("array.json", "[1, 2]")
	var broken_path := _write("broken.json", '{"a": ')
	var missing_path := TEMP_DIR.path_join("missing.json")

	var parsed := JsonIO.read_object(object_path)
	_expect(int(parsed.get("a", 0)) == 1 and (parsed.get("b", []) as Array).size() == 2, "read_object parses an object")
	_expect(JsonIO.read_object(array_path).is_empty(), "read_object rejects a non-object root")
	_expect(JsonIO.read_object(broken_path).is_empty(), "read_object rejects broken JSON")
	_expect(JsonIO.read_object(missing_path).is_empty(), "read_object returns empty for a missing file")

	var ok := JsonIO.read_object_status(object_path)
	_expect(ok.status == JsonIO.STATUS_OK and ok.data.has("a"), "status reader reports ok with data")
	_expect(JsonIO.read_object_status(missing_path).status == JsonIO.STATUS_MISSING, "status reader reports missing")
	_expect(JsonIO.read_object_status(array_path).status == JsonIO.STATUS_INVALID, "status reader reports non-object as invalid")
	_expect(JsonIO.read_object_status(broken_path).status == JsonIO.STATUS_INVALID, "status reader reports broken JSON as invalid")
	_expect(JsonIO.read_object_status(broken_path).data.is_empty(), "status reader returns empty data on failure")

	var result_ok := JsonIO.read_result(object_path, "label")
	_expect(bool(result_ok.ok) and result_ok.data is Dictionary, "result reader returns ok with data")
	var result_array := JsonIO.read_result(array_path, "label")
	_expect(bool(result_array.ok) and result_array.data is Array, "result reader accepts any root when objects are not required")
	var result_strict := JsonIO.read_result(array_path, "label", true)
	_expect(not bool(result_strict.ok) and String(result_strict.error) == "label: JSON root must be an object", "result reader enforces object roots on request")
	var result_missing := JsonIO.read_result(missing_path, "label")
	_expect(String(result_missing.error) == "label: content file not found: %s" % missing_path, "result reader names the missing file")
	var result_broken := JsonIO.read_result(broken_path, "label")
	_expect(not bool(result_broken.ok) and String(result_broken.error).begins_with("label: invalid JSON at line "), "result reader reports the parse failure")

	for name in ["object.json", "array.json", "broken.json"]:
		DirAccess.remove_absolute(TEMP_DIR.path_join(name))
	DirAccess.remove_absolute(TEMP_DIR)
	for message in failures:
		printerr(message)
	print("JSON_IO ", "pass" if failures.is_empty() else "fail", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func _write(file_name: String, text: String) -> String:
	var path := TEMP_DIR.path_join(file_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append("FAIL: " + message)
