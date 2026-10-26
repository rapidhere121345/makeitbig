extends SceneTree
const Locale = preload("res://src/localization/game_locale.gd")
const Catalog = preload("res://src/localization/game_translation.gd")
const Game = preload("res://src/game/game_root.gd")
const Hearth = preload("res://src/presentation/hearth_return_view.gd")
const Shell = preload("res://src/presentation/shell_theme.gd")
const Dialogue = preload("res://src/presentation/town_dialogue.gd")
const Title = preload("res://src/presentation/title_screen.gd")
const Stage = preload("res://src/presentation/pixel_stage.gd")
const Policy = preload("res://src/presentation/display_policy.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var catalog := Catalog.new()
	_expect(catalog.source_messages.size() >= 1700, "complete chapter translation catalog is loaded")
	for code: Variant in [null, 42, "fr", "", "zh_TW"]:
		_expect(Locale.normalize(code) == "en", "unsupported locale falls back safely")
	for code: String in ["zh", "zh-CN", "zh_CN", "zh_Hans", "zh-Hans-CN"]:
		_expect(Locale.normalize(code) == "zh_CN", "Simplified Chinese locale normalization")
	Locale.select("zh_CN")
	_expect(Locale.text("Resume") == catalog.source_messages["Resume"], "Godot translation dispatch uses the selected catalog")
	_expect(Locale.text("Room 2/3 · Corridor · Clear foes") ==
		String(catalog.source_messages["Room %d/%d · %s · %s"]) % [2, 3, catalog.render("Corridor"), catalog.render("Clear foes")], "formatted room label translates names and preserves numbers")
	_expect(Locale.text("Sound 23%") == String(catalog.source_messages["Sound %d%%"]) % 23, "literal percent retained")
	_expect(Locale.text("Lv.4 · Ranger") == String(catalog.source_messages["Lv.%d · %s"]) % [4, catalog.render("Ranger")], "level and class translate together")
	_expect(Locale.text("Not a game message / custom_123") == "Not a game message / custom_123", "unknown copy stays intact")
	_expect(Locale.text("12,345 / 99,999") == "12,345 / 99,999", "numbers are not reformatted")
	_expect(Locale.text("Ranger\nThreshold Colossus") == catalog.render("Ranger") + "\n" + catalog.render("Threshold Colossus"), "composite rows translate independently: " + Locale.text("Ranger\nThreshold Colossus"))
	_expect(Locale.text("Piercing Arrow, Hunter's Mark; Dodge / Dash") == catalog.render("Piercing Arrow") + ", " + catalog.render("Hunter's Mark") + "; " + catalog.render("Dodge") + " / " + catalog.render("Dash"), "composed equipment/skill lists translate each display name")
	_expect(Locale.text("Arrow Speed +12%") == catalog.render("Arrow Speed") + " +12%", "stat label translates while delta is preserved")
	_expect(Locale.text("Piercing Arrow T2") == catalog.render("Piercing Arrow") + " T2", "tiered item name translates without changing its tier")
	_expect(Locale.text("Unknown custom item T9") == "Unknown custom item T9", "unknown custom names are not rewritten")
	# Exact content translations include every dialogue/journal page, with no data mutation.
	var story: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/chapter_one_story.json"))
	_check_story(story, catalog)
	var campaign: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/early_campaign.json"))
	for layout: Dictionary in campaign.layouts:
		for key: String in ["display_name", "concept", "landmark", "entry_hint", "exit_hint"]:
			_expect(catalog.source_messages.has(layout[key]), "all combat room copy is translated: " + key)
	_expect(catalog.source_messages.has(Title.PREMISE_TEXT), "current title premise is translated")
	Locale.select("en")
	_expect(Locale.text("Resume") == "Resume", "English is immediately restored")
	await _check_dialogue(catalog)
	await _check_live_switch(catalog)
	await _check_persistence()
	_check_resolution_policy()
	await _check_art_and_glyphs(catalog)
	Locale.select("en")
	Locale.shutdown()
	for failure: String in failures: printerr(failure)
	print("LOCALIZATION ", "pass" if failures.is_empty() else "fail", " checks=", checks)
	quit(0 if failures.is_empty() else 1)

func _check_story(value: Variant, catalog: Resource) -> void:
	if value is Dictionary:
		for key: String in value:
			if key in ["title", "body", "text", "summary", "description", "objective"] and value[key] is String and not value[key].is_empty():
				_expect(catalog.source_messages.has(value[key]), "story has translation: " + String(value[key]).left(60))
			elif key == "pages" and value[key] is Array:
				for page: String in value[key]:
					_expect(catalog.source_messages.has(page), "full story page has a translation")
					var parts: Dictionary = Dialogue.speaker_line({}, page)
					_expect(catalog.source_messages.has(parts.speech), "rendered speech fragment has a translation")
			else: _check_story(value[key], catalog)
	elif value is Array:
		for item: Variant in value: _check_story(item, catalog)

func _check_dialogue(catalog: Resource) -> void:
	var story: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/chapter_one_story.json"))
	var entry: Dictionary = story.units[0].conversations[0]
	var dialogue := Dialogue.new()
	root.add_child(dialogue)
	dialogue.open_conversation(entry)
	dialogue.advance()
	var page: int = dialogue.dialogue_report().page
	var speech: Label = dialogue.find_child("DialogueSpeech", true, false)
	Locale.select("en")
	_expect(speech.tr(speech.text) == speech.text, "dialogue starts in English")
	Locale.select("zh_CN")
	_expect(speech.tr(speech.text) == catalog.source_messages[speech.text], "stripped NPC/player speech translates live")
	_expect(dialogue.dialogue_report().page == page, "language switching preserves dialogue position")
	Locale.select("en")
	_expect(speech.tr(speech.text) == speech.text, "dialogue restores English without replacing its nodes")
	dialogue.close_dialogue()
	dialogue.free()
	await process_frame


func _check_live_switch(catalog: Resource) -> void:
	var game := Game.new()
	game.playtest_logging_enabled = false
	game.initialize(PackedStringArray(["--game-flow-smoke"]))
	root.add_child(game)
	await process_frame
	game.start_new_game("ranger")
	game.complete_tutorial()
	game.open_contract()
	game.launch_contract({"contract_id":"mainline_01_first_hunt", "mode":"Manual", "seed":52969, "room_count":1})
	_expect(game.get_presentation_viewport().render_target_update_mode != SubViewport.UPDATE_ONCE, "newly routed combat continues rendering")
	var controller: Node = game.current_screen
	var arena: Node = controller.get("_current_runtime").get("room_instance")
	var menu: Node = game.get_session_menu()
	menu.open_menu()
	_expect(game.get_presentation_viewport().render_target_update_mode == SubViewport.UPDATE_ONCE, "paused game is cached instead of redrawn every frame")
	var tick: int = arena.sim_tick
	var before: Dictionary = game.application_state.profile.duplicate(true)
	var picker: OptionButton = menu.find_child("LanguageChoice", true, false)
	picker.select(1)
	picker.item_selected.emit(1)
	await process_frame
	_expect(Locale.current() == "zh_CN", "menu switches the live locale")
	_expect(game.current_screen == controller and arena.sim_tick == tick, "language switch preserves paused combat instance and tick")
	_expect(game.application_state.profile == before, "language selection does not change profile authority")
	var resume: Button = menu.find_child("ResumeButton", true, false)
	_expect(resume.tr(resume.text) == catalog.source_messages["Resume"], "open menu translates without rebuilding")
	game._set_language("en")
	_expect(resume.tr(resume.text) == "Resume", "same button restores English")
	menu.close_menu()
	_expect(game.get_presentation_viewport().render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE, "resume restores live game rendering")
	game.free()
	await process_frame

func _check_persistence() -> void:
	var directory := "user://locale-display-test-%d" % Time.get_ticks_usec()
	var game := Game.new()
	game.save_directory_path = directory
	game.playtest_logging_enabled = false
	root.add_child(game)
	await process_frame
	game._set_language("zh_CN")
	game._set_menu_scale(1.25)
	game._set_render_quality("fast")
	game._set_effects_volume(0.23)
	game.free()
	Locale.select("en")
	var restored := Game.new()
	restored.save_directory_path = directory
	restored.playtest_logging_enabled = false
	root.add_child(restored)
	await process_frame
	_expect(restored._language_code == "zh_CN" and Locale.current() == "zh_CN", "language survives restart")
	_expect(restored._menu_scale == 1.25 and restored._render_quality == "fast", "display preferences survive restart")
	_expect(is_equal_approx(restored._effects_volume, 0.23), "changing language/scale retains volume")
	restored.free()
	# Only this test's unique temporary configuration is removed.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join("display.cfg")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	await process_frame

func _check_resolution_policy() -> void:
	for invalid: Variant in [null, "1.25", 2.0, -1, NAN, INF]:
		_expect(Policy.parse_menu_scale(invalid) == 1.0, "invalid saved scale falls back")
	for size: Vector2i in [Vector2i(1280,720), Vector2i(1920,1200), Vector2i(2560,1440), Vector2i(3440,1440), Vector2i(3840,2160), Vector2i(5120,1440)]:
		for scale: float in [1.0,1.15,1.25]:
			var layout: Dictionary = Stage.adaptive_layout_for_window(size, scale)
			_expect(layout.ui_logic_size.x >= 1280 and layout.ui_logic_size.y >= 720, "large text keeps usable reading workspace")
			_expect(absf(float(layout.ui_logic_size.x) / layout.ui_logic_size.y - float(size.x) / size.y) < 0.002, "reading UI is uniformly scaled without distortion")
	_expect(Stage.render_shrink(Vector2i(3840,2160), Stage.POLICY_FIXED_PIXEL, "balanced") == 2, "balanced 4K uses a quarter of offscreen pixels")
	_expect(Stage.render_shrink(Vector2i(3840,2160), Stage.POLICY_FIXED_PIXEL, "native") == 1, "native detail remains available")
	_expect(Stage.render_shrink(Vector2i(3840,2160), Stage.POLICY_ADAPTIVE_SHELL, "fast") == 1, "reading menus always have native text")

func _check_art_and_glyphs(catalog: Resource) -> void:
	var font := Shell.ui_font()
	var glyphs := {}
	for target: String in catalog.source_messages.values():
		for character: String in target:
			var code := character.unicode_at(0)
			if code >= 0x3400 and code <= 0x9fff:
				glyphs[code] = true
	for code: int in glyphs:
		_expect(font.has_char(code), "bundled Chinese font contains glyph U+%04X" % code)
	var view := Hearth.new()
	root.add_child(view)
	for dimensions: Vector2 in [Vector2(640,360),Vector2(900,400),Vector2(640,640)]:
		view.size = dimensions
		view._fit_art()
		_expect(is_equal_approx(view._art_root.scale.x,view._art_root.scale.y), "actors are never stretched per axis")
		var art := Rect2(view._art_root.position, Vector2(640,360) * view._art_root.scale)
		_expect(Rect2(Vector2.ZERO,dimensions).grow(1).encloses(art), "whole illustration fits in its display bounds")
	view.free()
	await process_frame


func _expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
