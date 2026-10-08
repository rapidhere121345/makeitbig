class_name HearthReturnView
extends TextureRect
## Dedicated early-return scene based on v0.9 story panel 02, not final E03.
## The bench stays away from the cold door, Mira is still working, Leia records.
## No repair/shift-handover flag is inferred from Auto graduation.
const Ranger = preload("res://src/presentation/ranger_animation.gd")
const Life = preload("res://src/presentation/hamlet_life_animation.gd")
const AtmosphereScript = preload("res://src/presentation/scene_atmosphere.gd")
const AtmosphereLayerScript = preload("res://src/presentation/scene_atmosphere_layer.gd")
const ROOT := "res://art/production/p1/hearth_return_v01/"
const BACKGROUND_PATH := ROOT + "background.png"
const NATIVE_SIZE := Vector2i(640, 360)
const PLACEMENTS := [
	{"id":"return.mira", "feet":Vector2i(296,189)},
	{"id":"return.bench", "feet":Vector2i(235,225)},
	{"id":"return.leia", "feet":Vector2i(237,254)},
]
const RANGER_FEET := Vector2i(124,293)
const SOCKETS := [
	{"id":"HearthFire", "clip":"life.fire", "feet":Vector2i(189,191)},
	{"id":"RepairSteam", "clip":"life.steam", "feet":Vector2i(315,151)},
]
const ATMOSPHERE_PRESET := "hearth"
const ATMOSPHERE_BOUNDS := Rect2(Vector2.ZERO, Vector2(NATIVE_SIZE))
const HEARTH_LIGHT_FEET := Vector2(189.0, 187.0)
var _errors: Array[String] = []
var _atmosphere_layer: AtmosphereLayerScript
var _layers: Array[Dictionary] = []
var _effects: Array[Dictionary] = []
var _life = Life.new()
var _clock := 0.0
var _frozen := false
var _loaded := false

func _ready() -> void:
	load_scene()

func load_scene() -> bool:
	if _loaded:
		return _errors.is_empty()
	_loaded = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	custom_minimum_size = Vector2(NATIVE_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var atlas := _read_atlas()
	var backgrounds: Dictionary = atlas.get("sprites", {})
	var textures: Dictionary = atlas.get("textures", {})
	var background := _texture(textures.get("background", {}))
	if background == null or Vector2i(background.get_size()) != NATIVE_SIZE:
		_errors.append("dedicated background missing or wrong size")
		return false
	texture = background
	set_meta("source_path", BACKGROUND_PATH)
	_atmosphere_layer = AtmosphereLayerScript.new()
	_atmosphere_layer.name = "AtmosphereFore"
	_atmosphere_layer.preset = ATMOSPHERE_PRESET
	_atmosphere_layer.bounds = ATMOSPHERE_BOUNDS
	_atmosphere_layer.front = true
	_atmosphere_layer.include_ground = true
	_atmosphere_layer.warm_lights = [AtmosphereScript.warm_light(HEARTH_LIGHT_FEET, 43.0, 0.18)]
	# Parent TextureRect is the sole background. Draw atmosphere above it,
	# then published sprites/effects at z=1; do not cover them with a plate.
	_atmosphere_layer.z_index = 0
	add_child(_atmosphere_layer)
	for item: Dictionary in PLACEMENTS:
		var id := String(item.id)
		var spec: Dictionary = backgrounds.get(id, {})
		var sheet := _texture(textures.get(String(spec.get("texture", "")), {}))
		var rect := _rect(spec.get("rect", []))
		var anchor := _point(spec.get("anchor", []))
		if sheet == null or rect.size.x <= 0 or not Rect2i(Vector2i.ZERO,Vector2i(sheet.get_size())).encloses(rect):
			_errors.append("invalid sprite " + id)
			continue
		var node := _sprite(id, sheet, rect, Vector2i(item.feet), anchor)
		_layers.append({"id":id,"node":node,"rect":rect,"feet":item.feet,"anchor":anchor})
	var ranger = Ranger.new()
	var frame: Dictionary = ranger.frame_for("ranger.east.idle",0)
	if not ranger.has_real_art() or frame.is_empty():
		_errors.append("published ranger idle unavailable")
	else:
		var node := _sprite("ReturnRanger",frame.texture,frame.rect,RANGER_FEET,frame.anchor)
		_layers.append({"id":"ranger.east.idle","node":node,"rect":frame.rect,"feet":RANGER_FEET,"anchor":frame.anchor})
	if not _life.load_default_assets():
		_errors.append_array(_life.pending_reasons())
	else:
		for socket: Dictionary in SOCKETS:
			var entry: Dictionary = _life.frame_at(socket.clip,0.0)
			if entry.is_empty():
				_errors.append("published effect unavailable " + String(socket.clip))
				continue
			var node := _sprite(socket.id,entry.texture,entry.rect,socket.feet,entry.anchor)
			_effects.append({"node":node,"clip":socket.clip,"feet":socket.feet,"frame":0})
	set_process(_errors.is_empty())
	_update_effects()
	return _errors.is_empty()

func _sprite(id: String, sheet: Texture2D, rect: Rect2i, feet: Vector2i, anchor: Vector2i) -> Sprite2D:
	var node := Sprite2D.new()
	node.name = id.replace(".","_")
	node.texture = sheet
	node.centered = false
	node.region_enabled = true
	node.region_filter_clip_enabled = true
	node.region_rect = Rect2(rect)
	node.position = Vector2(feet-anchor)
	node.z_index = 1
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(node)
	return node

func _process(delta: float) -> void:
	if not _frozen:
		_clock = fposmod(_clock + maxf(0.0,delta),2.0)
		_update_effects()

func set_review_time(seconds: float) -> void:
	_frozen = true
	_clock = maxf(0.0,seconds)
	_update_effects()

func _update_effects() -> void:
	for item: Dictionary in _effects:
		var frame: Dictionary = _life.frame_at(item.clip,_clock)
		if frame.is_empty():
			continue
		var node: Sprite2D = item.node
		node.region_rect = Rect2(frame.rect)
		node.position = Vector2(Vector2i(item.feet)-Vector2i(frame.anchor))
		item.frame = frame.index

func scene_report() -> Dictionary:
	var layers: Array[Dictionary] = []
	for item: Dictionary in _layers:
		layers.append({"id":item.id,"feet":item.feet,"anchor":item.anchor,"rect":item.rect})
	var effects: Array[Dictionary] = []
	for item: Dictionary in _effects:
		effects.append({"id":str(item.node.name),"clip":item.clip,"frame":item.frame,"feet":item.feet})
	return {"ready":_loaded and _errors.is_empty(),"errors":_errors.duplicate(),"native_size":NATIVE_SIZE,
		"source_path":BACKGROUND_PATH,"layers":layers,"effects":effects,"time":_clock,
		"atmosphere":_atmosphere_layer.atmosphere_report() if _atmosphere_layer != null else {},
		"story_state":"early_return_unrepaired","final_e03_repair":false,"loop_seconds":2.0}

func _read_atlas() -> Dictionary:
	var file := FileAccess.open(ROOT+"atlas.json",FileAccess.READ)
	if file == null:
		_errors.append("return atlas missing")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or parsed.get("schema_version",0) != 1:
		_errors.append("return atlas invalid")
		return {}
	return parsed

func _texture(meta: Dictionary) -> Texture2D:
	var path := String(meta.get("path",""))
	if not path.begins_with(ROOT):
		return null
	var declared := Vector2i(int(meta.get("width",0)),int(meta.get("height",0)))
	return _life.load_texture_at(path,declared)

func _rect(value: Array) -> Rect2i:
	if value.size()!=4:
		return Rect2i()
	return Rect2i(int(value[0]),int(value[1]),int(value[2]),int(value[3]))

func _point(value: Array) -> Vector2i:
	return Vector2i(int(value[0]),int(value[1])) if value.size()==2 else Vector2i.ZERO
