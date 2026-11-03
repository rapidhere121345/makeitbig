extends RefCounted

## Pure validation of a native room scene and its spatial manifest. Every
## function is static and reads only its arguments; SceneRuntime calls it
## while mounting a room.

const RoomDefinitionScript = preload("res://src/runtime/world/room_definition.gd")
const WorldAssetScript = preload("res://src/runtime/world/world_asset.gd")
const SpatialManifestScript = preload("res://src/runtime/world/spatial_manifest.gd")
const WorldPresenterScript = preload("res://src/runtime/world/world_presenter.gd")
const ArenaGeometryScript = preload("res://src/core/geometry/arena_geometry.gd")
const StaticSpatialIndexScript = preload("res://src/runtime/spatial/static_spatial_index.gd")


static func validate_native_scene(scene_value: Variant, asset_snapshot: Dictionary) -> Dictionary:
	if not scene_value is PackedScene:
		return {"ok": false, "error": "world_scene_invalid"}
	var scene: PackedScene = scene_value as PackedScene
	var instance := scene.instantiate()
	if instance == null:
		return {"ok": false, "error": "world_scene_instantiate_failed"}
	if not instance is Node2D or (instance as Node2D).transform != Transform2D.IDENTITY:
		instance.free()
		return {"ok": false, "error": "native_scene_root_invalid"}
	# Two explicit native authoring locations: a declarative scene root, or the
	# RoomAsset component of a gameplay host. Neither is a legacy adapter.
	var author_root: Node = instance if instance.has_method("validate_contract") else instance.get_node_or_null("RoomAsset")
	if author_root == null or not author_root.has_method("validate_contract"):
		instance.free()
		return {"ok": false, "error": "native_scene_contract_missing"}
	var contract_value: Variant = author_root.call("validate_contract", {
		"gameplay_source": String(asset_snapshot["manifest_path"]).get_file(),
	})
	if not contract_value is Dictionary or not bool((contract_value as Dictionary).get("ok", false)):
		var errors: Variant = (contract_value as Dictionary).get("errors", []) if contract_value is Dictionary else []
		instance.free()
		return {"ok": false, "error": "native_scene_contract_invalid", "errors": errors}
	var snapshot_value: Variant = (contract_value as Dictionary).get("value", null)
	if not snapshot_value is Dictionary:
		instance.free()
		return {"ok": false, "error": "native_scene_contract_invalid"}
	var snapshot: Dictionary = (snapshot_value as Dictionary).duplicate(true)
	var error := validate_native_bindings(author_root, snapshot, asset_snapshot)
	if not error.is_empty():
		instance.free()
		return {"ok": false, "error": error}
	snapshot["native_contract_path"] = String(instance.get_path_to(author_root))
	instance.free()
	return {"ok": true, "error": "", "value": snapshot}


static func validate_native_bindings(author_root: Node, contract: Dictionary, asset_snapshot: Dictionary) -> String:
	for key: String in ["scene_id", "world_asset_id", "gameplay_source", "presentation_source", "movement_binding"]:
		if not contract.get(key, null) is String or String(contract[key]).strip_edges().is_empty():
			return "native_scene_contract_missing:%s" % key
	if String(contract["gameplay_source"]) != String(asset_snapshot["manifest_path"]).get_file():
		return "native_scene_gameplay_source_mismatch"
	var bounds: Variant = contract.get("authored_bounds", null)
	if not bounds is Rect2 or not (bounds as Rect2).position.is_finite() or not (bounds as Rect2).size.is_finite() or (bounds as Rect2).size.x <= 0.0 or (bounds as Rect2).size.y <= 0.0:
		return "invalid_authored_bounds"
	var groups: Variant = contract.get("groups", null)
	if not groups is Array:
		return "native_scene_groups_invalid"
	for group_name: String in WorldPresenterScript.LAYER_NAMES:
		var group := author_root.get_node_or_null(group_name) as Node2D
		if not (groups as Array).has(group_name) or group == null or group.transform != Transform2D.IDENTITY:
			return "native_scene_group_invalid:%s" % group_name
		if group_name == "SortRoot" and not group.y_sort_enabled:
			return "native_scene_sort_root_invalid"
	var bindings: Variant = contract.get("bindings", null)
	if not bindings is Dictionary:
		return "native_scene_bindings_invalid"
	var seen: Dictionary = {}
	for path: Variant in bindings:
		var id: Variant = bindings[path]
		if not path is String or not id is String or String(id).strip_edges().is_empty() or seen.has(id):
			return "native_scene_bindings_invalid"
		var node := author_root.get_node_or_null(String(path))
		if node == null or node.get_meta("binding_id", null) != id:
			return "native_scene_binding_mismatch:%s" % String(path)
		seen[id] = true
	if not seen.has(contract["movement_binding"]):
		return "native_movement_binding_missing"
	return ""


static func validate_room_identity(definition: RoomDefinition, native_contract: Dictionary) -> Dictionary:
	var identity: Dictionary = definition.snapshot()
	if identity["world_asset_id"] != native_contract["world_asset_id"]:
		return {"ok": false, "error": "room_identity_mismatch", "expected": identity["world_asset_id"], "actual": native_contract["world_asset_id"]}
	return {"ok": true, "error": ""}


static func validate_spatial_contract(spatial: SpatialManifest, native_contract: Dictionary) -> Dictionary:
	var source: Variant = native_contract.get("spatial_manifest", null)
	var derived: SpatialManifest = coerce_resource(source, SpatialManifestScript) as SpatialManifest
	if derived == null or not derived.is_valid():
		return {"ok": false, "error": "invalid_native_spatial_manifest"}
	# Compare every semantic field, including channels, traversal profiles,
	# portals, sockets and metadata. A manifest is a derived artifact, not an
	# alternative authoring source that can replace native geometry.
	if spatial.digest_input() != derived.digest_input():
		return {"ok": false, "error": "native_manifest_mismatch"}
	var manifest_snapshot: Dictionary = derived.snapshot()
	var coordinate: Dictionary = manifest_snapshot["coordinate_convention"]
	if not coordinate.get("units", null) is String or String(coordinate["units"]).strip_edges().is_empty() or not coordinate.get("up", null) is String or String(coordinate["up"]).strip_edges().is_empty():
		return {"ok": false, "error": "invalid_coordinate_convention"}
	var scale: Variant = coordinate.get("scale", null)
	if typeof(scale) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(scale)) or float(scale) <= 0.0:
		return {"ok": false, "error": "invalid_coordinate_convention"}
	var movement_id := String(native_contract["movement_binding"])
	var movement_bindings: Array = derived.movement_bindings()
	var canonical_movement: Array[Dictionary] = []
	for binding: Dictionary in movement_bindings:
		if String(binding.get("binding_id", "")) == movement_id:
			canonical_movement.append(binding)
	if canonical_movement.size() != 1:
		return {"ok": false, "error": "movement_binding_contract_invalid"}
	var normalized_boundary := ArenaGeometryScript.normalize_native_boundary(canonical_movement[0].get("geometry", null))
	if not bool(normalized_boundary.get("ok", false)):
		return {"ok": false, "error": "invalid_authored_geometry:%s" % String(normalized_boundary.get("error", "unknown"))}
	var static_blockers: Array[Dictionary] = []
	var authored_ids: Array = (native_contract["bindings"] as Dictionary).values()
	for binding: Dictionary in movement_bindings:
		var id := String(binding.get("binding_id", ""))
		if id == movement_id:
			if binding.get("kind", "") == "static_blocker":
				return {"ok": false, "error": "movement_binding_contract_invalid"}
			continue
		if not authored_ids.has(id) or binding.get("kind", "") != "static_blocker":
			return {"ok": false, "error": "static_binding_contract_invalid"}
		var solid := ArenaGeometryScript.normalize_native_static_geometry(binding.get("geometry", null))
		if not bool(solid.get("ok", false)):
			return {"ok": false, "error": "invalid_static_geometry"}
		static_blockers.append({"binding_id": id, "points": solid["value"]["points"]})
	var spawn_sockets: Array[Dictionary] = []
	var native_binding_ids: Array = (native_contract["bindings"] as Dictionary).values()
	for socket: Dictionary in manifest_snapshot["spawn_interaction_exit_sockets"]:
		var position: Variant = socket.get("position", null)
		if not position is Array or (position as Array).size() != 2:
			return {"ok": false, "error": "invalid_socket_position"}
		for component: Variant in position:
			if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
				return {"ok": false, "error": "invalid_socket_position"}
		var binding_id := String(socket.get("socket_id", ""))
		if not native_binding_ids.has(binding_id):
			return {"ok": false, "error": "native_socket_binding_missing:%s" % binding_id}
		if String(socket["kind"]) == "spawn":
			spawn_sockets.append({"binding": binding_id, "position": Vector2(float(position[0]), float(position[1]))})
	return {"ok": true, "error": "", "boundary": normalized_boundary["value"], "static_blockers": static_blockers, "spawn_sockets": spawn_sockets}


static func static_index_payload(spatial: Variant, asset_id: String, movement_binding_id: String = "") -> Dictionary:
	var manifest_snapshot: Dictionary = spatial.snapshot()
	var surfaces: Array[Dictionary] = []
	for binding: Dictionary in manifest_snapshot.get("stable_bindings", []):
		var geometry: Variant = binding.get("geometry", null)
		if geometry == null:
			continue
		var shape := manifest_shape(geometry)
		if shape.is_empty():
			continue
		var channels: Array[StringName] = []
		var declared: Variant = binding.get("channels", {})
		if declared is Dictionary:
			for channel: String in ["movement", "navigation", "vision", "projectile", "attack", "hurtbox", "occlusion"]:
				if bool((declared as Dictionary).get(channel, false)):
					channels.append(StringName(channel))
		if channels.is_empty():
			continue
		# Movement boundary is a containment boundary, not an obstacle surface.
		# Its geometry is passed separately below; adding it as a surface would
		# invert the ring/rect semantics.
		if String(binding.get("binding_id", "")) == movement_binding_id:
			continue
		surfaces.append({
			"id": String(binding.get("binding_id", binding.get("stable_id", ""))),
			"shape": shape,
			"channels": channels,
			"opaque": true,
			"vision_mode": "opaque",
			"attenuation": 0.0,
			"occlusion_rank": 0,
		})
	# Town's native derivative stores triangulated collision pieces in gameplay
	# metadata. They are authored movement surfaces even though the corresponding
	# stable bindings are presentation/identity entries without geometry.
	var gameplay_metadata: Variant = manifest_snapshot.get("gameplay_spatial_metadata", {})
	if gameplay_metadata is Dictionary:
		for geometry: Variant in (gameplay_metadata as Dictionary).get("static_geometry", []):
			if not geometry is Dictionary:
				continue
			var entry: Dictionary = geometry
			var shape := manifest_shape(entry)
			var geometry_id := String(entry.get("id", "")).strip_edges()
			if geometry_id.is_empty() or shape.is_empty():
				continue
			surfaces.append({
				"id": geometry_id,
				"shape": shape,
				"channels": [StringName("movement")],
				"opaque": true,
				"vision_mode": "opaque",
				"attenuation": 0.0,
				"occlusion_rank": 0,
			})
	var boundary_source: Dictionary = spatial.movement_geometry()
	var boundary := manifest_boundary(boundary_source)
	return {
		"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION,
		"asset_id": asset_id,
		"surfaces": surfaces,
		"movement_boundary": boundary,
	}


static func manifest_shape(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var source: Dictionary = value
	var kind := String(source.get("type", source.get("kind", "")))
	match kind:
		"rect":
			var raw_rect: Variant = source.get("rect", null)
			if raw_rect is Array and (raw_rect as Array).size() == 4:
				return {"kind": "rect", "rect": Rect2(float(raw_rect[0]), float(raw_rect[1]), float(raw_rect[2]), float(raw_rect[3]))}
			if raw_rect is Rect2:
				return {"kind": "rect", "rect": raw_rect}
		"polygon":
			var raw_points: Variant = source.get("points", [])
			if raw_points is Array:
				var points := PackedVector2Array()
				for raw_point: Variant in raw_points:
					if raw_point is Array and (raw_point as Array).size() == 2:
						points.append(Vector2(float(raw_point[0]), float(raw_point[1])))
				if points.size() >= 3:
					return {"kind": "polygon", "points": points}
		"circle":
			var raw_center: Variant = source.get("center", null)
			if raw_center is Array and (raw_center as Array).size() == 2:
				return {"kind": "circle", "center": Vector2(float(raw_center[0]), float(raw_center[1])), "radius": float(source.get("radius", 0.0))}
			if raw_center is Vector2:
				return {"kind": "circle", "center": raw_center, "radius": float(source.get("radius", 0.0))}
	return {}


static func manifest_boundary(value: Dictionary) -> Dictionary:
	if value.is_empty():
		return {}
	var kind := String(value.get("type", value.get("kind", "")))
	match kind:
		"rect", "corridor":
			var raw_rect: Variant = value.get("rect", null)
			var rect: Rect2
			if raw_rect is Rect2:
				rect = raw_rect
			elif raw_rect is Array and (raw_rect as Array).size() == 4:
				rect = Rect2(float(raw_rect[0]), float(raw_rect[1]), float(raw_rect[2]), float(raw_rect[3]))
			else:
				return {}
			var result := {"kind": kind, "rect": rect}
			if kind == "corridor":
				result["half_height"] = float(value.get("half_height", 0.0))
			return result
		"ring":
			var raw_center: Variant = value.get("center", null)
			var center := raw_center as Vector2 if raw_center is Vector2 else Vector2.ZERO
			if raw_center is Array and (raw_center as Array).size() == 2:
				center = Vector2(float(raw_center[0]), float(raw_center[1]))
			return {"kind": "ring", "center": center, "inner_radius": float(value.get("inner_radius", 0.0)), "outer_radius": float(value.get("outer_radius", 0.0))}
	return {}


static func coerce_resource(value: Variant, script: Script) -> Variant:
	if value is Dictionary:
		var errors: Array[String] = []
		if script == RoomDefinitionScript:
			errors = RoomDefinitionScript.validate_data(value)
		elif script == WorldAssetScript:
			errors = WorldAssetScript.validate_data(value)
		elif script == SpatialManifestScript:
			errors = SpatialManifestScript.validate_data(value)
		if not errors.is_empty():
			return null
		return script.new(value)
	if value is RefCounted and value.get_script() == script:
		return value
	return null
