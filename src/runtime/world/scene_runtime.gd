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

enum Lifecycle { EMPTY, LOADING, READY, UNLOADING }

var lifecycle: Lifecycle = Lifecycle.EMPTY
var room_instance_id := ""
var world_revision := 0
var room_definition: Variant
var world_asset: Variant
var manifest: Variant
var simulation: SimulationWorld
var actor_registry
var presenter: WorldPresenter
var _mounted_scene: Node
var _mount_sequence := 0


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
	scene: PackedScene,
	spatial_manifest_value: Variant,
	revision: int = 0,
	tick_rate: int = SimulationWorld.DEFAULT_TICK_RATE
) -> Dictionary:
	_ensure_runtime_nodes()
	if lifecycle != Lifecycle.EMPTY:
		return {"ok": false, "error": "runtime_not_empty"}
	if revision < 0 or tick_rate <= 0:
		return {"ok": false, "error": "invalid_room_instance"}
	var definition = _coerce_resource(room_definition_value, RoomDefinitionScript)
	var asset = _coerce_resource(world_asset_value, WorldAssetScript)
	var spatial = _coerce_resource(spatial_manifest_value, SpatialManifestScript)
	if definition == null or not bool(definition.call("is_valid")):
		return {"ok": false, "error": "invalid_room_definition"}
	if asset == null or not bool(asset.call("is_valid")):
		return {"ok": false, "error": "invalid_world_asset"}
	if spatial == null or not bool(spatial.call("is_valid")):
		return {"ok": false, "error": "invalid_spatial_manifest"}

	lifecycle = Lifecycle.LOADING
	_mount_sequence += 1
	room_instance_id = "%s/%d" % [String(definition.get("room_id")), _mount_sequence]
	world_revision = revision
	room_definition = definition
	world_asset = asset
	manifest = spatial
	var configure_result: Dictionary = simulation.configure(tick_rate, room_instance_id, world_revision)
	if not bool(configure_result.get("ok", false)):
		_reset_mount()
		return configure_result
	var registry_result: Dictionary = actor_registry.configure(room_instance_id, world_revision)
	if not bool(registry_result.get("ok", false)):
		_reset_mount()
		return registry_result
	_mounted_scene = presenter.mount_world_scene(scene)
	if scene != null and _mounted_scene == null:
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
	if _mounted_scene != null and is_instance_valid(_mounted_scene):
		_mounted_scene.queue_free()
	_mounted_scene = null
	room_definition = null
	world_asset = null
	manifest = null
	room_instance_id = ""
	world_revision = 0
	simulation = SimulationWorldScript.new()
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
		"simulation": simulation.snapshot() if simulation != null else {},
		"actors": actor_registry.snapshot() if actor_registry != null else {},
		"presenter": presenter.presentation_report() if presenter != null else {},
	}


func _coerce_resource(value: Variant, script: Script) -> Variant:
	if value is Dictionary:
		return script.new(value)
	if value is RefCounted and value.has_method("is_valid") and value.has_method("snapshot"):
		return value
	return null


func _reset_mount() -> void:
	if _mounted_scene != null and is_instance_valid(_mounted_scene):
		_mounted_scene.queue_free()
	_mounted_scene = null
	room_definition = null
	world_asset = null
	manifest = null
	room_instance_id = ""
	world_revision = 0
	simulation = SimulationWorldScript.new()
	actor_registry = ActorRegistryScript.new()
	lifecycle = Lifecycle.EMPTY

