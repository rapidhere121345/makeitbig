extends SceneTree
## Imagegen raster import + material reference transfer. No pose synthesis.
## Every action pixel stays at its authored coordinate with its original alpha.
## New environment art uses the established transparent-margin/native-cell fit.

const PREFIX := "res://art/production/p1/combat_style_r13/"
const DOCS := "res://docs/art-production/p1-combat-style-r13/"
const OLD_COLORS := ["111820", "e9ddc3", "5b4036", "1d2731", "896043", "d3cbb5", "bb713d", "aaafab", "bd4653", "eead56", "71808a", "46515a"]
## Existing hostile-cloth shadow and approved cold snow/decal colours already
## match the target. Preserve these exact pixels, rather than colour-keying them.
const RETAINED_COLORS := ["39262e", "b0c4d8", "d3dde7", "7f94ad", "2d3943"]
const SEEDS := {
	"ranger": ["161e28", "97a9bd", "4b3c37", "2a3543", "896043", "afc0cf", "ad7849", "90a4b4", "bd4653", "eead56", "6f8598", "4c6177"],
	"melee": ["171e28", "afbccb", "4c3a34", "2a3541", "856348", "95a7b9", "a87650", "8094a7", "bd4653", "eead56", "64788c", "3f5267"],
	"charger": ["171e28", "a7b9c9", "493b36", "293646", "87684a", "8c9fb5", "a3724b", "8194a8", "bd4653", "eead56", "647b91", "3e5065"],
	"ranged": ["151d28", "a2b5c8", "453631", "253244", "886344", "92a5ba", "a2744e", "7c93aa", "bd4653", "eead56", "5e758d", "3d5067"],
	"stone": ["17212b", "b3c2d2", "514139", "2d3a49", "88613e", "a7bacb", "a66d42", "8a9daf", "bd4653", "eead56", "70869b", "4d6074"],
}

var records: Array[Dictionary] = []
var samples: Dictionary = {}
var errors: Array[String] = []
var actor_ref: Image
var stone_ref: Image
var output := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("Usage: --script pack.gd -- /absolute/new/output-directory")
		quit(2)
		return
	output = String(args[0]).simplify_path().trim_suffix("/")
	var allowed := ProjectSettings.globalize_path(PREFIX)
	if not output.is_absolute_path() or (output != allowed.trim_suffix("/") and not output.begins_with(allowed)) or DirAccess.dir_exists_absolute(output):
		printerr("Output must be a new directory inside ", allowed)
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(2)
		return
	actor_ref = _load_image(DOCS + "sources/actors_material_reference.png")
	stone_ref = _load_image(DOCS + "sources/boss_body_original.png")
	if actor_ref == null or stone_ref == null:
		_finish()
		return
	_build_palettes()
	var ground := _load_image(DOCS + "sources/ground_original.png")
	if ground != null:
		ground.resize(1024, 640, Image.INTERPOLATE_NEAREST)
		_save("ground.png", ground, DOCS + "sources/ground_original.png", "nearest native 1024x640; no colour filter")
	_pack_sheet("ruins.png", DOCS + "sources/ruins_original.png", "res://art/production/p1/scene_rework_v01/ruins.png", 4, Vector2i(128, 128))
	_pack_sheet("boss_body.png", DOCS + "sources/boss_body_original.png", "res://art/production/p1/scene_rework_v01/boss_body.png", 2, Vector2i(128, 128))
	_pack_tower()
	_transfer("ranger.png", "res://art/production/p1/ranger_actions_v01/ranger.png", ["ranger"], 816)
	_transfer("enemies.png", "res://art/production/p1/enemy_actions_v01/enemies.png", ["melee", "charger", "ranged"], 48)
	_transfer("ranger_idle.png", "res://art/production/p1/scene_rework_v01/ranger.png", ["ranger"], 48)
	_transfer("legacy_enemies.png", "res://art/production/p1/calibration_v01/enemies.png", ["melee", "charger", "ranged"], 48)
	_transfer("boss_hands.png", "res://art/production/p1/scene_rework_v01/boss_hands.png", ["stone"], 64)
	_transfer("decals.png", "res://art/production/p1/scene_rework_v01/decals.png", ["stone"], 96)
	var core_path := "res://art/production/p1/scene_rework_v01/boss_core.png"
	var core := _load_image(core_path)
	if core != null:
		_save("boss_core.png", core, core_path, "retained purple phase signal; no palette transfer")
	_manifests()
	_finish()

func _build_palettes() -> void:
	for role: String in SEEDS.keys():
		var reference := stone_ref if role == "stone" else actor_ref
		var index := ["ranger", "melee", "charger", "ranged"].find(role)
		var region := Rect2i(Vector2i.ZERO, reference.get_size())
		if role != "stone":
			var begin := index * reference.get_width() / 4
			var end := (index + 1) * reference.get_width() / 4
			region = Rect2i(begin, 0, end - begin, reference.get_height())
		var palette := {}
		var selected: Array[Dictionary] = []
		for i in OLD_COLORS.size():
			var old_hex: String = OLD_COLORS[i]
			# The player must retain the uninterrupted bone-white hood/cloak,
			# and its ink silhouette. Do not make the main body a frost-grey
			# material ramp or a bright rim around a dark body.
			if role == "ranger" and old_hex in ["e9ddc3", "d3cbb5", "111820"]:
				palette[old_hex] = Color(old_hex)
				selected.append({"old": old_hex, "new": old_hex, "protected": true, "reason": "continuous player light mass / dark silhouette"})
				continue
			# Danger red and warm event/weapon amber survive verbatim. The
			# operation applies only to raster material colours, never effects.
			if old_hex in ["bd4653", "eead56"]:
				palette[old_hex] = Color(old_hex)
				selected.append({"old": old_hex, "new": old_hex, "protected": true})
				continue
			# Cold-lit cloth/metal/snow shares the generated colossus's winter
			# illumination. Leather and copper come from the role reference.
			var cold_material := i in [0, 1, 3, 5, 7, 10, 11]
			var sample_image := stone_ref if cold_material else reference
			var sample_region := Rect2i(Vector2i.ZERO, stone_ref.get_size()) if cold_material else region
			var sample_path := "boss_body_original.png" if cold_material or role == "stone" else "actors_material_reference.png"
			var pick := _nearest_sample(sample_image, sample_region, Color(SEEDS[role][i]), palette.values())
			palette[old_hex] = pick.color
			selected.append({"old": old_hex, "new": (pick.color as Color).to_html(false), "pixel": [pick.pixel.x, pick.pixel.y], "reference": DOCS + "sources/" + sample_path})
		if role == "ranger":
			palette["rim"] = Color("e9ddc3")
			selected.append({"old": "e9ddc3 on alpha boundary", "new": "e9ddc3", "protected": true, "reason": "same continuous player light mass, not a separate rim ramp"})
		else:
			var rim := _nearest_sample(stone_ref, Rect2i(Vector2i.ZERO, stone_ref.get_size()), Color("d4dfeb"), palette.values())
			palette["rim"] = rim.color
			selected.append({"old": "e9ddc3 on alpha boundary", "new": (rim.color as Color).to_html(false), "pixel": [rim.pixel.x, rim.pixel.y], "reference": DOCS + "sources/boss_body_original.png"})
		samples[role] = {"reference": DOCS + "sources/" + ("boss_body_original.png" if role == "stone" else "actors_material_reference.png"), "region": [region.position.x, region.position.y, region.size.x, region.size.y], "colors": selected, "palette": palette}

func _nearest_sample(reference: Image, region: Rect2i, seed: Color, used: Array) -> Dictionary:
	var best := INF
	var color := seed
	var pixel := Vector2i(-1, -1)
	for y in range(region.position.y, region.end.y, 2):
		for x in range(region.position.x, region.end.x, 2):
			var candidate := reference.get_pixel(x, y)
			if candidate.a < 0.95:
				continue
			candidate.a = 1.0
			if used.has(candidate):
				continue
			var distance := Vector3(candidate.r - seed.r, candidate.g - seed.g, candidate.b - seed.b).length_squared()
			if distance < best:
				best = distance
				color = candidate
				pixel = Vector2i(x, y)
	if pixel.x < 0:
		errors.append("material reference has no opaque sample for " + seed.to_html(false))
	return {"color": color, "pixel": pixel}

func _transfer(file: String, source_path: String, roles: Array, row_height: int) -> void:
	var original := _load_image(source_path)
	if original == null:
		return
	var result := original.duplicate()
	var changed := 0
	var alpha_mismatches := 0
	var unmapped := {}
	for y in original.get_height():
		var role: String = roles[mini(roles.size() - 1, y / row_height)]
		var palette: Dictionary = samples[role].palette
		for x in original.get_width():
			var old := original.get_pixel(x, y)
			if old.a <= 0:
				continue
			var key := old.to_html(false)
			if RETAINED_COLORS.has(key):
				continue
			if not palette.has(key):
				unmapped[key] = true
				continue
			var new_color: Color = palette[key]
			if key == "e9ddc3" and _alpha_edge(original, Vector2i(x, y)):
				new_color = palette.rim
			new_color.a = old.a
			result.set_pixel(x, y, new_color)
			if old != new_color:
				changed += 1
			if result.get_pixel(x, y).a != old.a:
				alpha_mismatches += 1
	if alpha_mismatches > 0 or not unmapped.is_empty():
		errors.append("%s palette incomplete or alpha changed: %s" % [file, str(unmapped.keys())])
	_save(file, result, source_path, "generated-reference material colours; fixed per-pixel silhouette; protected player bone-white light mass, hostile red and weapon amber")
	records[-1]["changed_pixels"] = changed
	records[-1]["alpha_mismatches"] = alpha_mismatches
	records[-1]["unmapped_colors"] = unmapped.keys()
	records[-1]["material_roles"] = roles

func _alpha_edge(original: Image, point: Vector2i) -> bool:
	for delta: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbor := point + delta
		if not Rect2i(Vector2i.ZERO, original.get_size()).has_point(neighbor) or original.get_pixelv(neighbor).a < 0.5:
			return true
	return false

func _pack_sheet(file: String, source_path: String, template_path: String, columns: int, cell: Vector2i) -> void:
	var original := _load_image(source_path)
	var template := _load_image(template_path)
	if original == null or template == null:
		return
	var sheet := Image.create(cell.x * columns, cell.y, false, Image.FORMAT_RGBA8)
	var cells: Array[Dictionary] = []
	for i in columns:
		var begin := i * original.get_width() / columns
		var end := (i + 1) * original.get_width() / columns
		var tile := original.get_region(Rect2i(begin, 0, end - begin, original.get_height()))
		var bounds := _solid_bounds(tile)
		var target := template.get_region(Rect2i(i * cell.x, 0, cell.x, cell.y)).get_used_rect()
		var fitted := _fit(tile, bounds, target)
		if fitted.is_empty():
			continue
		sheet.blit_rect(fitted.image, Rect2i(Vector2i.ZERO, fitted.image.get_size()), Vector2i(i * cell.x, 0) + fitted.position)
		cells.append({"cell": i, "source": [begin + bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y], "destination": [i * cell.x + fitted.position.x, fitted.position.y, fitted.image.get_width(), fitted.image.get_height()]})
	_save(file, sheet, source_path, "opaque-body margin crop, native nearest fit inside old art bounds; generated alpha retained")
	records[-1]["cells"] = cells

func _pack_tower() -> void:
	var source_path := DOCS + "sources/tower_original.png"
	var original := _load_image(source_path)
	if original == null:
		return
	var bounds := _solid_bounds(original)
	var fitted := _fit(original, bounds, Rect2i(4, 4, 120, 180))
	if fitted.is_empty():
		return
	var tower := Image.create(256, 192, false, Image.FORMAT_RGBA8)
	for column in 2:
		tower.blit_rect(fitted.image, Rect2i(Vector2i.ZERO, fitted.image.get_size()), Vector2i(column * 128, 0) + fitted.position)
	_save("tower.png", tower, source_path, "one complete tower in both original cells; existing keep_rows split 0..148 / 148..192")
	records[-1]["source_crop"] = [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]
	records[-1]["keep_rows"] = [[148, 192], [0, 148]]

func _fit(original: Image, bounds: Rect2i, target: Rect2i) -> Dictionary:
	if not bounds.has_area() or not target.has_area():
		errors.append("empty generated body / target cell")
		return {}
	var ratio := minf(float(target.size.x) / bounds.size.x, float(target.size.y) / bounds.size.y)
	var size := Vector2i(maxi(1, int(bounds.size.x * ratio)), maxi(1, int(bounds.size.y * ratio)))
	var fitted := original.get_region(bounds)
	fitted.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	return {"image": fitted, "position": Vector2i(target.position.x + (target.size.x - size.x) / 2, target.end.y - size.y)}

func _solid_bounds(original: Image) -> Rect2i:
	var low := original.get_size()
	var high := Vector2i(-1, -1)
	for y in original.get_height():
		for x in original.get_width():
			if original.get_pixel(x, y).a < 0.5:
				continue
			low = Vector2i(mini(low.x, x), mini(low.y, y))
			high = Vector2i(maxi(high.x, x), maxi(high.y, y))
	return Rect2i(low, high - low + Vector2i.ONE) if high.x >= 0 else Rect2i()

func _load_image(path: String) -> Image:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null:
		errors.append("cannot load " + path)
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image

func _save(file: String, image: Image, source: String, operation: String) -> void:
	var destination := output.path_join(file)
	if image.save_png(destination) != OK:
		errors.append("cannot save " + destination)
	records.append({"file": file, "source": source, "source_sha256": FileAccess.get_sha256(source), "sha256": FileAccess.get_sha256(destination), "size": [image.get_width(), image.get_height()], "operation": operation})

func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _write_json(file: String, value: Dictionary) -> void:
	var handle := FileAccess.open(output.path_join(file), FileAccess.WRITE)
	if handle == null:
		errors.append("cannot write " + file)
		return
	handle.store_string(JSON.stringify(value, "\t") + "\n")

func _manifests() -> void:
	var resource_prefix := ProjectSettings.localize_path(output).trim_suffix("/") + "/"
	for spec: Array in [["ranger", "ranger_actions_v01", "ranger.png"], ["enemy", "enemy_actions_v01", "enemies.png"]]:
		var atlas := _json("res://art/production/p1/" + spec[1] + "/atlas.json")
		var key := "ranger" if spec[0] == "ranger" else "enemies"
		var binding: Dictionary = atlas.textures[key].duplicate(true)
		binding.path = resource_prefix + spec[2]
		atlas["render_textures"] = {key: binding}
		atlas["material_skin"] = {"version": "r13", "source_atlas": "res://art/production/p1/" + spec[1] + "/atlas.json", "operation": "generated-reference material transfer; all action data unchanged"}
		_write_json(spec[0] + "_atlas.json", atlas)
	var scene := _json("res://art/production/p1/scene_rework_v01/atlas.json")
	for key: String in scene.textures.keys():
		scene.textures[key].path = resource_prefix + ("ranger_idle.png" if key == "ranger" else key + ".png")
	scene["source_atlas"] = "res://art/production/p1/scene_rework_v01/atlas.json"
	_write_json("scene_atlas.json", scene)
	var legacy := _json("res://art/production/p1/calibration_v01/atlas.json")
	# Keep only the reader's exact tower + four-state enemy contract, avoiding
	# unused legacy sheets and conflicting scene keys.
	var legacy_sprites := {}
	for key: String in legacy.sprites.keys():
		if key.begins_with("tower.") or key.begins_with("enemy."):
			legacy_sprites[key] = legacy.sprites[key]
	var legacy_textures := {"tower": legacy.textures.tower.duplicate(true), "enemies": legacy.textures.enemies.duplicate(true)}
	legacy_textures.tower.path = resource_prefix + "tower.png"
	legacy_textures.enemies.path = resource_prefix + "legacy_enemies.png"
	_write_json("legacy_atlas.json", {"schema_version": 1, "native_view": [640, 360], "textures": legacy_textures, "sprites": legacy_sprites, "source_atlas": "res://art/production/p1/calibration_v01/atlas.json"})
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://art/production/p1/scene_rework_v01/layout.json"), output.path_join("layout.json"))

func _finish() -> void:
	var public_samples := samples.duplicate(true)
	for role: String in public_samples.keys():
		public_samples[role].erase("palette")
	_write_json("IMPORT.json", {"status": "pass" if errors.is_empty() else "fail", "errors": errors, "generator": "built-in image_gen.imagegen", "sheets": records, "material_samples": public_samples, "bounds": "new generated environmental drawings; unchanged actor silhouettes/alpha/timings/sockets; existing core identity retained"})
	for error in errors:
		printerr(error)
	print("COMBAT_STYLE_R13_PACK_", "PASS" if errors.is_empty() else "FAIL", " sheets=", records.size())
	quit(0 if errors.is_empty() else 1)
