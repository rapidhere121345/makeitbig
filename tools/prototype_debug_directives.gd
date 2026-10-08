extends RefCounted

## Strictly bounded parser for Make It Big prototype debug directives.
##
## GameRoot is expected to load this script dynamically with
## load("res://tools/prototype_debug_directives.gd"), so this script intentionally
## declares no class_name: it must never enter the global class cache or become
## an export-time dependency.
##
## Directives (all gated behind --mib-debug):
##   --mib-debug                        master switch
##   --mib-save-dir=<user://|absolute>  debug save directory override
##   --mib-wipe                         wipe the DTO's own save directory
##   --mib-stage=<fresh|base|pre_boss|post_boss|graduated>
##   --mib-seed=<signed JSON-safe int>  deterministic seed override
##   --mib-force-family=<nonempty id>
##   --mib-force-item=<nonempty id>
##   --mib-no-persist                   disable persistence entirely
##
## Stable error codes:
##   debug_opt_in_required   a known non-master --mib-* flag without --mib-debug
##   unknown_debug_flag      an unrecognized --mib-* token
##   duplicate_debug_flag    the same single-value flag given more than once
##   empty_debug_value       a single-value flag with no value
##   invalid_seed            a seed that is not an exact JSON-safe integer
##   invalid_stage           a stage outside the fixed stage ladder
##   invalid_save_dir        a save dir that is neither user:// nor absolute
##   ambiguous_force_drop    both force-family and force-item given
##   protected_save_dir      effective save dir equals the protected dir
##
## Deterministic precedence:
##   1. unknown --mib-* tokens are rejected first;
##   2. then the opt-in gate (any non-master --mib-* without --mib-debug);
##   3. then per-flag checks in argument order (duplicate, empty, value);
##   4. then cross-field checks (ambiguous_force_drop, protected_save_dir).
##
## The success DTO always carries ok/enabled/save_directory/wipe/has_stage/stage/
## has_seed/seed/force_family/force_item/no_persist. Every field other than
## ok/enabled is
## inert when enabled is false, so consumers must check enabled before acting.
## Wipe semantics are defined to touch only the DTO's own save_directory, which
## is also guaranteed to differ from the protected directory after
## normalization.

const MIB_PREFIX: String = "--mib-"
const FLAG_DEBUG: String = "--mib-debug"
const FLAG_SAVE_DIR: String = "--mib-save-dir"
const FLAG_WIPE: String = "--mib-wipe"
const FLAG_STAGE: String = "--mib-stage"
const FLAG_SEED: String = "--mib-seed"
const FLAG_FORCE_FAMILY: String = "--mib-force-family"
const FLAG_FORCE_ITEM: String = "--mib-force-item"
const FLAG_NO_PERSIST: String = "--mib-no-persist"

const BOOLEAN_FLAGS: Array[String] = [FLAG_DEBUG, FLAG_WIPE, FLAG_NO_PERSIST]
const VALUE_FLAGS: Array[String] = [FLAG_SAVE_DIR, FLAG_STAGE, FLAG_SEED, FLAG_FORCE_FAMILY, FLAG_FORCE_ITEM]
const VALID_STAGES: Array[String] = ["fresh", "base", "pre_boss", "post_boss", "graduated"]
const DEFAULT_STAGE: String = "fresh"
const MAX_SAFE_JSON_INTEGER: int = 9007199254740991


static func parse(
	arguments: PackedStringArray,
	default_debug_save_dir: String = "user://makeitbig-prototype-debug",
	protected_save_dir: String = "user://framework-saves"
) -> Dictionary:
	var mib_tokens: Array[String] = []
	for argument in arguments:
		if argument.begins_with(MIB_PREFIX):
			mib_tokens.append(argument)

	for token in mib_tokens:
		if not _is_known_flag(token):
			return _failure("unknown_debug_flag", {"flag": token})

	var has_master: bool = mib_tokens.has(FLAG_DEBUG)
	var has_other_flag: bool = false
	for token in mib_tokens:
		if token != FLAG_DEBUG:
			has_other_flag = true
			break
	if has_other_flag and not has_master:
		return _failure("debug_opt_in_required", {"flags": mib_tokens})

	var save_dir_seen: bool = false
	var stage_seen: bool = false
	var seed_seen: bool = false
	var force_family_seen: bool = false
	var force_item_seen: bool = false
	var save_dir_value: String = ""
	var stage_value: String = ""
	var seed_value: int = 0
	var force_family_value: String = ""
	var force_item_value: String = ""
	var wipe: bool = false
	var no_persist: bool = false

	for token in mib_tokens:
		if token == FLAG_DEBUG:
			continue
		if token == FLAG_WIPE:
			wipe = true
			continue
		if token == FLAG_NO_PERSIST:
			no_persist = true
			continue
		if _matches_flag(token, FLAG_SAVE_DIR) != -1:
			if save_dir_seen:
				return _failure("duplicate_debug_flag", {"flag": FLAG_SAVE_DIR})
			save_dir_seen = true
			var candidate_dir: String = _flag_value(token, FLAG_SAVE_DIR)
			if candidate_dir.is_empty():
				return _failure("empty_debug_value", {"flag": FLAG_SAVE_DIR})
			if not _is_valid_save_dir(candidate_dir):
				return _failure("invalid_save_dir", {"flag": FLAG_SAVE_DIR, "value": candidate_dir})
			save_dir_value = candidate_dir
			continue
		if _matches_flag(token, FLAG_STAGE) != -1:
			if stage_seen:
				return _failure("duplicate_debug_flag", {"flag": FLAG_STAGE})
			stage_seen = true
			var candidate_stage: String = _flag_value(token, FLAG_STAGE)
			if candidate_stage.is_empty():
				return _failure("empty_debug_value", {"flag": FLAG_STAGE})
			if not VALID_STAGES.has(candidate_stage):
				return _failure("invalid_stage", {"flag": FLAG_STAGE, "value": candidate_stage})
			stage_value = candidate_stage
			continue
		if _matches_flag(token, FLAG_SEED) != -1:
			if seed_seen:
				return _failure("duplicate_debug_flag", {"flag": FLAG_SEED})
			seed_seen = true
			var seed_text: String = _flag_value(token, FLAG_SEED)
			if seed_text.is_empty():
				return _failure("empty_debug_value", {"flag": FLAG_SEED})
			var parsed_seed: Dictionary = _parse_exact_int(seed_text)
			if (
				not bool(parsed_seed.get("ok", false))
				or int(parsed_seed.get("value", 0)) < -MAX_SAFE_JSON_INTEGER
				or int(parsed_seed.get("value", 0)) > MAX_SAFE_JSON_INTEGER
			):
				return _failure("invalid_seed", {"flag": FLAG_SEED, "value": seed_text})
			seed_value = int(parsed_seed.get("value", 0))
			continue
		if _matches_flag(token, FLAG_FORCE_FAMILY) != -1:
			if force_family_seen:
				return _failure("duplicate_debug_flag", {"flag": FLAG_FORCE_FAMILY})
			force_family_seen = true
			var family: String = _flag_value(token, FLAG_FORCE_FAMILY)
			if family.is_empty():
				return _failure("empty_debug_value", {"flag": FLAG_FORCE_FAMILY})
			force_family_value = family
			continue
		if _matches_flag(token, FLAG_FORCE_ITEM) != -1:
			if force_item_seen:
				return _failure("duplicate_debug_flag", {"flag": FLAG_FORCE_ITEM})
			force_item_seen = true
			var item: String = _flag_value(token, FLAG_FORCE_ITEM)
			if item.is_empty():
				return _failure("empty_debug_value", {"flag": FLAG_FORCE_ITEM})
			force_item_value = item
			continue
		return _failure("unknown_debug_flag", {"flag": token})

	if has_master and not force_family_value.is_empty() and not force_item_value.is_empty():
		return _failure("ambiguous_force_drop", {})

	var chosen_save_directory: String = save_dir_value if save_dir_seen else default_debug_save_dir
	if has_master and _comparison_key(chosen_save_directory) == _comparison_key(protected_save_dir):
		return _failure("protected_save_dir", {
			"save_directory": chosen_save_directory,
			"protected_save_dir": protected_save_dir,
		})

	return {
		"ok": true,
		"enabled": has_master,
		"save_directory": chosen_save_directory,
		"wipe": wipe,
		"has_stage": stage_seen,
		"stage": stage_value if stage_seen else DEFAULT_STAGE,
		"has_seed": seed_seen,
		"seed": seed_value,
		"force_family": force_family_value,
		"force_item": force_item_value,
		"no_persist": no_persist,
	}


static func _is_known_flag(token: String) -> bool:
	for boolean_flag in BOOLEAN_FLAGS:
		if token == boolean_flag:
			return true
	for value_flag in VALUE_FLAGS:
		if _matches_flag(token, value_flag) != -1:
			return true
	return false


static func _matches_flag(token: String, flag_name: String) -> int:
	if token == flag_name:
		return 0
	if token.begins_with(flag_name + "="):
		return flag_name.length() + 1
	return -1


static func _flag_value(token: String, flag_name: String) -> String:
	if token == flag_name:
		return ""
	return token.substr(flag_name.length() + 1)


## Parses a signed exact 64-bit integer from decimal text without relying on
## is_valid_int()/to_int(), which silently wrap out-of-range digit strings in
## Godot 4.7.  Leading zeros and an optional + sign are accepted; whitespace,
## non-digits, and magnitudes beyond the int64 range are rejected.
static func _parse_exact_int(text: String) -> Dictionary:
	if text.is_empty():
		return {"ok": false}
	var negative := false
	var digits := text
	if digits.begins_with("-"):
		negative = true
		digits = digits.substr(1)
	elif digits.begins_with("+"):
		digits = digits.substr(1)
	if digits.is_empty():
		return {"ok": false}
	for index in digits.length():
		var codepoint: int = digits.unicode_at(index)
		if codepoint < 0x30 or codepoint > 0x39:
			return {"ok": false}
	var magnitude_limit := "9223372036854775808" if negative else "9223372036854775807"
	var trimmed := digits
	while trimmed.length() > 1 and trimmed.begins_with("0"):
		trimmed = trimmed.substr(1)
	if trimmed.length() > magnitude_limit.length():
		return {"ok": false}
	if trimmed.length() == magnitude_limit.length() and trimmed > magnitude_limit:
		return {"ok": false}
	var value: int = 0
	for index in digits.length():
		var digit: int = digits.unicode_at(index) - 0x30
		value = value * 10 + digit
	return {"ok": true, "value": -value if negative else value}


static func _is_valid_save_dir(value: String) -> bool:
	if value.begins_with("user://"):
		return true
	if value.begins_with("res://"):
		return false
	return value.is_absolute_path()


static func _comparison_key(value: String) -> String:
	var expanded: String = ProjectSettings.globalize_path(value) if value.begins_with("user://") else value
	return expanded.simplify_path()


static func _failure(code: String, context: Dictionary) -> Dictionary:
	var result := {"ok": false, "error": code}
	result.merge(context, true)
	return result
