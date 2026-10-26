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

var _main: MainArena


func _init(main: MainArena) -> void:
	_main = main


func _configure_actor_registry() -> bool:
	var room_key := _main.room_id.strip_edges()
	if room_key.is_empty():
		push_error("actor_registry_configuration_failed:missing_room_id")
		return false
	if _main.scene_runtime != null and not _main.scene_runtime.is_ready():
		push_error("actor_registry_configuration_failed:scene_runtime_not_ready")
		return false
	var injected_runtime: bool = _main.scene_runtime != null
	if injected_runtime:
		# SceneRuntime is the only authority for a mounted room: its actor
		# access, SimulationWorld, and the world's bound ports are adopted
		# as-is. Main must never rebuild or replace them here, including when
		# presentation is disabled.
		_main.actor_registry = _main.scene_runtime.get("actor_registry")
		_main.simulation_world = _main.scene_runtime.get("simulation")
		_main.actor_registry_instance_id = String(_main.scene_runtime.get("room_instance_id"))
		_main.actor_registry_revision = int(_main.scene_runtime.get("world_revision"))
		if _main.actor_registry == null or _main.simulation_world == null or _main.actor_registry_instance_id.is_empty():
			push_error("actor_registry_configuration_failed:injected_access_missing")
			return false
		_main.room_spatial_port = _main.scene_runtime.get("spatial_port")
		_main.room_combat_port = _main.scene_runtime.get("combat_port")
		_main.room_encounter_port = _main.scene_runtime.get("encounter_port")
		if _main.presentation_enabled:
			_main.scene_runtime.clear_actor_presentation_bindings()
			var presentation_ready: Dictionary = _main.scene_runtime.prepare_presentation()
			if not bool(presentation_ready.get("ok", false)):
				push_error("presentation_projector_configuration_failed:%s" % String(presentation_ready.get("error", "unknown")))
				return false
	else:
		if not _configure_standalone_room_access(room_key):
			push_error("actor_registry_configuration_failed:standalone_access_failed")
			return false
	if not _main._kernel_reconciler._bind_kernel_room_ports():
		_main.actor_registry_instance_id = ""
		return false
	var movement_policy_port := MainMovementPolicyPortScript.new()
	var movement_policy_bound: Dictionary = movement_policy_port.bind(_main)
	if not bool(movement_policy_bound.get("ok", false)):
		push_error("actor_registry_configuration_failed:movement_policy_port:%s" % String(movement_policy_bound.get("error", "unknown")))
		_main.actor_registry_instance_id = ""
		return false
	_main.actor_registry.set_movement_policy_port(movement_policy_port)
	var preserved_sim_tick := _main.sim_tick
	if _main.actor_registry.has_method("reset_actors"):
		var reset_result: Dictionary = _main.actor_registry.reset_actors()
		if not bool(reset_result.get("ok", false)):
			push_error("actor_registry_configuration_failed:actor_reset:%s" % str(reset_result))
			_main.actor_registry_instance_id = ""
			return false
	if not _main.actor_registry.has_method("has_movement_boundary") or not bool(_main.actor_registry.has_movement_boundary()):
		push_error("manifest_movement_boundary_missing:%s" % _main.layout_id)
		push_error("actor_registry_configuration_failed:movement_boundary_missing")
		_main.actor_registry_instance_id = ""
		return false
	var spawn_position: Vector2
	if injected_runtime:
		var authored_spawn: Variant = _main._room_socket("combat/spawn")
		if not authored_spawn is Vector2 or not _main.actor_registry.is_position_clear(authored_spawn, 14.0):
			push_error("actor_registry_configuration_failed:invalid_player_spawn:%s" % str(authored_spawn))
			return false
		spawn_position = authored_spawn
	else:
		var projected: Dictionary = _main._geometry._project_actor_spawn_position(_main._arena_rect().get_center() + Vector2(-220.0, 100.0), 14.0)
		if not bool(projected.get("ok", false)):
			return false
		spawn_position = _main._geometry._quantize_position(projected["position"])
	var player_result: Dictionary = _main.actor_registry.register_actor("ranger", spawn_position, 14.0, 1, &"soft", [&"movement", &"hurtbox"])
	if not bool(player_result.get("ok", false)):
		push_error("actor_registry_configuration_failed:player_registration:%s" % str(player_result))
		_main.actor_registry_instance_id = ""
		return false
	if injected_runtime and _main.presentation_enabled and not _bind_runtime_actor_presentation("ranger", "ranger.south.idle", 2):
		return false
	for enemy: CombatEnemyState in _main.enemies:
		if not _register_enemy_actor(enemy):
			push_error("actor_registry_configuration_failed:enemy_registration:%d" % enemy.entity_id)
			_main.actor_registry_instance_id = ""
			return false
	# Standalone Main fixtures do not own a SceneRuntime/RoomEncounter port.
	# Mounted production rooms do, and must bind the Boss domain to that typed
	# encounter authority. Keep the standalone authority self-contained so
	# geometry and combat tests can exercise a Boss without inventing a second
	# encounter runtime.
	if _main.scene_runtime != null and not _bind_boss_production_encounter():
		_main.actor_registry_instance_id = ""
		return false
	# The mounted SimulationWorld starts at tick zero.  A live room never
	# rewinds or fabricates its authority tick during actor registration.
	if not _main._configure_player_domain(preserved_sim_tick):
		push_error("actor_registry_configuration_failed:player_domain:%s" % _main.last_save_message)
		_main.actor_registry_instance_id = ""
		return false
	return true


func _configure_standalone_room_access(room_key: String) -> bool:
	_main.actor_registry_revision += 1
	_main.actor_registry_instance_id = "combat/%s/%d" % [room_key, _main.actor_registry_revision]
	var boundary := ArenaGeometryScript.movement_boundary(_main.layout_id, _main._arena_rect())
	if boundary.is_empty():
		return false
	var static_build: Dictionary = StaticSpatialIndexScript.build({
		"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION,
		"asset_id": "runtime/%s" % _main.layout_id,
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
	_main.simulation_world = SimulationWorldScript.new(spatial_port, combat_port, encounter_port, presentation_port, raw_registry)
	var configured = _main.simulation_world.configure(_main.actor_registry_instance_id, _main.actor_registry_revision, MainArena.SIM_TICKS_PER_SECOND)
	if not configured.ok:
		return false
	var access = RoomActorAccessScript.new()
	var access_result: Dictionary = access.configure(_main.simulation_world, raw_registry, static_index, dynamic_index, movement_build.get("value"), overlay)
	if not bool(access_result.get("ok", false)):
		return false
	_main.actor_registry = access
	spatial_port.bind(access)
	combat_port.bind(access)
	_main.room_spatial_port = spatial_port
	_main.room_combat_port = combat_port
	_main.room_encounter_port = encounter_port
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
	if _main.scene_runtime == null or not _main.scene_runtime.is_ready():
		return true
	var encounter_domain: Variant = _main.scene_runtime.get("encounter_domain")
	if encounter_domain == null:
		return true
	var phase := String(encounter_domain.snapshot().get("phase", "")) if encounter_domain.has_method("snapshot") else ""
	if phase != "idle" and _main.sim_tick == 0 and encounter_domain.has_method("restart"):
		var restarted: Dictionary = encounter_domain.restart(_main.sim_tick)
		if not bool(restarted.get("ok", false)):
			_main.last_save_message = "Deployment blocked: %s" % String(restarted.get("error", "encounter_restart_failed"))
			return false
		phase = "idle"
	if phase == "idle":
		var started: Dictionary = _main.scene_runtime.start_encounter(_main.sim_tick)
		if not bool(started.get("ok", false)):
			_main.last_save_message = "Deployment blocked: %s" % String(started.get("error", "encounter_start_failed"))
			return false
	var encounter_port = _main.scene_runtime.get("encounter_port")
	if encounter_port != null and encounter_port.has_method("prime_spawn_requests"):
		encounter_port.prime_spawn_requests(_main.sim_tick)
	var materialized: Array[Dictionary] = _main.scene_runtime.materialize_encounter_spawns()
	for result: Dictionary in materialized:
		if String(result.get("kind", "")) == "failed":
			_main.last_save_message = "Deployment blocked: encounter_spawn_failed:%s" % String(result.get("error", "unknown"))
			return false
	return true


func _register_enemy_actor(enemy: CombatEnemyState) -> bool:
	if _main.actor_registry == null or enemy == null:
		push_error("enemy_actor_registration_failed:missing_dependency")
		return false
	var projected: Dictionary = _main._geometry._project_actor_spawn_position(enemy.position, 16.0)
	if not bool(projected.get("ok", false)):
		push_error("enemy_actor_registration_failed:projection:%d:%s" % [enemy.entity_id, str(projected)])
		return false
	var position: Vector2 = projected["position"]
	if not _main.actor_registry.is_position_clear(position, 16.0):
		push_error("enemy_actor_registration_failed:blocked:%d:%s" % [enemy.entity_id, str(position)])
		return false
	var drop_tags: Array[String] = []
	for tag: Variant in _main.room_drop_tags:
		drop_tags.append(String(tag))
	var registered: Dictionary = _main.actor_registry.register_actor(
		"enemy/%d" % enemy.entity_id, position, 16.0, maxi(1, roundi(enemy.health)), &"soft",
		[&"movement", &"hurtbox"], PackedStringArray(), maxf(1.0, enemy.maximum_health), {},
		enemy.kind_id, "enemy/%d" % enemy.entity_id, drop_tags
	)
	if not bool(registered.get("ok", false)):
		push_error("enemy_actor_registration_failed:register:%d:%s" % [enemy.entity_id, str(registered)])
	if bool(registered.get("ok", false)):
		enemy.position = position
		_main._enemy_stable_keys["actor/%d" % int(registered.stable_key)] = enemy.entity_id
		if enemy.is_boss and not _register_boss_kernel_target(enemy, int(registered.stable_key), _main.enemies.find(enemy)):
			return false
		if _main.scene_runtime != null and _main.presentation_enabled:
			var role := "melee"
			match enemy.kind_id:
				"charging_raider": role = "charger"
				"fan_ranged": role = "ranged"
			if not _bind_runtime_actor_presentation("enemy/%d" % enemy.entity_id, "enemy.%s.idle" % role, 1):
				return false
	return bool(registered.get("ok", false))


func _register_boss_kernel_target(enemy: CombatEnemyState, stable_key: int, ordinal: int) -> bool:
	if not _main._kernel_reconciler._boss_domain_room_is_current():
		push_error("boss_domain_registration_room_mismatch")
		return false
	if stable_key < 1 or ordinal < 0:
		push_error("boss_domain_registration_identity_invalid:%d:%d" % [enemy.entity_id, stable_key])
		return false
	var maximum: BigValue = _main.combat_system.outcome_snapshot().boss_maximum
	if maximum == null or maximum.is_zero():
		push_error("boss_domain_maximum_unavailable:%d" % enemy.entity_id)
		return false
	var target_key := "actor/%d" % stable_key
	var drop_tags: Array[String] = []
	for tag: Variant in _main.room_drop_tags:
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
	var registered: Dictionary = _main._boss_combat_domain.register_target(target)
	if not bool(registered.get("ok", false)):
		push_error("boss_domain_target_registration_failed:%s" % String(registered.get("error", "unknown")))
		return false
	_main._boss_domain_targets[int(enemy.entity_id)] = target
	return true


func _production_boss_spawn_key(enemy: CombatEnemyState, ordinal: int) -> String:
	return "wave.production/%s.%d/0" % [enemy.kind_id, ordinal]


func _bind_boss_production_encounter() -> bool:
	if _main.boss == null:
		return true
	if _main.scene_runtime == null or not _main.scene_runtime.is_ready():
		push_error("boss_encounter_runtime_unavailable")
		return false
	# CombatRoomRuntime owns the single mixed-room encounter composition.  Its
	# production wave includes both ordinary roster actors and this Boss, so a
	# second Boss-only bind here would replace the shared domain and split
	# terminal/death authority.  Boss-only Main construction still uses this
	# fallback binding.
	var mounted_room_roster: Variant = _main.framework_room.get("enemy_ids", [])
	if mounted_room_roster is Array and not (mounted_room_roster as Array).is_empty():
		return true
	var spawns: Array = []
	for index: int in _main.enemies.size():
		var enemy: CombatEnemyState = _main.enemies[index]
		spawns.append({
			"spawn_id": "%s.%d" % [enemy.kind_id, index],
			"archetype_id": enemy.kind_id,
			"socket_id": "combat/encounter-origin",
			"count": 1,
		})
	var encounter := RoomEncounterScript.new()
	var configured: Dictionary = encounter.configure(_main.room_id, [{
		"wave_id": "wave.production",
		"clear_policy": "all_dead",
		"spawns": spawns,
	}])
	if not bool(configured.get("ok", false)):
		push_error("boss_encounter_configure_failed:%s" % String(configured.get("error", "unknown")))
		return false
	var bound: Dictionary = _main.scene_runtime.bind_encounter(encounter, _main.encounter_spawn_port)
	if not bool(bound.get("ok", false)):
		push_error("boss_encounter_bind_failed:%s" % String(bound.get("error", "unknown")))
		return false
	var started: Dictionary = _main.scene_runtime.start_encounter(_main.sim_tick)
	if not bool(started.get("ok", false)):
		push_error("boss_encounter_start_failed:%s" % String(started.get("error", "unknown")))
		return false
	_main.room_encounter_port = _main.scene_runtime.get("encounter_port")
	_main._boss_encounter_authority = true
	return true


func _bind_runtime_actor_presentation(actor_id: String, visual_id: String, rank: int) -> bool:
	if _main.scene_runtime == null or not _main.presentation_enabled:
		return true
	var world_view: Variant = _main.presentation.world_view if _main.presentation != null else null
	if world_view == null or not world_view.has_method("sprite_art_box"):
		push_error("presentation_art_box_unavailable:%s" % visual_id)
		return false
	var world_box: Rect2 = world_view.sprite_art_box(visual_id, Vector2.ZERO)
	if world_box.size.x <= 0.0 or world_box.size.y <= 0.0:
		push_error("presentation_art_box_missing:%s" % visual_id)
		return false
	# Simulation actors use authored gameplay pixels while the skin draws at its
	# fixed world scale. Convert the real art box once into the projector's
	# detached gameplay coordinate domain; never substitute the hurtbox radius.
	var scale := ArenaWorldViewScript.GAMEPLAY_TO_WORLD
	var gameplay_box := Rect2(world_box.position / scale, world_box.size / scale)
	var bound: Dictionary = _main.scene_runtime.bind_actor_presentation(actor_id, visual_id, rank, gameplay_box)
	if not bool(bound.get("ok", false)):
		push_error("presentation_binding_failed:%s:%s" % [actor_id, String(bound.get("error", "unknown"))])
		return false
	return true


func _ensure_actor_registry_ready() -> bool:
	if _main.actor_registry_instance_id.is_empty():
		if not _configure_actor_registry():
			return false
	return _main.actor_registry != null and _main.actor_registry.has_actor("ranger")


func _commit_actor_move(actor_id: String, displacement: Vector2, movement_policy: Variant = null) -> Dictionary:
	if not _ensure_actor_registry_ready():
		return {"ok": false, "error": "actor_registry_not_ready", "position": Vector2.ZERO, "displacement": Vector2.ZERO}
	var state = _main.actor_registry.actor(actor_id)
	if state == null:
		return {"ok": false, "error": "actor_not_registered", "position": Vector2.ZERO, "displacement": Vector2.ZERO}
	if movement_policy == null and actor_id == "ranger" and _has_active_charge():
		movement_policy = _charge_movement_policy_value()
	var result: Dictionary = _main.actor_registry.move_actor(actor_id, displacement, _main.sim_tick, movement_policy)
	if not bool(result.get("ok", false)):
		if String(result.get("error", "")) in ["non_monotonic_motor_tick", "non_monotonic_movement_tick"]:
			return result
		push_error("actor_move_failed:%s:%s" % [actor_id, String(result.get("error", "unknown"))])
		return result
	return result


func _charge_movement_policy_value() -> Variant:
	if _main._charge_movement_policy != null:
		return _main._charge_movement_policy
	var built: Dictionary = BodyCollisionPolicyScript.make({
		"solid": {"response": BodyCollisionPolicyScript.RESPONSE_BLOCK, "record": true},
		"soft": {"response": BodyCollisionPolicyScript.RESPONSE_IGNORE, "record": true},
		"ghost": {"response": BodyCollisionPolicyScript.RESPONSE_IGNORE, "record": true},
	})
	if bool(built.get("ok", false)):
		_main._charge_movement_policy = built.get("value")
	return _main._charge_movement_policy


## Main-owned mobility policy seam: an active dash/dodge crosses enemy soft
## bodies instead of being separated away, while contacts stay recorded for
## presentation. Normal movement keeps the default soft separation policy.
func _resolve_ranger_movement_policy(actor_id: String) -> Variant:
	if actor_id != "ranger" or _main.player_combat_state == null:
		return null
	var player: Dictionary = _main.player_combat_state.snapshot(_main.sim_tick)
	if int(player.get("dash_remaining_ticks", 0)) <= 0 and int(player.get("dodge_remaining_ticks", 0)) <= 0:
		return null
	return _mobility_policy_value()


func _mobility_policy_value() -> Variant:
	if _main._mobility_movement_policy != null:
		return _main._mobility_movement_policy
	var built: Dictionary = BodyCollisionPolicyScript.make({
		"solid": {"response": BodyCollisionPolicyScript.RESPONSE_BLOCK, "record": true},
		"soft": {"response": BodyCollisionPolicyScript.RESPONSE_IGNORE, "record": true},
		"ghost": {"response": BodyCollisionPolicyScript.RESPONSE_IGNORE, "record": true},
	})
	if bool(built.get("ok", false)):
		_main._mobility_movement_policy = built.get("value")
	return _main._mobility_movement_policy


func _has_active_charge() -> bool:
	for enemy: CombatEnemyState in _main.enemies:
		if enemy != null and enemy.action_state == "active" and enemy.action_id == "charge":
			return true
	return false


func _move_enemy_actor(enemy: CombatEnemyState, displacement: Vector2) -> Dictionary:
	var before := enemy.position
	var movement_policy: Variant = null
	if enemy.action_state == "active" and enemy.action_id == "charge":
		movement_policy = _charge_movement_policy_value()
	var result := _commit_actor_move("enemy/%d" % enemy.entity_id, displacement, movement_policy)
	if bool(result.get("ok", false)):
		enemy.position = result.get("position", before)
		enemy.facing = result.get("facing", enemy.facing)
	return result


func _set_enemy_collision_class(enemy: CombatEnemyState, collision_class: StringName) -> bool:
	if enemy == null or _main.actor_registry == null or not _main.actor_registry.has_method("set_collision_class"):
		return false
	var result: Dictionary = _main.actor_registry.set_collision_class("enemy/%d" % enemy.entity_id, collision_class)
	if not bool(result.get("ok", false)):
		push_error("enemy_collision_class_update_failed:%d:%s" % [enemy.entity_id, String(result.get("error", "unknown"))])
		return false
	return true
