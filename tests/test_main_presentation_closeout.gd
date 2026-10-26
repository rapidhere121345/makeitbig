extends SceneTree

const Runtime := preload("res://src/game/combat_room_runtime.gd")
const ItemRegistry := preload("res://src/content/early_item_registry.gd")
const BuildResolver := preload("res://src/systems/build_resolver.gd")
const Geometry := preload("res://src/runtime/geometry/arena_geometry.gd")
const Enemy := preload("res://src/runtime/world/combat_enemy_state.gd")

const Controller := preload("res://src/presentation/combat_presentation_controller.gd")
const Adapter := preload("res://src/presentation/combat_input_adapter.gd")
const CommandSource := preload("res://src/systems/combat_command_source.gd")
const Protocol := preload("res://src/systems/combat_command_protocol.gd")
const Snapshot := preload("res://src/presentation/combat_presentation_snapshot.gd")
const ThemeScript := preload("res://src/presentation/shell_theme.gd")
const Assert := preload("res://tests/helpers/assert.gd")

var failures: Array[String] = []


class FixtureCommandPort:
	extends "res://src/systems/combat_command_source_port.gd"

	var adapter: RefCounted = null
	var cast_factory := Callable()

	func bind(input_adapter: RefCounted, factory: Callable) -> void:
		adapter = input_adapter
		cast_factory = factory

	func make_cast(ability: String, target_entity_id: int, direction: Vector2) -> Dictionary:
		return cast_factory.call(ability, target_entity_id, direction) if cast_factory.is_valid() else {}

	func player_position() -> Vector2:
		return adapter.player_position() if adapter != null else Vector2.ZERO

	func player_facing() -> Vector2:
		return adapter.player_facing() if adapter != null else Vector2.RIGHT

	func locked_targeting_distance() -> float:
		return adapter.targeting_distance() if adapter != null else 0.0

	func hunter_mark_range() -> float:
		return adapter.mark_range() if adapter != null else 0.0

	func nearest_target(maximum_distance: float) -> Dictionary:
		return adapter.nearest_target(maximum_distance) if adapter != null else {}

	func preferred_target() -> Dictionary:
		return adapter.preferred_target() if adapter != null else {}

	func target_by_id(entity_id: int) -> Dictionary:
		return adapter.target_by_id(entity_id) if adapter != null else {}

	func pointer_target_entity_id() -> int:
		return adapter.pointer_target_id() if adapter != null else 0

	func refresh_pointer_lock() -> void:
		if adapter != null:
			adapter.refresh_pointer_lock()

	func mark_pointer_lost() -> void:
		if adapter != null:
			adapter.mark_pointer_lost()

	func mark_pointer_out_of_range() -> void:
		if adapter != null:
			adapter.mark_pointer_out_of_range()

	func held_attack_window_open(target: Dictionary) -> bool:
		return adapter.held_attack_window_open(target) if adapter != null else false

	func register_attack_source(sequence: int, source: String) -> void:
		if adapter != null:
			adapter.register_attack_source(sequence, source)

	func clear_input_feedback() -> void:
		if adapter != null:
			adapter.clear_feedback()

	func show_assisted_rejection_feedback() -> void:
		if adapter != null:
			adapter.show_assisted_rejection()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_hud_input_without_drawing()
	await _test_unconfigured_binding()
	await _test_mounted_boss_sort_and_cleanup()
	if failures.is_empty():
		print("PASS test_main_presentation_closeout.gd (mounted Boss/native sorting, cleanup and visible/off input)")
		quit(0)
	else:
		for failure: String in failures:
			printerr("- %s" % failure)
		quit(1)


func _test_hud_input_without_drawing() -> void:
	var controllers: Array = []
	var adapters: Array = []
	var viewports: Array[SubViewport] = []
	var snapshot := _fixture_snapshot()
	for enabled in [true, false]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1280, 720)
		root.add_child(viewport)
		var controller = Controller.new()
		viewport.add_child(controller)
		_expect(controller.configure_standalone().ok, "unmounted fixture failed explicit standalone binding")
		_expect(controller.load_assets(enabled, ThemeScript.create()).is_empty(), "presentation fixture assets failed")
		var adapter = Adapter.new()
		var command_port := FixtureCommandPort.new()
		command_port.bind(adapter, func(ability: String, target_id: int, direction: Vector2) -> Dictionary:
			return Protocol.cast(7, "ranger", 0, ability, target_id, roundi(direction.x * 1000.0), roundi(direction.y * 1000.0)))
		adapter.configure(CommandSource.new(), command_port, controller.feedback, controller.screen_to_gameplay, controller.is_pointer_over_interface)
		controller.commit(snapshot, adapter.view_state(snapshot))
		controllers.append(controller)
		adapters.append(adapter)
		viewports.append(viewport)
	await process_frame
	await process_frame
	var outcomes: Array = []
	for index in controllers.size():
		var controller = controllers[index]
		var adapter = adapters[index]
		var viewport := viewports[index]
		var hud: Control = controller.hud
		_expect(hud.visible and is_equal_approx(hud.modulate.a, 1.0 if index == 0 else 0.0), "off mode changed HUD participation instead of alpha")
		var button := hud.find_child("SummaryToggleButton", true, false) as Button
		var point := button.get_global_rect().get_center()
		_move_pointer(viewport, point)
		_expect(controller.is_pointer_over_interface(), "HUD pointer ownership vanished in mode %d" % index)
		var press := _pointer_press(point, true)
		adapter.capture_attack_event(press, controller.is_pointer_over_interface(), snapshot)
		_move_pointer(viewport, Vector2(640.0, 400.0))
		_expect(not controller.is_pointer_over_interface(), "world pointer was treated as a HUD pointer")
		var device: Dictionary = adapter.manual_combat_input.snapshot()
		_expect(bool(device.pointer_hud_owned_held) and not bool(device.pointer_world_held), "HUD-origin press became world-owned in mode %d" % index)
		_expect(adapter.collect_commands(snapshot).is_empty(), "HUD-origin drag submitted an attack in mode %d" % index)
		adapter.capture_attack_event(_pointer_press(Vector2(640.0, 400.0), false), false, snapshot)
		# A world press fires, pauses over HUD, and resumes after leaving it.
		var target_point: Vector2 = controller._input_projection.gameplay_to_screen(snapshot.enemies[0].position + Vector2(0.0, -22.0))
		_move_pointer(viewport, target_point)
		adapter.capture_attack_event(_pointer_press(target_point, true), controller.is_pointer_over_interface(), snapshot)
		var fired: Array[Dictionary] = adapter.collect_commands(snapshot)
		_expect(fired.size() == 1 and int(fired[0].get("target_entity_id", 0)) == 1, "world pointer did not produce its cast")
		_move_pointer(viewport, point)
		_expect(adapter.collect_commands(snapshot).is_empty(), "world hold fired through HUD")
		_move_pointer(viewport, target_point)
		var resumed: Array[Dictionary] = adapter.collect_commands(snapshot)
		_expect(resumed == fired, "world hold did not resume its original entity")
		# An assisted key remains assisted while the pointer is over the HUD.
		adapter.reset_intent()
		_move_pointer(viewport, point)
		var key := InputEventKey.new()
		key.keycode = KEY_SPACE
		key.physical_keycode = KEY_SPACE
		key.pressed = true
		adapter.capture_attack_event(key, controller.is_pointer_over_interface(), snapshot)
		var assisted: Array[Dictionary] = adapter.collect_commands(snapshot)
		_expect(adapter.manual_combat_input.attack_source(true) == "assisted" and assisted.size() == 1, "HUD ownership changed assisted device input")
		outcomes.append({"fired": fired, "resumed": resumed, "assisted": assisted, "device": adapter.manual_combat_input.snapshot()})
		var returns := [0]
		controller.return_requested.connect(func() -> void: returns[0] += 1)
		hud.return_requested.emit()
		_expect(returns[0] == 1, "HUD return did not emit exactly one presentation request")
	_expect(outcomes[0] == outcomes[1], "visible/off commands or physical source ownership differ")
	for viewport: SubViewport in viewports:
		root.remove_child(viewport)
		viewport.free()


func _test_unconfigured_binding() -> void:
	var controller := Controller.new()
	root.add_child(controller)
	var errors := controller.load_assets(true, ThemeScript.create())
	_expect(errors.has("presentation:sort_binding_unconfigured"), "unconfigured controller silently selected a sort domain")
	var result := controller.commit(_fixture_snapshot(), {})
	_expect(not result.ok and result.error == "sort_binding_unconfigured" and not controller.sort_report().render_active, "unconfigured commit silently rendered actors")
	controller.free()
	# A native author scene loaded without SceneRuntime must not be mistaken for
	# the bare unmounted Main fixture or get a replacement WorldPresenter.
	var authored: Node = load("res://content/rooms/combat/rectangle_arena.tscn").instantiate()
	authored.set("test_session", true)
	root.add_child(authored)
	authored.set_process(false)
	_expect((authored.get("startup_errors") as Array).has("presentation:mounted_runtime_detached"), "native Main without runtime injection silently used standalone rendering")
	var authored_controller: Controller = authored.get("presentation")
	authored_controller.reset_battle()
	var invalid := authored_controller.commit(_fixture_snapshot(), {})
	_expect(not invalid.ok and invalid.error == "mounted_runtime_detached" and authored_controller.sort_report().actor_ids.is_empty(), "unmounted native scene created orphan actors")
	_expect(not authored_controller.configure_standalone().ok, "native missing dependency could be replaced by a standalone fallback")
	authored.free()


func _test_mounted_boss_sort_and_cleanup() -> void:
	var registry := ItemRegistry.new()
	_expect(registry.load_all().is_empty(), "mounted fixture registry failed")
	var build: Dictionary = BuildResolver.new(registry).resolve_fixture("calibration_convergent")
	var runtime := Runtime.new()
	root.add_child(runtime)
	var started := runtime.start_session({
		"contract_id": "test.boss-native-sort", "mode": "Manual", "seed": 52969,
		"presentation_enabled": true,
		"room": {"room_id": "test.boss-native-sort", "layout_id": "rectangle_arena", "objective_id": "clear", "hazard_ids": [], "enemy_ids": [], "elite_rule_ids": [], "boss_id": "threshold_colossus", "drop_tags": []},
		"framework_context": {"active_build": {}, "resolved_build": build},
	})
	_expect(started.ok, "real mounted Boss room failed to start: " + str(started))
	if not started.ok:
		runtime.free()
		return
	runtime.set_process(false)
	var arena = runtime.room_instance
	arena.set_process(false)
	var scene = runtime.scene_runtime
	var domain: WorldPresenter = scene.presenter
	var controller: Controller = arena.presentation
	_expect(controller.sort_report().binding_mode == "mounted" and controller.sort_report().ok, "Main did not bind controller to injected mounted SceneRuntime")
	var boss: CombatEnemyState = arena.boss
	_expect(boss != null, "mounted room did not create the logical Boss")
	_expect(arena.teleport_actor("enemy/%d" % boss.entity_id, Vector2(640, 430)).ok, "failed to position mounted Boss")
	_expect(arena.teleport_actor("ranger", Vector2(640, 418)).ok, "failed to position mounted player")
	boss.left_hand_position = boss.position + Vector2(-34, 0)
	boss.right_hand_position = boss.position + Vector2(34, 0)
	var marker := Polygon2D.new()
	marker.polygon = PackedVector2Array([Vector2(-4, -12), Vector2(4, -12), Vector2(4, 0), Vector2(-4, 0)])
	marker.color = Color(0.8, 0.2, 0.2, 1.0)
	marker.name = "NativeInterleaveMarker"
	marker.position = Vector2(640, 412)
	domain.sort_root.add_child(marker)
	var before: String = arena._semantic_state_hash("mounted-sort")
	arena.refresh_presentation()
	var report := controller.sort_report()
	_expect(report.ok and report.render_active, "production commit did not submit mounted sort views")
	var nodes := _mounted_actor_nodes(domain)
	var body_id := "enemy/%d/body" % boss.entity_id
	var hand_id := "enemy/%d/left_hand" % boss.entity_id
	_expect(nodes.has(body_id) and nodes.has(hand_id) and nodes.has("ranger/body"), "production commit omitted Boss/player views")
	if not nodes.has(body_id) or not nodes.has(hand_id) or not nodes.has("ranger/body"):
		runtime.free()
		return
	var body: Node2D = nodes[body_id]
	var hand: Node2D = nodes[hand_id]
	var player: Node2D = nodes["ranger/body"]
	_expect(body.get_parent() == marker.get_parent() and hand.get_parent() == marker.get_parent() and player.get_parent() == marker.get_parent(), "mounted native marker and actor parts did not share one SortRoot")
	_expect(hand.position.y < marker.position.y and marker.position.y < player.position.y and player.position.y < body.position.y, "native/player/hand baselines did not interleave")
	print("MOUNTED_SORT hand=%.3f native=%.3f player=%.3f body=%.3f" % [hand.position.y, marker.position.y, player.position.y, body.position.y])
	_expect(domain.get_global_transform().is_equal_approx(controller.world_view.gameplay_transform()), "mounted native world did not use gameplay camera transform")
	_expect(controller.get_global_transform().is_equal_approx(Transform2D.IDENTITY), "controller inherited a second native camera transform")
	var expected_screen: Vector2 = controller.world_view.gameplay_to_screen(arena.player_position)
	_expect(player.get_global_transform_with_canvas().origin.is_equal_approx(expected_screen), "real mounted player was projected twice or used a different camera")
	for node: Node2D in nodes.values():
		_expect(node.z_index == 0, "mounted part used a z-index sorting shortcut")
	var ids: Array = report.ids.duplicate()
	var reversed_nodes := nodes.values()
	reversed_nodes.reverse()
	for node: Node2D in reversed_nodes:
		domain.sort_root.move_child(node, domain.sort_root.get_child_count() - 1)
	arena.refresh_presentation()
	_expect(_mounted_actor_order(domain) == ids, "mounted commit preserved reversed insertion order for equal-depth parts")
	await process_frame
	await process_frame
	_expect(arena._semantic_state_hash("mounted-sort") == before, "mounted draw/commit changed authoritative semantic hash")
	_expect(controller.sort_report().actor_ids.size() == ids.size(), "draw callback duplicated the mounted actor views")
	var published: Dictionary = arena.gameplay_snapshot()
	var input_view: Dictionary = arena.input_adapter.view_state(published)
	# A ready mounted runtime with its presentation dependency missing must fail
	# explicitly, never create a standalone replacement.
	scene.presenter = null
	var missing := controller.commit(published, input_view)
	_expect(not missing.ok and missing.error == "native_sort_domain_unavailable" and domain.actor_ids().is_empty(), "mounted missing presenter silently fell back or left old actor views")
	scene.presenter = domain
	arena.refresh_presentation()
	_expect(not domain.actor_ids().is_empty(), "mounted submission failed after restoring dependency")
	controller.leave_arena()
	_expect(domain.actor_ids().is_empty(), "leaving arena did not release mounted part views")
	var stale := controller.commit(published, input_view)
	_expect(not stale.ok and stale.error == "presentation_session_closed" and domain.actor_ids().is_empty(), "stale frame reattached actors after leave")
	controller.reset_battle()
	arena.refresh_presentation()
	_expect(not domain.actor_ids().is_empty(), "explicit room reset failed to reopen live presentation")
	# Actual SceneRuntime teardown also removes Main from the tree. Retained
	# stale frame calls must never reattach views while that Main is queued free.
	scene.unmount()
	_expect(domain.actor_ids().is_empty(), "unmount leaked registered part IDs")
	var after_unmount := controller.commit(published, input_view)
	_expect(not after_unmount.ok and after_unmount.error == "presentation_session_closed" and domain.actor_ids().is_empty(), "unmounted controller resurrected orphan part nodes")
	controller.reset_battle()
	_expect(not controller.commit(published, input_view).ok and domain.actor_ids().is_empty(), "reset resurrected an unmounted session")
	runtime.free()
	await process_frame


func _mounted_actor_nodes(domain: WorldPresenter) -> Dictionary:
	var nodes := {}
	for node: Node in domain.sort_root.get_children():
		if node is Node2D and node.get("drawable") is Dictionary:
			nodes[String(node.get("drawable").id)] = node
	return nodes


func _mounted_actor_order(domain: WorldPresenter) -> Array:
	var ids := []
	for node: Node in domain.sort_root.get_children():
		if node is Node2D and node.get("drawable") is Dictionary:
			ids.append(String(node.get("drawable").id))
	return ids


func _move_pointer(viewport: SubViewport, point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	viewport.push_input(motion, true)


func _pointer_press(point: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = pressed
	return event


func _fixture_snapshot() -> Dictionary:
	var arena := Rect2(42.0, 190.0, 1196.0, 488.0)
	return Snapshot.capture({
		"sim_tick": 7, "in_arena": true, "battle_over": false, "battle_victory": false,
		"player_position": arena.get_center(), "player_facing": Vector2.RIGHT,
		"player_health": 100.0, "player_maximum_health": 100.0, "player_last_displacement": Vector2.ZERO,
		"dodge_remaining_ticks": 0, "dash_remaining_ticks": 0, "dodge_started_tick": -1, "dash_started_tick": -1,
		"dodge_direction": Vector2.RIGHT, "dash_direction": Vector2.RIGHT,
		"attack_cooldown_ticks": 0, "dodge_cooldown_ticks": 0, "dash_cooldown_ticks": 0, "hunter_mark_cooldown_ticks": 0,
		"marked_entity_id": 0, "hunter_mark_expires_tick": 0, "hunter_mark_candidate_entity_id": 0, "hunter_mark_candidate_expires_tick": 0,
		"enemies": [Enemy.new(arena.get_center() + Vector2(100.0, 0.0), 100.0, false, 1, "melee_pursuer")],
		"boss": null, "boss_damage": BigValue.from_float(0.0), "boss_maximum": BigValue.from_power10(12.0),
		"room_id": "test.presentation.input", "layout_id": "rectangle_arena", "objective_id": "clear", "framework_room": {},
		"locked_build": {}, "locked_targeting_distance": 225.0, "talent_capabilities": {}, "equipped_skills": [],
		"equipped_parameters": {"shared_lifetime": 2.0, "distance": 225.0},
		"model": {"p": 0.1, "g": 0, "state": "convergent"},
		"selected_mode": "Manual", "proxy_prediction": "manual", "has_timeline": false, "timeline": {}, "action_phase": "idle",
		"shots": 0, "defeated": 0, "elapsed": 0.0, "room_entry_start_tick": 0,
		"hazard_states": [], "elite_rule_ids": [], "elite_entity_id": 0, "elite_barrier_active": false,
		"reinforcements_summoned": false, "timed_bonus_available": true, "last_attack_outcome": {},
		"arena_rect": arena, "walkable_geometry": Geometry.from_layout("rectangle_arena", arena, 14.0), "projectiles": [], "events": [],
	})


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)
