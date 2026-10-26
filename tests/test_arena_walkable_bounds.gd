extends SceneTree

## The ring layout is a true annulus. These checks exercise the same Main
## geometry used by player movement, enemy movement, telegraphs, and the
## published proxy snapshot. The planner geometry is padded; ActorMotor then
## applies the actor footprint to the authored boundary.

const MainScript := preload("res://src/game/main.gd")
const Protocol := preload("res://src/systems/combat_command_protocol.gd")
const Resolver := preload("res://src/systems/build_resolver.gd")
const Motion := preload("res://src/systems/player_motion_system.gd")

const ArenaGeometryScript := preload("res://src/runtime/geometry/arena_geometry.gd")
const Channels := preload("res://src/runtime/spatial/spatial_channels.gd")
const SceneRuntimeScript := preload("res://src/runtime/world/scene_runtime.gd")
const SpatialManifestScript := preload("res://src/runtime/world/spatial_manifest.gd")
const PhasePort := preload("res://tests/helpers/callable_combat_phase_port.gd")
const Assert := preload("res://tests/helpers/assert.gd")

class DrivenMain:
	extends MainScript
	var requested_movement := Vector2.ZERO
	var drive_enemy_outward := false
	func test_collect_commands() -> Array[Dictionary]:
		var commands: Array[Dictionary] = []
		if requested_movement != Vector2.ZERO:
			commands.append(_player_commands._move_command(requested_movement, 1.0))
		return commands
	func test_update_enemies_tick() -> void:
		if drive_enemy_outward:
			_enemy_ai._commit_normal_enemy_intent(enemies[0], {"move_direction": Vector2.RIGHT, "speed_scale": 1.0, "reason": "bounds_test"})


var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var arena = DrivenMain.new()
	arena.test_session = true
	root.add_child(arena)
	arena.set_process(false)
	await process_frame

	_test_ring_geometry(arena)
	_test_ring_circulation(arena)
	_test_geometry_layers(arena)
	_test_ring_player_boundaries(arena)
	_test_ring_enemy_boundary(arena)
	_test_ring_boss_target(arena)
	_test_public_proxy_geometry(arena)
	_test_other_layouts_unchanged(arena)

	_shutdown_arena(arena)
	if failures.is_empty():
		print("PASS  test_arena_walkable_bounds.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _configure_room(arena: Node, layout: String, enemy_ids: Array, boss_id: String = "") -> void:
	arena.test_session = true
	arena.framework_room = {
		"room_id": "bounds.%s" % layout,
		"layout_id": layout,
		"layout": layout,
		"objective_id": "clear",
		"objective": "clear",
		"hazard_ids": [],
		"enemy_ids": enemy_ids.duplicate(),
		"elite_rule_ids": [],
		"boss_id": boss_id,
		"drop_tags": ["equipment_general"],
	}
	arena.framework_resolved_build = Resolver.new(arena.content_registry.early_item_registry).resolve_fixture("calibration_convergent")
	arena.framework_active_build = {"skills": ["piercing_arrow", "hunter_mark", "dash"]}
	arena.requested_movement = Vector2.ZERO
	arena.drive_enemy_outward = false
	arena.start_room()
	_expect(arena.in_arena, "bounds fixture failed to reset a real player room")
	var callbacks := {
		"read_only_targets": Callable(arena, "_read_only_targets"),
		"set_elapsed": Callable(arena, "_simulation_set_elapsed"),
		"consume_player_events": Callable(arena, "_consume_player_events"),
		"update_room_rules": Callable(arena, "_update_room_rules_tick"),
		"refresh_hazard_states": Callable(arena, "_refresh_hazard_states_tick"),
		"collect_commands": Callable(arena, "test_collect_commands"),
		"route_commands": Callable(arena, "_route_commands"),
		"update_enemies": Callable(arena, "test_update_enemies_tick"),
		"advance_projectiles": Callable(arena, "_advance_piercing_projectiles_tick"),
		"resolve_hazard_hits": Callable(arena, "_resolve_hazard_hits_tick"),
		"check_battle_end": Callable(arena, "_check_battle_end"),
		"check_timeout": Callable(arena, "_simulation_check_timeout"),
	}
	var phase_port = PhasePort.new()
	var port_result: Dictionary = phase_port.bind(callbacks)
	_expect(bool(port_result.get("ok", false)), "bounds fixture failed to bind its typed phase port")
	var configured: Dictionary = arena.combat_simulation.configure(arena.simulation_world, arena.player_combat_rules, phase_port)
	_expect(bool(configured.get("ok", false)), "bounds fixture failed to configure its real command driver")


func _move_player(arena: Node, direction: Vector2) -> void:
	arena.requested_movement = direction
	var result: Dictionary = arena.combat_simulation.step()
	_expect(bool(result.get("ok", false)), "bounds movement tick failed")
	_expect((result.get("player_step", {}).get("protocol_receipts", []) as Array).size() == 1, "bounds movement command was not arbitrated")
	arena.requested_movement = Vector2.ZERO


func _ring_boundary(arena: Node) -> Dictionary:
	return ArenaGeometryScript.movement_boundary("ring", arena._arena_rect())


func _test_ring_geometry(arena: Node) -> void:
	_configure_room(arena, "ring", ["melee_pursuer"])
	var arena_rect: Rect2 = arena._arena_rect()
	var geometry: Dictionary = arena._walkable_geometry(14.0)
	var expected_bounds := arena_rect.grow(-14.0)
	var expected_basis := minf(expected_bounds.size.x, expected_bounds.size.y)
	var center: Vector2 = expected_bounds.get_center()
	_expect(String(arena.layout_id) == "ring", "ring: room identity was rewritten")
	_expect(String(geometry.get("kind", "")) == "ring", "ring: walkable geometry is not an annulus")
	_expect(Rect2(geometry.get("bounds", Rect2())) == expected_bounds, "ring: padded annulus bounds changed")
	_expect(Vector2(geometry.get("center", Vector2.ZERO)) == center, "ring: annulus center changed")
	_expect(_near(float(geometry.get("inner_radius", -1.0)), expected_basis * 0.20), "ring: inner radius changed")
	_expect(_near(float(geometry.get("outer_radius", -1.0)), expected_basis * 0.43), "ring: outer radius changed")
	_expect(is_zero_approx(float(geometry.get("corridor_half_height", -1.0))), "ring: corridor parameter leaked into annulus geometry")
	var normalized: Dictionary = ArenaGeometryScript.normalize(geometry)
	_expect(bool(normalized.get("ok", false)), "ring: annulus geometry no longer normalizes")

	var center_projection: Vector2 = arena._clamp_to_arena(center, 14.0)
	_expect(_near_vector(center_projection, center + Vector2.RIGHT * float(geometry.inner_radius)), "ring: the center projected into the inner hole")
	var hole_projection: Vector2 = arena._clamp_to_arena(center + Vector2.RIGHT * float(geometry.inner_radius) * 0.5, 14.0)
	_expect(_near_vector(hole_projection, center + Vector2.RIGHT * float(geometry.inner_radius)), "ring: a point in the inner hole remained walkable")
	var outer_projection: Vector2 = arena._clamp_to_arena(center + Vector2.RIGHT * (float(geometry.outer_radius) + 100.0), 14.0)
	_expect(_near_vector(outer_projection, center + Vector2.RIGHT * float(geometry.outer_radius)), "ring: the outer boundary did not project onto the annulus")


## A C-shaped annulus is still one connected component, so connectivity alone
## does not prove circulation. The ring must offer a full cycle around the
## beacon. The boundary comes from the same DrivenMain fixture the player
## movement checks use; the authored blocker set comes from a mount of the
## production ring room (the fixture's standalone index carries the boundary
## only). Sample the hero-eroded annulus on a polar grid (14 gp clearance, the
## player footprint), label the 4-connected free components, and require one
## whose complement cannot connect the inner edge to the outer edge — the same
## conservative winding test used to accept the authored placement moves.
func _test_ring_circulation(arena: Node) -> void:
	_configure_room(arena, "ring", ["melee_pursuer"])
	var boundary := _ring_boundary(arena)
	var center: Vector2 = boundary["center"]
	var r_lo := float(boundary["inner_radius"]) + 15.0
	var r_hi := float(boundary["outer_radius"]) - 15.0
	var n_r := int(floor(r_hi - r_lo)) + 1
	const N_THETA := 360
	var packed := load("res://content/rooms/combat/ring.tscn") as PackedScene
	_expect(packed != null, "ring circulation: production ring scene failed to load")
	if packed == null:
		return
	var manifest_path := "res://content/rooms/combat/ring.spatial.json"
	var manifest = SpatialManifestScript.new(JSON.parse_string(FileAccess.get_file_as_string(manifest_path)))
	var runtime: SceneRuntime = SceneRuntimeScript.new()
	root.add_child(runtime)
	var mounted: Dictionary = runtime.mount(
		{
			"room_id": "combat.ring",
			"world_asset_id": "combat/ring",
			"encounter_id": "encounter.circulation-regression",
			"ruleset_id": "rules.circulation-regression",
			"tags": ["regression"],
		},
		{
			"world_scene_path": packed.resource_path,
			"manifest_path": manifest_path,
			"gameplay_digest": manifest.gameplay_digest_sha256(),
			"presentation_digest": manifest.presentation_digest_sha256(),
			"schema_version": 1,
		},
		packed,
		null,
		0,
		30
	)
	_expect(bool(mounted.get("ok", false)), "ring circulation: production ring room failed to mount: %s" % str(mounted))
	var index: Variant = runtime.static_spatial_index if bool(mounted.get("ok", false)) else null
	if index == null:
		_expect(false, "ring circulation: static spatial index unavailable in the mounted room")
		runtime.free()
		return
	var free: Array = []
	var free_total := 0
	for ri in n_r:
		var row: Array = []
		row.resize(N_THETA)
		var rr := r_lo + float(ri)
		for ti in N_THETA:
			var angle := deg_to_rad(float(ti) + 0.5)
			var point := center + Vector2(rr, 0.0).rotated(angle)
			var clear: bool = index.is_position_clear(Channels.MOVEMENT, point, 14.0)
			row[ti] = clear
			if clear:
				free_total += 1
		free.append(row)
	runtime.shutdown()
	runtime.free()
	_expect(free_total > 0, "ring circulation: the hero-eroded annulus has no walkable cells at all")
	if free_total == 0:
		return
	var largest := _free_component_sizes(free, n_r, N_THETA)
	_expect(largest > N_THETA, "ring circulation: the largest free component is smaller than one inner lap (%d cells)" % largest)
	_expect(_has_winding_component(free, n_r, N_THETA), "ring circulation: no free component winds around the beacon with hero clearance (a sealed C-shape annulus)")


## 4-connected component labeling over the polar free grid.
func _free_component_sizes(free: Array, n_r: int, n_theta: int) -> int:
	var comp: Array = []
	for ri in n_r:
		var row: Array = []
		row.resize(n_theta)
		for ti in n_theta:
			row[ti] = -1
		comp.append(row)
	var best := 0
	for seed_r in n_r:
		for seed_t in n_theta:
			if not bool(free[seed_r][seed_t]) or comp[seed_r][seed_t] != -1:
				continue
			var size := 0
			var stack: Array = [[seed_r, seed_t]]
			comp[seed_r][seed_t] = 0
			while not stack.is_empty():
				var cell: Array = stack.pop_back()
				size += 1
				for step in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					var nr: int = cell[0] + step[0]
					var nt: int = (cell[1] + step[1] + n_theta) % n_theta
					if nr >= 0 and nr < n_r and bool(free[nr][nt]) and comp[nr][nt] == -1:
						comp[nr][nt] = 0
						stack.append([nr, nt])
			best = maxi(best, size)
	return best


## A free component winds around the beacon iff its complement cannot connect
## the inner edge (row 0) to the outer edge (row n_r-1). The complement floods
## 8-connected, which is conservative: diagonal gaps count as connected, so a
## claimed cycle survives grid discretization.
func _has_winding_component(free: Array, n_r: int, n_theta: int) -> bool:
	var comp: Array = []
	for ri in n_r:
		var row: Array = []
		row.resize(n_theta)
		for ti in n_theta:
			row[ti] = -1
		comp.append(row)
	var comps := 0
	for seed_r in n_r:
		for seed_t in n_theta:
			if not bool(free[seed_r][seed_t]) or comp[seed_r][seed_t] != -1:
				continue
			var stack: Array = [[seed_r, seed_t]]
			comp[seed_r][seed_t] = comps
			while not stack.is_empty():
				var cell: Array = stack.pop_back()
				for step in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					var nr: int = cell[0] + step[0]
					var nt: int = (cell[1] + step[1] + n_theta) % n_theta
					if nr >= 0 and nr < n_r and bool(free[nr][nt]) and comp[nr][nt] == -1:
						comp[nr][nt] = comps
						stack.append([nr, nt])
			comps += 1
	for c in comps:
		var visited: Array = []
		for ri in n_r:
			var row: Array = []
			row.resize(n_theta)
			for ti in n_theta:
				row[ti] = false
			visited.append(row)
		var stack: Array = []
		for ti in n_theta:
			if comp[0][ti] != c:
				visited[0][ti] = true
				stack.append([0, ti])
		var escaped := false
		while not stack.is_empty() and not escaped:
			var cell: Array = stack.pop_back()
			if cell[0] == n_r - 1:
				escaped = true
				break
			for step in [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]:
				var nr: int = cell[0] + step[0]
				var nt: int = (cell[1] + step[1] + n_theta) % n_theta
				if nr >= 0 and nr < n_r and not bool(visited[nr][nt]) and comp[nr][nt] != c:
					visited[nr][nt] = true
					stack.append([nr, nt])
		if not escaped:
			return true
	return false


func _test_geometry_layers(arena: Node) -> void:
	var snapshot: Dictionary = arena.gameplay_snapshot()
	var presentation: Dictionary = snapshot.get("presentation_geometry", {})
	var collision: Dictionary = arena._collision_geometry(14.0)
	_expect(String(presentation.get("kind", "")) == "ring", "ring: presentation geometry lost the native layout kind")
	_expect(is_equal_approx(float(presentation.get("inner_radius", 0.0)), 97.6)
		and is_equal_approx(float(presentation.get("outer_radius", 0.0)), 209.84), "ring: presentation geometry still used the planning inset")
	_expect(is_equal_approx(float(collision.get("inner_radius", 0.0)), 111.6)
		and is_equal_approx(float(collision.get("outer_radius", 0.0)), 195.84), "ring: collision geometry lost the player footprint clearance")
	_expect(not is_equal_approx(float(presentation.get("outer_radius", 0.0)), float(arena._walkable_geometry(14.0).get("outer_radius", 0.0))), "ring: presentation and planning geometry collapsed into one contract")


func _test_ring_player_boundaries(arena: Node) -> void:
	var boundary := _ring_boundary(arena)
	var center: Vector2 = boundary["center"]
	var inner := float(boundary["inner_radius"])
	var outer := float(boundary["outer_radius"])
	const PLAYER_RADIUS := 14.0

	# The inner edge blocks entry into the hole, while the same contact can be
	# left in the outward direction and can carry tangent movement.
	_configure_room(arena, "ring", ["melee_pursuer"])
	var inner_contact := center + Vector2.RIGHT * (inner + PLAYER_RADIUS)
	arena.teleport_actor("ranger", inner_contact)
	_move_player(arena, Vector2.LEFT)
	_expect(_near_vector(arena.player_position, inner_contact), "ring: player entered the inner hole")
	_expect(arena.player_combat_state.snapshot(arena.sim_tick).player_last_displacement == Vector2.ZERO, "ring: blocked inner-hole entry reported displacement")

	_configure_room(arena, "ring", ["melee_pursuer"])
	arena.teleport_actor("ranger", inner_contact)
	_move_player(arena, Vector2.UP)
	var tangent_step: float = Motion.PLAYER_SPEED * Motion.SIM_STEP_SECONDS
	_expect(_near_vector(arena.player_position, inner_contact + Vector2.UP * tangent_step), "ring: tangent movement did not continue along the inner edge (actual=%s expected=%s receipts=%s)" % [arena.player_position, inner_contact + Vector2.UP * tangent_step, arena.last_command_receipts])

	_configure_room(arena, "ring", ["melee_pursuer"])
	arena.teleport_actor("ranger", inner_contact)
	_move_player(arena, Vector2.RIGHT)
	_expect(_near_vector(arena.player_position, inner_contact + Vector2.RIGHT * tangent_step), "ring: reverse movement could not escape the inner edge (actual=%s expected=%s)" % [arena.player_position, inner_contact + Vector2.RIGHT * tangent_step])

	# The outer edge has the opposite blocking normal and also includes the
	# actor footprint clearance.
	_configure_room(arena, "ring", ["melee_pursuer"])
	var outer_contact := center + Vector2.RIGHT * (outer - PLAYER_RADIUS)
	arena.teleport_actor("ranger", outer_contact)
	_move_player(arena, Vector2.RIGHT)
	_expect(_near_vector(arena.player_position, outer_contact), "ring: player crossed the outer boundary")
	_expect(arena.player_combat_state.snapshot(arena.sim_tick).player_last_displacement == Vector2.ZERO, "ring: blocked outer-boundary exit reported displacement")

	_configure_room(arena, "ring", ["melee_pursuer"])
	arena.teleport_actor("ranger", outer_contact)
	_move_player(arena, Vector2.LEFT)
	_expect(_near_vector(arena.player_position, outer_contact - Vector2.RIGHT * tangent_step), "ring: reverse movement could not escape the outer edge (actual=%s expected=%s)" % [arena.player_position, outer_contact - Vector2.RIGHT * tangent_step])


func _test_ring_enemy_boundary(arena: Node) -> void:
	_configure_room(arena, "ring", ["melee_pursuer"])
	var boundary := _ring_boundary(arena)
	var center: Vector2 = boundary["center"]
	var outer := float(boundary["outer_radius"])
	var enemy = arena.enemies[0]
	var enemy_radius := 16.0
	arena.teleport_actor("ranger", center + Vector2.RIGHT * (float(boundary["inner_radius"]) + 14.0 + 40.0))
	arena.teleport_actor("enemy/%d" % enemy.entity_id, center + Vector2.RIGHT * (outer - enemy_radius - 20.0))
	arena.drive_enemy_outward = true
	for _tick in 200:
		arena._simulate_tick()
		if _tick == 0:
			var first_position: Vector2 = enemy.position
			arena._enemy_ai._commit_normal_enemy_intent(enemy, {"move_direction": Vector2.RIGHT, "speed_scale": 1.0, "reason": "bounds_test_duplicate"})
			_expect(enemy.position == first_position, "ring: duplicate enemy movement committed twice in one simulation tick")
	_expect(_near(float(enemy.position.distance_to(center)), outer - enemy_radius), "ring: enemy crossed the outer boundary or lost footprint clearance")


func _test_ring_boss_target(arena: Node) -> void:
	_configure_room(arena, "ring", [], "threshold_colossus")
	var boss = arena.boss
	_expect(boss != null, "ring: boss fixture did not spawn")
	if boss == null:
		return
	var outside: Vector2 = arena._arena_rect().get_center() + Vector2(999.0, -999.0)
	var expected_outside: Dictionary = ArenaGeometryScript.project(outside, arena._collision_geometry(28.0))
	var rejected_outside: Dictionary = arena.teleport_actor("ranger", outside)
	_expect(not bool(rejected_outside.get("ok", false)), "ring: out-of-bound setup teleport was accepted")
	_expect(bool(arena.teleport_actor("ranger", Vector2(expected_outside["position"])).get("ok", false)), "ring: projected outer setup teleport was rejected")
	arena._enemy_ai._start_boss_action(boss, "slam")
	var outside_shape: Dictionary = boss.target_shape
	_expect(String(outside_shape.get("type", "")) == "rect", "ring: boss slam target shape changed")
	_expect(_near_vector(Rect2(outside_shape.get("rect", Rect2())).get_center(), Vector2(expected_outside["position"])), "ring: boss slam target ignored the annulus outer edge")

	boss.action_state = "none"
	var center: Vector2 = arena._arena_rect().get_center()
	var expected_center: Dictionary = ArenaGeometryScript.project(center, arena._collision_geometry(28.0))
	_expect(bool(arena.teleport_actor("ranger", Vector2(expected_center["position"])).get("ok", false)), "ring: projected inner setup teleport was rejected")
	arena._enemy_ai._start_boss_action(boss, "slam")
	_expect(_near_vector(Rect2(boss.target_shape.get("rect", Rect2())).get_center(), Vector2(expected_center["position"])), "ring: boss slam target entered the inner hole")


func _test_public_proxy_geometry(arena: Node) -> void:
	_configure_room(arena, "ring", ["melee_pursuer"])
	var snapshot: Dictionary = arena._player_commands._public_proxy_snapshot()
	var geometry: Dictionary = snapshot.get("walkable_geometry", {})
	_expect(String(geometry.get("kind", "")) == "ring", "ring: published proxy geometry lost the annulus")
	_expect(not geometry.has("layout_id"), "ring: published proxy geometry leaked the room layout id")
	_expect(float(geometry.get("inner_radius", 0.0)) > 0.0 and float(geometry.get("outer_radius", 0.0)) > float(geometry.get("inner_radius", 0.0)), "ring: published proxy geometry has invalid radii")
	var normalized: Dictionary = ArenaGeometryScript.normalize(geometry)
	_expect(bool(normalized.get("ok", false)), "ring: published proxy geometry no longer normalizes")


func _test_other_layouts_unchanged(arena: Node) -> void:
	_configure_room(arena, "corridor", ["melee_pursuer"])
	_expect(String(arena.layout_id) == "corridor", "corridor: collision layout id changed")
	var corridor: Dictionary = arena._walkable_geometry(16.0)
	_expect(String(corridor.get("kind", "")) == "corridor" and float(corridor.get("corridor_half_height", -1.0)) > 0.0, "corridor: walkable strip geometry changed")
	_configure_room(arena, "rectangle_arena", ["melee_pursuer"])
	var rectangle: Dictionary = arena._walkable_geometry(14.0)
	_expect(String(rectangle.get("kind", "")) == "rectangle" and Rect2(rectangle.get("bounds", Rect2())) == (arena._arena_rect() as Rect2).grow(-14.0), "rectangle: walkable geometry changed")


func _near(left: float, right: float, tolerance: float = 0.0001) -> bool:
	return absf(left - right) <= tolerance


func _near_vector(left: Vector2, right: Vector2, tolerance: float = 0.0001) -> bool:
	return left.distance_to(right) <= tolerance


func _shutdown_arena(arena: Node) -> void:
	if arena == null or not is_instance_valid(arena):
		return
	var runtime: Variant = arena.get("scene_runtime")
	if runtime != null and runtime.has_method("unmount"):
		runtime.unmount()
	if arena.get_parent() != null:
		arena.get_parent().remove_child(arena)
	arena.free()


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)
