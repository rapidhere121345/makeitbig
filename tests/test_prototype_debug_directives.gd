extends RefCounted

const PrototypeDebugDirectives = preload("res://tools/prototype_debug_directives.gd")

const DEFAULT_DEBUG_SAVE_DIR: String = "user://makeitbig-prototype-debug"
const PROTECTED_SAVE_DIR: String = "user://framework-saves"
const VALID_STAGES: Array[String] = ["fresh", "base", "pre_boss", "post_boss", "graduated"]


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_no_arguments_stays_disabled(failures)
	_test_non_mib_arguments_ignored(failures)
	_test_master_switch_alone_uses_defaults(failures)
	_test_opt_in_required(failures)
	_test_unknown_flag(failures)
	_test_duplicate_single_value_flags(failures)
	_test_empty_values(failures)
	_test_invalid_seed(failures)
	_test_negative_seed(failures)
	_test_invalid_stage(failures)
	_test_every_stage(failures)
	_test_invalid_save_dir(failures)
	_test_user_and_absolute_save_dirs(failures)
	_test_protected_save_dir_rejected(failures)
	_test_force_drop_conflict(failures)
	_test_force_family_or_item_alone(failures)
	_test_wipe_and_no_persist(failures)
	_test_full_directive_set(failures)
	return failures


func _test_no_arguments_stays_disabled(failures: Array[String]) -> void:
	var dto: Dictionary = PrototypeDebugDirectives.parse(_args([]))
	_expect(bool(dto.get("ok", false)), "empty arguments were rejected: %s" % [dto], failures)
	_expect(not bool(dto.get("enabled", true)), "empty arguments enabled debug mode", failures)
	_expect(str(dto.get("save_directory", "")) == DEFAULT_DEBUG_SAVE_DIR, "disabled DTO changed the save directory", failures)
	_expect(not bool(dto.get("wipe", true)), "empty arguments requested a wipe", failures)
	_expect(not bool(dto.get("has_stage", true)), "empty arguments reported an explicit stage", failures)
	_expect(str(dto.get("stage", "")) == "fresh", "empty arguments changed the default stage", failures)
	_expect(not bool(dto.get("has_seed", true)), "empty arguments reported a seed", failures)
	_expect(int(dto.get("seed", 1)) == 0, "empty arguments reported a nonzero seed", failures)
	_expect(str(dto.get("force_family", "x")) == "", "empty arguments forced a family", failures)
	_expect(str(dto.get("force_item", "x")) == "", "empty arguments forced an item", failures)
	_expect(not bool(dto.get("no_persist", true)), "empty arguments disabled persistence", failures)


func _test_non_mib_arguments_ignored(failures: Array[String]) -> void:
	var dto: Dictionary = PrototypeDebugDirectives.parse(_args(["--verbose", "positional", "--other=x", "--mib"]))
	_expect(bool(dto.get("ok", false)), "non-mib arguments were rejected: %s" % [dto], failures)
	_expect(not bool(dto.get("enabled", true)), "non-mib arguments enabled debug mode", failures)
	var mixed: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--verbose", "--mib-wipe"]))
	_expect(bool(mixed.get("ok", false)) and bool(mixed.get("enabled", false)) and bool(mixed.get("wipe", false)), "non-mib arguments interfered with valid directives: %s" % [mixed], failures)


func _test_master_switch_alone_uses_defaults(failures: Array[String]) -> void:
	var dto: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug"]))
	_expect(bool(dto.get("ok", false)), "master switch alone was rejected: %s" % [dto], failures)
	_expect(bool(dto.get("enabled", false)), "master switch did not enable debug mode", failures)
	_expect(str(dto.get("save_directory", "")) == DEFAULT_DEBUG_SAVE_DIR, "enabled DTO did not default to the dedicated debug save dir", failures)
	_expect(not bool(dto.get("wipe", true)), "master switch alone requested a wipe", failures)
	_expect(not bool(dto.get("has_stage", true)), "master switch alone reported an explicit stage", failures)
	_expect(str(dto.get("stage", "")) == "fresh", "master switch alone changed the default stage", failures)
	_expect(not bool(dto.get("has_seed", true)), "master switch alone reported a seed", failures)
	_expect(str(dto.get("force_family", "x")) == "", "master switch alone forced a family", failures)
	_expect(str(dto.get("force_item", "x")) == "", "master switch alone forced an item", failures)
	_expect(not bool(dto.get("no_persist", true)), "master switch alone disabled persistence", failures)


func _test_opt_in_required(failures: Array[String]) -> void:
	var gated: Array[String] = [
		"--mib-wipe",
		"--mib-no-persist",
		"--mib-save-dir=user://example",
		"--mib-stage=base",
		"--mib-seed=5",
		"--mib-force-family=f",
		"--mib-force-item=i",
	]
	for directive in gated:
		var dto: Dictionary = PrototypeDebugDirectives.parse(_args([directive]))
		_expect(not bool(dto.get("ok", true)), "ungated directive was accepted: %s" % [directive], failures)
		_expect(str(dto.get("error", "")) == "debug_opt_in_required", "ungated directive returned the wrong error: %s" % [dto], failures)
	var trailing_master: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-wipe", "--mib-debug"]))
	_expect(bool(trailing_master.get("ok", false)) and bool(trailing_master.get("enabled", false)) and bool(trailing_master.get("wipe", false)), "master switch after a directive was not honored: %s" % [trailing_master], failures)


func _test_unknown_flag(failures: Array[String]) -> void:
	var dto: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-bogus"]))
	_expect(not bool(dto.get("ok", true)), "unknown flag was accepted: %s" % [dto], failures)
	_expect(str(dto.get("error", "")) == "unknown_debug_flag", "unknown flag returned the wrong error: %s" % [dto], failures)
	_expect(str(dto.get("flag", "")) == "--mib-bogus", "unknown flag error did not name the offending token: %s" % [dto], failures)
	var bare: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-bogus"]))
	_expect(str(bare.get("error", "")) == "unknown_debug_flag", "unknown flag without the master switch was misreported: %s" % [bare], failures)
	var valued_boolean: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-wipe=yes"]))
	_expect(str(valued_boolean.get("error", "")) == "unknown_debug_flag", "boolean flag with a value was misreported: %s" % [valued_boolean], failures)
	var prefix_only: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-"]))
	_expect(str(prefix_only.get("error", "")) == "unknown_debug_flag", "bare --mib- prefix was misreported: %s" % [prefix_only], failures)


func _test_duplicate_single_value_flags(failures: Array[String]) -> void:
	var duplicates: Array[Array] = [
		["--mib-debug", "--mib-save-dir=user://a", "--mib-save-dir=user://b"],
		["--mib-debug", "--mib-stage=base", "--mib-stage=post_boss"],
		["--mib-debug", "--mib-seed=1", "--mib-seed=2"],
		["--mib-debug", "--mib-force-family=f1", "--mib-force-family=f2"],
		["--mib-debug", "--mib-force-item=i1", "--mib-force-item=i2"],
	]
	for duplicate in duplicates:
		var packed := PackedStringArray()
		for argument in duplicate:
			packed.append(str(argument))
		var dto: Dictionary = PrototypeDebugDirectives.parse(packed)
		_expect(str(dto.get("error", "")) == "duplicate_debug_flag", "duplicate single-value flags were not rejected: %s" % [dto], failures)
	var repeated_booleans: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-wipe", "--mib-wipe", "--mib-debug"]))
	_expect(bool(repeated_booleans.get("ok", false)) and bool(repeated_booleans.get("wipe", false)), "repeated boolean flags should stay idempotent: %s" % [repeated_booleans], failures)


func _test_empty_values(failures: Array[String]) -> void:
	var empty_cases: Array[String] = [
		"--mib-save-dir=",
		"--mib-save-dir",
		"--mib-stage=",
		"--mib-stage",
		"--mib-seed=",
		"--mib-seed",
		"--mib-force-family=",
		"--mib-force-family",
		"--mib-force-item=",
		"--mib-force-item",
	]
	for directive in empty_cases:
		var dto: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", directive]))
		_expect(str(dto.get("error", "")) == "empty_debug_value", "empty value was not rejected: %s" % [dto], failures)


func _test_invalid_seed(failures: Array[String]) -> void:
	var invalid_seeds: Array[String] = ["abc", "1.5", "9007199254740992", "-9007199254740992", "9223372036854775808", "-", "0x10"]
	for seed_text in invalid_seeds:
		var dto: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-seed=" + seed_text]))
		_expect(str(dto.get("error", "")) == "invalid_seed", "invalid seed was accepted: %s" % [dto], failures)
	var max_seed: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-seed=9007199254740991"]))
	_expect(bool(max_seed.get("ok", false)) and str(max_seed.get("seed", "")) == "9007199254740991", "maximum JSON-safe seed was rejected: %s" % [max_seed], failures)


func _test_negative_seed(failures: Array[String]) -> void:
	var dto: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-seed=-42"]))
	_expect(bool(dto.get("ok", false)), "negative seed was rejected: %s" % [dto], failures)
	_expect(bool(dto.get("has_seed", false)), "negative seed did not set has_seed", failures)
	_expect(int(dto.get("seed", 0)) == -42, "negative seed was parsed incorrectly: %s" % [dto], failures)
	var min_seed: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-seed=-9007199254740991"]))
	_expect(bool(min_seed.get("ok", false)) and str(min_seed.get("seed", "")) == "-9007199254740991", "minimum JSON-safe seed was rejected: %s" % [min_seed], failures)


func _test_invalid_stage(failures: Array[String]) -> void:
	var dto: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-stage=boss"]))
	_expect(str(dto.get("error", "")) == "invalid_stage", "invalid stage was accepted: %s" % [dto], failures)
	_expect(str(dto.get("value", "")) == "boss", "invalid stage error lost the offending value: %s" % [dto], failures)


func _test_every_stage(failures: Array[String]) -> void:
	for stage in VALID_STAGES:
		var dto: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-stage=" + str(stage)]))
		_expect(bool(dto.get("ok", false)) and bool(dto.get("has_stage", false)) and str(dto.get("stage", "")) == str(stage), "valid stage was rejected: %s" % [dto], failures)


func _test_invalid_save_dir(failures: Array[String]) -> void:
	var invalid_dirs: Array[String] = ["res://saves", "relative/dir", "user:"]
	for save_dir in invalid_dirs:
		var dto: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-save-dir=" + save_dir]))
		_expect(str(dto.get("error", "")) == "invalid_save_dir", "invalid save dir was accepted: %s" % [dto], failures)


func _test_user_and_absolute_save_dirs(failures: Array[String]) -> void:
	var user_dir: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-save-dir=user://my-debug"]))
	_expect(bool(user_dir.get("ok", false)) and str(user_dir.get("save_directory", "")) == "user://my-debug", "user:// save dir was altered: %s" % [user_dir], failures)
	var absolute_dir: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-save-dir=/tmp/mib-debug-saves"]))
	_expect(bool(absolute_dir.get("ok", false)) and str(absolute_dir.get("save_directory", "")) == "/tmp/mib-debug-saves", "absolute save dir was altered: %s" % [absolute_dir], failures)


func _test_protected_save_dir_rejected(failures: Array[String]) -> void:
	var variants: Array[String] = [
		PROTECTED_SAVE_DIR,
		PROTECTED_SAVE_DIR + "/",
		"user://framework-saves/../framework-saves",
		ProjectSettings.globalize_path(PROTECTED_SAVE_DIR),
	]
	for save_dir in variants:
		var dto: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-save-dir=" + save_dir]))
		_expect(str(dto.get("error", "")) == "protected_save_dir", "protected save dir was accepted: %s" % [dto], failures)
	var custom_protected: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-save-dir=user://keep-out"]), "user://default-debug", "user://keep-out")
	_expect(str(custom_protected.get("error", "")) == "protected_save_dir", "custom protected save dir was accepted: %s" % [custom_protected], failures)
	var default_collision: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug"]), PROTECTED_SAVE_DIR, PROTECTED_SAVE_DIR)
	_expect(str(default_collision.get("error", "")) == "protected_save_dir", "debug default colliding with the protected dir was accepted: %s" % [default_collision], failures)


func _test_force_drop_conflict(failures: Array[String]) -> void:
	var dto: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-force-family=fam", "--mib-force-item=item"]))
	_expect(str(dto.get("error", "")) == "ambiguous_force_drop", "force-family plus force-item was accepted: %s" % [dto], failures)
	var reversed: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-force-item=item", "--mib-force-family=fam"]))
	_expect(str(reversed.get("error", "")) == "ambiguous_force_drop", "reversed force conflict was accepted: %s" % [reversed], failures)


func _test_force_family_or_item_alone(failures: Array[String]) -> void:
	var family: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-force-family=fam-1"]))
	_expect(bool(family.get("ok", false)) and str(family.get("force_family", "")) == "fam-1" and str(family.get("force_item", "")) == "", "force-family alone was mishandled: %s" % [family], failures)
	var item: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-force-item=item-9"]))
	_expect(bool(item.get("ok", false)) and str(item.get("force_item", "")) == "item-9" and str(item.get("force_family", "")) == "", "force-item alone was mishandled: %s" % [item], failures)


func _test_wipe_and_no_persist(failures: Array[String]) -> void:
	var dto: Dictionary = PrototypeDebugDirectives.parse(_args(["--mib-debug", "--mib-wipe", "--mib-no-persist"]))
	_expect(bool(dto.get("ok", false)) and bool(dto.get("wipe", false)) and bool(dto.get("no_persist", false)), "wipe/no-persist directives were mishandled: %s" % [dto], failures)


func _test_full_directive_set(failures: Array[String]) -> void:
	var dto: Dictionary = PrototypeDebugDirectives.parse(_args([
		"--mib-debug",
		"--mib-wipe",
		"--mib-stage=post_boss",
		"--mib-seed=-99",
		"--mib-force-family=family_7",
		"--mib-save-dir=user://debug-slot",
		"--mib-no-persist",
	]))
	_expect(bool(dto.get("ok", false)), "full directive set was rejected: %s" % [dto], failures)
	_expect(bool(dto.get("enabled", false)), "full directive set reported disabled", failures)
	_expect(str(dto.get("save_directory", "")) == "user://debug-slot", "full directive set lost the save directory", failures)
	_expect(bool(dto.get("wipe", false)), "full directive set lost wipe", failures)
	_expect(str(dto.get("stage", "")) == "post_boss", "full directive set lost the stage", failures)
	_expect(bool(dto.get("has_seed", false)) and int(dto.get("seed", 0)) == -99, "full directive set lost the seed", failures)
	_expect(str(dto.get("force_family", "")) == "family_7", "full directive set lost force-family", failures)
	_expect(str(dto.get("force_item", "")) == "", "full directive set invented a force-item", failures)
	_expect(bool(dto.get("no_persist", false)), "full directive set lost no-persist", failures)


func _args(items: Array[String]) -> PackedStringArray:
	return PackedStringArray(items)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
