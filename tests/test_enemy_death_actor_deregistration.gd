extends SceneTree

const Items := preload("res://src/content/early_item_registry.gd")
const Resolver := preload("res://src/systems/build_resolver.gd")
const RoomRuntime := preload("res://src/game/combat_room_runtime.gd")
const Assert := preload("res://tests/helpers/assert.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var items := Items.new()
	_expect(items.load_all().is_empty(), "death deregistration: item registry failed to load")
	if not _failures.is_empty():
		_finish()
		return
	var resolved: Dictionary = Resolver.new(items).resolve_fixture("calibration_convergent")
	_expect(bool(resolved.get("ok", false)), "death deregistration: resolved combat build was rejected")
	if not bool(resolved.get("ok", false)):
		_finish()
		return

	var runtime := RoomRuntime.new()
	root.add_child(runtime)
	var started := runtime.start_session({
		"mode": "Manual",
		"presentation_enabled": false,
		"seed": 90210,
		"room": {
			"room_id": "test.enemy.death.deregistration",
			"layout_id": "rectangle_arena",
			"objective_id": "clear",
			"hazard_ids": [],
			"enemy_ids": ["melee_pursuer"],
			"elite_rule_ids": [],
			"boss_id": "",
			"drop_tags": [],
			"loot_slots": [{
				"slot_id": "enemy_death_drop",
				"source": "enemy_death",
				"tag": "equipment_general",
				"pickup_radius": 18.0,
			}],
		},
		"framework_context": {
			"active_build": {"skills": ["piercing_arrow", "hunter_mark", "dash"]},
			"resolved_build": resolved,
		},
	})
	_expect(bool(started.get("ok", false)), "death deregistration: mounted runtime failed to start: %s" % String(started.get("error", "")))
	if not bool(started.get("ok", false)):
		_sever_kernel_cycle(runtime)
		runtime.free()
		_finish()
		return
	runtime.set_process(false)
	var arena: Node = runtime.room_instance
	arena.set_process(false)
	var enemies: Array = arena.enemies
	if enemies.is_empty():
		_expect(false, "death deregistration: mounted room did not create a live enemy")
		_sever_kernel_cycle(runtime)
		runtime.free()
		_finish()
		return

	var enemy = enemies[0]
	var entity_id := int(enemy.entity_id)
	var actor_id := "enemy/%d" % entity_id
	var registry = arena.actor_registry
	_expect(registry != null, "death deregistration: actor registry was not mounted")
	_expect(registry != null and registry.has_actor(actor_id), "death deregistration: enemy actor was not registered before death")
	var entity_handle = registry.actor_handle(actor_id) if registry != null else null

	# Keep the 120-pixel projectile lane north of the whole scenery blockers.
	var center: Vector2 = arena._arena_rect().get_center() + Vector2(0, -36)
	_expect(bool(arena.teleport_actor("ranger", center).get("ok", false)), "death deregistration: ranger fixture placement failed")
	_expect(bool(arena.teleport_actor(actor_id, center + Vector2.RIGHT * 120.0).get("ok", false)), "death deregistration: target placement failed")
	enemy.health = 1.0
	enemy.maximum_health = 1.0
	var death_position: Vector2 = enemy.position

	var cast: Dictionary = arena.request_player_cast("piercing_arrow", entity_id)
	_expect(bool(cast.get("accepted", false)), "death deregistration: real arrow was rejected: %s" % str(cast))
	var dead := _advance_until(arena, func() -> bool:
		return arena._enemy_by_entity_id(entity_id) == null
	, 120)
	_expect(dead, "death deregistration: enemy did not die through the mounted projectile path")
	if not dead:
		_sever_kernel_cycle(runtime)
		runtime.free()
		_finish()
		return
	_expect((arena.room_loot_snapshot.get("entities", []) as Array).size() == 1, "death deregistration: enemy death did not spawn one room loot entity")

	# Control: the live player record must survive the enemy death settlement.
	_expect(registry.has_actor("ranger"), "death deregistration: ranger actor record was lost during enemy death")
	_expect(registry.registry != null and entity_handle != null and not registry.registry.is_live(entity_handle), "death deregistration: dead enemy entity stayed live in the actor store")
	_expect(not registry.has_actor(actor_id), "death deregistration: dead enemy actor id stayed live in the room access")
	_expect(not registry.actor_ids().has(actor_id), "death deregistration: dead enemy actor id remained in the room id map")

	var dynamic_index = registry.dynamic_index
	_expect(dynamic_index != null, "death deregistration: dynamic spatial index was not mounted")
	_expect(dynamic_index == null or not dynamic_index.entity_ids().has(actor_id), "death deregistration: dead enemy body remained in the dynamic index")
	var hurtbox_contacts: Array = dynamic_index.overlaps(&"hurtbox", death_position, 16.0) if dynamic_index != null else []
	var corpse_contacts := 0
	for contact: Dictionary in hurtbox_contacts:
		if String(contact.get("entity_id", "")) == actor_id:
			corpse_contacts += 1
	_expect(corpse_contacts == 0, "death deregistration: corpse still produced hurtbox contacts")
	_expect(bool(registry.is_position_clear(death_position, 16.0)), "death deregistration: corpse still blocked a soft-collision clearance query")

	_sever_kernel_cycle(runtime)
	runtime.request_abandon()
	runtime.free()
	_finish()


func _arena_step(arena: Node) -> void:
	arena.call("_simulate_tick")


## Explicit teardown: sever the kernel -> port -> access -> registry borrow
## cycle while the runtime node still holds the room graph, so the retired
## kernel frees instead of leaking ObjectDB instances at engine exit.
func _sever_kernel_cycle(runtime: Variant) -> void:
	if runtime == null or not is_instance_valid(runtime):
		return
	var mounted = runtime.scene_runtime
	if mounted != null and mounted.simulation != null and mounted.simulation.kernel != null:
		mounted.simulation.kernel.shutdown()


func _advance_until(arena: Node, predicate: Callable, limit: int) -> bool:
	for _index in limit:
		if bool(predicate.call()):
			return true
		_arena_step(arena)
	return bool(predicate.call())


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, _failures)


func _finish() -> void:
	for failure: String in _failures:
		printerr("- %s" % failure)
	print("PASS test_enemy_death_actor_deregistration.gd" if _failures.is_empty() else "FAIL test_enemy_death_actor_deregistration.gd")
	quit(0 if _failures.is_empty() else 1)
