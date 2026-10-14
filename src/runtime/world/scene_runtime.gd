class_name SceneRuntime
extends Node2D

## Room lifecycle and dependency assembly only.
##
## SceneRuntime creates the room-scoped simulation and actor registry, mounts
## the native world scene, and publishes a readiness barrier. It does not
## decide movement, AI, attacks, room completion, or visual ordering.

signal ready_changed(ready: bool, report: Dictionary)

const RoomDefinitionScript = preload("res://src/runtime/world/room_definition.gd")
const WorldAssetScript = preload("res://src/runtime/world/world_asset.gd")
const SpatialManifestScript = preload("res://src/runtime/world/spatial_manifest.gd")
const SimulationWorldScript = preload("res://src/runtime/world/simulation_world.gd")
const ActorRegistryScript = preload("res://src/runtime/world/actor_registry.gd")
const WorldPresenterScript = preload("res://src/runtime/world/world_presenter.gd")
const ArenaGeometryScript = preload("res://src/runtime/geometry/arena_geometry.gd")

enum Lifecycle { EMPTY, LOADING, READY, UNLOADING }

var lifecycle: Lifecycle = Lifecycle.EMPTY
var room_instance_id := ""
var world_revision := 0
var room_definition: Variant
var world_asset: Variant
var manifest: Variant
var movement_boundary: Dictionary = {}
var authored_arena_rect := Rect2()
var spawn_socket_bindings: Array[Dictionary] = []
var simulation: SimulationWorld
var actor_registry
var presenter: WorldPresenter
var native_scene_contract: Dictionary = {}
var _mounted_scene: Node
var _mount_sequence := 0

var mounted_scene: Node:
	get:
		return _mounted_scene if is_instance_valid(_mounted_scene) else null


func _ready() -> void:
	_ensure_runtime_nodes()


func _ensure_runtime_nodes() -> void:
	if presenter == null:
		presenter = WorldPresenterScript.new()
		presenter.name = "WorldPresenter"
		add_child(presenter)
	if simulation == null:
		simulation = SimulationWorldScript.new()
	if actor_registry == null:
		actor_registry = ActorRegistryScript.new()


## Mounts one strict room definition and its native world asset. The manifest
## is a build-produced SpatialManifest, never a hand-merged runtime dictionary.
func mount(
	room_definition_value: Variant,
	world_asset_value: Variant,
	scene: Variant = null,
	spatial_manifest_value: Variant = null,
	revision: int = 0,
	tick_rate: int = SimulationWorld.DEFAULT_TICK_RATE,
	setup: Callable = Callable()
) -> Dictionary:
	_ensure_runtime_nodes()
	if lifecycle != Lifecycle.EMPTY:
		return {"ok": false, "error": "runtime_not_empty"}
	if revision < 0 or tick_rate <= 0:
		return {"ok": false, "error": "invalid_room_instance"}
	var definition = _coerce_resource(room_definition_value, RoomDefinitionScript)
	var asset = _coerce_resource(world_asset_value, WorldAssetScript)
	if definition == null or not bool(definition.call("is_valid")):
		return {"ok": false, "error": "invalid_room_definition"}
	if asset == null or not bool(asset.call("is_valid")):
		return {"ok": false, "error": "invalid_world_asset"}
	var asset_snapshot: Dictionary = asset.call("snapshot")
	var scene_result := _resolve_scene(scene, String(asset_snapshot.get("world_scene_path", "")))
	if not bool(scene_result.get("ok", false)):
		return scene_result
	var manifest_result := _resolve_manifest(spatial_manifest_value, String(asset_snapshot.get("manifest_path", "")))
	if not bool(manifest_result.get("ok", false)):
		return manifest_result
	var spatial = manifest_result.get("value", null)
	if spatial == null or not bool(spatial.call("is_valid")):
		return {"ok": false, "error": "invalid_spatial_manifest"}
	var native_contract_result := _validate_native_scene(scene_result.get("value", null), asset_snapshot)
	if not bool(native_contract_result.get("ok", false)):
		return native_contract_result
	var identity_result := _validate_room_identity(definition, native_contract_result.get("value", {}))
	if not bool(identity_result.get("ok", false)):
		return identity_result
	var spatial_contract_result := _validate_spatial_contract(spatial, native_contract_result.get("value", {}))
	if not bool(spatial_contract_result.get("ok", false)):
		return spatial_contract_result
	var boundary: Dictionary = (spatial_contract_result.get("boundary", {}) as Dictionary).duplicate(true)

	lifecycle = Lifecycle.LOADING
	_mount_sequence += 1
	room_instance_id = "%s/%d" % [String(definition.get("room_id")), _mount_sequence]
	world_revision = revision
	room_definition = definition
	world_asset = asset
	manifest = spatial
	native_scene_contract = (native_contract_result.get("value", {}) as Dictionary).duplicate(true)
	movement_boundary = boundary
	authored_arena_rect = native_scene_contract["authored_bounds"]
	spawn_socket_bindings = (spatial_contract_result.get("spawn_sockets", []) as Array).duplicate(true)
	var configure_result: Dictionary = simulation.configure(tick_rate, room_instance_id, world_revision)
	if not bool(configure_result.get("ok", false)):
		_reset_mount()
		return configure_result
	var registry_result: Dictionary = actor_registry.configure(room_instance_id, world_revision)
	if not bool(registry_result.get("ok", false)):
		_reset_mount()
		return registry_result
	if not actor_registry.set_boundary(boundary):
		_reset_mount()
		return {"ok": false, "error": "movement_boundary_configuration_failed"}
	for solid: Dictionary in spatial_contract_result.get("static_blockers", []):
		if not actor_registry.register_polygon(String(solid["binding_id"]), solid["points"]):
			_reset_mount()
			return {"ok": false, "error": "static_geometry_registration_failed"}
	_mounted_scene = presenter.mount_world_scene(scene_result.get("value", null), setup, native_scene_contract)
	if _mounted_scene == null:
		_reset_mount()
		return {"ok": false, "error": "world_scene_mount_failed"}
	lifecycle = Lifecycle.READY
	ready_changed.emit(true, report())
	return {"ok": true, "error": "", "room_instance_id": room_instance_id}


func unmount() -> Dictionary:
	if lifecycle == Lifecycle.EMPTY:
		return {"ok": true, "error": ""}
	if lifecycle == Lifecycle.UNLOADING:
		return {"ok": false, "error": "already_unloading"}
	lifecycle = Lifecycle.UNLOADING
	if presenter != null:
		presenter.unmount_world_scene()
	_mounted_scene = null
	room_definition = null
	world_asset = null
	manifest = null
	native_scene_contract = {}
	movement_boundary = {}
	authored_arena_rect = Rect2()
	spawn_socket_bindings = []
	room_instance_id = ""
	world_revision = 0
	simulation = SimulationWorldScript.new()
	_clear_actor_registrations()
	actor_registry = ActorRegistryScript.new()
	lifecycle = Lifecycle.EMPTY
	ready_changed.emit(false, report())
	return {"ok": true, "error": ""}


func is_ready() -> bool:
	return lifecycle == Lifecycle.READY


func accepts_version(instance_id: String, revision: int) -> bool:
	return is_ready() and instance_id == room_instance_id and revision == world_revision


func register_actor(actor_id: String, position: Vector2, radius: float, part_ids: Array[String] = []) -> Dictionary:
	if not is_ready():
		return {"ok": false, "error": "runtime_not_ready"}
	return actor_registry.register_actor(actor_id, position, radius, part_ids)


func unregister_actor(actor_id: String) -> Dictionary:
	if actor_registry == null:
		return {"ok": false, "error": "runtime_not_ready"}
	return actor_registry.unregister_actor(actor_id)


func move_actor(actor_id: String, displacement: Vector2, tick: int, bounds: Rect2 = Rect2()) -> Dictionary:
	if not is_ready():
		return {"ok": false, "error": "runtime_not_ready"}
	return actor_registry.move_actor(actor_id, displacement, tick, bounds)


func report() -> Dictionary:
	return {
		"lifecycle": Lifecycle.keys()[lifecycle].to_lower(),
		"room_instance_id": room_instance_id,
		"world_revision": world_revision,
		"room_definition": room_definition.call("snapshot") if room_definition != null else {},
		"world_asset": world_asset.call("snapshot") if world_asset != null else {},
		"has_manifest": manifest != null,
		"manifest": manifest.call("snapshot") if manifest != null else {},
		"native_scene": native_scene_contract.duplicate(true),
		"movement_boundary": movement_boundary.duplicate(true),
		"authored_arena_rect": authored_arena_rect,
		"spawn_sockets": spawn_socket_bindings.duplicate(true),
		"room_identity": _room_identity_snapshot(),
		"simulation": simulation.snapshot() if simulation != null else {},
		"actors": actor_registry.snapshot() if actor_registry != null else {},
		"presenter": presenter.presentation_report() if presenter != null else {},
	}


func _coerce_resource(value: Variant, script: Script) -> Variant:
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


func _resolve_scene(provided: Variant, path: String) -> Dictionary:
	if provided != null:
		if not provided is PackedScene:
			return {"ok": false, "error": "world_scene_invalid"}
		var provided_scene := provided as PackedScene
		var expected_path := path.strip_edges()
		var provided_path := provided_scene.resource_path.strip_edges()
		if not expected_path.is_empty() and not provided_path.is_empty() and provided_path != expected_path:
			return {"ok": false, "error": "world_scene_identity_mismatch"}
		return {"ok": true, "error": "", "value": provided_scene}
	var normalized_path := path.strip_edges()
	if normalized_path.is_empty() or not ResourceLoader.exists(normalized_path):
		return {"ok": false, "error": "world_scene_missing"}
	var loaded: Resource = load(normalized_path)
	if not loaded is PackedScene:
		return {"ok": false, "error": "world_scene_invalid"}
	return {"ok": true, "error": "", "value": loaded}


func _resolve_manifest(provided: Variant, path: String) -> Dictionary:
	if provided != null:
		var supplied = _coerce_resource(provided, SpatialManifestScript)
		if supplied == null:
			return {"ok": false, "error": "invalid_spatial_manifest"}
		return {"ok": true, "error": "", "value": supplied}
	var normalized_path := path.strip_edges()
	if normalized_path.is_empty() or not FileAccess.file_exists(normalized_path):
		return {"ok": false, "error": "manifest_missing"}
	var file := FileAccess.open(normalized_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "manifest_unreadable"}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {"ok": false, "error": "manifest_invalid_json"}
	var loaded_manifest = _coerce_resource(parsed, SpatialManifestScript)
	if loaded_manifest == null or not bool(loaded_manifest.call("is_valid")):
		return {"ok": false, "error": "invalid_spatial_manifest"}
	return {"ok": true, "error": "", "value": loaded_manifest}


func _reset_mount() -> void:
	if presenter != null:
		presenter.unmount_world_scene()
	_mounted_scene = null
	room_definition = null
	world_asset = null
	manifest = null
	native_scene_contract = {}
	movement_boundary = {}
	authored_arena_rect = Rect2()
	spawn_socket_bindings = []
	room_instance_id = ""
	world_revision = 0
	simulation = SimulationWorldScript.new()
	_clear_actor_registrations()
	actor_registry = ActorRegistryScript.new()
	lifecycle = Lifecycle.EMPTY


func _clear_actor_registrations() -> void:
	if actor_registry != null:
		actor_registry.reset_actors()
		actor_registry.clear_geometry()
		actor_registry.set_boundary(null)


func _validate_native_scene(scene_value: Variant, asset_snapshot: Dictionary) -> Dictionary:
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
	var error := _validate_native_bindings(author_root, snapshot, asset_snapshot)
	if not error.is_empty():
		instance.free()
		return {"ok": false, "error": error}
	snapshot["native_contract_path"] = String(instance.get_path_to(author_root))
	instance.free()
	return {"ok": true, "error": "", "value": snapshot}


func _validate_native_bindings(author_root: Node, contract: Dictionary, asset_snapshot: Dictionary) -> String:
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


func _validate_room_identity(definition: Variant, native_contract: Dictionary) -> Dictionary:
	var identity: Dictionary = definition.call("snapshot")
	if identity["world_asset_id"] != native_contract["world_asset_id"]:
		return {"ok": false, "error": "room_identity_mismatch", "expected": identity["world_asset_id"], "actual": native_contract["world_asset_id"]}
	return {"ok": true, "error": ""}


func _validate_spatial_contract(spatial: Variant, native_contract: Dictionary) -> Dictionary:
	var source: Variant = native_contract.get("spatial_manifest", null)
	var derived = _coerce_resource(source, SpatialManifestScript)
	if derived == null or not bool(derived.call("is_valid")):
		return {"ok": false, "error": "invalid_native_spatial_manifest"}
	# Compare every semantic field, including channels, traversal profiles,
	# portals, sockets and metadata. A manifest is a derived artifact, not an
	# alternative authoring source that can replace native geometry.
	if spatial.call("digest_input") != derived.call("digest_input"):
		return {"ok": false, "error": "native_manifest_mismatch"}
	var manifest_snapshot: Dictionary = derived.call("snapshot")
	var coordinate: Dictionary = manifest_snapshot["coordinate_convention"]
	if not coordinate.get("units", null) is String or String(coordinate["units"]).strip_edges().is_empty() or not coordinate.get("up", null) is String or String(coordinate["up"]).strip_edges().is_empty():
		return {"ok": false, "error": "invalid_coordinate_convention"}
	var scale: Variant = coordinate.get("scale", null)
	if typeof(scale) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(scale)) or float(scale) <= 0.0:
		return {"ok": false, "error": "invalid_coordinate_convention"}
	var movement_id := String(native_contract["movement_binding"])
	var movement_bindings: Array = derived.call("movement_bindings")
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


func _room_identity_snapshot() -> Dictionary:
	var definition_snapshot: Dictionary = room_definition.call("snapshot") if room_definition != null else {}
	return {
		"room_id": String(definition_snapshot.get("room_id", "")),
		"world_asset_id": String(definition_snapshot.get("world_asset_id", "")),
		"scene_id": String(native_scene_contract.get("scene_id", "")),
		"layout_id": String(native_scene_contract.get("layout_id", "")),
	}

