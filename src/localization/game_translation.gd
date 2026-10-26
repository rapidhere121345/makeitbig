class_name GameTranslation
extends Translation
## Translation boundary for existing presentation copy. Controls retain their English
## source and Godot reshapes them on locale changes, including an open dialogue.
## Exact source_messages are preferred. Legacy, already-formatted labels are matched against
## authored printf templates; numeric captures are kept verbatim (no rounding twice).

const CATALOG_PATH := "res://content/localization/zh_CN.json"
const CACHE_LIMIT := 2048
const MAX_DEPTH := 8
var source_messages: Dictionary = {}
var _patterns: Array[Dictionary] = []
var _cache: Dictionary = {}
var _anchor := RegEx.new()
var _placeholder := RegEx.new()
var _splitter := RegEx.new()
var _decorated_label := RegEx.new()


func _init() -> void:
	locale = "zh_CN"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not parsed is Dictionary:
		push_error("Cannot load translation catalog: " + CATALOG_PATH)
		return
	source_messages = parsed
	_install_dialogue_fragments()
	_placeholder.compile("%(?:[-+0 #]*[0-9]*(?:\\.[0-9]+)?)?[sdf]|%%")
	_anchor.compile("[A-Za-z]{2,}")
	_splitter.compile("(\\n+| · |  ·  | • |   +| → |: |：|, |; | / | \\| | \\+ )")
	_decorated_label.compile("\\A(.+?)( (?:T[0-9]+|Tier IV|Tier I{1,3})| [+-]?[0-9][0-9.,%/ xs+\\-]*)\\z")
	for source: String in source_messages:
		var tokens := _placeholder.search_all(source)
		if tokens.is_empty():
			continue
		var regex := "\\A"
		var cursor := 0
		var slots := 0
		var literal_count := 0
		for token: RegExMatch in tokens:
			var literal := source.substr(cursor, token.get_start() - cursor)
			regex += _escape(literal)
			literal_count += literal.length()
			var kind := token.get_string().right(1)
			if kind == "%": regex += "%"
			else:
				slots += 1
				regex += "([\\s\\S]+?)" if kind == "s" else "([-+0-9.,eE]+)"
			cursor = token.get_end()
		var tail := source.substr(cursor)
		regex += _escape(tail) + "\\z"
		literal_count += tail.length()
		# Generic '%s / %s' layouts belong to the separator fallback, not an
		# unconstrained recursive template which would match arbitrary prose.
		if literal_count < 3 or slots == 0 or _anchor.search(_placeholder.sub(source, "", true)) == null:
			continue
		var matcher := RegEx.new()
		if matcher.compile(regex) != OK:
			continue
		_patterns.append({"regex": matcher, "target": String(source_messages[source]),
			"prefix": source.substr(0, tokens[0].get_start()), "weight": literal_count})
	_patterns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.weight > b.weight)


## TownDialogue splits recognized speaker prefixes before assigning the speech
## label. Derive that exact fragment from the authored full-line translation,
## preserving one source of truth for the journal and the in-world conversation.
func _install_dialogue_fragments() -> void:
	for source: String in source_messages.keys():
		var split := source.find(": ")
		if split < 0 or source.left(split) not in ["Mira", "Iven", "Taren", "Leia", "Oren", "Wanderer"]:
			continue
		var target := String(source_messages[source])
		var target_split := target.find("\uff1a")
		if target_split < 0:
			target_split = target.find(":")
		if target_split < 0:
			continue
		var speech := source.substr(split + 2).strip_edges()
		if not source_messages.has(speech):
			source_messages[speech] = target.substr(target_split + 1).strip_edges()


func _get_message(source: StringName, context: StringName) -> StringName:
	if context == &"diagnostics":
		return &""
	var original := String(source)
	var translated := render(original)
	return StringName(translated) if translated != original else &""


func render(source: String, depth: int = 0) -> String:
	if source_messages.has(source):
		return String(source_messages[source])
	if source.is_empty() or depth >= MAX_DEPTH or not _has_letters(source):
		return source
	if _cache.has(source):
		return String(_cache[source])
	var translated := _render_uncached(source, depth)
	if _cache.size() >= CACHE_LIMIT:
		_cache.clear()
	_cache[source] = translated
	return translated


func _render_uncached(source: String, depth: int) -> String:
	# Item tiers and stat deltas are attached to known display names. Translate
	# only an exact catalog name followed by a typed suffix, never prose words.
	var decorated := _decorated_label.search(source)
	if decorated != null and source_messages.has(decorated.get_string(1)):
		return String(source_messages[decorated.get_string(1)]) + render(decorated.get_string(2), depth + 1)
	for pattern: Dictionary in _patterns:
		if not source.begins_with(String(pattern.prefix)):
			continue
		var found: RegExMatch = (pattern.regex as RegEx).search(source)
		if found == null:
			continue
		var target := String(pattern.target)
		var result := ""
		var cursor := 0
		var group := 1
		for token: RegExMatch in _placeholder.search_all(target):
			result += target.substr(cursor, token.get_start() - cursor)
			if token.get_string() == "%%": result += "%"
			else:
				var capture := found.get_string(group)
				# A self capture is an unconstrained wrapper. Let separators
				# handle it, so lookup always makes progress.
				if capture == source: break
				result += render(capture, depth + 1)
				group += 1
			cursor = token.get_end()
		if group == found.get_group_count() + 1:
			return result + target.substr(cursor)
	# Composite rows are authored from independently named items and sentences.
	# Split only at UI separators; never substitute words inside arbitrary prose,
	# identifiers, file paths, or BBCode tags.
	var output := ""
	var start := 0
	for separator: RegExMatch in _splitter.search_all(source):
		output += render(source.substr(start, separator.get_start() - start), depth + 1)
		output += separator.get_string()
		start = separator.get_end()
	if start > 0:
		return output + render(source.substr(start), depth + 1)
	var trimmed := source.strip_edges()
	if trimmed != source and source_messages.has(trimmed):
		return source.replace(trimmed, String(source_messages[trimmed]))
	return source


static func _escape(value: String) -> String:
	var result := ""
	for character: String in value:
		if character in "\\.^$|?*+()[]{}": result += "\\"
		result += character
	return result


static func _has_letters(value: String) -> bool:
	for character: String in value:
		if (character >= "A" and character <= "Z") or (character >= "a" and character <= "z"):
			return true
	return false
