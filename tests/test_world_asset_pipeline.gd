extends SceneTree

## World asset authoring/validation pipeline and detached occlusion
## contract regression.  Headless, no GPU harness:
##   godot --headless --path . --script res://tests/test_world_asset_pipeline.gd

const BakeCore := preload("res://tools/world_manifest/bake_core.gd")
const SpatialManifestScript := preload("res://src/runtime/world/spatial_manifest.gd")
const WorldAssetScript := preload("res://src/runtime/world/world_asset.gd")
const OcclusionPlanScript := preload("res://src/presentation/occlusion/occlusion_plan.gd")
const OcclusionControllerScript := preload("res://src/presentation/occlusion/occlusion_controller.gd")
const Fixtures := preload("res://tests/world_asset/manifest_fixtures.gd")
const EnvironmentDefinitionScript := preload("res://src/runtime/world/environment_object_definition.gd")
const EnvironmentPlacementScript := preload("res://src/runtime/world/environment_object_placement.gd")
const EnvironmentBakerScript := preload("res://src/runtime/world/environment_object_baker.gd")
const TownSceneRootScript := preload("res://src/runtime/world/town_scene_root.gd")

const RING_SCENE := "res://content/rooms/combat/ring.tscn"
const RING_MANIFEST := "res://content/rooms/combat/ring.spatial.json"
const SYNTHETIC_CANVAS := Vector2i(256, 224)

var _fade_created_files: Array[String] = []

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_deterministic_bake()
	_test_digest_separation()
	_test_authoring_validation_rejects_invalid_data()
	_test_overlay_separation()
	_test_world_asset_manifest_verification()
	_test_occlusion_plan_stability()
	_test_controller_interpolation_and_alpha()
	_test_no_art_box_fails_closed()
	_test_primitive_fade_metadata()
	if failures.is_empty():
		print("PASS  test_world_asset_pipeline.gd")
		quit(0)
		return
	printerr("%d world asset pipeline check(s) failed:" % failures.size())
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _contains(errors: Variant, needle: String) -> bool:
	if not errors is Array:
		return false
	for error: Variant in errors:
		if str(error).contains(needle):
			return true
	return false


func _test_deterministic_bake() -> void:
	var first: Dictionary = BakeCore.bake_scene(RING_SCENE, RING_MANIFEST)
	var second: Dictionary = BakeCore.bake_scene(RING_SCENE, RING_MANIFEST)
	_expect(bool(first.get("ok", false)), "bake: native ring scene failed to bake: %s" % str(first.get("errors", [])))
	if not bool(first.get("ok", false)):
		return
	_expect(first["manifest"] == second["manifest"], "bake: manifest payload was not byte-deterministic")
	_expect(first["world_asset"] == second["world_asset"], "bake: world asset payload was not byte-deterministic")
	_expect(String(first["world_asset"]["gameplay_digest"]).length() == 64, "bake: gameplay digest is not sha256-sized")
	_expect(String(first["world_asset"]["presentation_digest"]).length() == 64, "bake: presentation digest is not sha256-sized")
	_expect(first["world_asset"]["gameplay_digest"] != first["world_asset"]["presentation_digest"], "bake: gameplay and presentation digests collapsed into one value")
	# Deterministic ordering: shuffled input arrays normalize to the same digests.
	var shuffled: Dictionary = Fixtures.authoring_payload()
	(shuffled["stable_bindings"] as Array).reverse()
	(shuffled["spawn_interaction_exit_sockets"] as Array).reverse()
	var ordered: Dictionary = Fixtures.authoring_payload()
	_expect(
		SpatialManifestScript.gameplay_digest_input(shuffled) == SpatialManifestScript.gameplay_digest_input(ordered),
		"bake: gameplay digest input depended on authored array order"
	)
	_expect(
		SpatialManifestScript.presentation_digest_input(shuffled) == SpatialManifestScript.presentation_digest_input(ordered),
		"bake: presentation digest input depended on authored array order"
	)


func _test_digest_separation() -> void:
	var base: Dictionary = Fixtures.authoring_payload()
	var gameplay_base := SpatialManifestScript.gameplay_digest_input(base)
	var presentation_base := SpatialManifestScript.presentation_digest_input(base)
	# A pure-presentation change moves only the presentation half.
	var presentation_changed: Dictionary = Fixtures.authoring_payload()
	for binding: Variant in presentation_changed["stable_bindings"]:
		if String((binding as Dictionary).get("binding_id", "")) == "art.sign":
			(binding as Dictionary)["art_box"] = [-24.0, -48.0, 48.0, 48.0]
	_expect(SpatialManifestScript.gameplay_digest_input(presentation_changed) == gameplay_base, "digest: a pure presentation change moved the gameplay digest")
	_expect(SpatialManifestScript.presentation_digest_input(presentation_changed) != presentation_base, "digest: a pure presentation change did not move the presentation digest")
	# A pure gameplay change moves only the gameplay half.
	var gameplay_changed: Dictionary = Fixtures.authoring_payload()
	for binding: Variant in gameplay_changed["stable_bindings"]:
		if String((binding as Dictionary).get("binding_id", "")) == "combat/movement-boundary":
			((binding as Dictionary)["geometry"] as Dictionary)["rect"] = [0.0, 0.0, 210.0, 200.0]
	_expect(SpatialManifestScript.gameplay_digest_input(gameplay_changed) != gameplay_base, "digest: a pure gameplay change did not move the gameplay digest")
	_expect(SpatialManifestScript.presentation_digest_input(gameplay_changed) == presentation_base, "digest: a pure gameplay change moved the presentation digest")
	# Socket truth belongs to the gameplay half only.
	var socket_changed: Dictionary = Fixtures.authoring_payload()
	(socket_changed["spawn_interaction_exit_sockets"] as Array)[0]["position"] = [64.0, 170.0]
	_expect(SpatialManifestScript.gameplay_digest_input(socket_changed) != gameplay_base, "digest: socket move did not move the gameplay digest")
	_expect(SpatialManifestScript.presentation_digest_input(socket_changed) == presentation_base, "digest: socket move moved the presentation digest")
	var ground_changed := base.duplicate(true)
	ground_changed.stable_bindings.append({"binding_id": "town/ground", "kind": "native_visual",
		"source": "ground-content-sha", "channels": {"occlusion": false}})
	_expect(SpatialManifestScript.gameplay_digest_input(ground_changed) == gameplay_base, "digest: nonoccluding ground art changed gameplay")
	_expect(SpatialManifestScript.presentation_digest_input(ground_changed) != presentation_base, "digest: nonoccluding ground art was omitted")
	_expect(SpatialManifestScript.new(ground_changed).occlusion_bindings().size() == SpatialManifestScript.new(base).occlusion_bindings().size(), "digest: ground became an occluder")


func _test_authoring_validation_rejects_invalid_data() -> void:
	# Runtime contract still rejects unknown channels and duplicate ids.
	var unknown_channel: Dictionary = Fixtures.authoring_payload()
	(unknown_channel["stable_bindings"] as Array)[0]["channels"]["smell"] = true
	_expect(_contains(SpatialManifestScript.validate_data(unknown_channel), "unknown_channel:smell"), "validate: unknown channel was accepted")
	var duplicates: Dictionary = Fixtures.authoring_payload()
	(duplicates["stable_bindings"] as Array).append((duplicates["stable_bindings"] as Array)[0])
	_expect(_contains(SpatialManifestScript.validate_data(duplicates), "duplicate_stable_id"), "validate: duplicate stable id was accepted")
	# Authoring contract additionally fails closed on mismatched data.
	var cases: Array[Array] = [
		["units_pixel", _mutated(func(payload: Dictionary) -> void: payload["coordinate_convention"]["units"] = "pixel"), "invalid_coordinate_convention:units"],
		["missing_scale", _mutated(func(payload: Dictionary) -> void: (payload["coordinate_convention"] as Dictionary).erase("scale")), "missing_coordinate_field:scale"],
		["extra_convention", _mutated(func(payload: Dictionary) -> void: payload["coordinate_convention"]["flip"] = true), "unknown_coordinate_field:flip"],
		["bad_anchor_mode", _mutated(func(payload: Dictionary) -> void: (payload["stable_bindings"] as Array)[2]["feet_anchor"]["mode"] = "top_left"), "invalid_feet_anchor:top_left"],
		["anchor_mismatch", _mutated(func(payload: Dictionary) -> void: (payload["stable_bindings"] as Array)[2]["art_box"] = [-10.0, -40.0, 40.0, 40.0]), "art_box_anchor_mismatch"],
		["art_without_anchor", _mutated(func(payload: Dictionary) -> void: (payload["stable_bindings"] as Array)[2].erase("feet_anchor")), "missing_feet_anchor"],
		["anchor_without_art", _mutated(func(payload: Dictionary) -> void: (payload["stable_bindings"] as Array)[0]["feet_anchor"] = {"mode": "art_bottom_center"}), "orphan_feet_anchor"],
		["invalid_art_box", _mutated(func(payload: Dictionary) -> void: (payload["stable_bindings"] as Array)[2]["art_box"] = [-20.0, -40.0, 0.0, 40.0]), "invalid_art_box"],
		["attack_without_geometry", _mutated(func(payload: Dictionary) -> void: (payload["stable_bindings"] as Array)[2]["channels"] = {"attack": true}), "missing_solid_geometry:attack"],
		["unknown_binding_field", _mutated(func(payload: Dictionary) -> void: (payload["stable_bindings"] as Array)[0]["runtime_state"] = {"open": true}), "unknown_binding_field:runtime_state"],
		["socket_without_position", _mutated(func(payload: Dictionary) -> void: ((payload["spawn_interaction_exit_sockets"] as Array)[0] as Dictionary).erase("position")), "missing_socket_position"],
		["duplicate_profile", _mutated(func(payload: Dictionary) -> void: (payload["traversal_profiles"] as Array).append({"profile_id": "standard", "radius": 12.0})), "duplicate_profile_id:standard"],
		["bad_traversal_radius", _mutated(func(payload: Dictionary) -> void: (payload["traversal_profiles"] as Array)[0]["radius"] = 0.0), "invalid_traversal_radius"],
	]
	for case: Array in cases:
		var label := String(case[0])
		var errors := SpatialManifestScript.validate_authoring_data(case[1])
		_expect(_contains(errors, String(case[2])), "authoring: %s was accepted (errors: %s)" % [label, str(errors)])
	# The clean fixture passes both tiers and the channel vocabulary is explicit.
	_expect(SpatialManifestScript.validate_data(Fixtures.authoring_payload()).is_empty(), "authoring: clean fixture failed the runtime contract")
	_expect(SpatialManifestScript.validate_authoring_data(Fixtures.authoring_payload()).is_empty(), "authoring: clean fixture failed the authoring contract")
	_expect(SpatialManifestScript.CHANNELS == ["movement", "navigation", "vision", "projectile", "attack", "hurtbox", "occlusion"], "authoring: channel vocabulary is not the explicit seven-channel contract")
	# Seven-channel manifests validate and land in the gameplay digest half.
	var payload: Dictionary = Fixtures.authoring_payload()
	var manifest = SpatialManifestScript.new(payload)
	_expect(manifest.bindings_for_channel("attack").size() == 1 and manifest.bindings_for_channel("hurtbox").size() == 1, "authoring: attack/hurtbox channels were not selectable")
	_expect(manifest.gameplay_digest_sha256() != manifest.presentation_digest_sha256(), "authoring: digest halves collapsed")


func _mutated(mutator: Callable) -> Dictionary:
	var payload: Dictionary = Fixtures.authoring_payload()
	mutator.call(payload)
	return payload


func _test_overlay_separation() -> void:
	var manifest = SpatialManifestScript.new(Fixtures.authoring_payload())
	var snapshot_before: Dictionary = manifest.snapshot()
	var gameplay_before := manifest.gameplay_digest_sha256()
	var presentation_before := manifest.presentation_digest_sha256()
	var applied: Dictionary = manifest.with_overlay(Fixtures.overlay_entries())
	_expect(bool(applied.get("ok", false)), "overlay: clean gate overlay was rejected: %s" % str(applied.get("errors", [])))
	if not bool(applied.get("ok", false)):
		return
	# The authored manifest stays immutable; the overlay produced a NEW view.
	_expect(manifest.snapshot() == snapshot_before, "overlay: applying an overlay mutated the authored manifest")
	_expect(manifest.gameplay_digest_sha256() == gameplay_before and manifest.presentation_digest_sha256() == presentation_before, "overlay: applying an overlay changed the authored digests")
	var merged = applied["value"]
	_expect(merged.movement_bindings().size() == 2, "overlay: merged view did not gain the gate movement binding")
	var gate: Dictionary = {}
	for binding: Dictionary in merged.movement_bindings():
		if String(binding.get("overlay_id", "")) == "gate.east":
			gate = binding
	_expect(not gate.is_empty(), "overlay: gate binding lost its overlay provenance")
	_expect(String(gate.get("source", "")) == SpatialManifestScript.OVERLAY_SOURCE and String(gate.get("kind", "")) == "gate", "overlay: gate binding lost kind/source contract fields")
	_expect(gate.get("geometry", {}).get("rect", []) == [90.0, 0.0, 20.0, 60.0], "overlay: gate geometry was not carried as immutable data")
	# Deterministic merge: applying twice gives the identical view, ordering by id.
	var applied_twice: Dictionary = manifest.with_overlay(Fixtures.overlay_entries())
	_expect((applied["value"] as Object).call("snapshot") == (applied_twice["value"] as Object).call("snapshot"), "overlay: repeated application produced different views")
	var ids: Array[String] = []
	for binding: Dictionary in (applied["value"] as Object).call("snapshot")["stable_bindings"]:
		ids.append(String(binding["binding_id"]))
	var sorted_ids: Array[String] = ids.duplicate()
	sorted_ids.sort()
	_expect(ids == sorted_ids, "overlay: merged bindings were not deterministically ordered")
	# Invalid overlays fail closed without touching the manifest.
	var invalid_cases: Array[Array] = [
		["unknown_channel", [{"overlay_id": "gate.x", "kind": "gate", "channels": {"smell": true}, "geometry": {"type": "rect", "rect": [0.0, 0.0, 1.0, 1.0]}}], "unknown_channel:smell"],
		["bad_kind", [{"overlay_id": "gate.x", "kind": "turret", "channels": {"movement": true}, "geometry": {"type": "rect", "rect": [0.0, 0.0, 1.0, 1.0]}}], "invalid_overlay_kind:turret"],
		["duplicate_id", [
			{"overlay_id": "gate.x", "kind": "gate", "channels": {"movement": true}, "geometry": {"type": "rect", "rect": [0.0, 0.0, 1.0, 1.0]}},
			{"overlay_id": "gate.x", "kind": "gate", "channels": {"movement": true}, "geometry": {"type": "rect", "rect": [2.0, 0.0, 1.0, 1.0]}},
		], "duplicate_overlay_id:gate.x"],
		["presentation_only", [{"overlay_id": "gate.x", "kind": "gate", "channels": {"occlusion": true}, "geometry": {"type": "rect", "rect": [0.0, 0.0, 1.0, 1.0]}}], "overlay_without_solid_channel"],
		["no_geometry", [{"overlay_id": "gate.x", "kind": "destructible", "channels": {"movement": true}}], "missing_overlay_field:geometry"],
	]
	for case: Array in invalid_cases:
		var rejected: Dictionary = manifest.with_overlay(case[1])
		_expect(not bool(rejected.get("ok", false)), "overlay: %s overlay was accepted" % String(case[0]))
		_expect(_contains(rejected.get("errors", []), String(case[2])), "overlay: %s overlay failed without %s" % [String(case[0]), String(case[2])])
	_expect(manifest.gameplay_digest_sha256() == gameplay_before, "overlay: rejected overlays still changed the authored digests")


func _test_world_asset_manifest_verification() -> void:
	var bake: Dictionary = BakeCore.bake_scene(RING_SCENE, RING_MANIFEST)
	if not bool(bake.get("ok", false)):
		failures.append("verify: ring bake failed, verification untestable")
		return
	var asset = WorldAssetScript.from_bake(bake)
	_expect(bool(asset.is_valid()), "verify: baked asset did not validate")
	_expect(int(asset.schema_version) == WorldAssetScript.SCHEMA_VERSION, "verify: baked schema version drifted")
	var manifest = SpatialManifestScript.new(bake["manifest"])
	var matched: Dictionary = asset.matches_manifest(manifest)
	_expect(bool(matched.get("ok", false)), "verify: the baked manifest did not reproduce the baked digests")
	var tampered_asset = WorldAssetScript.from_dict({
		"world_scene_path": bake["world_asset"]["world_scene_path"],
		"manifest_path": bake["world_asset"]["manifest_path"],
		"gameplay_digest": "0".repeat(64),
		"presentation_digest": bake["world_asset"]["presentation_digest"],
		"schema_version": 1,
	})
	var mismatched: Dictionary = tampered_asset.matches_manifest(manifest)
	_expect(not bool(mismatched.get("ok", false)) and _contains(mismatched.get("errors", []), "digest_mismatch:gameplay"), "verify: a tampered gameplay digest was not detected")
	# Tampering gameplay truth (the ring boundary geometry) must fail the gate.
	var tampered_manifest: Dictionary = (bake["manifest"] as Dictionary).duplicate(true)
	var tampered_binding: Dictionary = (tampered_manifest["stable_bindings"] as Array)[0]
	(tampered_binding["geometry"] as Dictionary)["center"] = [0.0, 0.0]
	var tampered_result: Dictionary = asset.matches_manifest(SpatialManifestScript.new(tampered_manifest))
	_expect(not bool(tampered_result.get("ok", false)) and _contains(tampered_result.get("errors", []), "digest_mismatch:gameplay"), "verify: a gameplay-tampered manifest was accepted by the baked asset")
	# Tampering pure presentation truth (the fixture art piece) must fail only
	# the presentation half of the gate.
	var fixture_payload: Dictionary = Fixtures.authoring_payload()
	var fixture_asset = WorldAssetScript.from_dict({
		"world_scene_path": RING_SCENE,
		"manifest_path": RING_MANIFEST,
		"gameplay_digest": SpatialManifestScript.digest_payload_sha256(SpatialManifestScript.gameplay_digest_input(fixture_payload)),
		"presentation_digest": SpatialManifestScript.digest_payload_sha256(SpatialManifestScript.presentation_digest_input(fixture_payload)),
		"schema_version": 1,
	})
	_expect(bool(fixture_asset.is_valid()), "verify: fixture-built asset did not validate")
	_expect(bool(fixture_asset.matches_manifest(SpatialManifestScript.new(fixture_payload)).get("ok", false)), "verify: fixture asset rejected its own manifest")
	var presentation_tampered: Dictionary = fixture_payload.duplicate(true)
	for binding: Variant in presentation_tampered["stable_bindings"]:
		if String((binding as Dictionary).get("binding_id", "")) == "art.sign":
			(binding as Dictionary)["source"] = "tampered.art.v9"
	var presentation_result: Dictionary = fixture_asset.matches_manifest(SpatialManifestScript.new(presentation_tampered))
	_expect(not bool(presentation_result.get("ok", false)) and _contains(presentation_result.get("errors", []), "digest_mismatch:presentation"), "verify: a presentation-tampered manifest was accepted by the baked asset")
	var non_manifest: Dictionary = asset.matches_manifest("not a manifest")
	_expect(not bool(non_manifest.get("ok", true)) and _contains(non_manifest.get("errors", []), "invalid_manifest"), "verify: non-manifest input was accepted by the verification gate")


func _test_occlusion_plan_stability() -> void:
	# Equal baselines order by rank then stable id regardless of input order.
	var equal_baseline: Array = [
		{"stable_id": "bravo", "baseline_y": 100.0, "rank": 1, "feet_anchor": Vector2(10.0, 100.0), "art_box": Rect2(0.0, 50.0, 20.0, 50.0)},
		{"stable_id": "alpha", "baseline_y": 100.0, "rank": 1, "feet_anchor": Vector2(40.0, 100.0), "art_box": Rect2(30.0, 50.0, 20.0, 50.0)},
		{"stable_id": "charlie", "baseline_y": 100.0, "rank": 0, "feet_anchor": Vector2(70.0, 100.0), "art_box": Rect2(60.0, 50.0, 20.0, 50.0)},
	]
	var forward: Dictionary = OcclusionPlanScript.build(equal_baseline)
	var reversed_entries: Array = (equal_baseline as Array).duplicate()
	(reversed_entries as Array).reverse()
	var backward: Dictionary = OcclusionPlanScript.build(reversed_entries)
	_expect(bool(forward.get("ok", false)) and bool(backward.get("ok", false)), "plan: equal-baseline entries were rejected")
	if bool(forward.get("ok", false)) and bool(backward.get("ok", false)):
		var order_forward: Array[String] = []
		for entry: Dictionary in (forward["value"] as Object).call("entries"):
			order_forward.append(String(entry["stable_id"]))
		var order_backward: Array[String] = []
		for entry: Dictionary in (backward["value"] as Object).call("entries"):
			order_backward.append(String(entry["stable_id"]))
		_expect(order_forward == ["charlie", "alpha", "bravo"], "plan: equal baselines did not order by rank then id (got %s)" % str(order_forward))
		_expect(order_forward == order_backward, "plan: insertion order changed the plan order")
	# The plan is frozen presentation data: interpolated display positions
	# never reorder it.  Different update histories must agree with the plan.
	var built: Dictionary = OcclusionPlanScript.build(Fixtures.plan_entries())
	_expect(bool(built.get("ok", false)), "plan: fixture entries were rejected: %s" % str(built.get("errors", [])))
	if bool(built.get("ok", false)):
		var plan = built["value"]
		_expect(bool(plan.call("is_presentation_only")), "plan: plan did not self-identify as presentation-only")
		var plan_order: Array = (plan.call("entries") as Array).map(func(entry: Dictionary) -> String: return String(entry["stable_id"]))
		var controller_a = OcclusionControllerScript.new()
		var controller_b = OcclusionControllerScript.new()
		_expect(bool(controller_a.adopt_plan(plan).get("ok", false)) and bool(controller_b.adopt_plan(plan).get("ok", false)), "plan: controllers rejected the detached plan")
		controller_a.set_subject_anchor("hero", Vector2(120.0, 302.0))
		controller_b.set_subject_anchor("hero", Vector2(120.0, 302.0))
		for tick in 7:
			controller_a.update(1.0 / 144.0)
			controller_b.update(3.0 * (1.0 / 144.0))
		_expect((plan.call("entries") as Array).map(func(entry: Dictionary) -> String: return String(entry["stable_id"])) == plan_order, "plan: controller interpolation reordered the frozen plan")
		_expect(not controller_a.call("display_feet", "hero").is_equal_approx(controller_b.call("display_feet", "hero")), "plan: different refresh rates did not produce different interpolated display positions")
		# Occluders are reportable and deterministic under interpolation.
		var report: Dictionary = plan.call("occlusion_report", "hero")
		_expect(bool(report.get("ok", false)) and bool(report.get("occluded", false)), "plan: hero report did not find its authored front piece")
		_expect((report.get("occluder_ids", []) as Array) == ["sign"], "plan: hero occluder ids drifted: %s" % str(report.get("occluder_ids", [])))
		_expect(plan.call("occlusion_report", "hero") == plan.call("occlusion_report", "hero"), "plan: repeated reports drifted")
		_expect(not bool((plan.call("occlusion_report", "ghost") as Dictionary).get("ok", true)), "plan: unknown subject produced a successful report")


func _test_controller_interpolation_and_alpha() -> void:
	var built: Dictionary = OcclusionPlanScript.build(Fixtures.plan_entries())
	if not bool(built.get("ok", false)):
		failures.append("controller: plan fixture was rejected")
		return
	var controller = OcclusionControllerScript.new()
	_expect(not bool(controller.adopt_plan("nope").get("ok", false)), "controller: a non-plan object was adopted")
	_expect(bool(controller.adopt_plan(built["value"]).get("ok", false)), "controller: valid plan was rejected")
	_expect(not bool(controller.set_subject_anchor("ghost", Vector2.ZERO).get("ok", false)), "controller: unknown subject anchor was accepted")
	_expect(not bool(controller.set_cover("ghost", 0.5).get("ok", false)), "controller: unknown subject cover was accepted")
	# Alpha transition: dims toward the occluded target without overshoot,
	# then returns to full alpha when the cover clears.
	_expect(bool(controller.set_cover("hero", 0.6).get("ok", false)), "controller: hero cover update was rejected")
	var alphas: Array[float] = []
	for tick in 30:
		controller.update(1.0 / 30.0)
		alphas.append(controller.call("alpha", "hero"))
	_expect(alphas[0] > alphas[alphas.size() - 1], "controller: alpha did not dim under cover")
	_expect(controller.call("alpha", "hero") >= OcclusionControllerScript.OCCLUDED_TARGET_ALPHA, "controller: alpha overshot the occluded target")
	for alpha_value: float in alphas:
		_expect(alpha_value >= OcclusionControllerScript.OCCLUDED_TARGET_ALPHA and alpha_value <= OcclusionControllerScript.CLEAR_TARGET_ALPHA, "controller: alpha left the [occluded, clear] band")
	_expect(bool(controller.set_cover("hero", 0.0).get("ok", false)), "controller: clear-cover update was rejected")
	var returned := false
	for tick in 90:
		controller.update(1.0 / 30.0)
		if is_equal_approx(float(controller.call("alpha", "hero")), OcclusionControllerScript.CLEAR_TARGET_ALPHA):
			returned = true
			break
	_expect(returned, "controller: alpha never returned to full after clear cover")
	# Display feet interpolate toward the authoritative anchor only.
	controller.set_subject_anchor("hero", Vector2(140.0, 320.0))
	var before: Vector2 = controller.call("display_feet", "hero")
	controller.update(1.0 / 144.0)
	var after: Vector2 = controller.call("display_feet", "hero")
	_expect(after.x > before.x and after.y > before.y and after.distance_to(Vector2(140.0, 320.0)) > 0.5, "controller: display feet did not interpolate toward the anchor")
	var far_tick := 0
	while far_tick < 600 and not controller.call("display_feet", "hero").is_equal_approx(Vector2(140.0, 320.0)):
		controller.update(1.0 / 30.0)
		far_tick += 1
	_expect(controller.call("display_feet", "hero").is_equal_approx(Vector2(140.0, 320.0)), "controller: display feet never converged on the authoritative anchor")
	# Deterministic snapshot, plain values only.
	var first_snapshot: Dictionary = controller.call("snapshot")
	var second_snapshot: Dictionary = controller.call("snapshot")
	_expect(first_snapshot == second_snapshot, "controller: snapshots drifted between identical states")
	var keys: Array[String] = []
	for key: String in first_snapshot.keys():
		keys.append(key)
	var sorted_keys: Array[String] = keys.duplicate()
	sorted_keys.sort()
	_expect(keys == sorted_keys, "controller: snapshot keys were not deterministically ordered")
	for value: Variant in first_snapshot.values():
		_expect((value as Dictionary).has("display_feet") and (value as Dictionary).has("alpha") and (value as Dictionary).size() == 2, "controller: snapshot entries leaked non-presentation fields")


func _test_no_art_box_fails_closed() -> void:
	# Missing art box: no collision-rectangle fallback, no placeholder actor.
	var missing_art: Array = Fixtures.plan_entries()
	(missing_art as Array)[0].erase("art_box")
	var rejected: Dictionary = OcclusionPlanScript.build(missing_art)
	_expect(not bool(rejected.get("ok", false)) and _contains(rejected.get("errors", []), "missing_art_box:hero"), "plan: an entry without an art box was accepted (fallback drawing risk)")
	var zero_art: Array = Fixtures.plan_entries()
	(zero_art as Array)[1]["art_box"] = Rect2(0.0, 0.0, 0.0, 0.0)
	_expect(not bool((OcclusionPlanScript.build(zero_art) as Dictionary).get("ok", true)), "plan: a zero-size art box was accepted")
	var duplicate: Array = Fixtures.plan_entries()
	(duplicate as Array).append((duplicate as Array)[0])
	_expect(_contains((OcclusionPlanScript.build(duplicate) as Dictionary).get("errors", []), "duplicate_stable_id"), "plan: a duplicate stable id was accepted")
	var unknown_field: Array = Fixtures.plan_entries()
	(unknown_field as Array)[0]["channels"] = {"movement": true}
	_expect(_contains((OcclusionPlanScript.build(unknown_field) as Dictionary).get("errors", []), "unknown_entry_field:channels"), "plan: gameplay channel data leaked into the presentation plan")


## Primitive-fade authoring metadata on a synthetic loadout-shaped definition
## (same canvas, anchors and parts as the retired shipped sample, with PNGs
## written under build/current): common opts into an explicit solid
## "none", upper swaps its variant pair for "primitive_fade" plus authored
## local-canvas volumes. Validation fails closed on unknown policies, absent,
## malformed, non-finite or degenerate volumes and on any part carrying two
## policies at once; the baker translates volumes by the placement only,
## keeps them off the movement manifest and the static colliders, rejects
## stale or tampered scenes, lists the opted-in bindings in the contract, and
## the presentation fingerprint moves with the volumes while the gameplay
## digest does not.
func _test_primitive_fade_metadata() -> void:
	var loadout := _loadout_definition()
	_expect(loadout.validate().is_empty(), "primitive fade: the synthetic loadout definition is not valid: " + str(loadout.validate()))
	if not loadout.validate().is_empty():
		return
	var common_index := -1
	var upper_index := -1
	for index in loadout.visual_parts.size():
		var id := String(loadout.visual_parts[index].get("part_id", ""))
		common_index = index if id == "common" else common_index
		upper_index = index if id == "upper" else upper_index
	_expect(common_index >= 0 and upper_index >= 0, "primitive fade: the loadout lost its common/upper parts")
	if common_index < 0 or upper_index < 0:
		return

	## Validation, one fail-closed case per row: exactly one policy per part
	## and well-formed authored volumes.
	var expected_errors := {
		"unknown_policy": "invalid_environment_reveal_policy",
		"absent_volumes": "missing_environment_occlusion_volumes",
		"empty_volumes": "missing_environment_occlusion_volumes",
		"nonfinite_center": "invalid_environment_vector",
		"zero_radius": "invalid_environment_circle",
		"collinear_polygon": "invalid_environment_polygon",
		"variant_conflict": "primitive_fade_policy_conflict",
		"none_with_variant": "none_policy_conflict",
	}
	for invalid: String in expected_errors.keys():
		var mutated := loadout.duplicate(true) as EnvironmentDefinitionScript
		var part: Dictionary = mutated.visual_parts[upper_index]
		match invalid:
			"unknown_policy":
				part["reveal_policy"] = "pixel_ghost"
			"absent_volumes", "empty_volumes", "nonfinite_center", "zero_radius", "collinear_polygon":
				part.erase("revealed_path")
				part.erase("mask_path")
				part["reveal_policy"] = "primitive_fade"
				match invalid:
					"empty_volumes":
						part["occlusion_volumes"] = []
					"nonfinite_center":
						part["occlusion_volumes"] = [{"type": "circle", "center": Vector2.INF, "radius": 8.0}]
					"zero_radius":
						part["occlusion_volumes"] = [{"type": "circle", "center": Vector2.ZERO, "radius": 0.0}]
					"collinear_polygon":
						part["occlusion_volumes"] = [{"type": "polygon", "points": PackedVector2Array([Vector2.ZERO, Vector2(8, 0), Vector2(16, 0)])}]
			"variant_conflict":
				part["reveal_policy"] = "primitive_fade"
			"none_with_variant":
				part["reveal_policy"] = "none"
		_expect(_contains(mutated.validate(), String(expected_errors[invalid])),
			"primitive fade: %s was accepted by the definition" % invalid)

	## The opted-in definition the art owner ships: explicit solid base,
	## variant pair replaced by authored volumes (circle + rectangle polygon).
	var volumes: Array = [
		{"type": "circle", "center": Vector2(128, 90), "radius": 40.0},
		{"type": "polygon", "points": PackedVector2Array([Vector2(64, 30), Vector2(192, 30), Vector2(192, 96), Vector2(64, 96)])},
	]
	var faded := loadout.duplicate(true) as EnvironmentDefinitionScript
	var faded_common: Dictionary = faded.visual_parts[common_index]
	var faded_upper: Dictionary = faded.visual_parts[upper_index]
	faded_common["reveal_policy"] = "none"
	faded_upper.erase("revealed_path")
	faded_upper.erase("mask_path")
	faded_upper["reveal_policy"] = "primitive_fade"
	faded_upper["occlusion_volumes"] = volumes.duplicate(true)
	_expect(faded.validate().is_empty(), "primitive fade: the valid opted-in definition was rejected")

	## Placement translation, static-geometry separation and idempotence.
	var town := _fade_town(faded)
	var expand := EnvironmentBakerScript.expand(town)
	_expect(bool(expand.get("ok", false)), "primitive fade: the opted-in loadout failed to expand: " + str(expand.get("errors", [])))
	if bool(expand.get("ok", false)):
		var upper := _fade_binding(town, "fade.loadout/upper") as Sprite2D
		var common := _fade_binding(town, "fade.loadout/common") as Sprite2D
		_expect(upper != null and common != null, "primitive fade: the opted-in parts left no baked nodes")
		if upper != null:
			_expect(String(upper.get_meta("reveal_policy", "")) == "primitive_fade", "primitive fade: the baked node lost its explicit policy")
			_expect(not upper.has_meta("reveal_variant_path") and not upper.has_meta("reveal_mask_path"), "primitive fade: the fade node kept variant material")
			## Local canvas volume + placement (16, 10) only — the part's own
			## sort anchor (128, 142) must NOT shift the condition geometry.
			_expect((upper.get_meta("occlusion_volumes", []) as Array) == [
				{"type": "circle", "center": Vector2(144, 100), "radius": 40.0},
				{"type": "polygon", "points": PackedVector2Array([Vector2(80, 40), Vector2(208, 40), Vector2(208, 106), Vector2(80, 106)])},
			], "primitive fade: volumes were not translated by the placement alone: " + str(upper.get_meta("occlusion_volumes", [])))
			var entry: Dictionary = upper.get_meta("_environment_entry", {})
			_expect(String(entry.get("reveal_policy", "")) == "primitive_fade" and entry.has("occlusion_volumes"),
				"primitive fade: the baked entry lost its policy metadata")
		if common != null:
			_expect(String(common.get_meta("reveal_policy", "")) == "none" and not common.has_meta("occlusion_volumes"),
				"primitive fade: the explicit solid base lost its policy or gained volumes")
		## Condition volumes never become collision geometry: the single static
		## child is the definition's own movement envelope, nothing more.
		_expect(town.get_node("GeometrySources/Static").get_child_count() == 1,
			"primitive fade: occlusion volumes leaked into the static colliders")
		_expect(town.get_node("SortRoot").get_child_count() == 2 and town.get_node("Sockets").get_child_count() == 1,
			"primitive fade: the expansion generated unexpected leaves")
		var count := town.get_node("SortRoot").get_child_count()
		_expect(EnvironmentBakerScript.expand(town).ok and town.get_node("SortRoot").get_child_count() == count,
			"primitive fade: repeating the expansion is not idempotent")
		## Honest regional contract: the opted-in binding is listed, the global
		## modular claims stay unchanged.
		var contract := town.validate_contract()
		_expect(bool(contract.get("ok", false)), "primitive fade: the opted-in contract was rejected: " + str(contract.get("errors", [])))
		if bool(contract.get("ok", false)):
			var value: Dictionary = contract.value
			_expect((value.get("primitive_fade_bindings", []) as Array) == ["fade.loadout/upper"],
				"primitive fade: the contract bindings lost the opted-in piece: " + str(value.get("primitive_fade_bindings", [])))
			_expect(value.unknown_underplate == "opaque" and not bool(value.supports_fade),
				"primitive fade: opting one piece in changed the global modular claims")
		## Digest separation: volumes move the presentation fingerprint while
		## the gameplay digest stays byte-identical.
		var baseline := SpatialManifestScript.new(town.derive_spatial_manifest())
		_expect(baseline.is_valid(), "primitive fade: the baseline modular derivative is invalid")
		faded_upper["occlusion_volumes"] = [
			{"type": "circle", "center": Vector2(128, 90), "radius": 44.0},
			{"type": "polygon", "points": PackedVector2Array([Vector2(64, 30), Vector2(192, 30), Vector2(192, 96), Vector2(64, 96)])},
		]
		var variant := _fade_town(faded)
		var changed := SpatialManifestScript.new(variant.derive_spatial_manifest())
		_expect(changed.is_valid(), "primitive fade: the volume-variant derivative is invalid")
		_expect(changed.presentation_digest_sha256() != baseline.presentation_digest_sha256(),
			"primitive fade: edited volumes did not change the presentation digest")
		_expect(changed.gameplay_digest_sha256() == baseline.gameplay_digest_sha256(),
			"primitive fade: presentation volumes changed the gameplay digest")
		variant.free()

	## Scan fail-closed on the baked scene itself: absent volumes and variant
	## material on a fade piece reject the contract.
	var scanned := _fade_town(faded)
	_expect(EnvironmentBakerScript.expand(scanned).ok, "primitive fade: the scan fixture failed to expand")
	_fade_binding(scanned, "fade.loadout/upper").remove_meta("occlusion_volumes")
	var missing := scanned.validate_contract()
	_expect(_contains(missing.get("errors", []), "missing_modular_occlusion_volumes"),
		"primitive fade: a fade piece without volumes passed the contract")
	scanned.free()
	scanned = _fade_town(faded)
	_expect(EnvironmentBakerScript.expand(scanned).ok, "primitive fade: the scan fixture failed to expand")
	_fade_binding(scanned, "fade.loadout/upper").set_meta("reveal_variant_path", _synthetic_path("revealed"))
	_expect(_contains(scanned.validate_contract().get("errors", []), "primitive_fade_policy_conflict"),
		"primitive fade: a fade piece carrying variant material passed the contract")
	scanned.free()

	## Stale scenes are rejected: a tampered node and an edited source both
	## fail instead of silently rebuilding, and both recover once restored.
	var tampered := _fade_town(faded)
	_expect(EnvironmentBakerScript.expand(tampered).ok, "primitive fade: the tamper fixture failed to expand")
	var node := _fade_binding(tampered, "fade.loadout/upper")
	node.set_meta("occlusion_volumes", [{"type": "circle", "center": Vector2(144, 100), "radius": 48.0}])
	_expect(_contains(EnvironmentBakerScript.expand(tampered).get("errors", []), "environment_binding_conflict"),
		"primitive fade: a tampered volume node was silently accepted")
	node.set_meta("occlusion_volumes", [
		{"type": "circle", "center": Vector2(144, 100), "radius": 44.0},
		{"type": "polygon", "points": PackedVector2Array([Vector2(80, 40), Vector2(208, 40), Vector2(208, 106), Vector2(80, 106)])},
	])
	_expect(EnvironmentBakerScript.expand(tampered).ok, "primitive fade: the restored node still conflicted")
	faded_upper["occlusion_volumes"] = [
		{"type": "circle", "center": Vector2(128, 92), "radius": 40.0},
		{"type": "polygon", "points": PackedVector2Array([Vector2(64, 30), Vector2(192, 30), Vector2(192, 96), Vector2(64, 96)])},
	]
	_expect(_contains(EnvironmentBakerScript.expand(tampered).get("errors", []), "environment_source_changed_after_expansion"),
		"primitive fade: an edited definition was silently rebuilt")
	tampered.free()

	town.free()
	for path: String in _fade_created_files:
		DirAccess.remove_absolute(path)
	_fade_created_files.clear()


func _synthetic_path(name: String) -> String:
	return "res://build/current/world_asset_pipeline_loadout_%s_%d.png" % [name, OS.get_process_id()]


func _write_synthetic(name: String, size: Vector2i, color: Color) -> void:
	var path := _synthetic_path(name)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	_expect(image.save_png(path) == OK, "primitive fade: the synthetic %s image write failed" % name)
	if path not in _fade_created_files:
		_fade_created_files.append(path)


## Loadout-shaped definition: 256x224 canvas, a solid common part, an upper
## part with a revealed/mask pair, one shadow ground part, one footprint, one
## movement envelope and one interaction socket.
func _loadout_definition() -> EnvironmentDefinitionScript:
	_write_synthetic("common", SYNTHETIC_CANVAS, Color.SADDLE_BROWN)
	_write_synthetic("upper", SYNTHETIC_CANVAS, Color.FOREST_GREEN)
	_write_synthetic("revealed", SYNTHETIC_CANVAS, Color(0.3, 0.5, 0.7, 0.5))
	_write_synthetic("shadow", SYNTHETIC_CANVAS, Color(0.0, 0.0, 0.0, 0.4))
	var definition := EnvironmentDefinitionScript.new()
	definition.asset_id = "town.loadout.synthetic"
	definition.canvas_size = SYNTHETIC_CANVAS
	definition.visual_parts = [
		{"part_id": "common", "full_path": _synthetic_path("common"), "canvas_offset": Vector2.ZERO,
			"sort_anchor": Vector2(128, 178), "sort_rank": 0},
		{"part_id": "upper", "full_path": _synthetic_path("upper"), "mask_path": _synthetic_path("upper"),
			"revealed_path": _synthetic_path("revealed"), "canvas_offset": Vector2.ZERO,
			"sort_anchor": Vector2(128, 142), "sort_rank": 1},
	]
	definition.ground_parts = [
		{"part_id": "shadow.contact", "full_path": _synthetic_path("shadow"), "canvas_offset": Vector2.ZERO, "layer": "GroundEffects"},
	]
	definition.footprints = [{"part_id": "footprint.body", "type": "polygon",
		"points": PackedVector2Array([Vector2(64, 134), Vector2(192, 134), Vector2(192, 178), Vector2(64, 178)])}]
	definition.movement_envelopes = [{"part_id": "envelope.body", "type": "polygon",
		"points": PackedVector2Array([Vector2(58, 128), Vector2(198, 128), Vector2(198, 184), Vector2(58, 184)])}]
	definition.sockets = [{"part_id": "door.service", "id": "loadout", "kind": "interaction", "label": "Loadout",
		"landmark_offset_y": -112.0, "locked": false, "order": 1.0, "position": Vector2(128, 196), "radius": 48.0}]
	return definition


## A detached modular author root for one opted-in loadout placement, in the
## fixture shape of tests/test_environment_object.gd.
func _fade_town(definition: EnvironmentDefinitionScript) -> TownSceneRootScript:
	var underplate := "res://build/current/world_asset_pipeline_fade_" + str(OS.get_process_id()) + ".png"
	var image := Image.create(320, 288, false, Image.FORMAT_RGBA8)
	image.fill(Color.DARK_SLATE_GRAY)
	_expect(image.save_png(underplate) == OK, "primitive fade: the synthetic underplate write failed")
	if underplate not in _fade_created_files:
		_fade_created_files.append(underplate)
	var town := TownSceneRootScript.new()
	town.name = "FadeFixtureTown"
	town.world_size = Vector2(320, 288)
	town.modular_underplate_path = underplate
	for path: String in ["Ground", "GroundEffects", "SortRoot", "Foreground", "GeometrySources", "GeometrySources/MovementBoundary", "GeometrySources/Static", "GeometrySources/Routes", "Sockets", "EnvironmentObjects"]:
		var node := Node2D.new()
		node.name = path.get_file()
		var parent := town if path.get_base_dir().is_empty() else town.get_node(path.get_base_dir())
		parent.add_child(node)
	town.get_node("SortRoot").y_sort_enabled = true
	town.get_node("GeometrySources/MovementBoundary").set_meta("rect", Rect2(0, 0, 320, 288))
	var surface := Sprite2D.new()
	surface.name = "Surface"
	surface.centered = false
	surface.set_meta("binding_id", "town/ground")
	surface.set_meta("texture_path", underplate)
	surface.set_meta("reveal_policy", "none")
	town.get_node("Ground").add_child(surface)
	var placement := EnvironmentPlacementScript.new()
	placement.name = "fade"
	placement.placement_id = "fade.loadout"
	placement.definition = definition
	placement.position = Vector2(16, 10)
	town.get_node("EnvironmentObjects").add_child(placement)
	return town


func _fade_binding(node: Node, id: String) -> Node:
	if node.get_meta("binding_id", "") == id:
		return node
	for child: Node in node.get_children():
		var found := _fade_binding(child, id)
		if found != null:
			return found
	return null
