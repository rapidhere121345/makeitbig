extends SceneTree

## Default acceptance matrix: two authored templates x seeds 0..99 x three rooms.
## Uses unmodified native Main and its production CombatSimulation callbacks.
## Small ranges are available only for an explicit minimal reproduction; output
## always states the actual range and never labels those runs the full matrix.
const Plan = preload("res://src/game/contract_plan.gd")
const Runtime = preload("res://src/game/combat_room_runtime.gd")
const Campaign = preload("res://src/content/early_campaign_registry.gd")
const Items = preload("res://src/content/early_item_registry.gd")
const Resolver = preload("res://src/systems/build_resolver.gd")
const Content = preload("res://src/content/content_registry.gd")
const Proxy = preload("res://src/systems/proxy_build.gd")
const Spatial = preload("res://src/runtime/world/spatial_manifest.gd")
const TEMPLATES = ["side_targeted_equipment", "side_affix_and_law_tallies"]
const MIN_TICKS = 30
const MAX_TICKS = 300
const EVIDENCE_ROOT = "res://build/current/rebuild-repeatable-matrix"
var first_seed = 0
var seed_count = 100
var output_path = EVIDENCE_ROOT + "/full"
var failures: Array[String] = []
var context: Dictionary = {}
var room_log: FileAccess
var seed_log: FileAccess
var coverage: Dictionary = {}
var room_count = 0
var total_ticks = 0
var actor_checks = 0
var ring_probes = 0
var stale_rejections = 0
var outcomes: Dictionary = {}
var previous_instance = "matrix/unmounted"
var previous_revision = -1
var started_usec = 0
var source_fingerprints: Dictionary = {}
var evidence_files: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String, details: Dictionary = {}) -> void:
	if condition:
		return
	var failure = {"context": context, "message": message, "details": details}
	failures.append(JSON.stringify(failure, "", true, true))
	printerr("MATRIX_FAILURE ", failures.back())


func _write_json(path: String, value: Variant) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "\t", true, true) + "\n")


func _line(file: FileAccess, value: Dictionary) -> void:
	file.store_line(JSON.stringify(value, "", true, true))
	file.flush()


func _collect_files(path: String, paths: Array[String]) -> void:
	for filename: String in DirAccess.get_files_at(path):
		paths.append(path.path_join(filename))
	for dirname: String in DirAccess.get_directories_at(path):
		_collect_files(path.path_join(dirname), paths)


func _fingerprint_sources() -> void:
	for path: String in ["res://src", "res://content"]:
		_collect_files(path, evidence_files)
	evidence_files.append("res://tests/test_repeatable_encounter_matrix.gd")
	evidence_files.append("res://tests/test_repeatable_encounter_matrix.gd.uid")
	evidence_files.append("res://project.godot")
	evidence_files.sort()
	for path: String in evidence_files:
		source_fingerprints[path] = FileAccess.get_sha256(path)
	_write_json(output_path + "/source-fingerprints.json", source_fingerprints)


func _arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--matrix-first-seed="):
			first_seed = int(argument.trim_prefix("--matrix-first-seed="))
		elif argument.begins_with("--matrix-seed-count="):
			seed_count = int(argument.trim_prefix("--matrix-seed-count="))
		elif argument.begins_with("--matrix-output="):
			output_path = argument.trim_prefix("--matrix-output=")
	_expect(first_seed >= 0 and seed_count > 0 and first_seed + seed_count <= 100, "invalid seed range")
	_expect(output_path.begins_with(EVIDENCE_ROOT + "/") and not output_path.contains(".."), "evidence must stay in assigned directory")


func _resolved_builds() -> Dictionary:
	var items = Items.new()
	_expect(items.load_all().is_empty(), "item content load failed")
	var build: Dictionary = Resolver.new(items).resolve_fixture("calibration_convergent")
	_expect(bool(build.get("ok", false)), "canonical calibration build rejected", build)
	var content = Content.new()
	_expect(content.load_all().is_empty(), "proxy content load failed")
	var compiled: Dictionary = Proxy.compile({"cores": ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"]}, content.cores)
	_expect(bool(compiled.get("ok", false)), "canonical white proxy rejected", compiled)
	return {"resolved_build": build, "resolved_proxy_build": compiled.get("value", {}), "active_build": {"skills": ["piercing_arrow"]}}


func _bump(template: String, field: String, values: Array) -> void:
	for value: Variant in values:
		var key = String(value)
		coverage[template][field][key] = int(coverage[template][field].get(key, 0)) + 1


func _observe_actors(arena, registry, world) -> Dictionary:
	var positions: Dictionary = {}
	for id: String in registry.actor_ids():
		var actor = registry.actor(id)
		var position: Vector2 = actor.feet_position
		var radius = float(actor.footprint_radius)
		_expect(registry.is_position_clear(position, arena.scene_runtime.authored_arena_rect, radius),
			"actor footprint outside authored walkable domain", {"actor_id": id, "tick": world.tick, "position": position, "radius": radius})
		_expect(actor.room_instance_id == world.room_instance_id and actor.world_revision == world.world_revision,
			"actor identity differs from shared world", {"actor_id": id, "tick": world.tick})
		_expect(int(actor.last_motor_tick) <= int(world.tick), "actor motor used future tick", {"actor_id": id})
		if id == "ranger" and world.tick > 0:
			_expect(int(actor.last_motor_tick) == int(world.tick), "player did not commit motor on real tick", {"actor_tick": actor.last_motor_tick, "world_tick": world.tick})
		positions[id] = position
		actor_checks += 1
	return positions


func _ring_probe(scene, registry, tick: int) -> Dictionary:
	var boundary: Dictionary = scene.movement_boundary
	var center: Vector2 = boundary.center
	var inner = float(boundary.inner_radius)
	var outer = float(boundary.outer_radius)
	var distance = (inner + outer) * 0.5
	var start = center + Vector2(-distance, 0)
	var target = center + Vector2(distance, 0)
	_expect(not registry.is_position_clear(center, Rect2(), 14.0), "ring physical hole became walkable")
	_expect(registry.is_position_clear(start, Rect2(), 14.0) and registry.is_position_clear(target, Rect2(), 14.0), "ring probe endpoints illegal")
	# A separate probe actor uses this same registry and the already committed
	# real tick. No real player's position, State, health or combat totals change.
	_expect(bool(scene.register_actor("matrix/ring-probe", start, 14.0).ok), "ring probe registration failed")
	var swept: Dictionary = scene.move_actor("matrix/ring-probe", target - start, tick)
	_expect(bool(swept.get("ok", false)) and bool(swept.get("blocked", false)), "ring sweep crossed closed hole", swept)
	_expect(swept.position.x < center.x - inner and registry.is_position_clear(swept.position, Rect2(), 14.0), "ring sweep ended across/inside hole", swept)
	_expect(bool(scene.unregister_actor("matrix/ring-probe").ok), "ring probe did not unregister")
	ring_probes += 1
	return {"tick": tick, "start": start, "requested_end": target, "actual_end": swept.position, "blocked": swept.blocked, "contact_count": swept.contacts.size()}


func _release_movement() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)


func _manual_input(arena, tick: int) -> void:
	_release_movement()
	if tick < MIN_TICKS:
		# Defined player input, not a domain override: hold fire for the first
		# second so short natural victories do not truncate the 30-tick probe.
		Input.action_press("move_left")
		return
	var player: Dictionary = arena.player_combat_state.snapshot(tick)
	var position: Vector2 = player.player_position
	var nearest = Vector2.INF
	var distance = INF
	for enemy in arena.enemies:
		if float(enemy.health) > 0.0 and position.distance_to(enemy.position) < distance:
			nearest = enemy.position
			distance = position.distance_to(nearest)
	if nearest.is_finite() and distance > float(arena.locked_targeting_distance) * 0.8:
		var direction = position.direction_to(nearest)
		Input.action_press("move_left" if direction.x < 0 else "move_right", absf(direction.x))
		Input.action_press("move_up" if direction.y < 0 else "move_down", absf(direction.y))
	# Same signal used by the HUD. Main forwards it to CombatInputAdapter;
	# the unmodified production command collection/routes/Rules consume it.
	arena.presentation.skill_requested.emit("piercing_arrow")


func _empty_registry(registry, label: String) -> void:
	_expect(registry.actor_ids().is_empty() and registry.snapshot().blockers.is_empty()
		and not registry.has_movement_boundary() and registry.movement_boundary_snapshot().is_empty(), "unmount retained registry contents: " + label)


func _room(template: String, seed: int, index: int, plan: Dictionary, builds: Dictionary) -> void:
	context = {"template": template, "seed": seed, "room_index": index, "room": plan.rooms[index]}
	var room: Dictionary = plan.rooms[index]
	var runtime = Runtime.new()
	var results: Array[Dictionary] = []
	runtime.completed.connect(func(result: Dictionary) -> void: results.append({"signal": "completed", "result": result.duplicate(true)}))
	runtime.abandoned.connect(func(result: Dictionary) -> void: results.append({"signal": "abandoned", "result": result.duplicate(true)}))
	root.add_child(runtime)
	var started: Dictionary = runtime.start_session({"contract_id": template, "mode": "Manual", "seed": seed,
		"room_index": index, "room_count": 3, "room": room, "presentation_enabled": false, "framework_context": builds})
	_expect(bool(started.get("ok", false)), "real native runtime failed to start", started)
	if not bool(started.get("ok", false)):
		_line(room_log, {"context": context, "start_result": started, "failures": failures})
		runtime.queue_free()
		await process_frame
		return
	var arena = runtime.room_instance
	var scene = runtime.scene_runtime
	var registry = scene.actor_registry
	var world = scene.simulation
	# Disable automatic display-frame scheduling only. The production step and
	# all Main-installed callbacks remain intact, including AI/hazard/outcomes.
	arena.set_process(false)
	runtime.set_process(false)
	_expect(arena.get_script().resource_path == "res://src/game/main.gd", "Main was replaced or stripped")
	_expect(scene.is_ready() and scene.mounted_scene == arena and arena.scene_runtime == scene, "native SceneRuntime ownership missing")
	_expect(arena.actor_registry == registry and arena.simulation_world == world, "registry/world was duplicated")
	_expect(arena.player_combat_rules != null and arena.player_combat_state != null and arena.combat_simulation != null, "production domain wiring missing")
	_expect(arena.player_combat_state.actor_snapshot().entity_id == "ranger", "player State not bound to registry actor")
	var asset: Dictionary = scene.world_asset.snapshot()
	var expected_path = "res://content/rooms/combat/" + String(room.layout_id)
	_expect(asset.world_scene_path == expected_path + ".tscn" and asset.manifest_path == expected_path + ".spatial.json", "wrong native asset selected", asset)
	var formal = Spatial.new(JSON.parse_string(FileAccess.get_file_as_string(asset.manifest_path)))
	var authored = Spatial.new(scene.native_scene_contract.spatial_manifest)
	_expect(formal.is_valid() and authored.is_valid() and scene.manifest.digest_input() == formal.digest_input()
		and scene.manifest.digest_input() == authored.digest_input(), "native/derived/formal manifest fields differ")
	_expect(scene.room_definition.is_valid() and scene.world_asset.is_valid() and registry.has_movement_boundary(), "invalid room contract/boundary")
	_expect(registry.actor_ids().size() >= 2, "real encounter did not register enemies")
	var spawn = Vector2.INF
	for socket: Dictionary in scene.spawn_socket_bindings:
		if socket.binding == "combat/spawn":
			spawn = socket.position
	_expect(spawn.is_finite() and registry.actor("ranger").feet_position == spawn, "ranger did not use legal native spawn")
	var instance_id = String(scene.room_instance_id)
	var revision = int(scene.world_revision)
	_expect(not scene.accepts_version(previous_instance, previous_revision), "prior room version still accepted")
	var stale_room: Dictionary = world.queue_command({"kind": "move", "entity_id": "ranger", "room_instance_id": previous_instance, "world_revision": previous_revision})
	var stale_revision: Dictionary = world.queue_command({"kind": "move", "entity_id": "ranger", "room_instance_id": instance_id, "world_revision": revision + 1})
	_expect(stale_room.get("error") == "stale_room_command" and stale_revision.get("error") == "stale_world_command", "stale command accepted", {"room": stale_room, "revision": stale_revision})
	stale_rejections += 2
	var native_ref = weakref(arena)
	var actor_ref = weakref(registry.actor("ranger"))
	var presenter_ref = weakref(scene.presenter)
	var binding_ids: Array = scene.native_scene_contract.bindings.values().duplicate()
	var binding_refs: Array[WeakRef] = []
	for id: Variant in binding_ids:
		var node = scene.presenter.native_binding_node(String(id))
		_expect(node != null, "native binding missing", {"binding": id})
		if node != null:
			binding_refs.append(weakref(node))
	var initial = _observe_actors(arena, registry, world)
	var initial_registry = registry.snapshot()
	var changed_actors: Dictionary = {}
	var command_count = 0
	var accepted_receipts = 0
	var rejected_receipts = 0
	var minimum_enemy_distance = INF
	var tick = 0
	var terminal = false
	while tick < MAX_TICKS and not bool(arena.battle_over) and failures.is_empty():
		var before_tick = int(world.tick)
		_manual_input(arena, before_tick)
		var stepped: Dictionary = arena.combat_simulation.step()
		tick = int(world.tick)
		_expect(bool(stepped.get("ok", false)) and tick == before_tick + 1 and int(arena.sim_tick) == tick,
			"production simulation did not commit one real tick", stepped)
		if not bool(stepped.get("ok", false)):
			break
		_expect(stepped.world_step.commands.is_empty(), "stale lifecycle command reached committed tick")
		var positions = _observe_actors(arena, registry, world)
		for id: String in positions:
			if initial.has(id) and (positions[id] as Vector2).distance_to(initial[id]) > 0.001:
				changed_actors[id] = true
			if id != "ranger":
				minimum_enemy_distance = minf(minimum_enemy_distance, (positions[id] as Vector2).distance_to(positions.ranger))
		for receipt: Dictionary in stepped.player_step.receipts:
			command_count += 1
			if bool(receipt.get("accepted", false)):
				accepted_receipts += 1
			else:
				rejected_receipts += 1
		total_ticks += 1
	terminal = bool(arena.battle_over)
	_expect(tick >= MIN_TICKS, "encounter did not reach 30 real ticks", {"ticks": tick, "natural_terminal": terminal})
	_expect(not changed_actors.is_empty(), "real encounter never moved any actor")
	_expect(command_count > 0 and accepted_receipts > 0, "Manual device commands produced no accepted receipt", {"commands": command_count})
	_expect(arena.automation_smoke_failure.is_empty(), "production reported automation failure", {"failure": arena.automation_smoke_failure})
	var ring_result: Dictionary = {}
	if String(room.layout_id) == "ring" and failures.is_empty():
		ring_result = _ring_probe(scene, registry, tick)
	_release_movement()
	var final_registry = registry.snapshot()
	var final_player: Dictionary = arena.player_combat_state.snapshot(tick)
	var combat_totals: Dictionary = arena.combat_system.outcome_snapshot()
	var room_rules: Dictionary = arena.room_rules.snapshot()
	var presentation_before = scene.presenter.presentation_report()
	var rules_before = arena.room_rules.snapshot()
	# Exercise the real public return signal, duplicate return and public abandon.
	# Natural terminal rooms complete; bounded ongoing encounters are abandoned.
	arena.emit_signal("return_requested")
	arena.emit_signal("return_requested")
	runtime.request_abandon()
	_expect(results.size() == 1, "result was not submitted exactly once", {"results": results})
	var outcome = "missing"
	if results.size() == 1:
		var result: Dictionary = results[0].result
		outcome = String(result.get("outcome", ""))
		_expect(outcome in ["victory", "defeat"] if terminal else outcome == "abandoned", "return result disagreed with natural outcome", result)
		_expect(int(result.get("ticks", -1)) == tick and result.get("room_id") == room.room_id
			and result.get("seed") == seed and result.get("contract_id") == template, "result identity/tick mismatch", result)
		_expect(not runtime.is_processing() and not arena.is_processing(), "terminal observer or abandoned arena kept processing")
		_expect(arena.room_rules.snapshot() == rules_before, "repeated return recommitted room reward")
	outcomes[outcome] = int(outcomes.get(outcome, 0)) + 1
	var tick_after = int(world.tick)
	await process_frame
	_expect(int(world.tick) == tick_after and results.size() == 1, "closed encounter advanced or submitted again on tree frame")
	_expect(bool(scene.unmount().ok), "native unmount rejected")
	_empty_registry(registry, "retained old")
	_empty_registry(scene.actor_registry, "current empty")
	_expect(not scene.is_ready() and scene.mounted_scene == null and not scene.accepts_version(instance_id, revision), "unmounted version remained ready")
	_expect(scene.move_actor("ranger", Vector2.ONE, tick + 1).get("error") == "runtime_not_ready", "unmounted movement accepted")
	_expect(scene.simulation.queue_command({"kind": "move", "room_instance_id": instance_id, "world_revision": revision}).get("error") == "stale_room_command", "unmounted room command accepted")
	stale_rejections += 1
	_expect(scene.presenter.actor_ids().is_empty() and scene.presenter.presentation_report().native_content_count == 0, "presenter kept actor/native registrations")
	for id: Variant in binding_ids:
		_expect(scene.presenter.native_binding_node(String(id)) == null, "presenter kept binding ref after unmount")
	await process_frame
	await process_frame
	await process_frame
	_expect(native_ref.get_ref() == null and actor_ref.get_ref() == null, "native Main or player ActorState survived queue_free")
	for ref: WeakRef in binding_refs:
		_expect(ref.get_ref() == null, "native bound node survived queue_free")
	for layer: String in ["Ground", "GroundEffects", "SortRoot", "Foreground"]:
		_expect(scene.presenter.native_group(layer).get_child_count() == 0, "presenter retained child after tree frames", {"layer": layer})
	_expect(results.size() == 1, "unmount emitted duplicate result")
	var record = {"template": template, "seed": seed, "room_index": index, "room": room,
		"mode": "Manual", "input_policy": "move_left_first_30_ticks_then_approach_and_assisted_attack", "ticks": tick, "natural_terminal": terminal, "outcome": outcome, "result_signals": results,
		"instance_id": instance_id, "revision": revision, "asset": asset,
		"manifest_sha256": FileAccess.get_sha256(asset.manifest_path), "scene_sha256": FileAccess.get_sha256(asset.world_scene_path),
		"spawn": spawn, "initial_registry": initial_registry, "final_registry": final_registry, "final_player": final_player,
		"shots": combat_totals.shots, "hits": combat_totals.arrow_hits, "defeated": combat_totals.defeated,
		"room_rules": room_rules, "changed_actor_ids": changed_actors.keys(), "commands": command_count,
		"accepted_receipts": accepted_receipts, "rejected_receipts": rejected_receipts,
		"minimum_enemy_distance": minimum_enemy_distance, "ring_probe": ring_result, "presenter_before_unmount": presentation_before,
		"cleanup": {"old_actors": registry.actor_ids().size(), "old_blockers": registry.snapshot().blockers.size(),
			"old_boundary": registry.movement_boundary_snapshot(), "native_alive": native_ref.get_ref() != null,
			"actor_alive": actor_ref.get_ref() != null, "binding_ref_count": binding_refs.size()}, "failures": failures.duplicate()}
	previous_instance = instance_id
	previous_revision = revision
	runtime.queue_free()
	await process_frame
	await process_frame
	_expect(presenter_ref.get_ref() == null, "coordinator presenter survived runtime free")
	record["cleanup"]["presenter_alive"] = presenter_ref.get_ref() != null
	record["failures"] = failures.duplicate()
	_line(room_log, record)
	if failures.is_empty():
		room_count += 1


func _run() -> void:
	started_usec = Time.get_ticks_usec()
	_arguments()
	if not failures.is_empty():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_path)
	room_log = FileAccess.open(output_path + "/rooms.jsonl", FileAccess.WRITE)
	seed_log = FileAccess.open(output_path + "/seeds.jsonl", FileAccess.WRITE)
	_expect(room_log != null and seed_log != null, "evidence output unavailable")
	_fingerprint_sources()
	var builds = _resolved_builds()
	_write_json(output_path + "/resolved-builds.json", builds)
	var campaign = Campaign.new()
	_expect(campaign.load_campaign().is_empty(), "campaign content invalid")
	var template_specs: Dictionary = {}
	for template: String in TEMPLATES:
		template_specs[template] = campaign.get_node(template).room_template
		coverage[template] = {"seed_count": 0, "layout": {}, "objective": {}, "hazard": {}, "enemy": {}, "elite": {}, "drop": {}, "layout_objective": {}}
	for template: String in TEMPLATES:
		for seed: int in range(first_seed, first_seed + seed_count):
			if not failures.is_empty():
				break
			context = {"template": template, "seed": seed}
			var manual: Dictionary = Plan.build({"contract_id": template, "seed": seed, "mode": "Manual"})
			var repeated: Dictionary = Plan.build({"contract_id": template, "seed": seed, "mode": "Manual"})
			var automatic: Dictionary = Plan.build({"contract_id": template, "seed": seed, "mode": "Auto"})
			_expect(bool(manual.get("ok", false)) and bool(automatic.get("ok", false)) and bool(repeated.get("ok", false)), "real template plan rejected")
			if not failures.is_empty():
				break
			_expect(manual == repeated and manual.plan.rooms == automatic.plan.rooms, "same-seed stability or Manual/Auto plan equality failed")
			_expect(manual.plan.rooms.size() == 3 and automatic.plan.repeatable and automatic.plan.mode == "Auto", "template envelope changed")
			var hashes: Array[String] = []
			for room: Dictionary in automatic.plan.rooms:
				hashes.append(JSON.stringify(room, "", true, true).sha256_text())
			_line(seed_log, {"template": template, "seed": seed, "manual_auto_rooms_equal": manual.plan.rooms == automatic.plan.rooms,
				"same_seed_equal": manual == repeated, "room_hashes": hashes, "plan": automatic.plan})
			for index: int in 3:
				if not failures.is_empty():
					break
				var room: Dictionary = automatic.plan.rooms[index]
				var spec: Dictionary = template_specs[template]
				_expect(room.layout_id in spec.layout_ids and room.objective_id in spec.objective_ids, "generated layout/objective escaped template")
				for field: String in ["hazard_ids", "enemy_ids", "elite_rule_ids", "drop_tags"]:
					for value: Variant in room[field]:
						_expect(value in spec[field], "generated content escaped template", {"field": field, "value": value})
				_bump(template, "layout", [room.layout_id])
				_bump(template, "objective", [room.objective_id])
				_bump(template, "hazard", room.hazard_ids if not room.hazard_ids.is_empty() else ["<none>"])
				_bump(template, "elite", room.elite_rule_ids if not room.elite_rule_ids.is_empty() else ["<none>"])
				_bump(template, "enemy", room.enemy_ids)
				_bump(template, "drop", room.drop_tags)
				_bump(template, "layout_objective", [String(room.layout_id) + "/" + String(room.objective_id)])
				await _room(template, seed, index, automatic.plan, builds)
			if failures.is_empty():
				coverage[template].seed_count += 1
			if (seed + 1) % 10 == 0:
				print("MATRIX_PROGRESS template=", template, " last_seed=", seed, " rooms=", room_count, " ticks=", total_ticks)
	if failures.is_empty() and first_seed == 0 and seed_count == 100:
		for template: String in TEMPLATES:
			var spec: Dictionary = template_specs[template]
			for pair: Array in [["layout", "layout_ids"], ["objective", "objective_ids"], ["hazard", "hazard_ids"], ["enemy", "enemy_ids"], ["elite", "elite_rule_ids"], ["drop", "drop_tags"]]:
				for value: Variant in spec[pair[1]]:
					_expect(coverage[template][pair[0]].has(value), "full fixed-seed matrix missed authored content", {"template": template, "field": pair[0], "value": value})
			_expect(coverage[template].layout_objective.size() == 9, "full matrix missed layout/objective pair", {"template": template})
	_expect(room_count == TEMPLATES.size() * seed_count * 3, "matrix did not complete requested room count", {"completed": room_count})
	var changed: Array[String] = []
	for path: String in evidence_files:
		if source_fingerprints[path] != FileAccess.get_sha256(path):
			changed.append(path)
	_expect(changed.is_empty(), "frozen runtime/content changed during run", {"changed_paths": changed})
	var summary = {"ok": failures.is_empty(), "full_matrix": first_seed == 0 and seed_count == 100,
		"first_seed": first_seed, "last_seed": first_seed + seed_count - 1, "seeds_per_template": seed_count,
		"templates": TEMPLATES, "expected_rooms": TEMPLATES.size() * seed_count * 3, "completed_rooms": room_count,
		"encounter_mode": "Manual", "input_policy": "move_left_first_30_ticks_then_approach_and_assisted_attack",
		"minimum_required_ticks": MIN_TICKS, "maximum_ticks_per_room": MAX_TICKS, "total_ticks": total_ticks,
		"actor_footprint_checks": actor_checks, "ring_sweep_probes": ring_probes, "stale_rejections": stale_rejections,
		"outcomes": outcomes, "coverage": coverage, "elapsed_seconds": float(Time.get_ticks_usec() - started_usec) / 1000000.0,
		"source_changes": changed, "failures": failures}
	_write_json(output_path + "/summary.json", summary)
	room_log.close()
	seed_log.close()
	print("PASS " if failures.is_empty() else "FAIL ", "test_repeatable_encounter_matrix.gd rooms=", room_count,
		" seeds=", first_seed, "..", first_seed + seed_count - 1, " outcomes=", JSON.stringify(outcomes), " ticks=", total_ticks)
	quit(0 if failures.is_empty() else 1)
