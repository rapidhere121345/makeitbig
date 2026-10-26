extends SceneTree

const Channels := preload("res://src/runtime/spatial/spatial_channels.gd")
const Contact := preload("res://src/runtime/spatial/spatial_contact.gd")
const StaticSpatialIndexScript := preload("res://src/runtime/spatial/static_spatial_index.gd")
const DynamicSpatialIndexScript := preload("res://src/runtime/spatial/dynamic_spatial_index.gd")
const SpatialOverlayScript := preload("res://src/runtime/spatial/spatial_overlay.gd")
const BodyCollisionPolicyScript := preload("res://src/runtime/spatial/body_collision_policy.gd")
const MovementResolverScript := preload("res://src/runtime/spatial/movement_resolver.gd")
const ContinuousHitResolverScript := preload("res://src/runtime/spatial/continuous_hit_resolver.gd")
const VisionResolverScript := preload("res://src/runtime/spatial/vision_resolver.gd")
const OcclusionResolverScript := preload("res://src/runtime/spatial/occlusion_resolver.gd")
const SpatialSweepScript := preload("res://src/runtime/geometry/spatial_sweep.gd")
const ShapeScript := preload("res://src/runtime/geometry/spatial_shape.gd")
const Fixtures := preload("res://tests/spatial/spatial_fixtures.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_static_index_fails_closed()
	_test_direct_wall_contact()
	_test_oblique_slide()
	_test_ring_inner_and_outer_boundary()
	_test_rect_boundary_faces()
	_test_concave_piece_passage_and_narrow_gap()
	_test_thin_wall_anti_tunneling()
	_test_dynamic_solid_soft_ghost_policy()
	_test_dynamic_duplicate_registration_fails_closed()
	_test_channel_independence()
	_test_projectile_static_dynamic_tie_break()
	_test_separating_circle_does_not_fabricate_contact()
	_test_vision_vs_occlusion_separation()
	_test_overlay_revision()
	_test_byte_stable_snapshots_and_ordering()
	_test_request_validation()
	_test_zero_displacement_contract()
	_test_broadphase_differential()
	if failures.is_empty():
		print("PASS  test_spatial_kernel.gd")
		quit(0)
		return
	for failure: String in failures:
		printerr("- " + failure)
	quit(1)


func _test_static_index_fails_closed() -> void:
	var duplicate := Fixtures.wall_world()
	duplicate["surfaces"].append(Fixtures.surface("wall", Rect2(0, 0, 4, 4), [Channels.MOVEMENT]))
	_expect(not bool(StaticSpatialIndexScript.build(duplicate)["ok"]), "load: duplicate surface id was accepted")

	var unknown_channel := Fixtures.wall_world()
	unknown_channel["surfaces"].append(Fixtures.surface("scent", Rect2(0, 0, 4, 4), [&"scent"]))
	_expect(not bool(StaticSpatialIndexScript.build(unknown_channel)["ok"]), "load: unknown channel was accepted")

	var reflex := Fixtures.wall_world()
	reflex["surfaces"].append({
		"id": "concave",
		"shape": {"kind": "polygon", "points": PackedVector2Array([
			Vector2(0, 0), Vector2(20, 0), Vector2(20, 20), Vector2(10, 10), Vector2(0, 20),
		])},
		"channels": [Channels.MOVEMENT],
	})
	_expect(not bool(StaticSpatialIndexScript.build(reflex)["ok"]), "load: non-convex polygon was accepted")

	var unknown_field := Fixtures.wall_world()
	unknown_field["banana"] = 1
	_expect(not bool(StaticSpatialIndexScript.build(unknown_field)["ok"]), "load: unknown asset field was accepted")

	var unknown_surface_field := Fixtures.wall_world()
	unknown_surface_field["surfaces"][0]["banana"] = 1
	_expect(not bool(StaticSpatialIndexScript.build(unknown_surface_field)["ok"]), "load: unknown surface field was accepted")

	var bad_boundary := Fixtures.ring_world()
	bad_boundary["movement_boundary"]["outer_radius"] = 30.0
	_expect(not bool(StaticSpatialIndexScript.build(bad_boundary)["ok"]), "load: inverted ring radii were accepted")

	var nan_shape := Fixtures.wall_world()
	nan_shape["surfaces"][0]["shape"] = {"kind": "circle", "center": Vector2(NAN, 0), "radius": 5.0}
	_expect(not bool(StaticSpatialIndexScript.build(nan_shape)["ok"]), "load: non-finite circle was accepted")

	var built := StaticSpatialIndexScript.build(Fixtures.wall_world())
	_expect(bool(built["ok"]), "load: valid asset failed to build")
	var index: StaticSpatialIndex = built["value"]
	_expect(index.surface_ids() == ["wall"], "load: surface id listing changed")
	_expect(index.surface_ids(Channels.MOVEMENT) == ["wall"], "load: movement channel listing changed")
	_expect(index.surface_ids(Channels.OCCLUSION) == [], "load: occlusion channel saw a movement wall")
	var snapshot_text := JSON.stringify(index.snapshot())
	_expect(snapshot_text.contains("coordinate") or snapshot_text.contains("toi"), "load: snapshot omitted the numeric contract")
	_expect(String(snapshot_text).contains("+x right"), "load: coordinate contract missing axis statement")


func _test_direct_wall_contact() -> void:
	var index: StaticSpatialIndex = StaticSpatialIndexScript.build(Fixtures.wall_world())["value"]
	var resolver: MovementResolver = MovementResolverScript.make(index)["value"]
	var result: Dictionary = resolver.move({"start": Vector2(80.0, 60.0), "displacement": Vector2(40.0, 0.0), "radius": 6.0})
	_expect(bool(result["ok"]) and String(result["mode"]) != "start_penetrating", "wall: valid move failed")
	_expect(_near(result["position"].x, 94.0) and _near(result["position"].y, 60.0), "wall: head-on stop crossed the contact plane")
	_expect(bool(result["blocked"]), "wall: head-on contact was not reported blocked")
	var contacts: Array = result["contacts"]
	_expect(contacts.size() == 1, "wall: expected exactly one contact, got %d" % contacts.size())
	if contacts.size() == 1:
		var contact := contacts[0] as Contact
		_expect(contact.channel == Channels.MOVEMENT, "wall: contact channel was not movement")
		_expect(contact.kind == Contact.KIND_STATIC_SURFACE, "wall: contact kind was not a static surface")
		_expect(contact.source_id == "wall", "wall: contact surface identity lost")
		_expect(_near_vector(contact.normal, Vector2(-1, 0)), "wall: push-out normal was not -x")
		_expect(_near(contact.toi, 0.35), "wall: head-on toi changed")
		_expect(contact.feature.begins_with("edge"), "wall: contact feature was not an edge")
	_expect(index.is_position_clear(Channels.MOVEMENT, result["position"], 6.0), "wall: resolved position penetrates the wall")


func _test_oblique_slide() -> void:
	var index: StaticSpatialIndex = StaticSpatialIndexScript.build(Fixtures.wall_world())["value"]
	var resolver: MovementResolver = MovementResolverScript.make(index)["value"]
	var result: Dictionary = resolver.move({"start": Vector2(80.0, 40.0), "displacement": Vector2(40.0, 40.0), "radius": 6.0})
	_expect(bool(result["blocked"]), "slide: oblique contact was not reported blocked")
	_expect(_near(result["position"].x, 94.0), "slide: slide crossed the wall plane")
	_expect(_near(result["position"].y, 80.0, 0.01), "slide: tangential motion was lost, got y=%s" % [result["position"].y])
	var contacts: Array = result["contacts"]
	if not contacts.is_empty():
		_expect(_near_vector((contacts[0] as Contact).normal, Vector2(-1, 0)), "slide: wall normal changed during slide")
	_expect(index.is_position_clear(Channels.MOVEMENT, result["position"], 6.0), "slide: slid position penetrates the wall")


func _test_ring_inner_and_outer_boundary() -> void:
	var index: StaticSpatialIndex = StaticSpatialIndexScript.build(Fixtures.ring_world())["value"]
	var resolver: MovementResolver = MovementResolverScript.make(index)["value"]
	var outward: Dictionary = resolver.move({"start": Vector2(100.0, 170.0), "displacement": Vector2(0.0, 40.0), "radius": 6.0})
	_expect(bool(outward["blocked"]), "ring: outer boundary did not block")
	_expect(_near(outward["position"].x, 100.0) and _near(outward["position"].y, 184.0), "ring: outer boundary stop radius changed")
	var outward_contacts: Array = outward["contacts"]
	if not outward_contacts.is_empty():
		var contact := outward_contacts[0] as Contact
		_expect(contact.kind == Contact.KIND_BOUNDARY, "ring: outer contact was not typed as boundary")
		_expect(_near_vector(contact.normal, Vector2(0, -1)), "ring: outer normal did not point inward")
		_expect(_near(contact.toi, 0.35), "ring: outer boundary toi changed")
	var inward: Dictionary = resolver.move({"start": Vector2(100.0, 170.0), "displacement": Vector2(0.0, -80.0), "radius": 6.0})
	_expect(bool(inward["blocked"]), "ring: inner boundary did not block")
	_expect(_near(inward["position"].x, 100.0) and _near(inward["position"].y, 136.0), "ring: inner boundary stop radius changed")
	var inward_contacts: Array = inward["contacts"]
	if not inward_contacts.is_empty():
		var contact := inward_contacts[0] as Contact
		_expect(contact.feature == "inner", "ring: inner contact feature changed")
		_expect(_near_vector(contact.normal, Vector2(0, 1)), "ring: inner normal did not point outward")
	var tangent: Dictionary = resolver.move({"start": Vector2(100.0, 184.0), "displacement": Vector2(30.0, 0.0), "radius": 6.0})
	var tangent_position: Vector2 = tangent["position"]
	_expect(_near(tangent_position.distance_to(Vector2(100.0, 100.0)), 84.0, 0.01) and tangent_position.x > 100.0, "ring: tangent slide left the outer boundary radius")


func _test_rect_boundary_faces() -> void:
	var index: StaticSpatialIndex = StaticSpatialIndexScript.build(Fixtures.open_world())["value"]
	var resolver: MovementResolver = MovementResolverScript.make(index)["value"]
	var result: Dictionary = resolver.move({"start": Vector2(20.0, 60.0), "displacement": Vector2(400.0, 0.0), "radius": 6.0})
	_expect(bool(result["blocked"]), "rect boundary: right face did not block")
	_expect(_near(result["position"].x, 194.0), "rect boundary: right face inset changed")
	var contacts: Array = result["contacts"]
	if not contacts.is_empty():
		var contact := contacts[0] as Contact
		_expect(contact.feature == "face:right", "rect boundary: face feature changed")
		_expect(_near_vector(contact.normal, Vector2(-1, 0)), "rect boundary: face normal changed")
	var top: Dictionary = resolver.move({"start": Vector2(60.0, 20.0), "displacement": Vector2(0.0, -40.0), "radius": 6.0})
	_expect(bool(top["blocked"]) and _near(top["position"].y, 6.0), "rect boundary: top face did not block at the inset")


func _test_concave_piece_passage_and_narrow_gap() -> void:
	var wide: StaticSpatialIndex = StaticSpatialIndexScript.build(Fixtures.doorway_world(50.0, 70.0))["value"]
	var wide_resolver: MovementResolver = MovementResolverScript.make(wide)["value"]
	var passed: Dictionary = wide_resolver.move({"start": Vector2(80.0, 60.0), "displacement": Vector2(40.0, 0.0), "radius": 6.0})
	_expect(_near_vector(passed["position"], Vector2(120.0, 60.0), 0.01), "passage: valid convex-piece gap was not traversed")
	_expect(not bool(passed["blocked"]), "passage: valid gap reported a false contact")

	var narrow: StaticSpatialIndex = StaticSpatialIndexScript.build(Fixtures.doorway_world(55.0, 65.0))["value"]
	var narrow_resolver: MovementResolver = MovementResolverScript.make(narrow)["value"]
	var jammed: Dictionary = narrow_resolver.move({"start": Vector2(80.0, 60.0), "displacement": Vector2(40.0, 0.0), "radius": 6.0})
	_expect(bool(jammed["blocked"]), "passage: too-narrow gap did not block")
	_expect((jammed["position"] as Vector2).x < 97.0, "passage: mover tunneled through a too-narrow gap")
	_expect(narrow.is_position_clear(Channels.MOVEMENT, jammed["position"], 6.0), "passage: jammed position penetrated a piece")
	var saw_corner := false
	for entry: Variant in jammed["contacts"]:
		if String((entry as Contact).feature).begins_with("vertex"):
			saw_corner = true
	_expect(saw_corner, "passage: gap corner contact was not reported as a vertex feature")


func _test_thin_wall_anti_tunneling() -> void:
	var index: StaticSpatialIndex = StaticSpatialIndexScript.build(Fixtures.thin_wall_world())["value"]
	var resolver: MovementResolver = MovementResolverScript.make(index)["value"]
	var moved: Dictionary = resolver.move({"start": Vector2(10.0, 60.0), "displacement": Vector2(790.0, 0.0), "radius": 6.0})
	_expect(bool(moved["blocked"]), "thin wall: fast movement tunneled through")
	_expect(_near(moved["position"].x, 94.0), "thin wall: fast movement stop plane changed")
	_expect(index.is_position_clear(Channels.MOVEMENT, moved["position"], 6.0), "thin wall: resolved position penetrated the wall")

	var hits: ContinuousHitResolver = ContinuousHitResolverScript.make(index)["value"]
	var shot: Dictionary = hits.resolve_path({
		"channel": Channels.PROJECTILE,
		"start": Vector2(0.0, 60.0),
		"displacement": Vector2(800.0, 0.0),
		"radius": 3.0,
	})
	_expect(bool(shot["ok"]) and bool(shot["clipped"]), "thin wall: fast projectile tunneled through")
	_expect(_near(float(shot["stop_toi"]), 97.0 / 800.0, 0.000001), "thin wall: projectile stop toi changed")
	_expect(_near((shot["end_point"] as Vector2).x, 97.0), "thin wall: projectile end point changed")
	var behind: Dictionary = hits.resolve_path({
		"channel": Channels.PROJECTILE,
		"start": Vector2(110.0, 60.0),
		"displacement": Vector2(80.0, 0.0),
		"radius": 3.0,
	})
	_expect(not bool(behind["clipped"]), "thin wall: projectile behind the wall reported a false contact")


func _test_separating_circle_does_not_fabricate_contact() -> void:
	var hit := SpatialSweepScript.sweep_circle_circle(
		Vector2(0.0, 0.0),
		Vector2(-20.0, 0.0),
		4.0,
		Vector2(10.0, 0.0),
		6.0,
		"behind",
		false
	)
	_expect(hit.is_empty(), "sweep: separating dynamic body fabricated a toi-zero contact")


func _test_dynamic_solid_soft_ghost_policy() -> void:
	var index: StaticSpatialIndex = StaticSpatialIndexScript.build(Fixtures.open_world())["value"]
	var dynamic := DynamicSpatialIndexScript.new()
	var resolver: MovementResolver = MovementResolverScript.make(index, null, dynamic)["value"]

	_expect(bool(dynamic.register_body(Fixtures.body("guard", Vector2(96.0, 60.0), 6.0, [Channels.MOVEMENT], &"solid"))["ok"]), "policy: solid body registration failed")
	var solid: Dictionary = resolver.move({"start": Vector2(80.0, 60.0), "displacement": Vector2(32.0, 0.0), "radius": 6.0})
	_expect(bool(solid["blocked"]), "policy: solid body did not block")
	_expect(_near(solid["position"].x, 84.0) and _near(solid["position"].y, 60.0), "policy: solid body stop distance changed")
	var solid_contacts: Array = solid["contacts"]
	if not solid_contacts.is_empty():
		var contact := solid_contacts[0] as Contact
		_expect(contact.kind == Contact.KIND_DYNAMIC and contact.source_id == "guard", "policy: solid contact identity lost")
		_expect(_near_vector(contact.normal, Vector2(-1, 0)), "policy: solid contact normal changed")
		_expect(String(contact.response.get("action", "")) == "block", "policy: solid response material missing")

	dynamic.unregister_body("guard")
	dynamic.register_body(Fixtures.body("crowd", Vector2(96.0, 60.0), 6.0, [Channels.MOVEMENT], &"soft"))
	var soft: Dictionary = resolver.move({"start": Vector2(80.0, 60.0), "displacement": Vector2(12.0, 0.0), "radius": 6.0})
	_expect(not bool(soft["blocked"]), "policy: soft body blocked movement")
	var soft_applied := false
	for entry: Variant in soft["contacts"]:
		var contact := entry as Contact
		if contact.source_id == "crowd" and contact.feature == "separation":
			soft_applied = bool(contact.response.get("applied", false))
	_expect(soft_applied, "policy: soft separation was not applied in open space")
	_expect(_near(soft["position"].x, 84.0 - 0.0001, 0.001), "policy: soft separation displacement changed")

	# The mover rests against the wall face while a soft body overlaps from the
	# right; separation would push it into the wall and must be rejected.
	var wall_asset := Fixtures.wall_world()
	wall_asset["asset_id"] = "fixture/soft_validation_room"
	wall_asset["surfaces"] = [Fixtures.surface("blocker", Rect2(98.0, 0.0, 6.0, 120.0), [Channels.MOVEMENT])]
	var wall_index: StaticSpatialIndex = StaticSpatialIndexScript.build(wall_asset)["value"]
	var wall_dynamic := DynamicSpatialIndexScript.new()
	wall_dynamic.register_body(Fixtures.body("bulwark", Vector2(118.0, 60.0), 10.0, [Channels.MOVEMENT], &"soft"))
	var wall_resolver: MovementResolver = MovementResolverScript.make(wall_index, null, wall_dynamic)["value"]
	var soft_into_wall: Dictionary = wall_resolver.move({"start": Vector2(110.0, 60.0), "displacement": Vector2(0.0, 0.0), "radius": 6.0})
	var separation_rejected := false
	for entry: Variant in soft_into_wall["contacts"]:
		var contact := entry as Contact
		if contact.source_id == "bulwark" and contact.feature == "separation":
			separation_rejected = not bool(contact.response.get("applied", true))
	_expect(separation_rejected, "policy: soft separation into a wall was not rejected by the static query")
	_expect(_near(soft_into_wall["position"].x, 110.0), "policy: rejected separation still moved the body")

	dynamic.unregister_body("crowd")
	dynamic.register_body(Fixtures.body("spirit", Vector2(96.0, 60.0), 6.0, [Channels.MOVEMENT], &"ghost"))
	var ghost: Dictionary = resolver.move({"start": Vector2(80.0, 60.0), "displacement": Vector2(40.0, 0.0), "radius": 6.0})
	_expect(not bool(ghost["blocked"]), "policy: ghost body blocked movement")
	_expect(_near(ghost["position"].x, 120.0), "policy: ghost body changed the resolved position")
	var ghost_recorded := false
	for entry: Variant in ghost["contacts"]:
		var contact := entry as Contact
		if contact.source_id == "spirit" and String(contact.response.get("action", "")) == "ignore":
			ghost_recorded = true
	_expect(ghost_recorded, "policy: ghost contact was not recorded with response material")

	dynamic.unregister_body("spirit")
	dynamic.register_body(Fixtures.body("hurt_only", Vector2(96.0, 60.0), 6.0, [Channels.HURTBOX], &"solid"))
	var through: Dictionary = resolver.move({"start": Vector2(80.0, 60.0), "displacement": Vector2(40.0, 0.0), "radius": 6.0})
	_expect(not bool(through["blocked"]) and _near(through["position"].x, 120.0), "policy: hurtbox-only body leaked into the movement channel")


func _test_channel_independence() -> void:
	var asset := Fixtures.wall_world()
	asset["asset_id"] = "fixture/channel_room"
	asset["surfaces"] = [
		Fixtures.surface("arrow_wall", Rect2(100.0, 0.0, 6.0, 120.0), [Channels.PROJECTILE]),
		Fixtures.surface("move_wall", Rect2(40.0, 0.0, 6.0, 120.0), [Channels.MOVEMENT]),
		Fixtures.surface("nav_region", Rect2(0.0, 0.0, 200.0, 120.0), [Channels.NAVIGATION]),
	]
	var index: StaticSpatialIndex = StaticSpatialIndexScript.build(asset)["value"]
	var mover: MovementResolver = MovementResolverScript.make(index)["value"]
	var result: Dictionary = mover.move({"start": Vector2(20.0, 60.0), "displacement": Vector2(60.0, 0.0), "radius": 6.0})
	_expect(bool(result["blocked"]), "channels: movement wall did not block movement")
	_expect(_near(result["position"].x, 34.0), "channels: movement-only stop plane changed")
	var hits: ContinuousHitResolver = ContinuousHitResolverScript.make(index)["value"]
	var shot: Dictionary = hits.resolve_path({"channel": Channels.PROJECTILE, "start": Vector2(20.0, 60.0), "displacement": Vector2(160.0, 0.0), "radius": 3.0})
	_expect(bool(shot["clipped"]), "channels: projectile wall did not stop the projectile")
	_expect(_near((shot["end_point"] as Vector2).x, 97.0), "channels: projectile stop plane changed")
	for entry: Variant in shot["contacts"]:
		_expect((entry as Contact).source_id != "move_wall", "channels: movement wall leaked into the projectile channel")
	_expect(index.surface_ids(Channels.NAVIGATION) == ["nav_region"], "channels: navigation surface listing changed")


func _test_dynamic_duplicate_registration_fails_closed() -> void:
	var index: StaticSpatialIndex = StaticSpatialIndexScript.build(Fixtures.wall_world())["value"]
	var dynamic := DynamicSpatialIndexScript.new()
	_expect(bool(dynamic.register_body(Fixtures.body("twin", Vector2(96.0, 60.0), 6.0, [Channels.MOVEMENT], &"solid"))["ok"]), "duplicate: first registration failed")
	var revision_before := dynamic.revision()
	var duplicate := dynamic.register_body(Fixtures.body("twin", Vector2(96.0, 60.0), 4.0, [Channels.HURTBOX], &"ghost", 2))
	_expect(not bool(duplicate["ok"]), "duplicate: re-registration overwrote an existing entity")
	_expect(dynamic.revision() == revision_before, "duplicate: rejected registration changed the revision")
	var movement_ids := dynamic.entity_ids()
	_expect(movement_ids == ["twin"] and dynamic.bodies(Channels.MOVEMENT).size() == 1, "duplicate: stale channel membership after rejection")
	_expect(dynamic.bodies(Channels.HURTBOX).is_empty(), "duplicate: rejected hurtbox channels leaked into the bucket")
	var stored := dynamic.body("twin")
	_expect(int(stored["generation"]) == 1 and float(stored["radius"]) == 6.0, "duplicate: original body data was mutated")
	var resolver: MovementResolver = MovementResolverScript.make(index, null, dynamic)["value"]
	var blocked: Dictionary = resolver.move({"start": Vector2(80.0, 60.0), "displacement": Vector2(32.0, 0.0), "radius": 6.0})
	_expect(bool(blocked["blocked"]) and _near(blocked["position"].x, 84.0), "duplicate: rejected registration changed movement results")

	_expect(bool(dynamic.unregister_body("twin")["ok"]), "duplicate: unregister failed")
	_expect(bool(dynamic.register_body(Fixtures.body("twin", Vector2(96.0, 60.0), 4.0, [Channels.HURTBOX], &"ghost", 2))["ok"]), "duplicate: re-registration after unregister failed")
	_expect(dynamic.bodies(Channels.MOVEMENT).is_empty(), "duplicate: old movement membership survived unregister and re-register")
	_expect(dynamic.bodies(Channels.HURTBOX).size() == 1, "duplicate: new hurtbox membership missing after re-register")


func _test_projectile_static_dynamic_tie_break() -> void:
	var index: StaticSpatialIndex = StaticSpatialIndexScript.build(Fixtures.tie_world())["value"]
	var dynamic := DynamicSpatialIndexScript.new()
	dynamic.register_body(Fixtures.body("target", Vector2(106.0, 60.0), 6.0, [Channels.HURTBOX], &"soft"))
	var hits: ContinuousHitResolver = ContinuousHitResolverScript.make(index, dynamic)["value"]
	var tie: Dictionary = hits.resolve_path({
		"channel": Channels.PROJECTILE,
		"start": Vector2(0.0, 60.0),
		"displacement": Vector2(112.0, 0.0),
		"radius": 0.0,
	})
	_expect(bool(tie["ok"]) and bool(tie["clipped"]), "tie: path did not stop")
	_expect(int(tie["stop_index"]) == 0, "tie: stop index moved off the opaque wall")
	var tie_contacts: Array = tie["contacts"]
	_expect(tie_contacts.size() == 1, "tie: equal-toi target was not excluded by the environment tie rule")
	if tie_contacts.size() == 1:
		var contact := tie_contacts[0] as Contact
		_expect(contact.kind == Contact.KIND_STATIC_SURFACE and contact.source_id == "shield", "tie: opaque wall did not win the tie")
		_expect(String(contact.response.get("action", "")) == "stop", "tie: stopping contact lost its response material")

	dynamic.commit_pose("target", Vector2(104.0, 60.0))
	var near: Dictionary = hits.resolve_path({
		"channel": Channels.PROJECTILE,
		"start": Vector2(0.0, 60.0),
		"displacement": Vector2(112.0, 0.0),
		"radius": 0.0,
	})
	var near_contacts: Array = near["contacts"]
	_expect(near_contacts.size() == 1, "tie: earlier target did not clip the trailing wall contacts")
	if near_contacts.size() == 1:
		var contact := near_contacts[0] as Contact
		_expect(contact.kind == Contact.KIND_DYNAMIC and contact.source_id == "target", "tie: earlier target was not first")
		_expect(String(contact.response.get("action", "")) == "hit", "tie: entity contact missed hit response material")
	_expect(_near((near["end_point"] as Vector2).x, 98.0), "tie: entity clip end point changed")

	var pierce: Dictionary = hits.resolve_path({
		"channel": Channels.PROJECTILE,
		"start": Vector2(0.0, 60.0),
		"displacement": Vector2(112.0, 0.0),
		"radius": 0.0,
		"piercing": true,
	})
	var pierce_contacts: Array = pierce["contacts"]
	_expect(pierce_contacts.size() == 2, "tie: piercing shot did not pass the target into the wall")
	if pierce_contacts.size() == 2:
		_expect((pierce_contacts[0] as Contact).kind == Contact.KIND_DYNAMIC, "tie: piercing order lost the earlier target")
		_expect(bool((pierce_contacts[0] as Contact).response.get("pierce", false)), "tie: piercing response material missing")
		_expect((pierce_contacts[1] as Contact).kind == Contact.KIND_STATIC_SURFACE, "tie: piercing wall contact lost")


func _test_vision_vs_occlusion_separation() -> void:
	var index: StaticSpatialIndex = StaticSpatialIndexScript.build(Fixtures.vision_world())["value"]
	var vision: VisionResolver = VisionResolverScript.make(index)["value"]
	var occlusion: OcclusionResolver = OcclusionResolverScript.make(index)["value"]

	var sight_blocked: Dictionary = vision.line_of_sight({"from": Vector2(10.0, 30.0), "to": Vector2(190.0, 30.0)})
	_expect(not bool(sight_blocked["visible"]), "vision: sight wall did not block line of sight")
	_expect((sight_blocked["blockers"] as Array).size() == 1, "vision: blocker count changed")
	var sight_clear_of_occluder: Dictionary = vision.line_of_sight({"from": Vector2(10.0, 90.0), "to": Vector2(190.0, 90.0)})
	_expect(bool(sight_clear_of_occluder["visible"]), "vision: occlusion-only panel blocked line of sight")

	var view_blocked: Dictionary = occlusion.segment({"from": Vector2(10.0, 90.0), "to": Vector2(190.0, 90.0)})
	_expect(bool(view_blocked["occluded"]), "occlusion: foreground panel did not occlude the view ray")
	_expect(int(view_blocked["contact"]["response"]["rank"]) == 7, "occlusion: authored rank was lost")
	var view_clear_of_sight_wall: Dictionary = occlusion.segment({"from": Vector2(10.0, 30.0), "to": Vector2(190.0, 30.0)})
	_expect(not bool(view_clear_of_sight_wall["occluded"]), "occlusion: vision-only wall occluded the view ray")

	var through_bush: Dictionary = vision.line_of_sight({"from": Vector2(10.0, 114.0), "to": Vector2(190.0, 114.0)})
	_expect(bool(through_bush["visible"]), "vision: attenuating bush fully blocked sight")
	_expect(_near(float(through_bush["transparency"]), 0.5), "vision: bush attenuation factor changed")

	var dynamic := DynamicSpatialIndexScript.new()
	dynamic.register_body(Fixtures.body("zeta", Vector2(190.0, 30.0), 8.0, [Channels.HURTBOX], &"soft"))
	dynamic.register_body(Fixtures.body("alpha", Vector2(60.0, 80.0), 8.0, [Channels.HURTBOX], &"soft"))
	dynamic.register_body(Fixtures.body("far", Vector2(30.0, 120.0), 8.0, [Channels.HURTBOX], &"soft"))
	var targets: Dictionary = vision.visible_targets({
		"from": Vector2(10.0, 30.0),
		"range": 300.0,
		"half_angle": PI * 0.5,
		"facing": Vector2(0, 1),
		"dynamic_index": dynamic,
	})
	_expect(bool(targets["ok"]), "vision: target query failed")
	var listed: Array = targets["targets"]
	_expect(listed.size() == 2, "vision: hidden target was visible or visible targets were lost")
	if listed.size() == 2:
		_expect(String(listed[0]["entity_id"]) == "alpha", "vision: target ordering ignored distance")
		_expect(String(listed[1]["entity_id"]) == "far", "vision: target ordering ignored distance for the far target")


func _test_overlay_revision() -> void:
	var index: StaticSpatialIndex = StaticSpatialIndexScript.build(Fixtures.doorway_world(50.0, 70.0))["value"]
	var static_snapshot := JSON.stringify(index.snapshot())
	var overlay := SpatialOverlayScript.new()
	var resolver: MovementResolver = MovementResolverScript.make(index, overlay)["value"]
	_expect(overlay.revision() == 0, "overlay: initial revision was not zero")

	var open: Dictionary = resolver.move({"start": Vector2(80.0, 60.0), "displacement": Vector2(40.0, 0.0), "radius": 6.0})
	_expect(not bool(open["blocked"]), "overlay: empty overlay blocked the doorway")

	var gate := overlay.add_surface({
		"id": "gate",
		"shape": {"kind": "rect", "rect": Rect2(98.0, 50.0, 4.0, 20.0)},
		"channels": [Channels.MOVEMENT, Channels.PROJECTILE],
	})
	_expect(bool(gate["ok"]) and overlay.revision() == 0 and overlay.pending_operation_count() == 1, "overlay: gate add mutated before its tick boundary")
	var before_commit: Dictionary = resolver.move({"start": Vector2(80.0, 60.0), "displacement": Vector2(40.0, 0.0), "radius": 6.0})
	_expect(not bool(before_commit["blocked"]), "overlay: pending gate changed a query before commit")
	var gate_commit := overlay.commit_pending(1)
	_expect(bool(gate_commit["ok"]) and overlay.revision() == 1 and overlay.last_committed_tick() == 1, "overlay: gate add did not commit at tick 1")
	var closed: Dictionary = resolver.move({"start": Vector2(80.0, 60.0), "displacement": Vector2(40.0, 0.0), "radius": 6.0})
	_expect(bool(closed["blocked"]), "overlay: closed gate did not block")
	_expect(_near(closed["position"].x, 92.0), "overlay: gate stop plane changed")
	var saw_overlay_contact := false
	for entry: Variant in closed["contacts"]:
		var contact := entry as Contact
		if contact.kind == Contact.KIND_OVERLAY_SURFACE and contact.source_id == "gate":
			saw_overlay_contact = true
	_expect(saw_overlay_contact, "overlay: gate contact was not typed as an overlay surface")
	_expect(JSON.stringify(index.snapshot()) == static_snapshot, "overlay: query mutated the baked static snapshot")

	var duplicate := overlay.add_surface({
		"id": "gate",
		"shape": {"kind": "rect", "rect": Rect2(0.0, 0.0, 4.0, 4.0)},
		"channels": [Channels.MOVEMENT],
	})
	_expect(bool(duplicate["ok"]) and overlay.revision() == 1 and overlay.pending_operation_count() == 1, "overlay: duplicate gate request was applied before its boundary")
	var duplicate_commit := overlay.commit_pending(2)
	_expect(not bool(duplicate_commit["ok"]) and (duplicate_commit["errors"] as Array).has("surface.id:duplicate:gate") and overlay.revision() == 1, "overlay: duplicate gate commit changed the revision")

	overlay.remove_surface("gate")
	_expect(overlay.revision() == 1 and overlay.pending_operation_count() == 1, "overlay: gate remove mutated before its tick boundary")
	_expect(bool(overlay.commit_pending(3)["ok"]) and overlay.revision() == 2, "overlay: gate remove did not produce revision 2")
	var reopened: Dictionary = resolver.move({"start": Vector2(80.0, 60.0), "displacement": Vector2(40.0, 0.0), "radius": 6.0})
	_expect(not bool(reopened["blocked"]) and _near(reopened["position"].x, 120.0), "overlay: removed gate still blocked")

	var pillar_index: StaticSpatialIndex = StaticSpatialIndexScript.build(Fixtures.pillar_world())["value"]
	var pillar_overlay := SpatialOverlayScript.new()
	var pillar_resolver: MovementResolver = MovementResolverScript.make(pillar_index, pillar_overlay)["value"]
	var pillar_blocked: Dictionary = pillar_resolver.move({"start": Vector2(80.0, 60.0), "displacement": Vector2(40.0, 0.0), "radius": 6.0})
	_expect(bool(pillar_blocked["blocked"]), "overlay: destructible pillar did not block")
	pillar_overlay.suppress_static("pillar")
	_expect(pillar_overlay.revision() == 0 and pillar_overlay.pending_operation_count() == 1, "overlay: suppress mutated before its tick boundary")
	var pillar_suppress_commit := pillar_overlay.commit_pending(1)
	_expect(bool(pillar_suppress_commit["ok"]) and pillar_overlay.revision() == 1, "overlay: suppress did not produce a new revision")
	_expect(pillar_overlay.validate_against(pillar_index).is_empty(), "overlay: valid suppression failed validation")
	var pillar_open: Dictionary = pillar_resolver.move({"start": Vector2(80.0, 60.0), "displacement": Vector2(40.0, 0.0), "radius": 6.0})
	_expect(not bool(pillar_open["blocked"]) and _near(pillar_open["position"].x, 120.0), "overlay: suppressed pillar still blocked")
	pillar_overlay.restore_static("pillar")
	_expect(bool(pillar_overlay.commit_pending(2)["ok"]) and pillar_overlay.revision() == 2, "overlay: restore did not commit at the next tick boundary")
	var pillar_again: Dictionary = pillar_resolver.move({"start": Vector2(80.0, 60.0), "displacement": Vector2(40.0, 0.0), "radius": 6.0})
	_expect(bool(pillar_again["blocked"]), "overlay: restored pillar did not block again")
	pillar_overlay.suppress_static("missing")
	var missing_commit := pillar_overlay.commit_pending(3)
	_expect(bool(missing_commit["ok"]) and pillar_overlay.revision() == 3, "overlay: unknown static suppression was not staged deterministically")
	_expect(not pillar_overlay.validate_against(pillar_index).is_empty(), "overlay: unknown static suppression passed validation")
	var stale_commit := pillar_overlay.commit_pending(3)
	_expect(not bool(stale_commit["ok"]) and (stale_commit["errors"] as Array).has("overlay:stale_tick"), "overlay: same tick accepted a second overlay commit")
	_expect(JSON.stringify(pillar_index.snapshot()) == JSON.stringify(StaticSpatialIndexScript.build(Fixtures.pillar_world())["value"].snapshot()), "overlay: static asset bytes changed after overlay use")


func _test_byte_stable_snapshots_and_ordering() -> void:
	var shuffled := Fixtures.wall_world()
	shuffled["surfaces"] = [
		Fixtures.surface("b_wall", Rect2(60.0, 0.0, 6.0, 40.0), [Channels.MOVEMENT, Channels.PROJECTILE, Channels.VISION]),
		Fixtures.surface("a_wall", Rect2(120.0, 0.0, 6.0, 40.0), [Channels.MOVEMENT, Channels.PROJECTILE, Channels.VISION]),
		Fixtures.surface("c_wall", Rect2(20.0, 0.0, 6.0, 40.0), [Channels.MOVEMENT, Channels.PROJECTILE, Channels.VISION]),
	]
	var shuffled_reversed := Fixtures.wall_world()
	shuffled_reversed["surfaces"] = [
		Fixtures.surface("c_wall", Rect2(20.0, 0.0, 6.0, 40.0), [Channels.MOVEMENT, Channels.PROJECTILE, Channels.VISION]),
		Fixtures.surface("b_wall", Rect2(60.0, 0.0, 6.0, 40.0), [Channels.MOVEMENT, Channels.PROJECTILE, Channels.VISION]),
		Fixtures.surface("a_wall", Rect2(120.0, 0.0, 6.0, 40.0), [Channels.MOVEMENT, Channels.PROJECTILE, Channels.VISION]),
	]
	var first: StaticSpatialIndex = StaticSpatialIndexScript.build(shuffled)["value"]
	var second: StaticSpatialIndex = StaticSpatialIndexScript.build(shuffled_reversed)["value"]
	var first_text := JSON.stringify(first.snapshot())
	var second_text := JSON.stringify(second.snapshot())
	_expect(first_text == second_text, "bytes: snapshot depended on authored surface order")

	var first_dynamic := DynamicSpatialIndexScript.new()
	first_dynamic.register_body(Fixtures.body("zeta", Vector2(90.0, 90.0), 6.0, [Channels.MOVEMENT, Channels.HURTBOX], &"solid"))
	first_dynamic.register_body(Fixtures.body("alpha", Vector2(90.0, 90.0), 6.0, [Channels.MOVEMENT, Channels.HURTBOX], &"ghost"))
	var second_dynamic := DynamicSpatialIndexScript.new()
	second_dynamic.register_body(Fixtures.body("alpha", Vector2(90.0, 90.0), 6.0, [Channels.MOVEMENT, Channels.HURTBOX], &"ghost"))
	second_dynamic.register_body(Fixtures.body("zeta", Vector2(90.0, 90.0), 6.0, [Channels.MOVEMENT, Channels.HURTBOX], &"solid"))
	_expect(JSON.stringify(first_dynamic.snapshot()) == JSON.stringify(second_dynamic.snapshot()), "bytes: dynamic snapshot depended on registration order")

	var first_resolver: MovementResolver = MovementResolverScript.make(first, null, first_dynamic)["value"]
	var second_resolver: MovementResolver = MovementResolverScript.make(second, null, second_dynamic)["value"]
	var request := {"start": Vector2(10.0, 90.0), "displacement": Vector2(100.0, 0.0), "radius": 4.0}
	var first_move: Dictionary = first_resolver.move(request)
	var second_move: Dictionary = second_resolver.move(request)
	var first_move_text := JSON.stringify(Contact.encode(first_move["contacts"]))
	var second_move_text := JSON.stringify(Contact.encode(second_move["contacts"]))
	_expect(first_move_text == second_move_text, "bytes: movement contacts depended on registration order")
	_expect(JSON.stringify(first_move["position"]) == JSON.stringify(second_move["position"]), "bytes: movement position depended on registration order")
	_expect(JSON.stringify(Contact.encode(first_resolver.move(request)["contacts"])) == first_move_text, "bytes: repeated identical query changed bytes")

	var ordered: Array = first_move["contacts"]
	if ordered.size() >= 2:
		_expect((ordered[0] as Contact).source_id == "alpha", "bytes: simultaneous dynamic contacts were not id-ordered")

	var first_hits: ContinuousHitResolver = ContinuousHitResolverScript.make(first, first_dynamic)["value"]
	var second_hits: ContinuousHitResolver = ContinuousHitResolverScript.make(second, second_dynamic)["value"]
	var shot_request := {"channel": Channels.PROJECTILE, "start": Vector2(10.0, 90.0), "displacement": Vector2(150.0, 0.0), "radius": 2.0}
	var first_shot: Dictionary = first_hits.resolve_path(shot_request)
	var second_shot: Dictionary = second_hits.resolve_path(shot_request)
	_expect(JSON.stringify(Contact.encode(first_shot["contacts"])) == JSON.stringify(Contact.encode(second_shot["contacts"])), "bytes: projectile contacts depended on registration order")
	_expect(JSON.stringify(Contact.encode(first_hits.resolve_path(shot_request)["contacts"])) == JSON.stringify(Contact.encode(first_shot["contacts"])), "bytes: repeated projectile query changed bytes")

	var first_vision: VisionResolver = VisionResolverScript.make(first)["value"]
	var second_vision: VisionResolver = VisionResolverScript.make(second)["value"]
	var sight_request := {"from": Vector2(0.0, 20.0), "to": Vector2(150.0, 20.0)}
	var first_sight: Dictionary = first_vision.line_of_sight(sight_request)
	var second_sight: Dictionary = second_vision.line_of_sight(sight_request)
	var first_blockers := Contact.encode(first_sight["blockers"])
	var second_blockers := Contact.encode(second_sight["blockers"])
	_expect(JSON.stringify(first_blockers) == JSON.stringify(second_blockers), "bytes: vision blockers depended on registration order")
	_expect(JSON.stringify(Contact.encode(first_vision.line_of_sight(sight_request)["blockers"])) == JSON.stringify(first_blockers), "bytes: repeated vision query changed bytes")


func _contact_signature(contacts: Array) -> Array:
	var rows: Array = []
	for entry: Variant in contacts:
		var contact := entry as Contact
		rows.append("%s|%s|%s|%s|%s|%s" % [contact.source_id, contact.feature, contact.toi, contact.point, contact.normal, contact.penetrating])
	return rows


func _test_broadphase_differential() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261026
	var channel_sets: Array = [[Channels.MOVEMENT], [Channels.MOVEMENT, Channels.PROJECTILE], [Channels.PROJECTILE], [Channels.VISION, Channels.MOVEMENT]]
	var surfaces: Array = []
	for number in 90:
		var origin := Vector2(rng.randf_range(-300.0, 900.0), rng.randf_range(-300.0, 700.0))
		var shape: Dictionary
		match number % 3:
			0: shape = {"kind": "rect", "rect": Rect2(origin, Vector2(rng.randf_range(2.0, 90.0), rng.randf_range(2.0, 90.0)))}
			1: shape = {"kind": "circle", "center": origin, "radius": rng.randf_range(1.0, 40.0)}
			_: shape = {"kind": "polygon", "points": PackedVector2Array([origin, origin + Vector2(rng.randf_range(20.0, 80.0), rng.randf_range(0.0, 10.0)), origin + Vector2(rng.randf_range(10.0, 60.0), rng.randf_range(30.0, 70.0))])}
		surfaces.append({"id": "s%03d" % number, "shape": shape, "channels": channel_sets[number % channel_sets.size()]})
	var built: Dictionary = StaticSpatialIndexScript.build({"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION, "asset_id": "fixture/broadphase", "surfaces": surfaces})
	_expect(bool(built["ok"]), "broadphase: fixture index failed to build")
	if not bool(built["ok"]):
		return
	var index: StaticSpatialIndex = built["value"]
	var checked := 0
	var hit_queries := 0
	for iteration in 700:
		var position := Vector2(rng.randf_range(-350.0, 950.0), rng.randf_range(-350.0, 750.0))
		var radius := rng.randf_range(0.0, 30.0)
		if iteration % 7 == 0:
			var target: Dictionary = index.surface("s%03d" % rng.randi_range(0, 89))
			var shape: Dictionary = target["shape"]
			if shape["kind"] != "circle":
				var points: PackedVector2Array = shape["points"]
				var anchor: Vector2 = points[0]
				position = anchor + Vector2(-radius + [-0.0001, 0.0, 0.0001][iteration % 3], 0.0)
		var channel: StringName = [Channels.MOVEMENT, Channels.PROJECTILE, Channels.VISION, Channels.ATTACK][iteration % 4]
		var expected: Array = []
		var swept_expected: Array = []
		var displacement := Vector2(rng.randf_range(-120.0, 120.0), rng.randf_range(-120.0, 120.0))
		if iteration % 5 == 0:
			displacement = Vector2.ZERO
		for id: String in index.surface_ids(channel):
			var stored: Dictionary = index.surface(id)
			var overlap: Dictionary = ShapeScript.circle_shape_overlap(position, radius, stored["shape"])
			if bool(overlap["overlaps"]):
				expected.append(Contact.from_raw({"toi": 0.0, "point": overlap["point"], "normal": overlap["normal"], "feature": overlap["feature"], "penetrating": true, "initial": true}, channel, Contact.KIND_STATIC_SURFACE, id, 0))
			var raw: Dictionary = StaticSpatialIndexScript._sweep_shape(stored["shape"], position, displacement, radius)
			if not raw.is_empty():
				swept_expected.append(Contact.from_raw(raw, channel, Contact.KIND_STATIC_SURFACE, id, 0))
		expected = Contact.sort_contacts(expected)
		swept_expected = Contact.sort_contacts(swept_expected)
		if not expected.is_empty() or not swept_expected.is_empty():
			hit_queries += 1
		_expect(_contact_signature(index.overlaps(channel, position, radius)) == _contact_signature(expected), "broadphase: overlaps differ from brute force at iteration %d" % iteration)
		_expect(_contact_signature(index.sweep(channel, position, displacement, radius)) == _contact_signature(swept_expected), "broadphase: sweep differs from brute force at iteration %d" % iteration)
		checked += 1
	_expect(checked == 700 and hit_queries > 100, "broadphase: differential run did not exercise enough contacts (%d)" % hit_queries)
	_expect(index.overlaps(Channels.MOVEMENT, Vector2(NAN, 0.0), 4.0).is_empty() and index.overlaps(Channels.MOVEMENT, Vector2.ZERO, -1.0).is_empty(), "broadphase: invalid overlap input was not empty")
	_expect(index.sweep(Channels.MOVEMENT, Vector2.ZERO, Vector2(INF, 0.0), 4.0).is_empty() and index.overlaps(&"bogus", Vector2.ZERO, 4.0).is_empty(), "broadphase: invalid sweep input was not empty")
	_expect(var_to_str(index.snapshot()) == var_to_str(StaticSpatialIndexScript.build({"schema_version": StaticSpatialIndexScript.SCHEMA_VERSION, "asset_id": "fixture/broadphase", "surfaces": surfaces})["value"].snapshot()), "broadphase: snapshot is not rebuild-stable")


func _test_zero_displacement_contract() -> void:
	var wall_index: StaticSpatialIndex = StaticSpatialIndexScript.build(Fixtures.wall_world())["value"]
	var wall: MovementResolver = MovementResolverScript.make(wall_index)["value"]
	var idle: Dictionary = wall.move({"start": Vector2(20.0, 60.0), "displacement": Vector2.ZERO, "radius": 6.0})
	_expect(bool(idle["ok"]) and not bool(idle["blocked"]) and String(idle["mode"]) == "completed", "zero: idle move was not a clean completion")
	_expect(idle["position"] == Vector2(20.0, 60.0) and (idle["contacts"] as Array).is_empty() and int(idle["iterations"]) == 0, "zero: idle move changed state or reported contacts")
	var overlapping: Dictionary = wall.move({"start": Vector2(102.0, 60.0), "displacement": Vector2.ZERO, "radius": 6.0})
	_expect(String(overlapping["mode"]) == "start_penetrating" and bool(overlapping["blocked"]) and not (overlapping["contacts"] as Array).is_empty(), "zero: overlapping start was not reported")
	_expect(overlapping["position"] == Vector2(102.0, 60.0), "zero: overlapping start moved")
	var recovery: Dictionary = wall.move({"start": Vector2(102.0, 60.0), "displacement": Vector2(-8.0, 0.0), "radius": 6.0})
	_expect(String(recovery["mode"]) == "start_penetrating", "zero: nonzero move from an overlapping start changed contract")
	var ring: MovementResolver = MovementResolverScript.make(StaticSpatialIndexScript.build(Fixtures.ring_world())["value"])["value"]
	var outside: Dictionary = ring.move({"start": Vector2(100.0, 190.0), "displacement": Vector2.ZERO, "radius": 6.0})
	_expect(String(outside["mode"]) == "start_penetrating" and bool(outside["blocked"]), "zero: boundary overlap at an unmoved start was not reported")
	var inside: Dictionary = ring.move({"start": Vector2(100.0, 170.0), "displacement": Vector2.ZERO, "radius": 6.0})
	_expect(not bool(inside["blocked"]) and inside["position"] == Vector2(100.0, 170.0), "zero: legal boundary position changed")
	var open_index: StaticSpatialIndex = StaticSpatialIndexScript.build(Fixtures.open_world())["value"]
	var dynamic := DynamicSpatialIndexScript.new()
	var open: MovementResolver = MovementResolverScript.make(open_index, null, dynamic)["value"]
	dynamic.register_body(Fixtures.body("self", Vector2(80.0, 60.0), 6.0, [Channels.MOVEMENT], &"solid"))
	var own: Dictionary = open.move({"start": Vector2(80.0, 60.0), "displacement": Vector2.ZERO, "radius": 6.0, "source_id": "self"})
	_expect(not bool(own["blocked"]) and (own["contacts"] as Array).is_empty(), "zero: own body filtered incorrectly")
	dynamic.register_body(Fixtures.body("guard", Vector2(84.0, 60.0), 6.0, [Channels.MOVEMENT], &"solid"))
	var solid: Dictionary = open.move({"start": Vector2(80.0, 60.0), "displacement": Vector2.ZERO, "radius": 6.0, "source_id": "self"})
	_expect(String(solid["mode"]) == "start_penetrating" and bool(solid["blocked"]), "zero: overlapping solid body not reported")
	dynamic.unregister_body("guard")
	dynamic.register_body(Fixtures.body("crowd", Vector2(84.0, 60.0), 6.0, [Channels.MOVEMENT], &"soft"))
	var soft: Dictionary = open.move({"start": Vector2(80.0, 60.0), "displacement": Vector2.ZERO, "radius": 6.0, "source_id": "self"})
	_expect(soft["position"] != Vector2(80.0, 60.0), "zero: soft separation was skipped for an unmoved start")
	var repeat: Dictionary = wall.move({"start": Vector2(20.0, 60.0), "displacement": Vector2.ZERO, "radius": 6.0})
	_expect(var_to_str(repeat) == var_to_str(idle), "zero: repeated idle result is not deterministic")
	# At this coordinate the contact skin rounds back to the exact float32
	# starting point. A real blocked move therefore exercises the endpoint
	# reuse branch, rather than only testing an empty movement command.
	var far_asset: Dictionary = Fixtures.wall_world()
	far_asset.erase("movement_boundary")
	far_asset["surfaces"][0]["shape"] = {"kind": "rect", "rect": Rect2(50000.0, 0.0, 20.0, 120.0)}
	var far_index: StaticSpatialIndex = StaticSpatialIndexScript.build(far_asset)["value"]
	var far_resolver: MovementResolver = MovementResolverScript.make(far_index)["value"]
	var stopped: Dictionary = far_resolver.move({"start": Vector2(49994.0, 60.0), "displacement": Vector2(20.0, 0.0), "radius": 6.0})
	_expect(stopped.position == Vector2(49994.0, 60.0) and stopped.blocked and stopped.mode == "blocked", "zero-net: blocked contact must retain its mode and exact start")
	_expect(stopped.remaining == Vector2.ZERO and stopped.iterations == 1 and stopped.contacts.size() == 1, "zero-net: blocked report lost its contact or residual contract")
	if stopped.contacts.size() == 1:
		var stopped_contact := stopped.contacts[0] as Contact
		_expect(stopped_contact.source_id == "wall" and stopped_contact.toi == 0.0 and _near_vector(stopped_contact.normal, Vector2.LEFT), "zero-net: blocking contact changed")
	_expect(far_index.overlaps(Channels.MOVEMENT, stopped.position, 6.0).is_empty(), "zero-net: skipped endpoint query must be empty")


func _test_request_validation() -> void:
	var index: StaticSpatialIndex = StaticSpatialIndexScript.build(Fixtures.wall_world())["value"]
	var dynamic := DynamicSpatialIndexScript.new()
	var resolver: MovementResolver = MovementResolverScript.make(index, null, dynamic)["value"]
	var bad_field: Dictionary = resolver.move({"start": Vector2(0, 0), "displacement": Vector2(1, 0), "radius": 4.0, "banana": 1})
	_expect(not bool(bad_field["ok"]), "validate: unknown move field was accepted")
	var bad_vector: Dictionary = resolver.move({"start": Vector2(0, 0), "displacement": Vector2(NAN, 0), "radius": 4.0})
	_expect(not bool(bad_vector["ok"]), "validate: non-finite displacement was accepted")
	var bad_radius: Dictionary = resolver.move({"start": Vector2(0, 0), "displacement": Vector2(1, 0), "radius": -1.0})
	_expect(not bool(bad_radius["ok"]), "validate: negative radius was accepted")

	var penetrating: Dictionary = resolver.move({"start": Vector2(102.0, 60.0), "displacement": Vector2(4.0, 0.0), "radius": 6.0})
	_expect(String(penetrating["mode"]) == "start_penetrating", "validate: penetrating start was not reported")
	_expect(_near_vector(penetrating["position"], Vector2(102.0, 60.0)), "validate: penetrating start moved anyway")

	var commit := dynamic.commit_pose("missing", Vector2(10.0, 10.0))
	_expect(not bool(commit["ok"]), "validate: unknown entity pose commit was accepted")
	var bad_register := dynamic.register_body({"entity_id": "x", "generation": 0, "position": Vector2.ZERO, "radius": 2.0, "channels": [Channels.MOVEMENT], "collision_class": &"solid"})
	_expect(not bool(bad_register["ok"]), "validate: generation zero body was accepted")
	var bad_class := dynamic.register_body(Fixtures.body("y", Vector2.ZERO, 2.0, [Channels.MOVEMENT], &"sticky"))
	_expect(not bool(bad_class["ok"]), "validate: unknown collision class was accepted")
	var policy := BodyCollisionPolicyScript.make({"solid": {"response": &"banana", "record": true}, "soft": {"response": &"separate"}, "ghost": {"response": &"ignore"}})
	_expect(not bool(policy["ok"]), "validate: unknown policy response was accepted")
	var hits: ContinuousHitResolver = ContinuousHitResolverScript.make(index)["value"]
	var bad_channel: Dictionary = hits.resolve_path({"channel": Channels.MOVEMENT, "start": Vector2.ZERO, "displacement": Vector2(10, 0), "radius": 1.0})
	_expect(not bool(bad_channel["ok"]), "validate: non-combat channel was accepted by the hit resolver")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _near(value: float, expected: float, epsilon: float = 0.001) -> bool:
	return absf(value - expected) <= epsilon


func _near_vector(value: Vector2, expected: Vector2, epsilon: float = 0.001) -> bool:
	return _near(value.x, expected.x, epsilon) and _near(value.y, expected.y, epsilon)
