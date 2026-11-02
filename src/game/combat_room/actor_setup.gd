class_name RoomActorSetup
extends RefCounted

## Actor registry and spatial setup extracted from MainArena: registry/world
## configuration for standalone and mounted rooms, enemy and Boss actor
## registration, movement policies and committed actor moves. Room state stays
## owned by MainArena and is reached through the typed owner reference.

const ArenaWorldViewScript := preload("res://src/presentation/arena_world_view.gd")
const ArenaGeometryScript = preload("res://src/runtime/geometry/arena_geometry.gd")
const ActorRegistryScript = preload("res://src/runtime/world/actor_registry.gd")
const SimulationWorldScript = preload("res://src/runtime/world/simulation_world.gd")
const StaticSpatialIndexScript = preload("res://src/runtime/spatial/static_spatial_index.gd")
const DynamicSpatialIndexScript = preload("res://src/runtime/spatial/dynamic_spatial_index.gd")
const SpatialOverlayScript = preload("res://src/runtime/spatial/spatial_overlay.gd")
const MovementResolverScript = preload("res://src/runtime/spatial/movement_resolver.gd")
const BodyCollisionPolicyScript = preload("res://src/runtime/spatial/body_collision_policy.gd")
const RoomActorAccessScript = preload("res://src/runtime/world/room_actor_access.gd")
const RoomSpatialPortScript = preload("res://src/runtime/world/room_spatial_port.gd")
const RoomCombatPortScript = preload("res://src/runtime/world/room_combat_port.gd")
const RoomEncounterPortScript = preload("res://src/runtime/world/room_encounter_port.gd")
const RoomPresentationPortScript = preload("res://src/runtime/world/room_presentation_port.gd")
const BossTargetViewScript := preload("res://src/runtime/combat/boss_target_view.gd")
const BossHurtboxScript := preload("res://src/runtime/combat/boss_hurtbox.gd")
const RoomEncounterScript := preload("res://src/runtime/encounter/room_encounter.gd")
const MainMovementPolicyPortScript := preload("res://src/game/ports/main_movement_policy_port.gd")

## Visual ids the room binds into the presentation projector (the player and
## the three enemy roles).
const ACTOR_VISUAL_IDS: Array[String] = ["ranger.south.idle", "enemy.melee.idle", "enemy.charger.idle", "enemy.ranged.idle"]

var _main: MainArena
## The room authority; read at use time, never cache its replaced members.
var _session: RoomSession
var _charge_movement_policy = null
var _mobility_movement_policy = null


func _init(main: MainArena) -> void:
	_main = main
	_session = main.session


func _configure_actor_registry() -> bool:
	var room_key := _session.room_id.strip_edges()
	if room_key.is_empty():
		push_error("actor_registry_configuration_failed:missing_room_id")
		return false
	if _session.scene_runtime != null and not _session.scene_runtime.is_ready():
		push_error("actor_registry_configuration_failed:scene_runtime_not_ready")
		return false
	var injected_runtime: bool = _session.scene_runtime != null
	if injected_runtime:
		# SceneRuntime is the only authority for a mounted room: its actor
		# access, SimulationWorld, and the world's bound ports are adopted
		# as-is. Main must never rebuild or replace them here, including when
		# presentation is disabled.
		_session.actor_registry = _session.scene_runtime.get("actor_registry")
		_session.simulation_world = _session.scene_runtime.get("simulation")
		_session.actor_registry_instance_id = String(_session.scene_runtime.get("room_instance_id"))
		_session.actor_registry_revision = int(_session.scene_runtime.get("world_revision"))
		if _session.actor_registry == null or _session.simulation_world == null or _session.actor_registry_instance_id.is_empty():
			push_error("actor_registry_configuration_failed:injected_access_missing")
			return false
		_session.room_spatial_port = _session.scene_runtime.get("spatial_port")
		_session.room_combat_port = _session.scene_runtime.get("combat_port")
		_session.room_encounter_port = _session.scene_runtime.get("encounter_port")
		if _main.presentation_enabled:
			# Art boxes are read once here, never while a tick spawns an enemy.
			_session.actor_art_boxes = _main.actor_art_boxes(ACTOR_VISUAL_IDS)
			_session.scene_runtime.clear_actor_presentation_bindings()
			var presentation_ready: Dictionary = _session.scene_runtime.prepare_presentation()
			if not bool(presentation_ready.get("ok", false)):
				push_error("presentation_projector_configuration_failed:%s" % String(presentation_ready.get("error", "unknown")))
				return false
	else:
		if not _configure_standalone_room_access(room_key):
			push_error("actor_registry_configuration_failed:standalone_access_failed")
			return false
	if not _main.kernel_reconciler.bind_kernel_room_ports():
		_session.actor_registry_instance_id = ""
		return false
	var movement_policy_port := MainMovementPolicyPortScript.new()
	var movement_policy_bound: Dictionary = movement_policy_port.bind(_main)
	if not bool(movement_policy_bound.get("ok", false)):
		push_error("actor_registry_configuration_failed:movement_policy_port:%s" % String(movement_policy_bound.get("error", "unknown")))
		_session.actor_registry_instance_id = ""
		return false
	_session.actor_registry.set_movement_policy_port(movement_policy_port)
	var preserved_sim_tick := _session.sim_tick
	if _session.actor_registry.has_method("reset_actors"):
		var reset_result: Dictionary = _session.actor_registry.reset_actors()
		if not bool(reset_result.get("ok", false)):
			push_error("actor_registry_configuration_failed:actor_reset:%s" % str(reset_result))
			_session.actor_registry_instance_id = ""
			return false
	if not _session.actor_registry.has_method("has_movement_boundary") or not bool(_session.actor_registry.has_movement_boundary()):
		push_error("manifest_movement_boundary_missing:%s" % _session.layout_id)
		push_error("actor_registry_configuration_failed:movement_boundary_missing")
		_session.actor_registry_instance_id = ""
		return false
	var spawn_position: Vector2
	if injected_runtime:
		var authored_spawn: Variant = _main.room_geometry.room_socket("combat/spawn")
		if not authored_spawn is Vector2 or not _session.actor_registry.is_position_clear(authored_spawn, 14.0):
			push_error("actor_registry_configuration_failed:invalid_player_spawn:%s" % str(authored_spawn))
			return false
		spawn_position = authored_spawn
	else:
		var projected: Dictionary = _main.room_geometry.project_actor_spawn_position(_main.room_geometry.arena_rect().get_center() + Vector2(-220.0, 100.0), 14.0)
		if not bool(projected.get("ok", false)):
			return false
		spawn_position = _main.room_geometry.quantize_position(projected["position"])
	var player_result: Dictionary = _session.actor_registry.register_actor(_session.kit.actor_id(), spawn_position, 14.0, 1, &"soft", [&"movement", &"hurtbox"])
	if not bool(player_result.get("ok", false)):
		push_error("actor_registry_configuration_failed:player_registration:%s" % str(player_result))
		_session.actor_registry_instance_id = ""
		return false
	if injected_runtime and _main.presentation_enabled and not _bind_runtime_actor_presentation(_session.kit.actor_id(), "ranger.south.idle", 2):
		return false
	for enemy: CombatEnemyState in _session.encounter_director.enemies:
		if not register_enemy_actor(enemy):
			push_error("actor_registry_configuration_failed:enemy_registration:%d" % enemy.entity_id)
			_session.actor_registry_instance_id = ""
			return false
	# Standalone Main fixtures do not own a SceneRuntime/RoomEncounter port.
	# Mounted production rooms do, and must bind the Boss domain to that typed
	# encounter authority. Keep the standalone authority self-contained so
	# geometry and combat tests can exercise a Boss without inventing a second
	# encounter runtime.
	if _session.scene_runtime != null and not _bind_boss_production_encounter():
		_session.actor_registry_instance_id = ""
		return false
	# The mounted SimulationWorld starts at tick zero.  A live room never
	# rewinds or fabricates its authority tick during actor registration.
	if not _main.configure_player_domain(preserved_sim_tick):
		push_error("actor_registry_configuration_failed:player_domain:%s" % _main.last_save_message)
		_session.actor_registry_instance_id = ""
		return false
	return true


func _configure_standalone_room_access(room_key: String) -> bool:
	_session.actor_registry_revision += 1
	_session.actor_registry_instance_id = "combat/%s/%d" % [room_key, _session.actor_registry_revision]
	var boundary := ArenaGeometryScript.movement_boundary(_session.layout_id, _main.room_geometry.arena_rect())
	if boundary.is_empty():
		return false
	var static_build: Dictionary = StaticSpatialIndexScript.build({
		"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION,
		"asset_id": "runtime/%s" % _session.layout_id,
		"surfaces": [],
		"movement_boundary": _boundary_for_static_index(boundary),
	})
	if not bool(static_build.get("ok", false)):
		return false
	var static_index = static_build.get("value")
	var dynamic_index = DynamicSpatialIndexScript.new()
	var overlay = SpatialOverlayScript.new()
	var movement_build: Dictionary = MovementResolverScript.make(static_index, overlay, dynamic_index)
	if not bool(movement_build.get("ok", false)):
		return false
	var spatial_port = RoomSpatialPortScript.new()
	var combat_port = RoomCombatPortScript.new()
	var encounter_port = RoomEncounterPortScript.new()
	var presentation_port = RoomPresentationPortScript.new()
	var raw_registry = ActorRegistryScript.new()
	_session.simulation_world = SimulationWorldScript.new(spatial_port, combat_port, encounter_port, presentation_port, raw_registry)
	var configured = _session.simulation_world.configure(_session.actor_registry_instance_id, _session.actor_registry_revision, MainArena.SIM_TICKS_PER_SECOND)
	if not configured.ok:
		return false
	var access = RoomActorAccessScript.new()
	var access_result: Dictionary = access.configure(_session.simulation_world, raw_registry, static_index, dynamic_index, movement_build.get("value"), overlay)
	if not bool(access_result.get("ok", false)):
		return false
	_session.actor_registry = access
	spatial_port.bind(access)
	combat_port.bind(access)
	_session.room_spatial_port = spatial_port
	_session.room_combat_port = combat_port
	_session.room_encounter_port = encounter_port
	return true


func _boundary_for_static_index(boundary: Dictionary) -> Dictionary:
	var kind := String(boundary.get("type", boundary.get("kind", "")))
	match kind:
		"rect", "corridor":
			var rect: Variant = boundary.get("rect", null)
			var value := {"kind": kind, "rect": rect}
			if kind == "corridor":
				value["half_height"] = float(boundary.get("half_height", 0.0))
			return value
		"ring":
			return {
				"kind": "ring",
				"center": boundary.get("center", Vector2.ZERO),
				"inner_radius": float(boundary.get("inner_radius", 0.0)),
				"outer_radius": float(boundary.get("outer_radius", 0.0)),
			}
	return {}


func _start_mounted_encounter() -> bool:
	if _session.scene_runtime == null or not _session.scene_runtime.is_ready():
		return true
	var encounter_domain: Variant = _session.scene_runtime.get("encounter_domain")
	if encounter_domain == null:
		return true
	var phase := String(encounter_domain.snapshot().get("phase", "")) if encounter_domain.has_method("snapshot") else ""
	if phase != "idle" and _session.sim_tick == 0 and encounter_domain.has_method("restart"):
		var restarted: Dictionary = encounter_domain.restart(_session.sim_tick)
		if not bool(restarted.get("ok", false)):
			_main.last_save_message = "Deployment blocked: %s" % String(restarted.get("error", "encounter_restart_failed"))
			return false
		phase = "idle"
	if phase == "idle":
		var started: Dictionary = _session.scene_runtime.start_encounter(_session.sim_tick)
		if not bool(started.get("ok", false)):
			_main.last_save_message = "Deployment blocked: %s" % String(started.get("error", "encounter_start_failed"))
			return false
	var encounter_port = _session.scene_runtime.get("encounter_port")
	if encounter_port != null and encounter_port.has_method("prime_spawn_requests"):
		encounter_port.prime_spawn_requests(_session.sim_tick)
	var materialized: Array[Dictionary] = _session.scene_runtime.materialize_encounter_spawns()
	for result: Dictionary in materialized:
		if String(result.get("kind", "")) == "failed":
			_main.last_save_message = "Deployment blocked: encounter_spawn_failed:%s" % String(result.get("error", "unknown"))
			return false
	return true


func register_enemy_actor(enemy: CombatEnemyState) -> bool:
	if _session.actor_registry == null or enemy == null:
		push_error("enemy_actor_registration_failed:missing_dependency")
		return false
	var projected: Dictionary = _main.room_geometry.project_actor_spawn_position(enemy.position, 16.0)
	if not bool(projected.get("ok", false)):
		push_error("enemy_actor_registration_failed:projection:%d:%s" % [enemy.entity_id, str(projected)])
		return false
	var position: Vector2 = projected["position"]
	if not _session.actor_registry.is_position_clear(position, 16.0):
		push_error("enemy_actor_registration_failed:blocked:%d:%s" % [enemy.entity_id, str(position)])
		return false
	var drop_tags: Array[String] = []
	for tag: Variant in _session.room_drop_tags:
		drop_tags.append(String(tag))
	var registered: Dictionary = _session.actor_registry.register_actor(
		"enemy/%d" % enemy.entity_id, position, 16.0, maxi(1, roundi(enemy.health)), &"soft",
		[&"movement", &"hurtbox"], PackedStringArray(), maxf(1.0, enemy.maximum_health), {},
		enemy.kind_id, "enemy/%d" % enemy.entity_id, drop_tags
	)
	if not bool(registered.get("ok", false)):
		push_error("enemy_actor_registration_failed:register:%d:%s" % [enemy.entity_id, str(registered)])
	if bool(registered.get("ok", false)):
		enemy.position = position
		_session.kernel_bindings.enemy_stable_keys["actor/%d" % int(registered.stable_key)] = enemy.entity_id
		if enemy.is_boss and not _register_boss_kernel_target(enemy, int(registered.stable_key), _session.encounter_director.enemies.find(enemy)):
			return false
		if _session.scene_runtime != null and _main.presentation_enabled:
			var role := "melee"
			match enemy.kind_id:
				"charging_raider": role = "charger"
				"fan_ranged": role = "ranged"
			if not _bind_runtime_actor_presentation("enemy/%d" % enemy.entity_id, "enemy.%s.idle" % role, 1):
				return false
	return bool(registered.get("ok", false))


func _register_boss_kernel_target(enemy: CombatEnemyState, stable_key: int, ordinal: int) -> bool:
	if not _main.kernel_reconciler.boss_domain_room_is_current():
		push_error("boss_domain_registration_room_mismatch")
		return false
	if stable_key < 1 or ordinal < 0:
		push_error("boss_domain_registration_identity_invalid:%d:%d" % [enemy.entity_id, stable_key])
		return false
	var maximum: BigValue = _session.combat_system.outcome_snapshot().boss_maximum
	if maximum == null or maximum.is_zero():
		push_error("boss_domain_maximum_unavailable:%d" % enemy.entity_id)
		return false
	var target_key := "actor/%d" % stable_key
	var drop_tags: Array[String] = []
	for tag: Variant in _session.room_drop_tags:
		drop_tags.append(String(tag))
	var target := BossTargetViewScript.make(
		target_key,
		maximum,
		enemy.position,
		enemy.kind_id,
		_production_boss_spawn_key(enemy, ordinal),
		drop_tags
	)
	for part: Dictionary in enemy.hurtbox_parts():
		var hurtbox: Variant = (part.get("hurtbox", {}) as Dictionary).get("radius", null)
		var boss_part := BossHurtboxScript.make(
			String(part.get("part_id", "")),
			String(part.get("damage_group_id", "body")),
			part.get("pose", Vector2.ZERO),
			float(hurtbox),
			bool(part.get("active", true)),
			bool(part.get("broken", false))
		)
		var added: Dictionary = target.add_part(boss_part)
		if not bool(added.get("ok", false)):
			push_error("boss_domain_part_registration_failed:%s" % String(added.get("error", "unknown")))
			return false
	var registered: Dictionary = _session.kernel_bindings.boss_domain.register_target(target)
	if not bool(registered.get("ok", false)):
		push_error("boss_domain_target_registration_failed:%s" % String(registered.get("error", "unknown")))
		return false
	_session.kernel_bindings.boss_domain_targets[int(enemy.entity_id)] = target
	return true


func _production_boss_spawn_key(enemy: CombatEnemyState, ordinal: int) -> String:
	return "wave.production/%s.%d/0" % [enemy.kind_id, ordinal]


func _bind_boss_production_encounter() -> bool:
	if _session.encounter_director.boss == null:
		return true
	if _session.scene_runtime == null or not _session.scene_runtime.is_ready():
		push_error("boss_encounter_runtime_unavailable")
		return false
	# CombatRoomRuntime owns the single mixed-room encounter composition.  Its
	# production wave includes both ordinary roster actors and this Boss, so a
	# second Boss-only bind here would replace the shared domain and split
	# terminal/death authority.  Boss-only Main construction still uses this
	# fallback binding.
	var mounted_room_roster: Variant = _session.framework_room.get("enemy_ids", [])
	if mounted_room_roster is Array and not (mounted_room_roster as Array).is_empty():
		return true
	var spawns: Array = []
	for index: int in _session.encounter_director.enemies.size():
		var enemy: CombatEnemyState = _session.encounter_director.enemies[index]
		spawns.append({
			"spawn_id": "%s.%d" % [enemy.kind_id, index],
			"archetype_id": enemy.kind_id,
			"socket_id": "combat/encounter-origin",
			"count": 1,
		})
	var encounter := RoomEncounterScript.new()
	var configured: Dictionary = encounter.configure(_session.room_id, [{
		"wave_id": "wave.production",
		"clear_policy": "all_dead",
		"spawns": spawns,
	}])
	if not bool(configured.get("ok", false)):
		push_error("boss_encounter_configure_failed:%s" % String(configured.get("error", "unknown")))
		return false
	var bound: Dictionary = _session.scene_runtime.bind_encounter(encounter, _session.encounter_spawn_port)
	if not bool(bound.get("ok", false)):
		push_error("boss_encounter_bind_failed:%s" % String(bound.get("error", "unknown")))
		return false
	var started: Dictionary = _session.scene_runtime.start_encounter(_session.sim_tick)
	if not bool(started.get("ok", false)):
		push_error("boss_encounter_start_failed:%s" % String(started.get("error", "unknown")))
		return false
	_session.room_encounter_port = _session.scene_runtime.get("encounter_port")
	return true


func _bind_runtime_actor_presentation(actor_id: String, visual_id: String, rank: int) -> bool:
	if _session.scene_runtime == null or not _main.presentation_enabled:
		return true
	if not _session.actor_art_boxes.has(visual_id):
		push_error("presentation_art_box_unavailable:%s" % visual_id)
		return false
	var world_box: Rect2 = _session.actor_art_boxes[visual_id]
	if world_box.size.x <= 0.0 or world_box.size.y <= 0.0:
		push_error("presentation_art_box_missing:%s" % visual_id)
		return false
	# Simulation actors use authored gameplay pixels while the skin draws at its
	# fixed world scale. Convert the real art box once into the projector's
	# detached gameplay coordinate domain; never substitute the hurtbox radius.
	var scale := ArenaWorldViewScript.GAMEPLAY_TO_WORLD
	var gameplay_box := Rect2(world_box.position / scale, world_box.size / scale)
	var bound: Dictionary = _session.scene_runtime.bind_actor_presentation(actor_id, visual_id, rank, gameplay_box)
	if not bool(bound.get("ok", false)):
		push_error("presentation_binding_failed:%s:%s" % [actor_id, String(bound.get("error", "unknown"))])
		return false
	return true


func _ensure_actor_registry_ready() -> bool:
	if _session.actor_registry_instance_id.is_empty():
		if not _configure_actor_registry():
			return false
	return _session.actor_registry != null and _session.actor_registry.has_actor(_session.kit.actor_id())


func _commit_actor_move(actor_id: String, displacement: Vector2, movement_policy: Variant = null) -> Dictionary:
	if not _ensure_actor_registry_ready():
		return {"ok": false, "error": "actor_registry_not_ready", "position": Vector2.ZERO, "displacement": Vector2.ZERO}
	var state = _session.actor_registry.actor(actor_id)
	if state == null:
		return {"ok": false, "error": "actor_not_registered", "position": Vector2.ZERO, "displacement": Vector2.ZERO}
	if movement_policy == null and actor_id == _session.kit.actor_id() and _has_active_charge():
		movement_policy = _charge_movement_policy_value()
	var result: Dictionary = _session.actor_registry.move_actor(actor_id, displacement, _session.sim_tick, movement_policy)
	if not bool(result.get("ok", false)):
		if String(result.get("error", "")) in ["non_monotonic_motor_tick", "non_monotonic_movement_tick"]:
			return result
		push_error("actor_move_failed:%s:%s" % [actor_id, String(result.get("error", "unknown"))])
		return result
	return result


func _charge_movement_policy_value() -> Variant:
	if _charge_movement_policy != null:
		return _charge_movement_policy
	var built: Dictionary = BodyCollisionPolicyScript.make({
		"solid": {"response": BodyCollisionPolicyScript.RESPONSE_BLOCK, "record": true},
		"soft": {"response": BodyCollisionPolicyScript.RESPONSE_IGNORE, "record": true},
		"ghost": {"response": BodyCollisionPolicyScript.RESPONSE_IGNORE, "record": true},
	})
	if bool(built.get("ok", false)):
		_charge_movement_policy = built.get("value")
	return _charge_movement_policy


## Main-owned mobility policy seam: an active dash/dodge crosses enemy soft
## bodies instead of being separated away, while contacts stay recorded for
## presentation. Normal movement keeps the default soft separation policy.
func resolve_ranger_movement_policy(actor_id: String) -> Variant:
	if actor_id != _session.kit.actor_id() or _session.player_combat_state == null:
		return null
	var player: Dictionary = _session.player_combat_state.snapshot(_session.sim_tick)
	if int(player.get("dash_remaining_ticks", 0)) <= 0 and int(player.get("dodge_remaining_ticks", 0)) <= 0:
		return null
	return _mobility_policy_value()


func _mobility_policy_value() -> Variant:
	if _mobility_movement_policy != null:
		return _mobility_movement_policy
	var built: Dictionary = BodyCollisionPolicyScript.make({
		"solid": {"response": BodyCollisionPolicyScript.RESPONSE_BLOCK, "record": true},
		"soft": {"response": BodyCollisionPolicyScript.RESPONSE_IGNORE, "record": true},
		"ghost": {"response": BodyCollisionPolicyScript.RESPONSE_IGNORE, "record": true},
	})
	if bool(built.get("ok", false)):
		_mobility_movement_policy = built.get("value")
	return _mobility_movement_policy


func _has_active_charge() -> bool:
	for enemy: CombatEnemyState in _session.encounter_director.enemies:
		if enemy != null and enemy.action_state == "active" and enemy.action_id == "charge":
			return true
	return false


func move_enemy_actor(enemy: CombatEnemyState, displacement: Vector2) -> Dictionary:
	var before := enemy.position
	var movement_policy: Variant = null
	if enemy.action_state == "active" and enemy.action_id == "charge":
		movement_policy = _charge_movement_policy_value()
	var result := _commit_actor_move("enemy/%d" % enemy.entity_id, displacement, movement_policy)
	if bool(result.get("ok", false)):
		enemy.position = result.get("position", before)
		enemy.facing = result.get("facing", enemy.facing)
	return result


func set_enemy_collision_class(enemy: CombatEnemyState, collision_class: StringName) -> bool:
	if enemy == null or _session.actor_registry == null or not _session.actor_registry.has_method("set_collision_class"):
		return false
	var result: Dictionary = _session.actor_registry.set_collision_class("enemy/%d" % enemy.entity_id, collision_class)
	if not bool(result.get("ok", false)):
		push_error("enemy_collision_class_update_failed:%d:%s" % [enemy.entity_id, String(result.get("error", "unknown"))])
		return false
	return true
