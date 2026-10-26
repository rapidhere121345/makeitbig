extends SceneTree
## Scene-authored town exit gateways: validation, distance/priority/blocking rules,
## and the real contract signal in the real game root.
const Game = preload("res://src/game/game_root.gd")
const TownController = preload("res://src/runtime/world/town_controller.gd")
const GATE := {"id": "expedition", "label": "Expedition Gate", "position": [576.0, 595.3125], "radius": 48.0, "action": "contract"}
var failures: Array[String] = []
var _contract_signals := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := Game.new()
	game.save_directory_path = "user://town-gateways-no-player-save"
	game.playtest_logging_enabled = false
	game.initialize(PackedStringArray(["--game-flow-smoke"]))
	root.add_child(game)
	await process_frame
	_expect(game.start_new_game("ranger").ok and game.complete_tutorial().ok, "new profile reaches town")
	await process_frame
	var hub = game.current_screen
	var town = hub.get_town_runtime()
	var spawn: Vector2 = town.hero_world_position()
	var base_content: Dictionary = town._content.duplicate(true)

	# The production scene may author gates; whatever it authors must be valid and bound.
	var live_gates: Array = (base_content.get("gateways", []) as Array).duplicate(true)
	var sockets: Array = hub._town_controller.scene_runtime.manifest.snapshot().get("spawn_interaction_exit_sockets", [])
	for gate: Dictionary in live_gates:
		_expect(String(gate.get("action", "")) in town.GATEWAY_ACTIONS, "live gate %s has a whitelisted action" % gate.get("id", "?"))
		var bound := false
		for socket: Dictionary in sockets:
			bound = bound or (String(socket.get("socket_id", "")) == "town/exit/" + String(gate.get("id", "")) and String(socket.get("kind", "")) == "exit")
		_expect(bound, "live gate %s has an exit socket binding" % gate.get("id", "?"))

	# Gateless compatibility is synthetic: the live metadata with its gateways removed.
	base_content.erase("gateways")
	_expect(bool(town.configure(town.simulation, town.registry, base_content).get("ok", false)), "gateless synthetic metadata configures")
	spawn = town.hero_world_position()
	_expect(town.gateway_entries().is_empty() and town.nearby_gateway_id() == "", "a gateless town reports no gateway")
	_expect(not hub.activate_nearby_gateway() and hub.nearby_gateway_id() == "", "no gateway to activate in a gateless town")
	_expect(town.snapshot().has("gateways") and (town.snapshot().gateways as Array).is_empty(), "snapshot carries an empty gateway list")
	_expect(town.feature_entries().size() == 5 and town.FACILITY_IDS == ["contract", "loadout", "forge", "training", "proxy"], "facility set changed")

	# Malformed gate definitions fail configure closed and leave the live town untouched.
	var bad_cases := {
		"duplicate_id": [GATE, GATE],
		"facility_id": [GATE.merged({"id": "loadout"}, true)],
		"resident_id": [GATE.merged({"id": "iven"}, true)],
		"empty_id": [GATE.merged({"id": ""}, true)],
		"radius_small": [GATE.merged({"radius": 2.0}, true)],
		"radius_large": [GATE.merged({"radius": 500.0}, true)],
		"radius_nan": [GATE.merged({"radius": NAN}, true)],
		"radius_string": [GATE.merged({"radius": "48"}, true)],
		"action_combat": [GATE.merged({"action": "combat"}, true)],
		"action_missing": [{"id": "expedition", "position": [576.0, 595.3125], "radius": 48.0}],
		"position_nan": [GATE.merged({"position": [NAN, 10.0]}, true)],
		"position_short": [GATE.merged({"position": [10.0]}, true)],
		"position_blocked": [GATE.merged({"position": [-500.0, -500.0]}, true)],
		"not_a_dictionary": ["expedition"],
		"gateways_not_array": "expedition",
	}
	for name: String in bad_cases:
		var result: Dictionary = _configure(town, base_content, bad_cases[name])
		_expect(not bool(result.get("ok", true)) and String(result.get("error", "")).begins_with("town_gateway_invalid"), "%s must be rejected, got %s" % [name, str(result)])
		_expect(town.is_ready() and town.gateway_entries().is_empty() and town.hero_world_position() == spawn, "%s must leave the town untouched" % name)
	# A failed reconfiguration must also preserve the borrowed world/registry,
	# even when the proposed replacement is a different valid mounted world.
	var alternate := TownController.new()
	root.add_child(alternate)
	var alternate_mount: Dictionary = alternate.mount(alternate)
	_expect(bool(alternate_mount.get("ok", false)), "alternate town mounts for atomic-config regression")
	if bool(alternate_mount.get("ok", false)):
		var previous_world = town.simulation
		var previous_registry = town.registry
		var invalid_content := base_content.duplicate(true)
		invalid_content["gateways"] = [GATE, GATE]
		var denied: Dictionary = town.configure(alternate.town.simulation, alternate.town.registry, invalid_content)
		_expect(not bool(denied.get("ok", true)), "alternate-world invalid gateway rejected")
		_expect(town.simulation == previous_world and town.registry == previous_registry and town.is_ready(), "invalid gateway replaced live simulation dependencies")
		alternate.scene_runtime.simulation.kernel.shutdown()
	alternate.free()

	var accepted: Dictionary = _configure(town, base_content, [GATE])
	_expect(bool(accepted.get("ok", false)), "valid gate accepted: " + str(accepted))
	var entry: Dictionary = town.entry_for_gateway("expedition")
	_expect(entry.feet == Vector2(576.0, 595.3125) and entry.radius == 48.0 and entry.action == "contract" and entry.label == "Expedition Gate", "gate entry fields")
	_expect(town.feature_entries().size() == 5 and town.nearby_feature_id() == "", "a gate must not become a facility")
	var feature_radii := {}
	for facility: Dictionary in town.feature_entries():
		feature_radii[facility.id] = facility.radius
	_expect(feature_radii == {"contract": 48.0, "loadout": 48.0, "forge": 48.0, "training": 48.0, "proxy": 48.0}, "facility radii changed: " + str(feature_radii))

	hub.contract_requested.connect(func(): _contract_signals += 1)
	var profile_before: Dictionary = game.application_state.persistent_payload()

	# Far activation does nothing and shows no prompt.
	var far_point: Vector2 = town.route_points("loadout")[1]
	_expect(bool(town.place_hero(far_point).get("ok", false)) and far_point.distance_to(entry.feet) > 48.0, "far fixture placed")
	hub._update_nearby_feature()
	_expect(town.nearby_gateway_id() == "" and not hub.activate_nearby_interaction() and not hub.activate_nearby_gateway(), "far press must be rejected")
	_expect(_contract_signals == 0 and game.current_route == "base" and hub.get_prompt_rect() == Rect2(), "far press emitted or prompted")

	# In range: prompt names the gate; blocked by dialogue and details.
	_expect(bool(town.place_hero(spawn).get("ok", false)), "hero returned to the gate")
	hub._update_nearby_feature()
	_expect(town.nearby_gateway_id() == "expedition" and hub.nearby_gateway_id() == "expedition", "gate in range")
	_expect(hub.get_prompt_rect() != Rect2() and hub._nearby_label.text == "[E / Space] Enter Expedition Gate", "prompt text: " + hub._nearby_label.text)
	hub.set_information_details_expanded(true)
	_expect(hub.nearby_gateway_id() == "" and not hub.activate_nearby_interaction(), "details panel must block the gate")
	hub.set_information_details_expanded(false)
	var resident_ids: Array = hub._resident_conversations.keys()
	_expect(not resident_ids.is_empty(), "a resident conversation exists for the dialogue fixture")
	if not resident_ids.is_empty():
		var rid := String(resident_ids[0])
		var resident_feet: Vector2 = town.resident_positions()[rid]
		var talk_point := Vector2.INF
		for offset: Vector2 in [Vector2(0, 20), Vector2(0, -20), Vector2(20, 0), Vector2(-20, 0), Vector2(14, 14), Vector2(-14, 14)]:
			if town.hero_position_is_clear(resident_feet + offset):
				talk_point = resident_feet + offset
				break
		_expect(talk_point.is_finite() and bool(_configure(town, base_content, [GATE.merged({"position": [talk_point.x, talk_point.y]}, true)]).get("ok", false)), "gate placed beside a resident")
		_expect(bool(town.place_hero(talk_point).get("ok", false)) and hub.talk_to_resident(rid), "dialogue opened for the blocking fixture")
		_expect(hub.nearby_gateway_id() == "" and not hub.activate_nearby_gateway(), "dialogue must block the gate")
		hub._dialogue.close_dialogue()
		_expect(bool(_configure(town, base_content, [GATE]).get("ok", false)) and bool(town.place_hero(spawn).get("ok", false)), "gate restored at spawn")
	_expect(_contract_signals == 0 and game.current_route == "base", "blocked presses emitted a contract request")

	# A facility in range keeps priority: the gate never steals its interaction.
	var proxy_feet: Vector2 = town.entry_for("proxy").feet
	var shifted: Dictionary = _configure(town, base_content, [GATE.merged({"position": [proxy_feet.x, proxy_feet.y]}, true)])
	_expect(bool(shifted.get("ok", false)) and bool(town.place_hero(proxy_feet).get("ok", false)), "gate stacked on the proxy stand")
	_expect(town.nearby_feature_id() == "proxy" and town.nearby_gateway_id() == "expedition", "both in range")
	hub._update_nearby_feature()
	_expect(not hub._nearby_label.text.contains("Expedition"), "prompt must not name the gate while a stand or resident wins: " + hub._nearby_label.text)
	hub.activate_nearby_interaction()
	_expect(_contract_signals == 0, "gate stole a facility or resident interaction")
	if hub._dialogue != null and hub._dialogue.is_open():
		hub._dialogue.close_dialogue()
	if game.current_route != "base":
		_expect(game.leave_facility().ok, "back from the stand")
		await process_frame
		hub = game.current_screen
		town = hub.get_town_runtime()
	_expect(bool(_configure(town, base_content, [GATE]).get("ok", false)), "gate restored on the live hub")
	hub.contract_requested.connect(func(): _contract_signals += 1)

	# Real signal, real route, no settlement.
	_expect(bool(town.place_hero(spawn).get("ok", false)), "hero at the gate again")
	_expect(hub.activate_nearby_interaction(), "E at the gate activates it")
	_expect(_contract_signals == 1 and game.current_route == "contract", "gate must request the contract screen, got %s with %d signals" % [game.current_route, _contract_signals])
	_expect(game.application_state.persistent_payload() == profile_before, "opening the contract from the gate changed progression")
	_expect(game.cancel_contract().ok, "contract cancels back to town")
	await process_frame
	# Freshly mounted scene metadata, without replacing it with a synthetic gate.
	hub = game.current_screen
	town = hub.get_town_runtime()
	var authored: Dictionary = town.entry_for_gateway("expedition")
	_expect(town.gateway_entries().size() == 1 and not authored.is_empty(), "production town must expose its authored expedition gateway")
	if not authored.is_empty():
		_contract_signals = 0
		hub.contract_requested.connect(func(): _contract_signals += 1)
		_expect(bool(town.place_hero(authored.feet).get("ok", false)), "authored expedition stand is clear")
		hub._update_nearby_feature()
		_expect(hub.nearby_gateway_id() == "expedition" and hub.get_prompt_rect() != Rect2(), "authored gate has an in-range prompt")
		_expect(hub.activate_nearby_interaction(), "authored expedition interaction accepted")
		_expect(game.current_route == "contract" and _contract_signals == 1, "authored expedition gateway must open Contracts exactly once")
		_expect(game.application_state.persistent_payload() == profile_before, "authored gate changed progression")
		print("TOWN_GATEWAY_AUTHORED expedition feet=", authored.feet, " route=", game.current_route, " signals=", _contract_signals)

	game.free()
	await process_frame
	for failure: String in failures:
		printerr(failure)
	print("TOWN_GATEWAYS ", "pass" if failures.is_empty() else "fail")
	quit(0 if failures.is_empty() else 1)


func _configure(town, base_content: Dictionary, gateways: Variant) -> Dictionary:
	var content := base_content.duplicate(true)
	content["gateways"] = gateways
	return town.configure(town.simulation, town.registry, content)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
