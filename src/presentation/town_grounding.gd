extends Node2D
## Mounted visual receivers. Lives above all Ground art (including bridge decks)
## and below dressing/SortRoot. Detached actor feet, never a physics writer.
const Effects := preload("res://src/presentation/grounding_effects.gd")
var _pieces: Array[Dictionary] = []
var _lights: Array[Dictionary] = []
var _actors: Array[Dictionary] = []
var _contacts: ActorContacts

class ActorContacts extends Node2D:
	const ContactEffects := preload("res://src/presentation/grounding_effects.gd")
	var actors: Array[Dictionary] = []
	func _draw() -> void:
		for actor: Dictionary in actors:
			ContactEffects.draw_contact(self, actor.feet, Vector2(21, 9), 0.60)

func configure(sort_root: Node2D) -> void:
	if _contacts == null:
		_contacts = ActorContacts.new()
		_contacts.name = "ActorContacts"
		add_child(_contacts)
	_pieces.clear()
	_lights.clear()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for node: Node in sort_root.get_children():
		if not node is Sprite2D or not node.has_meta("environment_asset_id"):
			continue
		var sprite := node as Sprite2D
		if sprite.texture == null:
			continue
		var rect := sprite.get_rect()
		var family := String(sprite.get_meta("environment_asset_id")).get_file()
		var row := {"id": String(sprite.get_meta("binding_id", sprite.name)), "node": weakref(sprite),
			"feet": sprite.position, "texture": sprite.texture, "anchor": -rect.position, "family": family}
		Effects.base_stamp(sprite.texture, Rect2(Vector2.ZERO, sprite.texture.get_size()), row.anchor)
		_pieces.append(row)
		var radius := 0.0
		var strength := 0.20
		var color := Effects.AMBER
		match family:
			"lamp": radius = 46.0
			"hearth", "forge", "forge_west": radius = 68.0; strength = 0.25
			"loadout", "loadout_east", "house_east", "house_west": radius = 43.0; strength = 0.14
			"proxy": radius = 38.0; color = Effects.ARCANE; strength = 0.13
		if radius > 0.0:
			_lights.append({"id": row.id, "position": sprite.position, "radius": radius, "color": color, "strength": strength})
	# RGB self modulation does not touch modulate.a or the paired-reveal shader.
	for row: Dictionary in _pieces:
		var sprite: Sprite2D = row.node.get_ref()
		sprite.self_modulate = Effects.illumination(row.feet, _lights)
	queue_redraw()

func sync_actors(rows: Array[Dictionary]) -> void:
	if rows == _actors:
		return
	_actors = rows.duplicate(true)
	if _contacts != null:
		_contacts.actors = _actors
		_contacts.queue_redraw()

func illumination_at(feet: Vector2) -> Color:
	return Effects.illumination(feet, _lights)

func _draw() -> void:
	for light: Dictionary in _lights:
		Effects.draw_pool(self, light.position, light.radius, light.color, light.strength)
	for row: Dictionary in _pieces:
		Effects.draw_base(self, row.texture, Rect2(Vector2.ZERO, row.texture.get_size()), row.anchor, row.feet)
	# Godot retains these static draw commands while only the child contact
	# layer redraws for moving actors. Camera transforms move both together.

func report() -> Dictionary:
	return {"presentation_only": true, "layer": "GroundEffects", "base_count": _pieces.size(),
		"lights": _lights.duplicate(true), "actors": _actors.duplicate(true), "contact_size": Vector2(21, 9),
		"actor_alpha": 1.0, "texture_mutations": 0,
		"rgb_tint_owner": "presenter_after_native_contract_validation"}
