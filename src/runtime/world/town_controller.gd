class_name TownController
extends Node

## Assembles the town room and forwards input to its gameplay domain. It never
## draws actors, solves collision, or owns an independent authority clock.
const SceneRuntimeScript := preload("res://src/runtime/world/scene_runtime.gd")
const RoomSceneSetupPortScript := preload("res://src/runtime/world/room_scene_setup_port.gd")
const TownRuntimeScript := preload("res://src/runtime/world/town_runtime.gd")
const SpatialManifestScript := preload("res://src/runtime/world/spatial_manifest.gd")
const SCENE_PATH := "res://content/rooms/town/hearthside.tscn"
const MANIFEST_PATH := "res://content/rooms/town/hearthside.spatial.json"
const LAYER_PATH := "res://content/rooms/town/layers/manifest.json"

var scene_runtime
var town = TownRuntimeScript.new()
var load_report := {"ok": false, "error": "town_not_loaded"}


func mount(world_parent: Node) -> Dictionary:
	if scene_runtime != null:
		return {"ok": false, "error": "town_already_mounted"}
	if not FileAccess.file_exists(MANIFEST_PATH) or not ResourceLoader.exists(SCENE_PATH):
		load_report = {"ok": false, "error": "town_native_source_missing"}
		return load_report
	var manifest_payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	var manifest := SpatialManifestScript.new(manifest_payload)
	if not manifest.is_valid():
		load_report = {"ok": false, "error": "town_manifest_invalid"}
		return load_report
	scene_runtime = SceneRuntimeScript.new()
	scene_runtime.name = "TownSceneRuntime"
	world_parent.add_child(scene_runtime)
	load_report = scene_runtime.mount(
		{"room_id": "town/hearthside", "world_asset_id": "town/hearthside", "encounter_id": "town/exploration", "ruleset_id": "town/v1", "tags": ["town", "chapter_one"]},
		{"world_scene_path": SCENE_PATH, "manifest_path": MANIFEST_PATH,
			"gameplay_digest": manifest.gameplay_digest_sha256(), "presentation_digest": manifest.presentation_digest_sha256(), "schema_version": 1},
		null, null, 0, 30, TownSetupPort.new().bind(self))
	if not bool(load_report.get("ok", false)):
		return load_report
	var metadata: Dictionary = scene_runtime.manifest.snapshot().get("gameplay_spatial_metadata", {})
	var registry: Variant = scene_runtime.actor_registry
	for resident: Dictionary in metadata.get("residents", []):
		var position := _point(resident.position)
		var result: Dictionary = registry.register_actor("town/npc/" + String(resident.id), position, float(resident.radius))
		if not bool(result.get("ok", false)):
			return _fail("town_resident_registration_failed:" + String(resident.id))
	var spawn := Vector2.INF
	for socket: Dictionary in scene_runtime.spawn_socket_bindings:
		if String(socket.binding) == "town/spawn":
			spawn = socket.position
	var radius := float(metadata.get("hero_radius", 6.0))
	if not registry.is_position_clear(spawn, Rect2(), radius):
		return _fail("town_spawn_blocked")
	var hero: Dictionary = registry.register_actor(TownRuntimeScript.HERO_ID, spawn, radius)
	if not bool(hero.get("ok", false)):
		return _fail("town_hero_registration_failed")
	load_report = town.configure(scene_runtime.simulation, registry, metadata)
	return load_report


func advance_frame(direction: Vector2, display_delta: float) -> Dictionary:
	var submitted: Dictionary = town.submit_move(direction)
	return town.advance_frame(display_delta) if bool(submitted.get("ok", false)) else submitted


func abort_loading(report: Dictionary) -> void:
	town.close()
	if scene_runtime != null:
		scene_runtime.unmount()
	load_report = report.duplicate(true)


func _fail(error: String) -> Dictionary:
	abort_loading({"ok": false, "error": error})
	return load_report


static func _point(pair: Array) -> Vector2:
	return Vector2(float(pair[0]), float(pair[1]))


class TownSetupPort extends "res://src/runtime/world/room_scene_setup_port.gd":

	var _owner: TownController = null

	func bind(owner: TownController) -> TownSetupPort:
		_owner = owner
		return self

	func setup(source: Node) -> void:
		if source != null and source.has_method("bind_native_art"):
			source.bind_native_art()
