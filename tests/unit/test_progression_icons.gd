extends SceneTree
## Reader/atlas contract and screen integration with an in-memory delivery.
## Production art is never created or changed here.

const ProgressionIconsScript = preload("res://src/presentation/progression_icons.gd")
const CharacterScreenScript = preload("res://src/presentation/character_screen.gd")
const TalentRegistryScript = preload("res://src/content/talent_registry.gd")

const TALENT_TEXTURE := "ranger_talents.png"
const LAW_TEXTURE := "law_tokens.png"


class Fixture extends "res://src/presentation/progression_icons.gd":
	var atlas: Dictionary
	var textures: Dictionary


	func _parse_atlas(path: String) -> Dictionary:
		if path == ATLAS_PATH:
			var parsed: Dictionary = atlas.duplicate(true)
			if int(parsed.get("schema_version", 0)) != SCHEMA_VERSION:
				return parsed
			var by_id := {}
			for raw_entry in (parsed.get("sprites", []) as Array):
				var entry: Dictionary = raw_entry
				by_id[String(entry.get("id", ""))] = entry
			parsed["sprites"] = by_id
			return parsed
		return super._parse_atlas(path)


	func _load_texture(path: String) -> Texture2D:
		var texture: Texture2D = textures.get(path, null)
		if texture != null:
			return texture
		pending_reason = "ASSETS PENDING: missing %s" % path
		return null



func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var errors: Array[String] = []
	var fixture := _fixture(false)
	fixture.load_icons()
	_expect(not fixture.is_ready() and fixture.pending_reason.begins_with("ASSETS PENDING:"),
		"an incomplete pack must stay pending: %s" % fixture.pending_reason, errors)

	var reader := _fixture(true)
	reader.load_icons()
	_expect(reader.is_ready() and reader.pending_reason.is_empty(),
		"the complete delivery was refused: %s" % reader.pending_reason, errors)
	var talent_ids := _ranger_talent_order()
	var seen: Array[String] = []
	for talent_id in talent_ids:
		var texture := reader.icon("talent.%s" % talent_id)
		_expect(texture != null, "talent icon is null: %s" % talent_id, errors)
		if texture != null:
			var atlas_texture := texture as AtlasTexture
			var cell := atlas_texture.region
			_expect(atlas_texture.atlas != null and cell == Rect2(32 * seen.size(), 0, 32, 32),
				"talent %s does not use its own sequential 32x32 cell: %s" % [talent_id, cell], errors)
			seen.append(talent_id)
	for operation in ["inscribe", "rewrite", "refine"]:
		var texture := reader.icon("law_token.%s" % operation)
		_expect(texture != null and (texture as AtlasTexture).region == Rect2(32 * ProgressionIconsScript.FORGE_OPERATION_ORDER.find(operation), 0, 32, 32),
			"law token %s is missing or not in its fixed cell" % operation, errors)

	var production := ProgressionIconsScript.new()
	_expect(production.load_icons() and production.is_ready() and production.pending_reason.is_empty(),
		"the installed production atlas was refused: %s" % production.pending_reason, errors)
	for index in talent_ids.size():
		var texture := production.icon("talent.%s" % talent_ids[index])
		_expect(texture is AtlasTexture and texture.region == Rect2(32 * index, 0, 32, 32)
			and texture.atlas != null and texture.atlas.get_size() == Vector2(480, 32),
			"production talent cell %d is not a distinct 32x32 region on the 480x32 sheet" % index, errors)
	for operation in ProgressionIconsScript.FORGE_OPERATION_ORDER:
		var texture := production.icon("law_token.%s" % operation)
		var index := ProgressionIconsScript.FORGE_OPERATION_ORDER.find(operation)
		_expect(texture is AtlasTexture and texture.region == Rect2(32 * index, 0, 32, 32)
			and texture.atlas != null and texture.atlas.get_size() == Vector2(96, 32),
			"production law-token %s is not its distinct 32x32 region on the 96x32 sheet" % operation, errors)

	for changed in [_bad_schema(), _wrong_anchor(), _short_sheet(), _wrong_texture()]:
		var broken := _fixture(true)
		for key in changed:
			_match_fixture_field(broken, key, changed[key])
		var refused := not broken.load_icons()
		_expect(refused and not broken.is_ready() and broken.pending_reason.begins_with("ASSETS PENDING:"),
			"a malformed atlas was accepted: %s" % broken.pending_reason, errors)
		_expect(broken.icon("talent.ranger_steady_string") == null and broken.icon("law_token.inscribe") == null,
			"a refused reload left stale icons", errors)

	var screen := CharacterScreenScript.new()
	root.add_child(screen)
	await process_frame
	screen.present(_screen_snapshot())
	var implemented_button: Button = screen.find_child("TalentNode_ranger_steady_string", true, false) as Button
	var pending_button: Button = screen.find_child("TalentNode_ranger_wind_slice_stance", true, false) as Button
	_expect(implemented_button != null and not implemented_button.disabled
		and pending_button != null and not pending_button.disabled
		and pending_button.text.contains("Windcut Stance")
		and pending_button.get_theme_font_size("font_size") >= 22,
		"iconed pending wind-slice stopped being inspectable or lost its visible name", errors)
	if pending_button != null:
		pending_button.pressed.emit()
	var allocate_button: Button = screen.find_child("AllocateTalentButton", true, false) as Button
	var pending_detail: Label = screen.find_child("SelectedTalentState", true, false) as Label
	_expect(allocate_button != null and allocate_button.disabled
		and pending_detail != null and pending_detail.text.contains("This node will unlock when its mechanic is implemented"),
		"selecting iconed pending wind-slice did not keep allocation disabled while exposing its reason", errors)
	for button in [implemented_button, pending_button]:
		if button == null:
			continue
		_expect(button.icon is AtlasTexture and button.icon.get_size() == Vector2(32, 32)
			and button.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
			and int(button.get_theme_constant("icon_max_width")) == 32
			and button.get_combined_minimum_size() <= Vector2(96, 96),
			"talent icon is missing or its 96x96 node contract changed: %s" % button.name, errors)
	var board: Control = screen.find_child("RangerTalentBoard", true, false) as Control
	for talent_id in talent_ids:
		var button: Button = board.find_child("TalentNode_%s" % talent_id, true, false) as Button
		_expect(button != null and button.get_combined_minimum_size() <= Vector2(96, 96),
			"talent %s exceeds the fixed 96x96 node: %s" % [talent_id, str(button.get_combined_minimum_size())], errors)
	root.remove_child(screen)
	screen.free()

	if errors.is_empty():
		print("PROGRESSION_ICONS_PASS")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)


func _fixture(complete := true) -> Fixture:
	var fixture := Fixture.new()
	var talent_sheet := Image.create(480, 32, false, Image.FORMAT_RGBA8)
	var law_sheet := Image.create(96, 32, false, Image.FORMAT_RGBA8)
	if complete:
		talent_sheet.fill(Color(0.2, 0.4, 0.5, 1.0))
		law_sheet.fill(Color(0.5, 0.4, 0.2, 1.0))
	fixture.textures = {} if not complete else {
		ProgressionIconsScript.ATLAS_DIRECTORY.path_join(TALENT_TEXTURE): ImageTexture.create_from_image(talent_sheet),
		ProgressionIconsScript.ATLAS_DIRECTORY.path_join(LAW_TEXTURE): ImageTexture.create_from_image(law_sheet),
	}
	var sprites: Array = []
	var talent_ids := _ranger_talent_order()
	for index in talent_ids.size():
		sprites.append(_sprite("talent.%s" % talent_ids[index], TALENT_TEXTURE, index))
	var operations := ProgressionIconsScript.FORGE_OPERATION_ORDER
	for index in operations.size():
		sprites.append(_sprite("law_token.%s" % operations[index], LAW_TEXTURE, index))
	fixture.atlas = {"schema_version": 1, "sprites": sprites}
	return fixture


func _sprite(id: String, texture: String, index: int) -> Dictionary:
	return {"id": id, "texture": texture, "type": "ui_icon", "anchor": [16, 16], "rect": [32 * index, 0, 32, 32]}


func _ranger_talent_order() -> Array[String]:
	var registry := TalentRegistryScript.new()
	var ids: Array[String] = []
	for tree_value in registry.catalog().trees:
		var tree: Dictionary = tree_value
		if String(tree.class_id) != "ranger":
			continue
		for node_value in tree.nodes:
			ids.append(String((node_value as Dictionary).id))
	return ids


func _screen_snapshot() -> Dictionary:
	var nodes: Array = []
	var registry := TalentRegistryScript.new()
	for tree_value in registry.catalog().trees:
		var tree: Dictionary = tree_value
		if String(tree.class_id) != "ranger":
			continue
		for node_value in tree.nodes:
			var source: Dictionary = node_value
			var talent_id := String(source.id)
			var pending := talent_id == "ranger_wind_slice_stance"
			nodes.append({
				"id": talent_id, "name": String(source.name), "tier": int(source.layer),
				"keystone": bool(source.is_key), "description": String(source.description), "allocated": false,
				"can_allocate": not pending, "lock_reason": "This node will unlock when its mechanic is implemented" if pending else "",
			})
	return {"trees": [{"id": "ranger", "name": "Hunting", "available": true, "nodes": nodes}]}


func _bad_schema() -> Dictionary:
	return {"schema_version": 2}


func _wrong_anchor() -> Dictionary:
	return {"anchor": [15, 16]}


func _short_sheet() -> Dictionary:
	return {"texture": "missing-law"}


func _wrong_texture() -> Dictionary:
	return {"texture": "other.png"}


func _match_fixture_field(fixture: Fixture, key: String, value: Variant) -> void:
	match key:
		"schema_version": fixture.atlas["schema_version"] = value
		"anchor": fixture.atlas.sprites[0].anchor = value
		"texture": fixture.atlas.sprites[0].texture = value


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
