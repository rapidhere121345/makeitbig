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
const RoomManifestValidatorScript = preload("res://src/runtime/world/room_manifest_validator.gd")
const SpatialManifestScript = preload("res://src/runtime/world/spatial_manifest.gd")
const SimulationWorldScript = preload("res://src/runtime/world/simulation_world.gd")
const ActorRegistryScript = preload("res://src/runtime/world/actor_registry.gd")
const WorldPresenterScript = preload("res://src/runtime/world/world_presenter.gd")
const StaticSpatialIndexScript = preload("res://src/runtime/spatial/static_spatial_index.gd")
const DynamicSpatialIndexScript = preload("res://src/runtime/spatial/dynamic_spatial_index.gd")
const SpatialOverlayScript = preload("res://src/runtime/spatial/spatial_overlay.gd")
const MovementResolverScript = preload("res://src/runtime/spatial/movement_resolver.gd")
const RoomActorAccessScript = preload("res://src/runtime/world/room_actor_access.gd")
const RoomSpatialPortScript = preload("res://src/runtime/world/room_spatial_port.gd")
const RoomCombatPortScript = preload("res://src/runtime/world/room_combat_port.gd")
const RoomEncounterPortScript = preload("res://src/runtime/world/room_encounter_port.gd")
const RoomSceneSetupPortScript = preload("res://src/runtime/world/room_scene_setup_port.gd")
const RoomPresentationPortScript = preload("res://src/runtime/world/room_presentation_port.gd")
const RoomPresentationProjectorScript = preload("res://src/presentation/room_presentation_projector.gd")
const RoomPresentationBindingScript = preload("res://src/presentation/room_presentation_binding.gd")
const EncounterSpawnRequestScript = preload("res://src/runtime/encounter/encounter_spawn_request.gd")
const EncounterSpawnResultScript = preload("res://src/runtime/encounter/encounter_spawn_result.gd")
const RoomTerminalObservationScript = preload("res://src/runtime/encounter/room_terminal_observation.gd")
const SimKernelScript = preload("res://src/runtime/simulation/sim_kernel.gd")
const SimOutcomeScript = preload("res://src/runtime/simulation/sim_outcome.gd")

const DEFAULT_TICK_RATE: int = SimKernelScript.DEFAULT_TICK_RATE

enum Lifecycle { EMPTY, LOADING, READY, UNLOADING }

var lifecycle: Lifecycle = Lifecycle.EMPTY
var room_instance_id := ""
var world_revision := 0
var room_definition: RoomDefinition = null
var world_asset: WorldAsset = null
var manifest: SpatialManifest = null
var movement_boundary: Dictionary = {}
var authored_arena_rect := Rect2()
var spawn_socket_bindings: Array[Dictionary] = []
var simulation: SimulationWorld
## Public room actor boundary. The underlying typed entity store is exposed as
## entity_registry only to the SimulationWorld composition root.
var actor_registry: Variant = null
var entity_registry: Variant = null
var static_spatial_index: StaticSpatialIndex = null
var dynamic_spatial_index: DynamicSpatialIndex = null
var spatial_overlay: SpatialOverlay = null
var movement_resolver: MovementResolver = null
var spatial_port: Variant = null
var combat_port: Variant = null
var encounter_port: Variant = null
var presentation_port: Variant = null
var presentation_projector: Variant = null
## Static authored visual bindings assembled from the mounted native scene at
## mount. SceneRuntime owns them for the room's lifetime so a restart can
## re-assemble the same real art without re-deriving it from nodes.
var _static_visual_bindings: Array = []
var encounter_domain: Variant = null
var encounter_spawn_binding: RoomEncounterSpawnPort = null
var encounter_step_result: Dictionary = {}
var encounter_spawn_results: Array[Dictionary] = []
var presenter: WorldPresenter
var native_scene_contract: Dictionary = {}
var _mounted_scene: Node
var _mount_sequence := 0

var mounted_scene: Node:
	get:
		return _mounted_scene if is_instance_valid(_mounted_scene) else null


func _ready() -> void:
	_ensure_runtime_nodes()


func _exit_tree() -> void:
	if lifecycle != Lifecycle.EMPTY:
		unmount()


func _ensure_runtime_nodes() -> void:
	if presenter == null:
		presenter = WorldPresenterScript.new()
		presenter.name = "WorldPresenter"
		add_child(presenter)
	if entity_registry == null:
		entity_registry = ActorRegistryScript.new()


## Mounts one strict room definition and its native world asset. The manifest
## is a build-produced SpatialManifest, never a hand-merged runtime dictionary.
func mount(
	room_definition_value: Variant,
	world_asset_value: Variant,
	scene: Variant = null,
	spatial_manifest_value: Variant = null,
	revision: int = 0,
	tick_rate: int = DEFAULT_TICK_RATE,
	setup: RoomSceneSetupPort = null,
	encounter_domain_value: Variant = null,
	encounter_spawn_binding_value: RoomEncounterSpawnPort = null,
	auto_start_encounter: bool = false
) -> Dictionary:
	_ensure_runtime_nodes()
	if lifecycle != Lifecycle.EMPTY:
		return {"ok": false, "error": "runtime_not_empty"}
	if revision < 0 or tick_rate <= 0:
		return {"ok": false, "error": "invalid_room_instance"}
	var definition: RoomDefinition = RoomManifestValidatorScript.coerce_resource(room_definition_value, RoomDefinitionScript) as RoomDefinition
	var asset: WorldAsset = RoomManifestValidatorScript.coerce_resource(world_asset_value, WorldAssetScript) as WorldAsset
	if definition == null or not definition.is_valid():
		return {"ok": false, "error": "invalid_room_definition"}
	if asset == null or not asset.is_valid():
		return {"ok": false, "error": "invalid_world_asset"}
	var asset_snapshot: Dictionary = asset.snapshot()
	var scene_result := _resolve_scene(scene, String(asset_snapshot.get("world_scene_path", "")))
	if not bool(scene_result.get("ok", false)):
		return scene_result
	var manifest_result := _resolve_manifest(spatial_manifest_value, String(asset_snapshot.get("manifest_path", "")))
	if not bool(manifest_result.get("ok", false)):
		return manifest_result
	var spatial: SpatialManifest = manifest_result.get("value", null) as SpatialManifest
	if spatial == null or not spatial.is_valid():
		return {"ok": false, "error": "invalid_spatial_manifest"}
	var manifest_match: Dictionary = asset.matches_manifest(spatial)
	if not bool(manifest_match.get("ok", false)):
		return {"ok": false, "error": "world_asset_manifest_mismatch", "details": manifest_match}
	var native_contract_result := RoomManifestValidatorScript.validate_native_scene(scene_result.get("value", null), asset_snapshot)
	if not bool(native_contract_result.get("ok", false)):
		return native_contract_result
	var identity_result := RoomManifestValidatorScript.validate_room_identity(definition, native_contract_result.get("value", {}))
	if not bool(identity_result.get("ok", false)):
		return identity_result
	var spatial_contract_result := RoomManifestValidatorScript.validate_spatial_contract(spatial, native_contract_result.get("value", {}))
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
	var definition_snapshot: Dictionary = definition.snapshot()
	var static_build: Dictionary = StaticSpatialIndexScript.build(RoomManifestValidatorScript.static_index_payload(
		spatial,
		String(definition_snapshot.get("world_asset_id", "")),
		String(native_scene_contract.get("movement_binding", ""))
	))
	if not bool(static_build.get("ok", false)):
		_reset_mount()
		return {"ok": false, "error": "static_spatial_index_invalid", "details": static_build}
	static_spatial_index = static_build.get("value")
	dynamic_spatial_index = DynamicSpatialIndexScript.new()
	spatial_overlay = SpatialOverlayScript.new()
	var movement_build: Dictionary = MovementResolverScript.make(static_spatial_index, spatial_overlay, dynamic_spatial_index)
	if not bool(movement_build.get("ok", false)):
		_reset_mount()
		return {"ok": false, "error": "movement_resolver_invalid", "details": movement_build}
	movement_resolver = movement_build.get("value")
	spatial_port = RoomSpatialPortScript.new()
	combat_port = RoomCombatPortScript.new()
	encounter_port = RoomEncounterPortScript.new()
	presentation_port = RoomPresentationPortScript.new()
	simulation = SimulationWorldScript.new(spatial_port, combat_port, encounter_port, presentation_port, entity_registry)
	var configure_result: SimOutcome = simulation.configure(room_instance_id, world_revision, tick_rate)
	if not configure_result.ok:
		_reset_mount()
		return {"ok": false, "error": String(configure_result.error)}
	var access := RoomActorAccessScript.new()
	var access_result: Dictionary = access.configure(simulation, entity_registry, static_spatial_index, dynamic_spatial_index, movement_resolver, spatial_overlay)
	if not bool(access_result.get("ok", false)):
		_reset_mount()
		return access_result
	actor_registry = access
	spatial_port.bind(access)
	combat_port.bind(access)
	if encounter_domain_value != null:
		var encounter_result := bind_encounter(encounter_domain_value, encounter_spawn_binding_value)
		if not bool(encounter_result.get("ok", false)):
			_reset_mount()
			return encounter_result
	_mounted_scene = presenter.mount_world_scene(scene_result.get("value", null), setup, native_scene_contract)
	if _mounted_scene == null:
		_reset_mount()
		return {"ok": false, "error": "world_scene_mount_failed"}
	# The presentation assembly binds through prepare_presentation(), whose
	# gate requires a ready runtime, so READY is taken before assembly; an
	# assembly failure rolls the whole mount back below, and no ready_changed
	# observer can run in between (assembly is synchronous).
	lifecycle = Lifecycle.READY
	var presentation_result := _assemble_presentation_domain()
	if not bool(presentation_result.get("ok", false)):
		_reset_mount()
		return presentation_result
	if auto_start_encounter and encounter_domain != null:
		var start_result := start_encounter()
		if not bool(start_result.get("ok", false)):
			_reset_mount()
			return start_result
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
	_clear_actor_registrations()
	if encounter_port != null and encounter_port.has_method("shutdown"):
		encounter_port.shutdown()
	_shutdown_simulation_kernel()
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
	actor_registry = null
	entity_registry = null
	static_spatial_index = null
	dynamic_spatial_index = null
	spatial_overlay = null
	movement_resolver = null
	spatial_port = null
	combat_port = null
	encounter_port = null
	presentation_port = null
	presentation_projector = null
	encounter_domain = null
	encounter_spawn_binding = null
	encounter_step_result = {}
	encounter_spawn_results = []
	_static_visual_bindings = []
	entity_registry = ActorRegistryScript.new()
	lifecycle = Lifecycle.EMPTY
	ready_changed.emit(false, report())
	return {"ok": true, "error": ""}


## Explicit teardown alias for callers that own SceneRuntime as a disposable
## room service. It shares the same fail-closed unmount boundary.
func shutdown() -> Dictionary:
	return unmount()


## Starts a fresh authoritative room instance while retaining the mounted native
## scene and its immutable spatial indexes.  A restart changes the room
## identity and revision, reconfigures the typed store, and binds a fresh
## room-facing actor access object; it never rewinds an already-used kernel.
func restart_room_instance(tick_rate: int = DEFAULT_TICK_RATE) -> Dictionary:
	if lifecycle != Lifecycle.READY:
		return {"ok": false, "error": "runtime_not_ready"}
	if tick_rate <= 0 or simulation == null or entity_registry == null:
		return {"ok": false, "error": "invalid_room_instance"}
	if actor_registry != null and actor_registry.has_method("reset_actors"):
		var reset_result: Dictionary = actor_registry.reset_actors()
		if not bool(reset_result.get("ok", false)):
			return {"ok": false, "error": String(reset_result.get("error", "actor_reset_failed"))}
	_mount_sequence += 1
	room_instance_id = "%s/%d" % [String(room_definition.get("room_id")), _mount_sequence]
	world_revision += 1
	var configure_result: SimOutcome = simulation.configure(room_instance_id, world_revision, tick_rate)
	if not configure_result.ok:
		return {"ok": false, "error": String(configure_result.error)}
	var access := RoomActorAccessScript.new()
	var access_result: Dictionary = access.configure(simulation, entity_registry, static_spatial_index, dynamic_spatial_index, movement_resolver, spatial_overlay)
	if not bool(access_result.get("ok", false)):
		return access_result
	actor_registry = access
	spatial_port.bind(access)
	combat_port.bind(access)
	if presentation_projector != null:
		var replacement := RoomPresentationProjectorScript.new()
		var replacement_access: Dictionary = replacement.bind_access(access)
		if not bool(replacement_access.get("ok", false)):
			return replacement_access
		for binding: Variant in _static_visual_bindings:
			var static_bound: Dictionary = replacement.bind_static_visual(binding)
			if not bool(static_bound.get("ok", false)):
				return static_bound
		var replacement_port: Dictionary = presentation_port.replace_projector(replacement)
		if not bool(replacement_port.get("ok", false)):
			return replacement_port
		presentation_projector = replacement
	if encounter_domain != null:
		if encounter_domain.has_method("restart"):
			var encounter_restart: Dictionary = encounter_domain.restart(-1)
			if not bool(encounter_restart.get("ok", false)):
				return encounter_restart
		var encounter_bind_result: Dictionary = encounter_port.bind(encounter_domain, room_instance_id, world_revision)
		if not bool(encounter_bind_result.get("ok", false)):
			return encounter_bind_result
		if encounter_spawn_binding != null:
			var spawn_bind_result: Dictionary = encounter_port.bind_spawn_binding(encounter_spawn_binding)
			if not bool(spawn_bind_result.get("ok", false)):
				return spawn_bind_result
		encounter_step_result = {}
		encounter_spawn_results = []
	return {"ok": true, "error": "", "room_instance_id": room_instance_id, "world_revision": world_revision}


## Binds the room-owned encounter after simulation and actor access exist.
## SceneRuntime does not create spawn Nodes or decide encounter outcomes.
func bind_encounter(domain: Variant, spawn_binding: RoomEncounterSpawnPort = null) -> Dictionary:
	if encounter_port == null or domain == null or not domain.has_method("step") or not domain.has_method("notify_death"):
		return {"ok": false, "error": "invalid_room_encounter_domain"}
	var typed_binding: RoomEncounterSpawnPort = null
	if spawn_binding == null:
		var default_binding := DefaultEncounterSpawnPort.new()
		var default_bound: Dictionary = default_binding.bind(self)
		if not bool(default_bound.get("ok", false)):
			return default_bound
		typed_binding = default_binding
	else:
		typed_binding = spawn_binding
	encounter_domain = domain
	encounter_spawn_binding = typed_binding
	var bound: Dictionary = encounter_port.bind(domain, room_instance_id, world_revision)
	if not bool(bound.get("ok", false)):
		return bound
	return encounter_port.bind_spawn_binding(typed_binding)


## Binds the detached presentation domain for the mounted room at the
## composition root: one typed projector per RoomActorAccess, plus every
## manifest occlusion-channel piece derived from the mounted native scene's
## real art nodes. Missing art is a load error; there is no fallback source.
## Actor visual bindings stay a composition-side call because only the parent
## knows which drawn skin belongs to each simulation actor.
func _assemble_presentation_domain() -> Dictionary:
	var prepared: Dictionary = prepare_presentation()
	if not bool(prepared.get("ok", false)):
		return prepared
	var occlusion_bindings: Array = manifest.occlusion_bindings()
	_static_visual_bindings = []
	if occlusion_bindings.is_empty():
		return {"ok": true, "error": ""}
	# mount_world_scene() reparents the authored layer content into the
	# presenter's shared layers, so after mount the real art nodes live under
	# the presenter, not under the mounted scene shell. The presenter subtree
	# is the art root; its own display transform stays out of the measurement.
	var derived: Dictionary = RoomPresentationProjectorScript.derive_static_bindings(presenter, occlusion_bindings)
	if not bool(derived.get("ok", false)):
		return derived
	for entry: Variant in derived.get("value", []):
		if not entry is Dictionary:
			return {"ok": false, "error": "presentation_static_binding_invalid"}
		var source: Dictionary = entry
		var bound: Dictionary = bind_static_presentation(
			String(source["stable_id"]),
			String(source["visual_id"]),
			int(source["rank"]),
			source["art_box"],
			source["feet_anchor"]
		)
		if not bool(bound.get("ok", false)):
			return bound
	var assembled: Array = []
	for entry: Variant in derived.get("value", []):
		var binding_id := String((entry as Dictionary)["stable_id"])
		var binding: Variant = presentation_projector.static_binding(binding_id)
		if binding == null:
			return {"ok": false, "error": "presentation_static_binding_lost:%s" % binding_id}
		assembled.append(binding)
	_static_visual_bindings = assembled
	return {"ok": true, "error": ""}


## Creates the detached presentation projector for the current room. The
## projector is deliberately separate from the Canvas presenter: it reads only
## SimSnapshot rows and explicit art bindings, with no collision-geometry
## fallback. Callers add bindings before the next authoritative tick.
func prepare_presentation() -> Dictionary:
	if not is_ready() or actor_registry == null or presentation_port == null:
		return {"ok": false, "error": "presentation_runtime_unavailable"}
	if presentation_projector != null:
		return {"ok": true, "error": "", "projector": presentation_projector}
	var projector := RoomPresentationProjectorScript.new()
	var access_result: Dictionary = projector.bind_access(actor_registry)
	if not bool(access_result.get("ok", false)):
		return access_result
	var port_result: Dictionary = presentation_port.bind_projector(projector)
	if not bool(port_result.get("ok", false)):
		return port_result
	presentation_projector = projector
	return {"ok": true, "error": "", "projector": projector}


func bind_actor_presentation(stable_id: String, visual_id: String, rank: int, art_box: Variant) -> Dictionary:
	var prepared := prepare_presentation()
	if not bool(prepared.get("ok", false)):
		return prepared
	var created: Dictionary = RoomPresentationBindingScript.for_actor(stable_id, visual_id, rank, art_box)
	if not bool(created.get("ok", false)):
		return created
	return presentation_projector.bind_actor_visual(created.get("value"))


func clear_actor_presentation_bindings() -> void:
	if presentation_projector != null and presentation_projector.has_method("clear_actor_bindings"):
		presentation_projector.clear_actor_bindings()


func bind_static_presentation(stable_id: String, visual_id: String, rank: int, art_box: Variant, feet_anchor: Variant) -> Dictionary:
	var prepared := prepare_presentation()
	if not bool(prepared.get("ok", false)):
		return prepared
	var created: Dictionary = RoomPresentationBindingScript.for_static_piece(stable_id, visual_id, rank, art_box, feet_anchor)
	if not bool(created.get("ok", false)):
		return created
	return presentation_projector.bind_static_visual(created.get("value"))


func is_ready() -> bool:
	return lifecycle == Lifecycle.READY


func accepts_version(instance_id: String, revision: int) -> bool:
	return is_ready() and instance_id == room_instance_id and revision == world_revision


## Advances one authoritative fixed tick and then resolves encounter spawn
## requests in the between-tick structural window.  The returned snapshot is
## the kernel snapshot published by the tick; newly materialized actors are
## intentionally visible from the next tick onward.
func step_tick() -> SimOutcome:
	if not is_ready() or simulation == null or simulation.kernel == null:
		return SimOutcomeScript.failure(&"runtime_not_ready")
	var stepped: SimOutcome = simulation.step_tick()
	if not stepped.ok:
		return stepped
	materialize_encounter_spawns()
	return stepped


## Drains the pending kernel encounter spawn requests for the committed tick.
## SceneRuntime.step_tick() calls this after its own authoritative tick;
## mounted production rooms submit SimulationWorld.step_tick() through
## CombatSimulation, so Main invokes this from its first post-kernel room
## phase. Both paths materialize exactly once, after the tick snapshot was
## published and before the next fixed tick reads the entity store.
func materialize_encounter_spawns() -> Array[Dictionary]:
	if not is_ready() or encounter_port == null or encounter_domain == null or not encounter_port.has_method("materialize_spawn_requests"):
		return []
	encounter_spawn_results.clear()
	encounter_spawn_results = encounter_port.materialize_spawn_requests(simulation.tick)
	encounter_step_result = encounter_port.last_step.duplicate(true)
	return encounter_spawn_results.duplicate(true)


## Alias used by room-facing callers that treat SceneRuntime as the fixed-tick
## authority rather than reaching through SimulationWorld.
func step() -> SimOutcome:
	return step_tick()


func start_encounter(start_tick: int = -1) -> Dictionary:
	if not is_ready() or encounter_domain == null or not encounter_domain.has_method("start"):
		return {"ok": false, "error": "encounter_runtime_unavailable"}
	var tick := simulation.tick if start_tick < 0 else start_tick
	if tick != simulation.tick or tick < 0:
		return {"ok": false, "error": "stale_encounter_tick"}
	var started: Dictionary = encounter_domain.start(tick)
	if bool(started.get("ok", false)):
		encounter_step_result = encounter_domain.snapshot() if encounter_domain.has_method("snapshot") else {}
	return started


func request_encounter_defeat(reason: String, tick: int = -1) -> Dictionary:
	if not is_ready() or encounter_domain == null or not encounter_domain.has_method("request_defeat"):
		return {"ok": false, "error": "encounter_runtime_unavailable"}
	var effective_tick := simulation.tick if tick < 0 else tick
	return encounter_domain.request_defeat(effective_tick, reason)


## Default production spawn binding.  It creates a real ActorState through the
## mounted RoomActorAccess; content-specific bindings can replace it through
## mount(..., encounter_spawn_binding_value) or bind_encounter().
func _spawn_encounter_request(request: EncounterSpawnRequest, _context: Dictionary) -> Variant:
	if request == null or actor_registry == null or not is_ready():
		return EncounterSpawnResultScript.failed(request, "runtime_not_ready")
	var socket_position: Variant = _encounter_socket_position(request.socket_id)
	if not socket_position is Vector2:
		return EncounterSpawnResultScript.failed(request, "unknown_encounter_spawn_socket")
	var actor_id := "encounter/%s" % request.spawn_key.replace("/", "_")
	var radius := _encounter_spawn_radius()
	var registered: Dictionary = actor_registry.register_actor(
		actor_id,
		socket_position,
		radius,
		1,
		&"soft",
		[&"movement", &"hurtbox"],
		PackedStringArray(),
		1.0,
		{},
		request.archetype_id,
		request.spawn_key,
		request.tags
	)
	if not bool(registered.get("ok", false)):
		return EncounterSpawnResultScript.failed(request, String(registered.get("error", "actor_spawn_failed")))
	var handle: SimEntityHandle = registered.get("handle", null)
	var stable_key := int(registered.get("stable_key", 0))
	var entity_key: String = actor_registry.entity_key_for_handle(handle) if handle != null and actor_registry.has_method("entity_key_for_handle") else "actor/%d" % stable_key
	return EncounterSpawnResultScript.spawned(
		request,
		handle,
		String(entity_key),
		stable_key,
		handle.generation if handle != null else 0,
		room_instance_id,
		world_revision
	)


func _encounter_socket_position(socket_id: String) -> Variant:
	for socket: Dictionary in spawn_socket_bindings:
		if String(socket.get("binding", "")) == socket_id:
			return socket.get("position", null)
	return null


func _encounter_spawn_radius() -> float:
	if manifest != null and manifest.has_method("snapshot"):
		var snapshot_value: Dictionary = manifest.snapshot()
		for profile: Dictionary in snapshot_value.get("traversal_profiles", []):
			if String(profile.get("profile_id", "")) == "standard":
				var candidate := float(profile.get("radius", 14.0))
				if is_finite(candidate) and candidate > 0.0:
					return candidate
	return 14.0


func register_actor(actor_id: String, position: Vector2, radius: float, part_ids: Array[String] = []) -> Dictionary:
	if not is_ready() or actor_registry == null:
		return {"ok": false, "error": "runtime_not_ready"}
	var packed_parts := PackedStringArray()
	for part: String in part_ids:
		packed_parts.append(part)
	return actor_registry.register_actor(actor_id, position, radius, 1, &"soft", [&"movement", &"hurtbox"], packed_parts)


func unregister_actor(actor_id: String) -> Dictionary:
	if actor_registry == null:
		return {"ok": false, "error": "runtime_not_ready"}
	return actor_registry.unregister_actor(actor_id)


func move_actor(actor_id: String, displacement: Vector2, tick: int, bounds: Rect2 = Rect2()) -> Dictionary:
	if not is_ready():
		return {"ok": false, "error": "runtime_not_ready"}
	return actor_registry.move_actor(actor_id, displacement, tick)


func teleport_actor(actor_id: String, position: Vector2) -> Dictionary:
	if not is_ready() or actor_registry == null:
		return {"ok": false, "error": "runtime_not_ready"}
	return actor_registry.teleport_actor(actor_id, position)


func is_position_clear(position: Vector2, radius: float) -> bool:
	return actor_registry != null and actor_registry.is_position_clear(position, radius)


func report() -> Dictionary:
	return {
		"lifecycle": Lifecycle.keys()[lifecycle].to_lower(),
		"room_instance_id": room_instance_id,
		"world_revision": world_revision,
		"room_definition": room_definition.snapshot() if room_definition != null else {},
		"world_asset": world_asset.snapshot() if world_asset != null else {},
		"has_manifest": manifest != null,
		"manifest": manifest.snapshot() if manifest != null else {},
		"native_scene": native_scene_contract.duplicate(true),
		"movement_boundary": movement_boundary.duplicate(true),
		"authored_arena_rect": authored_arena_rect,
		"spawn_sockets": spawn_socket_bindings.duplicate(true),
		"room_identity": _room_identity_snapshot(),
		"simulation": _simulation_report(),
		"actors": actor_registry.snapshot() if actor_registry != null else {},
		"entity_registry": entity_registry.store().snapshot_rows() if entity_registry != null else [],
		"static_spatial_index": static_spatial_index.snapshot() if static_spatial_index != null else {},
		"dynamic_spatial_index": dynamic_spatial_index.snapshot() if dynamic_spatial_index != null else {},
		"spatial_overlay": spatial_overlay.snapshot() if spatial_overlay != null else {},
		"combat_port": combat_port.combat_snapshot() if combat_port != null and combat_port.has_method("combat_snapshot") else {},
		"encounter_port": encounter_port.snapshot() if encounter_port != null and encounter_port.has_method("snapshot") else {},
		"encounter_step": encounter_step_result.duplicate(true),
		"encounter_spawn_results": encounter_spawn_results.duplicate(true),
		"presentation_port": presentation_port.snapshot() if presentation_port != null and presentation_port.has_method("snapshot") else {},
		"presentation_projector_bound": presentation_projector != null,
		"presenter": presenter.presentation_report() if presenter != null else {},
	}


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
		var supplied = RoomManifestValidatorScript.coerce_resource(provided, SpatialManifestScript)
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
	var loaded_manifest: SpatialManifest = RoomManifestValidatorScript.coerce_resource(parsed, SpatialManifestScript) as SpatialManifest
	if loaded_manifest == null or not loaded_manifest.is_valid():
		return {"ok": false, "error": "invalid_spatial_manifest"}
	return {"ok": true, "error": "", "value": loaded_manifest}


func _reset_mount() -> void:
	if presenter != null:
		presenter.unmount_world_scene()
	_clear_actor_registrations()
	if encounter_port != null and encounter_port.has_method("shutdown"):
		encounter_port.shutdown()
	_shutdown_simulation_kernel()
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
	actor_registry = null
	entity_registry = null
	static_spatial_index = null
	dynamic_spatial_index = null
	spatial_overlay = null
	movement_resolver = null
	spatial_port = null
	combat_port = null
	encounter_port = null
	presentation_port = null
	presentation_projector = null
	encounter_domain = null
	encounter_spawn_binding = null
	encounter_step_result = {}
	encounter_spawn_results = []
	_static_visual_bindings = []
	entity_registry = ActorRegistryScript.new()
	lifecycle = Lifecycle.EMPTY


## Retires the mounted room's kernel before the SimulationWorld is replaced.
## shutdown() is safe on unconfigured kernels and idempotent, so clean
## unmounts and failed-mount cleanup can both call it unconditionally. The
## actor registrations are cleared first, while the kernel can still resolve
## their structural removals; a shut-down kernel can never be reconfigured,
## which is why restart_room_instance keeps using the live kernel.
func _shutdown_simulation_kernel() -> void:
	if simulation != null and simulation.kernel != null:
		simulation.kernel.shutdown()


func _clear_actor_registrations() -> void:
	if actor_registry != null:
		for actor_id: String in actor_registry.actor_ids():
			actor_registry.unregister_actor(actor_id)
	# Unmount is an authority boundary with no following kernel tick.  The
	# normal structural phase reclaims tombstones at tick end, but a stale
	# external reference to the old SimulationWorld must not keep room records
	# alive after this boundary.
	if entity_registry != null and entity_registry.store() != null:
		entity_registry.store().reclaim_tombstones()
	actor_registry = null


func _simulation_report() -> Dictionary:
	if simulation == null:
		return {}
	return {
		"configured": simulation.kernel != null and simulation.kernel.is_configured(),
		"tick": simulation.kernel.tick if simulation.kernel != null else 0,
		"tick_rate": simulation.kernel.tick_rate if simulation.kernel != null else 0,
		"room_instance_id": simulation.kernel.room_instance_id if simulation.kernel != null else "",
		"world_revision": simulation.kernel.world_revision if simulation.kernel != null else -1,
		"latest_snapshot": simulation.latest_snapshot().serialize() if simulation.latest_snapshot() != null else [],
	}


func _room_identity_snapshot() -> Dictionary:
	var definition_snapshot: Dictionary = room_definition.snapshot() if room_definition != null else {}
	return {
		"room_id": String(definition_snapshot.get("room_id", "")),
		"world_asset_id": String(definition_snapshot.get("world_asset_id", "")),
		"scene_id": String(native_scene_contract.get("scene_id", "")),
		"layout_id": String(native_scene_contract.get("layout_id", "")),
	}


class DefaultEncounterSpawnPort extends "res://src/runtime/world/room_encounter_spawn_port.gd":

	var _owner: SceneRuntime = null

	func bind(owner: SceneRuntime) -> Dictionary:
		if owner == null or not is_instance_valid(owner):
			return {"ok": false, "error": "encounter_spawn_owner_unavailable"}
		_owner = owner
		return {"ok": true, "error": ""}

	func spawn(request: EncounterSpawnRequest, context: Dictionary) -> Variant:
		if _owner == null or not is_instance_valid(_owner):
			return EncounterSpawnResultScript.failed(request, "runtime_not_ready")
		return _owner._spawn_encounter_request(request, context)

