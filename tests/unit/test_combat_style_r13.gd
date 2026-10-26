extends SceneTree
## Focused R13 skin delivery test. The legacy action suites remain unchanged.
## Checks real pixels and every published action, not a generated atlas promise.

const Ranger := preload("res://src/presentation/ranger_animation.gd")
const Enemy := preload("res://src/presentation/enemy_animation.gd")
const World := preload("res://src/presentation/arena_world_view.gd")
const Palette := preload("res://src/presentation/combat_palette.gd")
const Assert := preload("res://tests/helpers/assert.gd")
const PACK := "res://art/production/p1/combat_style_r13/v03/"

var failures: Array[String] = []
var facts := {}

func _initialize() -> void:
	var ranger = Ranger.new()
	var enemy = Enemy.new()
	_expect(ranger.has_real_art(), "ranger material skin did not load: " + ranger.pending_reason())
	_expect(enemy.has_real_art(), "enemy material skin did not load: " + enemy.pending_reason())
	_expect(ranger.render_texture_path() == Ranger.STYLE_TEXTURE_PATH, "ranger reader silently used the old sheet")
	_expect(enemy.render_texture_path() == Enemy.STYLE_TEXTURE_PATH, "enemy reader silently used the old sheet")
	_contract("ranger", Ranger.ATLAS_PATH, Ranger.STYLE_ATLAS_PATH)
	_contract("enemy", Enemy.ATLAS_PATH, Enemy.STYLE_ATLAS_PATH)
	## The R13 recolor check stays pinned to the retained v03 sheets — it
	## proves the historical material-skin claim, nothing about actors_v02.
	_pixels("ranger", Ranger.TEXTURE_PATH, PACK + "ranger.png")
	_pixels("enemy", Enemy.TEXTURE_PATH, PACK + "enemies.png")
	## The live pack is a full redraw, so different pixels are required:
	## changed silhouette, binarized alpha, and nonempty distinct cells.
	_pack_pixels("ranger", Ranger.TEXTURE_PATH, Ranger.STYLE_TEXTURE_PATH)
	_pack_pixels("enemy", Enemy.TEXTURE_PATH, Enemy.STYLE_TEXTURE_PATH)
	_matrix(ranger, ranger.clip_ids(), 68, "ranger")
	_matrix(enemy, enemy.declared_clip_ids(), 39, "enemy")
	for role: String in Enemy.ROLES:
		for action: String in Enemy.ACTIONS:
			for frame_index in Enemy.ACTION_FRAME_COUNTS[action]:
				var clock := int(ceil(float(frame_index) * 30.0 / float(Enemy.ACTION_CONTRACT[action].fps)))
				var state := {"role": role, "facing": "west", "tick": clock, "phase_ticks": clock}
				match action:
					"walk": state["moving"] = true
					"windup":
						state["action_state"] = "windup"
						state["tick"] = frame_index * 30
						state["state_started_tick"] = 0
						state["state_ends_tick"] = 60
					"active": state["action_state"] = "active"
					"recover": state["action_state"] = "recovery"
					"hit": state["hit_ticks"] = clock
					"death":
						state["dead"] = true
						state["death_ticks"] = clock
				var frame: Dictionary = enemy.resolve(state)
				var clip := Enemy.clip_id(role, "west", action)
				_expect(bool(frame.get("flip_x", false)), "west mirror lost: " + clip)
				_expect(frame.get("anchor") == Enemy.DEFAULT_ANCHOR, "mirrored feet moved: " + clip)
				_expect(frame.get("action") == action and int(frame.get("frame", -1)) == frame_index, "mirrored action/frame changed: " + clip)
	_broken_skin(Ranger, Ranger.STYLE_ATLAS_PATH, "ranger")
	_broken_skin(Enemy, Enemy.STYLE_ATLAS_PATH, "enemies")
	_world()
	_expect(Palette.DANGER == Color("a83b3f") and Palette.DANGER_BRIGHT == Color("ed7370"), "hostile warning colours changed")
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--report="):
			var file := FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			if file != null:
				file.store_string(JSON.stringify({"status": "pass" if failures.is_empty() else "fail", "facts": facts, "failures": failures}, "\t") + "\n")
	for failure in failures:
		printerr(failure)
	print("COMBAT_STYLE_R13_UNIT_", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _contract(name: String, source: String, skin: String) -> void:
	var original := _json(source)
	var styled := _json(skin)
	_expect(not original.is_empty() and not styled.is_empty(), "missing manifest: " + name)
	for key: String in original.keys():
		_expect(styled.get(key) == original[key], "%s changed action contract field %s" % [name, key])
	facts[name + "_contract"] = {"source_sha256": FileAccess.get_sha256(source), "skin_sha256": FileAccess.get_sha256(skin), "source_fields_preserved": original.keys(), "sprites": original.get("sprites", {}).size(), "clips": original.get("animations", {}).size()}

func _pixels(name: String, source: String, skin: String) -> void:
	var original := Image.load_from_file(ProjectSettings.globalize_path(source))
	var styled := Image.load_from_file(ProjectSettings.globalize_path(skin))
	if original == null or styled == null:
		_expect(false, "missing pixels: " + name)
		return
	original.convert(Image.FORMAT_RGBA8)
	styled.convert(Image.FORMAT_RGBA8)
	_expect(original.get_size() == styled.get_size(), "sheet dimensions changed: " + name)
	var left := original.get_data()
	var right := styled.get_data()
	var alpha_changes := 0
	var danger_changes := 0
	var player_light_changes := 0
	var player_light_pixels := 0
	var opaque_changes := 0
	for offset in range(0, mini(left.size(), right.size()), 4):
		if left[offset + 3] != right[offset + 3]:
			alpha_changes += 1
		if left[offset] == 189 and left[offset + 1] == 70 and left[offset + 2] == 83 and left[offset + 3] > 0:
			if left.slice(offset, offset + 4) != right.slice(offset, offset + 4):
				danger_changes += 1
		if name == "ranger" and left[offset + 3] > 0 and (left.slice(offset, offset + 3) == PackedByteArray([233, 221, 195]) or left.slice(offset, offset + 3) == PackedByteArray([211, 203, 181])):
			player_light_pixels += 1
			if left.slice(offset, offset + 3) != right.slice(offset, offset + 3):
				player_light_changes += 1
		if left[offset + 3] > 0 and left.slice(offset, offset + 3) != right.slice(offset, offset + 3):
			opaque_changes += 1
	_expect(alpha_changes == 0, "actor silhouette/alpha changed: " + name)
	_expect(danger_changes == 0, "hostile accent lost: " + name)
	_expect(player_light_changes == 0, "continuous player bone-white hood/cloak was recoloured")
	_expect(opaque_changes > 100, "material skin does not change rendered pixels: " + name)
	facts[name + "_pixels"] = {"size": [original.get_width(), original.get_height()], "alpha_changes": alpha_changes, "hostile_red_changes": danger_changes, "material_pixel_changes": opaque_changes, "player_light_pixels_preserved": player_light_pixels, "player_light_changes": player_light_changes}

func _pack_pixels(name: String, source: String, skin: String) -> void:
	var original := Image.load_from_file(ProjectSettings.globalize_path(source))
	var styled := Image.load_from_file(ProjectSettings.globalize_path(skin))
	if original == null or styled == null:
		_expect(false, "missing pixels: " + name)
		return
	original.convert(Image.FORMAT_RGBA8)
	styled.convert(Image.FORMAT_RGBA8)
	var data := styled.get_data()
	var alpha_changes := 0
	var opaque_changes := 0
	var nonbinary_alpha := 0
	var left := original.get_data()
	var limit := mini(left.size(), data.size())
	for offset in range(0, limit, 4):
		if left[offset + 3] != data[offset + 3]:
			alpha_changes += 1
		if left[offset + 3] > 0 and left.slice(offset, offset + 3) != data.slice(offset, offset + 3):
			opaque_changes += 1
		if data[offset + 3] != 0 and data[offset + 3] != 255:
			nonbinary_alpha += 1
	_expect(alpha_changes > 0, name + ": actors_v02 must redraw the silhouette, not just recolour")
	_expect(opaque_changes > 1000, name + ": actors_v02 material barely differs from the old sheet")
	_expect(nonbinary_alpha == 0, name + ": actors_v02 alpha is not threshold-binarized")
	facts[name + "_v02_pixels"] = {"alpha_changes": alpha_changes,
		"opaque_changes": opaque_changes, "nonbinary_alpha": nonbinary_alpha}

func _matrix(reader, clips: Array, sprite_count: int, name: String) -> void:
	var total := 0
	_expect(reader.sprite_ids().size() == sprite_count, "sprite matrix incomplete: " + name)
	_expect(reader.contract_notes().is_empty(), "timing/alias drift: " + name)
	for clip: String in clips:
		for index in reader.frame_count(clip):
			var frame: Dictionary = reader.frame_for(clip, index)
			var texture: Texture2D = frame.get("texture")
			_expect(texture != null, "null action texture: " + clip)
			_expect(frame.get("texture_path") == reader.render_texture_path(), "frame report conceals rendered skin: " + clip)
			_expect(frame.get("rect").size == Vector2i(48, 48), "action cell changed: " + clip)
			_expect(frame.get("anchor") == Vector2i(24, 44), "action anchor changed: " + clip)
			if texture != null:
				var raw := Image.load_from_file(ProjectSettings.globalize_path(reader.render_texture_path()))
				_expect(_same_visible_pixels(texture.get_image(), raw), "loaded/imported texture disagrees with published pixels: " + clip)
			total += 1
	facts[name + "_matrix"] = {"clips": clips.size(), "sampled_frames": total, "render_texture": reader.render_texture_path()}

func _broken_skin(script: Script, manifest: String, key: String) -> void:
	var broken := _json(manifest)
	broken.render_textures[key].width = 1
	var reader = script.new(true, {}, broken)
	_expect(reader.asset_state() == "invalid" and not reader.has_real_art(), "wrong-size material binding silently accepted: " + key)
	broken = _json(manifest)
	broken.render_textures[key].path = "res://art/production/p1/combat_style_r13/missing.png"
	reader = script.new(true, {}, broken)
	_expect(reader.asset_state() == "invalid" and not reader.has_real_art(), "unapproved material binding silently accepted: " + key)

func _world() -> void:
	var world = World.new()
	_expect(world.load_assets(), "world skin incomplete: " + world.pending_reason)
	var source_scene := _json("res://art/production/p1/scene_rework_v01/atlas.json")
	var style_scene := _json(World.SCENE_ATLAS_PATH)
	_expect(source_scene.sprites == style_scene.sprites, "environment cell/anchor contract changed")
	var base_layout := _json("res://art/production/p1/scene_rework_v01/layout.json")
	_expect(base_layout.structures[6].id == "ruin.wall_corner" and base_layout.structures[6].feet == [733.0, 557.0], "historical shared wall source changed")
	# The one shared five-pixel move clears the enlarged whole-object socket.
	base_layout.structures[6].feet = [738.0, 557.0]
	var styled_layout := _json(World.SCENE_LAYOUT_PATH)
	_expect(styled_layout.get("room_structure_overrides", {}) == _json("res://docs/art-production/p1-combat-style-r13/room_structure_overrides.json"), "runtime room overrides differ from their authored packing source")
	styled_layout.erase("room_structure_overrides")
	_expect(styled_layout == base_layout, "default world placements changed outside explicit room overrides")
	var old_legacy := _json("res://art/production/p1/calibration_v01/atlas.json")
	var new_legacy := _json(World.LEGACY_ATLAS_PATH)
	for id: String in World.LEGACY_SPRITE_IDS:
		_expect(old_legacy.sprites[id] == new_legacy.sprites[id], "four-state enemy/tower cell moved: " + id)
	var all_sheets := {}
	var imports := {}
	for manifest: Dictionary in [style_scene, new_legacy]:
		for key: String in manifest.textures.keys():
			var entry: Dictionary = manifest.textures[key]
			var raw := Image.load_from_file(ProjectSettings.globalize_path(entry.path))
			_expect(raw != null and raw.get_size() == Vector2i(entry.width, entry.height), "world texture cannot be loaded: " + entry.path)
			all_sheets[key] = entry.path
			if FileAccess.file_exists(String(entry.path) + ".import"):
				var imported := ResourceLoader.load(entry.path, "Texture2D") as Texture2D
				_expect(imported != null, "declared Godot texture import cannot load: " + entry.path)
				if imported != null:
					_expect(_same_visible_pixels(imported.get_image(), raw), "world import changed visible source pixels: " + entry.path)
					imports[key] = {"path": entry.path, "size": [imported.get_width(), imported.get_height()], "visible_pixels_preserved": true}
	var old_core := Image.load_from_file(ProjectSettings.globalize_path("res://art/production/p1/scene_rework_v01/boss_core.png"))
	var new_core := Image.load_from_file(ProjectSettings.globalize_path(PACK + "boss_core.png"))
	old_core.convert(Image.FORMAT_RGBA8)
	new_core.convert(Image.FORMAT_RGBA8)
	_expect(old_core.get_data() == new_core.get_data(), "retained phase/core colours changed")
	## The live boss parts now come from actors_v02: they must exist as real
	## new art, not the retained sheets again.
	for part: String in ["boss_body", "boss_core", "boss_hands"]:
		var v02 := Image.load_from_file(ProjectSettings.globalize_path("res://art/production/p1/actors_v02/%s.png" % part))
		_expect(v02 != null, "actors_v02 %s.png missing" % part)
		if v02 != null:
			v02.convert(Image.FORMAT_RGBA8)
			var d: PackedByteArray = v02.get_data()
			var opaque := 0
			for i in range(3, d.size(), 4):
				if d[i] > 0:
					opaque += 1
			_expect(opaque > 200, "actors_v02 %s has almost no visible art" % part)
			var old_part := Image.load_from_file(ProjectSettings.globalize_path(PACK + "%s.png" % part))
			if old_part != null:
				old_part.convert(Image.FORMAT_RGBA8)
				_expect(old_part.get_data() != v02.get_data(), "actors_v02 %s is byte-identical to the old sheet" % part)
	var record := _json(PACK + "IMPORT.json")
	_expect(record.get("status") == "pass", "production import report contains failures")
	facts["world"] = {"textures": all_sheets, "cells": World.CELL_CONTRACTS.size(), "layout_sha256": FileAccess.get_sha256(World.SCENE_LAYOUT_PATH), "core_retained": true}
	facts["environment_imports"] = imports

func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)

func _same_visible_pixels(left: Image, right: Image) -> bool:
	# Godot's fix_alpha_border fills RGB under zero-alpha pixels. Those pixels
	# cannot render; every visible RGB and every alpha byte must still agree.
	if left.get_size() != right.get_size():
		return false
	left.convert(Image.FORMAT_RGBA8)
	right.convert(Image.FORMAT_RGBA8)
	var a := left.get_data()
	var b := right.get_data()
	for offset in range(0, a.size(), 4):
		if a[offset + 3] != b[offset + 3]:
			return false
		if b[offset + 3] > 0 and a.slice(offset, offset + 3) != b.slice(offset, offset + 3):
			return false
	return true
