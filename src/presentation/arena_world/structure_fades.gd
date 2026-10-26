extends RefCounted
## Whole-object structure fades extracted from ArenaWorldView: the eased paired
## reveal state per placed piece and the ShaderMaterial each one draws through.
## The generated-world pack records live on GeneratedWorld; the view supplies
## them, the hero sort entry and the detection rects.

const PairedReveal := preload("res://src/presentation/occlusion/paired_reveal_controller.gd")
const SortRelation = preload("res://src/presentation/occlusion_query.gd")

var _structure_fades: Dictionary = {}
var _paired_materials: Dictionary = {}


func clear_materials() -> void:
	_paired_materials.clear()


## Immediate-mode structure bands share the town controller's state machine.
## Collision remains authored in room scenes; these boxes only affect drawing.
func reset_structure_fades() -> void:
	_structure_fades.clear()
	for material: ShaderMaterial in _paired_materials.values():
		material.set_shader_parameter("reveal_weight", 0.0)


func _structure_key(sprite_id: String, feet: Vector2) -> String:
	return sprite_id + "@" + str(feet)


func structure_fade_state(sprite_id: String, feet: Vector2) -> Dictionary:
	return (_structure_fades.get(_structure_key(sprite_id, feet), {}) as Dictionary).duplicate(true)


func structure_fade_report() -> Dictionary:
	return _structure_fades.duplicate(true)


## The material one placed whole-object piece draws through, or null before
## advance_structure_fades has created it. The presenter attaches it to that
## drawable's own sort view.
func paired_reveal_material(sprite_id: String, feet: Vector2) -> Material:
	return _paired_materials.get(_structure_key(sprite_id, feet), null)


func _paired_material(view: ArenaWorldProjection, key: String, sprite_id: String) -> ShaderMaterial:
	var existing: Variant = _paired_materials.get(key, null)
	if existing is ShaderMaterial:
		return existing
	var record: Dictionary = view._generated.sprites.get(sprite_id, {})
	var material := ShaderMaterial.new()
	material.shader = PairedReveal.RevealShader
	material.set_shader_parameter("revealed_texture", record.get("variant", null))
	material.set_shader_parameter("reveal_weight", 0.0)
	_paired_materials[key] = material
	return material


func advance_structure_fades(view: ArenaWorldProjection, drawables: Array, subjects: Array, delta: float) -> void:
	var next: Dictionary = {}
	for drawable: Dictionary in drawables:
		if drawable.kind not in ["structure", "tower"]:
			continue
		var id := "tower" if drawable.kind == "tower" else String(drawable.sprite)
		var feet: Vector2 = drawable.world
		var key := _structure_key(id, feet)
		if not view._generated.sprites.has(id):
			continue
		## Whole-object pair: one authored detection rect, one eased
		## reveal weight, no band split. The rect stays report-only
		## geometry; collision remains authored in the room scene.
		var rect := view.paired_detection_rect_world(id, feet)
		var state := PairedReveal.advance_state(rect, drawable, subjects, _structure_fades.get(key, {}), delta)
		var material := _paired_material(view, key, id)
		material.set_shader_parameter("reveal_weight", state.weight)
		state.merge({"policy": PairedReveal.POLICY, "sprite_id": id, "feet_world": feet,
			"part": drawable.duplicate(), "volume": rect, "material": material,
			"alpha": lerpf(1.0, float(view._generated.sprites[id].variant_max_alpha), float(state.weight)),
			"variant_max_alpha": float(view._generated.sprites[id].variant_max_alpha),
			"transition_seconds": PairedReveal.TRANSITION_SECONDS})
		next[key] = state
	_structure_fades = next


## Upper-band report. Solid-base clearance belongs to the authored movement
## contract and rendered acceptance, not this presentation-only overlap query.
func hero_cover_report(view: ArenaWorldProjection, hero_world_point: Vector2) -> Dictionary:
	var in_front: Array[String] = []
	var faded: Array[String] = []
	var full_covers: Array[String] = []
	var box := view.hero_cell_world(hero_world_point)
	for state: Dictionary in _structure_fades.values():
		if not SortRelation.is_front(state.part, view._hero_sort_entry(hero_world_point)) or not (state.volume as Rect2).intersects(box):
			continue
		var id := String(state.sprite_id)
		in_front.append(id)
		if float(state.alpha) < 1.0:
			faded.append(id)
		elif (state.volume as Rect2).encloses(box):
			full_covers.append(id)
	return {"hero_cell": box, "in_front": in_front, "faded": faded,
		"unfaded_full_covers": full_covers, "hero_visible": full_covers.is_empty(),
		"scope": "upper structure bands and whole-object paired rects; solid-base clearance is a movement contract"}
