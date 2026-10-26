extends SceneTree
## R13's replacement art has a new palette; the original fourteen-colour life
## package keeps its existing independent regression. Pin this package's cells,
## anchors, source identity and real animation poses instead of changing it.

const Life = preload("res://src/presentation/hamlet_life_animation.gd")
const Assert := preload("res://tests/helpers/assert.gd")
const STYLE := "res://art/production/p1/hamlet_style_r13/"
const CYCLES := "res://art/production/p1/hamlet_life_r13/"
var failures: Array[String] = []

func _init() -> void:
	var old: Dictionary = _read("res://art/production/p1/hamlet_concept_v02/atlas.json")
	var current: Dictionary = _read(STYLE + "atlas.json")
	_expect(current.sprites == old.sprites, "replacement art changed native cells or foot anchors")
	for name in ["hearth", "forge", "facilities", "edges", "residents"]:
		var meta: Dictionary = current.textures[name]
		_expect(meta.path == STYLE + name + ".png", name + " still references old art")
		var texture := load(String(meta.path)) as Texture2D
		var image := texture.get_image() if texture != null else null
		_expect(image != null and image.get_size() == Vector2i(int(meta.width), int(meta.height)), name + " native dimensions")
		_expect(image != null and image.get_used_rect().has_area(), name + " empty image")
		_expect(image != null and image.get_pixel(0, 0).a == 0.0, name + " lost transparent padding")
	var life = Life.new()
	life.configure(_read(CYCLES + "atlas.json"), _read(CYCLES + "life.json"), _read(Life.EFFECT_ATLAS_PATH))
	_expect(life.life_ready(), "R13 life package did not load: " + str(life.pending_reasons()))
	for person in ["mira", "iven", "taren", "leia", "oren"]:
		var clip := String(person) + ".south.work"
		_expect(life.clip_texture_path(clip) == CYCLES + "v02/residents.png", person + " texture path")
		_expect(life.clip_frame_count(clip) == 4 and life.clip_unique_frames(clip) == 4, person + " needs four distinct work poses")
		var frame: Dictionary = life.frame_at(clip, 0.0)
		_expect(frame.get("anchor", Vector2.ZERO) == Vector2(24, 44), person + " work pose foot anchor drifted")
	for package in [STYLE, CYCLES + "v02/"]:
		var record: Dictionary = _read(package + "IMPORT.json")
		for sheet: Dictionary in record.sheets:
			_expect(FileAccess.get_sha256(package + String(sheet.file)) == String(sheet.sha256), String(sheet.file) + " differs from recorded native import")
	for failure in failures:
		printerr(failure)
	print("HAMLET_STYLE_R13_PASS" if failures.is_empty() else "HAMLET_STYLE_R13_FAIL")
	quit(0 if failures.is_empty() else 1)

func _read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _expect(ok: bool, label: String) -> void: Assert.expect(ok, label, failures)
