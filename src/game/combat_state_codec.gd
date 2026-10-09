class_name CombatStateCodec
extends RefCounted

const SaveStoreScript = preload("res://src/persistence/save_store.gd")


static func geometry_state(origin: Vector2, direction: Vector2, size_a: float, size_b: float) -> Dictionary:
	return {
		"direction_x_milli": roundi(direction.x * 1000.0),
		"direction_y_milli": roundi(direction.y * 1000.0),
		"origin_x_milli": roundi(origin.x * 1000.0),
		"origin_y_milli": roundi(origin.y * 1000.0),
		"size_a_milli": roundi(size_a * 1000.0),
		"size_b_milli": roundi(size_b * 1000.0),
	}


static func target_shape_state(shape: Dictionary) -> Dictionary:
	var type := String(shape.get("type", ""))
	if type == "rect":
		var rect: Rect2 = shape.get("rect", Rect2())
		return {"type": type, "x_milli": roundi(rect.position.x * 1000.0), "y_milli": roundi(rect.position.y * 1000.0), "width_milli": roundi(rect.size.x * 1000.0), "height_milli": roundi(rect.size.y * 1000.0)}
	if type == "fan":
		return {"type": type, "geometry": geometry_state(shape.get("origin", Vector2.ZERO), shape.get("direction", Vector2.RIGHT), float(shape.get("radius", 0.0)), float(shape.get("half_angle", 0.0)))}
	if type == "lane":
		return {"type": type, "geometry": geometry_state(shape.get("origin", Vector2.ZERO), shape.get("direction", Vector2.RIGHT), float(shape.get("length", 0.0)), float(shape.get("width", 0.0)))}
	if type == "circle":
		var origin: Vector2 = shape.get("origin", Vector2.ZERO)
		return {"type": type, "origin_x_milli": roundi(origin.x * 1000.0), "origin_y_milli": roundi(origin.y * 1000.0), "radius_milli": roundi(float(shape.get("radius", 0.0)) * 1000.0)}
	return {}


## Converts authority snapshots into SaveStore's strict JSON domain. Vector
## values become integer millipixel records, so hashes are portable and never
## depend on Variant's debug-string formatting.
static func hash_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2:
			var vector: Vector2 = value
			return {"x_milli": roundi(vector.x * 1000.0), "y_milli": roundi(vector.y * 1000.0)}
		TYPE_VECTOR2I:
			var vector_i: Vector2i = value
			return {"x": vector_i.x, "y": vector_i.y}
		TYPE_RECT2:
			var rect: Rect2 = value
			return {
				"x_milli": roundi(rect.position.x * 1000.0),
				"y_milli": roundi(rect.position.y * 1000.0),
				"width_milli": roundi(rect.size.x * 1000.0),
				"height_milli": roundi(rect.size.y * 1000.0),
			}
		TYPE_ARRAY:
			var converted: Array = []
			for item: Variant in value:
				converted.append(hash_safe(item))
			return converted
		TYPE_DICTIONARY:
			var converted_dictionary := {}
			var original_by_text := {}
			var keys: Array[String] = []
			for original_key: Variant in value.keys():
				## Hash snapshots occasionally carry a structured diagnostic key. `String()`
				## rejects that Variant at runtime; `str()` is the engine's total textual
				## conversion and keeps this reporting serializer from changing simulation.
				var text_key := str(original_key)
				keys.append(text_key)
				original_by_text[text_key] = original_key
			keys.sort()
			for text_key: String in keys:
				converted_dictionary[text_key] = hash_safe(value[original_by_text[text_key]])
			return converted_dictionary
		_:
			return value


static func sha256_canonical(value: Variant) -> String:
	var canonical := SaveStoreScript.canonical_json(value)
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(canonical.to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()
