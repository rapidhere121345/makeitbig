extends SceneTree
## Mutate metadata in memory only; production atlases and PNGs stay untouched.
const Art = preload("res://src/presentation/facility_art.gd")

class OverlayFixture extends "res://src/presentation/facility_art.gd":
	var overlay: Dictionary
	func _parse_atlas(path: String) -> Dictionary:
		if path == OVERRIDE_DIRECTORY.path_join(OVERRIDE_ATLAS_FILE):
			return overlay.duplicate(true)
		return super._parse_atlas(path)

func _initialize() -> void:
	var errors: Array[String] = []
	var published: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Art.OVERRIDE_DIRECTORY.path_join(Art.OVERRIDE_ATLAS_FILE)))
	var valid := OverlayFixture.new()
	valid.overlay = published
	if not valid.load_art(): errors.append("published overlay rejected")
	var cases: Array[Dictionary] = []
	for value in [0.5, "0", false, -0.5]:
		var changed := published.duplicate(true)
		changed.sprites[0].rect[0] = value
		cases.append(changed)
	for value in [16.5, "16", true]:
		var changed := published.duplicate(true)
		changed.sprites[0].anchor[0] = value
		cases.append(changed)
	var extra_texture := published.duplicate(true)
	extra_texture.textures.append({"id":"extra", "file":"overrides.png"})
	cases.append(extra_texture)
	var duplicate_id := published.duplicate(true)
	duplicate_id.sprites[1].id = duplicate_id.sprites[0].id
	cases.append(duplicate_id)
	var short_sheet := published.duplicate(true)
	short_sheet.sprites.pop_back()
	cases.append(short_sheet)
	for index in cases.size():
		# Fail after a successful load as well: no old entry may survive a reload.
		valid.overlay = published
		if not valid.load_art(): errors.append("reload fixture failed")
		valid.overlay = cases[index]
		if valid.load_art() or valid.is_ready(): errors.append("accepted malformed case %d" % index)
		if not valid.pending_reason.begins_with("ASSETS PENDING"): errors.append("missing refusal reason")
		for canonical in valid.required_ids():
			if valid.icon(canonical) != null: errors.append("stale icon after refusal: " + canonical)
	print("FACILITY_OVERRIDE_CONTRACT ", "pass" if errors.is_empty() else "fail", " malformed_cases=", cases.size(), " errors=", errors)
	quit(0 if errors.is_empty() else 1)
