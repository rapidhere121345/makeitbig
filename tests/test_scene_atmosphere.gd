extends SceneTree
## Bounded acceptance check for the R11 scene-atmosphere package.
## Headless-safe: it validates the presentation contract, node placement and
## drawing budgets without launching the whole game or capturing pixels.
##
## Run:
##   GODOT --headless --path . --script res://tests/test_scene_atmosphere.gd
## Pixel regression (requires a rendering display; headless exits 2 / GPU SKIP):
##   GODOT --path . --script res://tests/test_scene_atmosphere.gd -- --gpu-cutout-only
## The existing --gpu capture mode also runs this isolated shader regression.
## Authored reveal fixture: -- --gpu-authored-reveal --output=/fresh/absolute/path
## Silhouette production-path fixture: -- --gpu-silhouette-only --output=/fresh/absolute/path

const Atmosphere = preload("res://src/presentation/scene_atmosphere.gd")
const AuthoredReveal = preload("res://src/presentation/occlusion/authored_reveal_controller.gd")
const AtmosphereLayerScript = preload("res://src/presentation/scene_atmosphere_layer.gd")
const BaseHubScript = preload("res://src/presentation/base_hub_screen.gd")
const TownExpectations = preload("res://tests/helpers/town_scene_expectations.gd")
const ArenaWorldViewScript = preload("res://src/presentation/arena_world_view.gd")
const HearthReturnViewScript = preload("res://src/presentation/hearth_return_view.gd")
const SilhouetteRevealScript = preload("res://src/presentation/occlusion/silhouette_reveal_controller.gd")

var failures: Array[String] = []
var output_dir := ""
var captures: Array[Dictionary] = []

func _initialize() -> void:
	if _has_arg("--gpu-authored-reveal"):
		call_deferred("_run_authored_reveal_gpu")
		return
	if _has_arg("--gpu-cutout-only"):
		call_deferred("_run_cutout_gpu")
		return
	if _has_arg("--gpu-silhouette-only"):
		call_deferred("_run_silhouette_gpu")
		return
	if _has_arg("--gpu"):
		call_deferred("_run_gpu")
		return
	_test_presets()
	_test_layer()
	_test_hamlet()
	_test_arena()
	_test_hearth()
	if failures.is_empty():
		print("PASS ui_atmosphere_r11 lighting_check")
		quit(0)
		return
	printerr("%d atmosphere check(s) failed:" % failures.size())
	for failure in failures:
		printerr("- %s" % failure)
	quit(1)

func _run_gpu() -> void:
	if DisplayServer.get_name().to_lower().contains("headless"):
		printerr("GPU SKIP: display is headless")
		quit(2)
		return
	output_dir = _arg("--output=")
	if not output_dir.is_absolute_path() or DirAccess.dir_exists_absolute(output_dir):
		printerr("GPU REJECTED: fresh absolute --output directory required")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		printerr("GPU REJECTED: cannot create %s" % output_dir)
		quit(2)
		return
	await _test_cutout_gpu()
	await _test_silhouette_gpu()
	await _test_authored_reveal_gpu()
	await _capture_hamlet()
	await _capture_hearth()
	await _capture_arena()
	var report := {"status":"pass" if failures.is_empty() else "fail", "errors":failures, "captures":captures, "fixture_note":"Synthetic shader fixtures plus isolated published scene views with fixed lighting toggles; not production-art acceptance or a playable combat test."}
	var file := FileAccess.open(output_dir.path_join("REPORT.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("R11_LIGHTING_GPU ",report.status," captures=",captures.size())
	quit(0 if failures.is_empty() else 1)

func _run_cutout_gpu() -> void:
	if DisplayServer.get_name().to_lower().contains("headless"):
		printerr("GPU SKIP: cutout pixel regression requires a rendering display")
		quit(2)
		return
	await _test_cutout_gpu()
	for failure in failures:
		printerr("- %s" % failure)
	print("CUTOUT_GPU ", "pass" if failures.is_empty() else "fail")
	quit(0 if failures.is_empty() else 1)

func _test_cutout_gpu() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(96, 32)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var source := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	source.fill(Color(0.5, 0.75, 0.25, 0.65))
	source.fill_rect(Rect2i(0, 0, 16, 32), Color(0.8, 0.3, 0.6, 0.4))
	var texture := ImageTexture.create_from_image(source)
	var material := ShaderMaterial.new()
	material.shader = load("res://src/presentation/occlusion/occluder_cutout.gdshader")
	material.set_shader_parameter("hole_count", 0)
	material.set_shader_parameter("feather", 2.0)
	material.set_shader_parameter("inner_alpha", 0.18)
	for index in range(3):
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = Vector2(index * 32, 0)
		sprite.modulate = Color(0.8, 0.6, 0.9, 0.7)
		sprite.self_modulate = Color(0.9, 0.8, 0.7, 0.85)
		if index == 1:
			sprite.material = material
		elif index == 2:
			# A native alpha-only reference also handles render-target blending.
			sprite.modulate.a *= 0.18
		viewport.add_child(sprite)
	await _settle()
	await RenderingServer.frame_post_draw
	var identity := viewport.get_texture().get_image()
	if identity == null or identity.is_empty():
		_expect(false, "cutout GPU returned no rendered pixels")
		viewport.queue_free()
		return
	var identity_error := 0.0
	for y in range(32):
		for x in range(32):
			identity_error = maxf(identity_error, _color_error(identity.get_pixel(x, y), identity.get_pixel(x + 32, y)))
	_expect(identity.get_pixel(20, 16).a > 0.1, "cutout reference must contain visible translucent pixels")
	_expect(identity_error <= 2.0 / 255.0, "hole_count=0 changed texture/modulate RGBA: error=%f" % identity_error)

	var holes := PackedVector4Array()
	holes.resize(8)
	holes[0] = Vector4(48.0, 16.0, 6.0, 0.0)
	material.set_shader_parameter("holes", holes)
	material.set_shader_parameter("hole_count", 1)
	await _settle()
	await RenderingServer.frame_post_draw
	var cutout := viewport.get_texture().get_image()
	var exterior_error := 0.0
	for y in range(32):
		for x in range(32):
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(16, 16)) >= 9.0:
				exterior_error = maxf(exterior_error, _color_error(cutout.get_pixel(x, y), cutout.get_pixel(x + 32, y)))
	var center := cutout.get_pixel(50, 16)
	var expected_center := cutout.get_pixel(82, 16)
	_expect(_color_error(center, expected_center) <= 2.0 / 255.0, "cutout center differs from native alpha-only reference: actual=%s expected=%s" % [center, expected_center])
	_expect(center.a < cutout.get_pixel(18, 16).a * 0.3, "cutout did not reduce center alpha")
	_expect(exterior_error <= 2.0 / 255.0, "cutout changed unaffected exterior RGBA: error=%f" % exterior_error)
	print("CUTOUT_GPU identity_error=", identity_error, " exterior_error=", exterior_error, " center=", center, " expected=", expected_center)
	viewport.queue_free()
	await process_frame

func _run_silhouette_gpu() -> void:
	if DisplayServer.get_name().to_lower().contains("headless"):
		printerr("GPU SKIP: silhouette production-path regression requires a rendering display")
		quit(2)
		return
	output_dir = _arg("--output=")
	if not output_dir.is_absolute_path() or DirAccess.dir_exists_absolute(output_dir):
		printerr("GPU REJECTED: fresh absolute --output directory required")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		printerr("GPU REJECTED: cannot create output directory")
		quit(2)
		return
	print("SILHOUETTE_GPU display=", DisplayServer.get_name(), " adapter=", RenderingServer.get_video_adapter_name())
	await _test_silhouette_gpu()
	var report := {"status": "pass" if failures.is_empty() else "fail",
		"errors": failures, "captures": captures,
		"fixture_note": "Production-path silhouette reveal, frozen-pose frame-matched references: per-stage cover/nopiece/off/R/L/bracket sets, exact texel identities, no animation exemptions; readability deltas reported for visual review, never excluded."}
	var file := FileAccess.open(output_dir.path_join("REPORT.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	for failure in failures:
		printerr("- %s" % failure)
	print("SILHOUETTE_GPU ", report.status)
	quit(0 if failures.is_empty() else 1)


## Renders the real town presenter and checks the silhouette reveal through
## the PRODUCTION path: the hub mounts, the presenter's own _sync_occlusion
## uploads actor slots, and only captures plus the material/visibility
## reference toggles are fixture-driven. v3 semantics: every stage FREEZES
## the presentation (tree paused, so ambient and resident animation stop and
## frame_post_draw never fires; captures ride two process frames), then builds
## its own frame-matched reference set - cover (live reveal), nopiece (pair
## piece hidden), off (silhouette materials detached = intact scene), R
## (actors z-lifted over the intact scene), L (piece and actors hidden = pure
## backing), bracket (everything restored, must equal cover). Expected colors
## are ALWAYS other rendered frames; CPU sprite sampling is used only to
## CLASSIFY pixels (which texel alpha the shader samples), never to guess an
## expected color, and nothing is exempted as "animation" - the bracket check
## proves the pose frozen instead. Classification follows the same integer
## floor-then-mirror texel convention as the shader.
const SIL_TOLERANCE := 2.0 / 255.0

func _test_silhouette_gpu() -> void:
	var hub := BaseHubScript.new()
	root.add_child(hub)
	hub._ready()
	var view := hub.get_hub_view()
	var town: Variant = hub.get_town_runtime()
	_expect(bool(hub.town_load_report.get("ok", false)), "silhouette GPU: native town must load actual layers")
	var runtime_ref: Variant = view._presentation_runtime
	view._presentation_runtime = null
	for _warm in range(3):
		await process_frame
	view.protect_dialogue_resident("mira")
	var placed: Dictionary = town.place_hero(Vector2(1290.0, 410.0))
	_expect(bool(placed.get("ok", false)), "silhouette GPU: hero placement rejected: " + str(placed))
	for _tick in range(3):
		view._process(1.0 / 30.0)
	var mira_sprite: Sprite2D = (view._resident_views.get("mira") as Dictionary)["node"] as Sprite2D

	# Production open: re-attach the runtime and let the presenter open the
	# pair reveal through its own sync loop.
	view._presentation_runtime = runtime_ref
	for _tick in range(12):
		view._process(1.0 / 30.0)
	if not _silhouette_authority_settle(town, view, "initial placement"):
		hub.queue_free()
		await process_frame
		return
	var camera := view.camera_world_offset()
	_expect(camera != Vector2.ZERO, "silhouette GPU: calibrated nonzero camera clamp expected, got " + str(camera))
	var report: Dictionary = view.occlusion_report()
	_expect(bool(report.get("silhouette_native_piece_only", false)), "silhouette GPU: reveal must stay native-piece-only")

	# Pair resolution on the authored unflipped pose the reveal opened with.
	var pair := _paired_pair_row(view)
	_expect(not pair.is_empty(), "paired GPU: no reveal row covers the hero and protected mira together")
	if pair.is_empty():
		hub.queue_free()
		await process_frame
		return
	_paired_expect_pair_row(pair["row"])
	var piece_sprite: Sprite2D = view.world_presenter.native_binding_node(pair["id"]) as Sprite2D
	_expect(piece_sprite != null, "silhouette GPU: pair occluder must resolve to a native piece node")
	if piece_sprite == null:
		hub.queue_free()
		await process_frame
		return

	paused = true
	# Stage "original": the calibrated unflipped pair at the authored .25
	# origin - the one pose whose opaque hero/resident overlap is guaranteed
	# positive (9..29 texels across the resident's frames), so only here does
	# the fixture DEMAND an exercised two-slot overlap. Every other stage
	# still verifies whatever overlap pixels actually exist.
	var _original := await _silhouette_stage(view, "pair_original", piece_sprite, [view._hero_sprite, mira_sprite], true)

	# Stage "flipped": both hero axes flipped over the fractional .25 origin;
	# flipped poses carry at most a handful of overlap texels, so none are
	# demanded here - they are verified if present.
	view._hero_sprite.flip_h = true
	view._hero_sprite.flip_v = true
	for _tick in range(12):
		view._process(1.0 / 30.0)
	var flipped_pair := _paired_pair_row(view)
	_expect(not flipped_pair.is_empty(), "paired GPU: no reveal row covers the flipped hero and mira together")
	if not flipped_pair.is_empty():
		_expect(String(flipped_pair["id"]) == String(pair["id"]),
			"paired GPU: the flips must keep the same pair piece (got %s after %s)" % [str(flipped_pair["id"]), str(pair["id"])])
		_paired_expect_pair_row(flipped_pair["row"])
	var _flipped := await _silhouette_stage(view, "pair_flipped", piece_sprite, [view._hero_sprite, mira_sprite], true)

	# Stage "moved": flips released and the hero shifts +4px inside the
	# detection ring - the whole-object reveal must stay open on the same
	# piece (hysteresis, not a re-trigger).
	view._hero_sprite.flip_h = false
	view._hero_sprite.flip_v = false
	placed = town.place_hero(Vector2(1294.0, 410.0))
	_expect(bool(placed.get("ok", false)), "paired GPU: hero move rejected: " + str(placed))
	if not _silhouette_authority_settle(town, view, "+4 move"):
		paused = false
		hub.queue_free()
		await process_frame
		return
	_expect(view.camera_world_offset() == camera, "paired GPU: camera must hold its clamp across the hero shift")
	var moved_pair := _paired_pair_row(view)
	_expect(not moved_pair.is_empty(), "paired GPU: the pair reveal row was lost after the hero shift")
	if not moved_pair.is_empty():
		_expect(String(moved_pair["id"]) == String(pair["id"]),
			"paired GPU: the +4px shift must keep the same pair piece (got %s after %s)" % [str(moved_pair["id"]), str(pair["id"])])
		_paired_expect_pair_row(moved_pair["row"])
	var _moved := await _silhouette_stage(view, "pair_moved", piece_sprite, [view._hero_sprite, mira_sprite], true)

	# Stage "closed": the hero walks fully clear of the ring - the whole
	# object must restore its exact authored opaque pixels inside the piece
	# rect, verified against the materials-detached reference.
	placed = town.place_hero(Vector2(711.0, 250.0))
	_expect(bool(placed.get("ok", false)), "paired GPU: hero exit placement rejected: " + str(placed))
	if not _silhouette_authority_settle(town, view, "exit"):
		paused = false
		hub.queue_free()
		await process_frame
		return
	var _closed := await _silhouette_stage(view, "pair_closed", piece_sprite, [view._hero_sprite, mira_sprite], false)

	# Return to the covering pose before protection removal.
	placed = town.place_hero(Vector2(1290.0, 410.0))
	_expect(bool(placed.get("ok", false)), "paired GPU: hero return to the covering pose rejected: " + str(placed))
	if not _silhouette_authority_settle(town, view, "return to cover"):
		paused = false
		hub.queue_free()
		await process_frame
		return

	# Stage "unprotected": protection removal - the resident loses its slot,
	# the hero keeps its exact silhouette, the piece closes over the resident.
	view.protect_dialogue_resident("")
	for _tick in range(12):
		view._process(1.0 / 30.0)
	var final_rows: Dictionary = (view.occlusion_report().get("paired_reveal", {}) as Dictionary)
	for occluder_id: String in final_rows.keys():
		_expect(not (final_rows[occluder_id].get("actors", {}) as Dictionary).has("town/npc/mira"),
			"paired GPU: resident slot survived protection removal on " + occluder_id)
	var _unprotected := await _silhouette_stage(view, "pair_unprotected", piece_sprite, [view._hero_sprite], true)

	# Final reset: the production reset path (runtime detached, presenter
	# uploads count 0 while materials stay attached) must restore the intact
	# scene exactly - compared against its own materials-detached reference.
	view._presentation_runtime = null
	for _tick in range(3):
		view._process(1.0 / 30.0)
	var reset := await _silhouette_reset_stage(view, "sil_after_reset")
	paused = false
	view._presentation_runtime = runtime_ref

	_silhouette_diag("flipped", [view._hero_sprite, mira_sprite], piece_sprite, view)
	_silhouette_diag("moved", [view._hero_sprite, mira_sprite], piece_sprite, view)
	_silhouette_diag("unprotected", [view._hero_sprite, mira_sprite], piece_sprite, view)
	hub.queue_free()
	await process_frame


## d19's stale-port correction, exactly as directed: place_hero commits the
## teleport and the drawn sprite follows through state_changed/consume, but
## RoomPresentationPort.latest_frame refreshes only via on_snapshot from an
## authority step_tick, so the occlusion plan keeps the hero's PREVIOUS
## feet_anchor and the reveal never grants the hero its slot under the pair
## piece. One zero-input TownRuntime.step_tick() - the existing authority path;
## the fixture never submits move intent and place_hero zeroes it - publishes
## the authoritative snapshot, then presenter settle ticks consume it. Records
## before/after authority tick, hero feet, presentation frame tick, plan
## town/ranger feet_anchor, tree_east occluder cover, and the resulting
## tree_east row actor keys/weight. If the plan feet ALREADY match the
## committed feet before the tick, or never converge after it, the stale-port
## diagnosis is disproved: record the state, fail, stop - no speculative
## probing, no weaker asserts.
func _silhouette_authority_settle(town: Variant, view, label: String) -> bool:
	var before: Dictionary = _silhouette_port_state(town, view)
	print("SILHOUETTE_GPU authority '", label, "' before ", str(before))
	var before_feet: Vector2 = before["plan_feet"]
	var committed_feet: Vector2 = before["committed_feet"]
	if before_feet == committed_feet:
		_expect(false, "%s: stale-port diagnosis disproved - plan feet already matched committed feet before the authority tick (%s)" % [label, str(before)])
		return false
	var step: Dictionary = town.step_tick()
	_expect(bool(step.get("ok", false)), "%s: zero-input authority step_tick failed: %s" % [label, str(step)])
	if not bool(step.get("ok", false)):
		return false
	for _tick in range(12):
		view._process(1.0 / 30.0)
	var after: Dictionary = _silhouette_port_state(town, view)
	print("SILHOUETTE_GPU authority '", label, "' after ", str(after))
	var after_feet: Vector2 = after["plan_feet"]
	var after_committed: Vector2 = after["committed_feet"]
	if after_feet != after_committed:
		_expect(false, "%s: plan feet anchor did not converge to the committed feet after the authority tick (%s)" % [label, str(after)])
		return false
	return true


## Port/plan/reveal-row evidence for the authority settle: committed hero feet,
## port snapshot tick, presentation frame tick, plan town/ranger feet_anchor,
## tree_east cover over the hero in the plan, and the tree_east reveal row's
## actor keys and weight. Read through the same port the presenter consumes.
func _silhouette_port_state(town: Variant, view) -> Dictionary:
	var state := {"committed_feet": town.hero_world_position(),
		"snapshot_tick": -1, "frame_tick": -1, "plan_ok": false,
		"plan_feet": Vector2.INF, "tree_east_cover": -1.0,
		"tree_row_actors": [], "tree_row_weight": -1.0}
	var runtime: Variant = view._presentation_runtime
	if not runtime is Object:
		return state
	var port: Variant = runtime.get("presentation_port")
	if port == null:
		return state
	var latest_snapshot: Variant = port.get("latest_snapshot")
	if latest_snapshot != null:
		state["snapshot_tick"] = int(latest_snapshot.get("tick"))
	var frame: Variant = port.get("latest_frame")
	if frame != null:
		state["frame_tick"] = int(frame.get("tick"))
	var plan_result: Dictionary = port.latest_occlusion_plan()
	if bool(plan_result.get("ok", false)):
		state["plan_ok"] = true
		var plan: Variant = plan_result.get("value", null)
		for entry: Dictionary in plan.entries():
			if String(entry.get("stable_id", "")) == "town/ranger":
				state["plan_feet"] = entry.get("feet_anchor", Vector2.INF)
		for occluder: Dictionary in plan.occluders_of("town/ranger"):
			if String(occluder.get("stable_id", "")) == "town/native/tree_east":
				state["tree_east_cover"] = float(occluder.get("cover_fraction", -1.0))
	var rows: Dictionary = (view.occlusion_report().get("paired_reveal", {}) as Dictionary)
	var tree_row: Dictionary = (rows.get("town/native/tree_east", {}) as Dictionary)
	if not tree_row.is_empty():
		var actors: Dictionary = (tree_row.get("actors", {}) as Dictionary)
		state["tree_row_actors"] = actors.keys()
		state["tree_row_weight"] = float(tree_row.get("weight", -1.0))
	return state


## Frozen capture: the tree is paused (or about to be bracketed by two process
## frames anyway), so two process frames guarantee the toggled state has been
## drawn; frame_post_draw never fires while paused.
func _silhouette_capture(view, capture_name: String) -> Image:
	await process_frame
	await process_frame
	var image: Image = view.world_viewport.get_texture().get_image()
	_expect(image != null and not image.is_empty(), "silhouette GPU: capture returned no pixels: " + capture_name)
	if image != null and not image.is_empty():
		var path := output_dir.path_join(capture_name)
		_expect(image.save_png(path) == OK, "silhouette GPU: capture write failed: " + capture_name)
		captures.append({"name": capture_name, "sha256": FileAccess.get_sha256(path)})
	return image


## The paired reveal row the covering hero opens. Mira stands SOUTH of
## tree_east's baseline - in front of it - so she can never be its covered
## subject; the honest live row names the hero alone.
func _paired_pair_row(view) -> Dictionary:
	var report: Dictionary = view.occlusion_report()
	for occluder_id: String in (report.get("paired_reveal", {}) as Dictionary).keys():
		var row: Dictionary = (report.get("paired_reveal", {}) as Dictionary)[occluder_id]
		if (row.get("actors", {}) as Dictionary).has("town/ranger"):
			return {"id": occluder_id, "row": row}
	return {}


func _paired_expect_pair_row(pair_row: Dictionary) -> void:
	_expect(bool(pair_row.get("open", false)) and absf(float(pair_row.get("weight", 0.0)) - 1.0) < 0.001,
		"paired GPU: pair row must sit at full reveal weight")
	_expect(String(pair_row.get("policy", "")) == "paired_reveal", "paired GPU: pair row must carry the whole-object policy")
	var pair_actors: Dictionary = pair_row.get("actors", {})
	_expect(int(pair_actors.size()) == 1 and pair_actors.has("town/ranger"),
		"paired GPU: the front-side resident must not be a covered subject")


## Captures one stage's full frame-matched reference set under the frozen pose
## and runs the stage audit. Capture order matters: nopiece with materials
## attached (the hidden piece's own material never shades), then materials
## detached for off/R. R lifts the pair actors to piece.z_index + 1 - above
## the native piece, still BELOW foreground marker layers, preserving their
## mutual order (equal z keeps the sort); z+1000 would jump the markers and
## corrupt the reference. Materials are restored before L so other open
## pieces' clears match nopiece exactly. Returns the images for cross-stage
## checks.
func _silhouette_stage(view, stage: String, piece: Sprite2D, slot_actors: Array, expect_open: bool = true) -> Dictionary:
	var hero: Sprite2D = view._hero_sprite
	var mira: Sprite2D = (view._resident_views.get("mira") as Dictionary)["node"] as Sprite2D
	var cover: Image = await _silhouette_capture(view, stage + "_cover.png")
	piece.visible = false
	var nopiece: Image = await _silhouette_capture(view, stage + "_nopiece.png")
	piece.visible = true
	var detached := _silhouette_detach_materials(view)
	var off: Image = await _silhouette_capture(view, stage + "_off.png")
	var lift := piece.z_index + 1
	var lifted_pair := [hero, mira]
	var original_z: Array = []
	for actor: Sprite2D in lifted_pair:
		original_z.append(actor.z_index)
		actor.z_index = lift
	var actors_front: Image = await _silhouette_capture(view, stage + "_actors_front.png")
	for index in range(lifted_pair.size()):
		(lifted_pair[index] as Sprite2D).z_index = original_z[index]
	_silhouette_diag_front_layers(view, piece, stage)
	_silhouette_restore_materials(detached)
	piece.visible = false
	hero.visible = false
	mira.visible = false
	var backing: Image = await _silhouette_capture(view, stage + "_backing.png")
	hero.visible = true
	mira.visible = true
	piece.visible = true
	var bracket: Image = await _silhouette_capture(view, stage + "_bracket.png")
	var images := {"cover": cover, "nopiece": nopiece, "off": off,
		"actors_front": actors_front, "backing": backing, "bracket": bracket}
	_silhouette_save_crop(cover, piece, stage)
	_paired_stage_checks(view, stage, images, piece, expect_open)
	return images


## The production-reset stage: one live capture plus its materials-detached
## reference; they must be identical everywhere (zero-slot identity).
func _silhouette_reset_stage(view, stage: String) -> Dictionary:
	var live: Image = await _silhouette_capture(view, stage + "_live.png")
	var detached := _silhouette_detach_materials(view)
	var off: Image = await _silhouette_capture(view, stage + "_off.png")
	_silhouette_restore_materials(detached)
	if live == null or live.is_empty() or off == null or off.is_empty():
		_expect(false, stage + ": reset reference captures missing")
		return {"live": live, "off": off}
	var frame := Rect2(Vector2.ZERO, Vector2(live.get_width(), live.get_height()))
	var identity := _silhouette_diff_in(live, off, frame)
	_expect(int(identity["count"]) == 0,
		"silhouette GPU: reset identity failed: %d pixels differ from the materials-off reference (first %s)" % [int(identity["count"]), str(identity["first"])])
	print("SILHOUETTE_GPU stage '", stage, "' reset_identity_diff=", identity["count"])
	return {"live": live, "off": off}


## Whole-object stage audit, entirely from rendered references:
## - bracket == cover everywhere (the pose was truly frozen);
## - cover vs off differs ONLY inside the tested piece's viewport rect and
##   any other currently-open piece's rect (their reveals differ legally);
## - every OPAQUE texel of an open piece must equal the authored blend
##   off*a + nopiece*(1-a), where a is the measured maximum alpha of the
##   baked variant texture - the reveal endpoint is measured, never invented;
## - transparent piece texels never change (pair members share RGB geometry);
## - a closed piece restores its exact opaque pixels inside its rect.
func _paired_stage_checks(view, stage: String, images: Dictionary, piece: Sprite2D, expect_open: bool) -> void:
	var cover: Image = images["cover"]
	var nopiece: Image = images["nopiece"]
	var off: Image = images["off"]
	var bracket: Image = images["bracket"]
	if cover == null or cover.is_empty() or nopiece == null or nopiece.is_empty() or off == null \
			or off.is_empty() or bracket == null or bracket.is_empty():
		_expect(false, stage + ": stage reference set incomplete")
		return
	var frame := Rect2(Vector2.ZERO, Vector2(cover.get_width(), cover.get_height()))
	var drift := _silhouette_diff_in(cover, bracket, frame)
	_expect(int(drift["count"]) == 0, "%s: frozen pose drifted across the reference set: %d pixels (first %s)" % [stage, int(drift["count"]), str(drift["first"])])

	var piece_cell: Rect2 = SilhouetteRevealScript.viewport_cell_rect(piece)
	_expect(piece_cell.has_area(), stage + ": piece lost its viewport rect")
	if not piece_cell.has_area():
		return
	var variant_path := String(piece.get_meta("reveal_variant_path", ""))
	var variant_img := Image.new()
	_expect(FileAccess.file_exists(variant_path) and variant_img.load(variant_path) == OK
		and not variant_img.is_empty(), stage + ": baked variant texture missing: " + variant_path)
	if variant_img.is_empty():
		return
	var opaque_img := piece.texture.get_image()
	var variant_alpha := 0.0
	for ty in range(variant_img.get_height()):
		for tx in range(variant_img.get_width()):
			variant_alpha = maxf(variant_alpha, variant_img.get_pixel(tx, ty).a)
	_expect(variant_alpha > 0.1 and variant_alpha < 1.0, stage + ": variant must be a real reveal bake")
	if variant_alpha <= 0.1 or variant_alpha >= 1.0:
		return

	var open_cells: Array = [piece_cell]
	var rows: Dictionary = view.occlusion_report().get("paired_reveal", {})
	for occluder_id: String in rows.keys():
		if not bool((rows[occluder_id] as Dictionary).get("open", false)):
			continue
		var node := view.world_presenter.native_binding_node(occluder_id) as Sprite2D
		if node == null or node == piece:
			continue
		var cell := SilhouetteRevealScript.viewport_cell_rect(node)
		if cell.has_area():
			open_cells.append(cell)
	var outside := _silhouette_diff_in(cover, off, frame, open_cells)
	_expect(int(outside["count"]) == 0,
		"%s: %d pixels changed outside the whole pieces' rects (first %s)" % [stage, int(outside["count"]), str(outside["first"])])

	var opened := 0
	var blend_fails := 0
	var transparent_fails := 0
	var closed_fails := 0
	for py in range(maxi(int(floor(piece_cell.position.y)), 0), mini(int(ceil(piece_cell.end.y)), cover.get_height())):
		for px in range(maxi(int(floor(piece_cell.position.x)), 0), mini(int(ceil(piece_cell.end.x)), cover.get_width())):
			var tx := clampi(int(floor((float(px) + 0.5 - piece_cell.position.x) / piece_cell.size.x * opaque_img.get_width())), 0, opaque_img.get_width() - 1)
			var ty := clampi(int(floor((float(py) + 0.5 - piece_cell.position.y) / piece_cell.size.y * opaque_img.get_height())), 0, opaque_img.get_height() - 1)
			var piece_opaque := opaque_img.get_pixel(tx, ty).a > 0.5
			var s := cover.get_pixel(px, py)
			var f := off.get_pixel(px, py)
			if not expect_open:
				if _color_error(s, f) > SIL_TOLERANCE:
					closed_fails += 1
					if closed_fails <= 6:
						failures.append("%s: closed piece pixel (%d,%d) diverged from its opaque draw" % [stage, px, py])
				continue
			if piece_opaque:
				var n := nopiece.get_pixel(px, py)
				var expected := Color(f.r * variant_alpha + n.r * (1.0 - variant_alpha),
					f.g * variant_alpha + n.g * (1.0 - variant_alpha),
					f.b * variant_alpha + n.b * (1.0 - variant_alpha), 1.0)
				if _color_error(s, f) > SIL_TOLERANCE:
					opened += 1
				if _color_error(s, expected) > 4.0 / 255.0:
					blend_fails += 1
					if blend_fails <= 6:
						failures.append("%s: whole-object blend pixel (%d,%d) cover=%s expected=%s" % [stage, px, py, str(s), str(expected)])
			elif _color_error(s, f) > SIL_TOLERANCE:
				transparent_fails += 1
	if expect_open:
		_expect(opened >= 50, "%s: the whole object looked inert: %d changed pixels" % [stage, opened])
		_expect(blend_fails == 0, "%s: %d piece pixels diverged from the authored blend" % [stage, blend_fails])
		_expect(transparent_fails == 0, "%s: %d transparent piece texels changed" % [stage, transparent_fails])
	else:
		_expect(closed_fails == 0, "%s: %d pixels kept a stale reveal after the hero left" % [stage, closed_fails])
	print("PAIR_GPU stage '", stage, "' opened=", opened, " blend_fails=", blend_fails,
		" transparent_fails=", transparent_fails, " closed_fails=", closed_fails,
		" variant_alpha=", variant_alpha, " drift=", drift["count"])


## The retired hero strip after the +8px move: pixels the flipped stage's
## hero cell covered, minus the moved stage's actor cells and any other open
## piece's cell (their own reveals legitimately differ), must show the intact
## scene again - no stale clear survives the placement change. The strip must
## contain real opaque FOREGROUND texels of the tested piece (verified
## unchanged), not just background area where nothing ever drew.
func _silhouette_check_retired(view, moved: Dictionary, pair_actors: Array, piece: Sprite2D, old_cell: Rect2, label: String) -> void:
	var cover: Image = moved["cover"]
	var off: Image = moved["off"]
	if cover == null or cover.is_empty() or off == null or off.is_empty() or not old_cell.has_area():
		_expect(false, label + ": retired strip audit missing captures")
		return
	var current_cells: Array = []
	for actor: Sprite2D in pair_actors:
		var cell: Rect2 = SilhouetteRevealScript.viewport_cell_rect(actor)
		if cell.has_area():
			current_cells.append(cell)
	var open_facts := _silhouette_open_facts(view, piece)
	var piece_facts: Dictionary = _silhouette_actor_facts([piece])[0]
	var retired := 0
	var retired_piece_opaque := 0
	var retired_skipped := 0
	var retired_fails := 0
	for py in range(maxi(int(floor(old_cell.position.y)), 0), mini(int(ceil(old_cell.end.y)), cover.get_height())):
		for px in range(maxi(int(floor(old_cell.position.x)), 0), mini(int(ceil(old_cell.end.x)), cover.get_width())):
			var center := Vector2(float(px) + 0.5, float(py) + 0.5)
			if not old_cell.has_point(center) or _silhouette_in_any(current_cells, center):
				continue
			if _silhouette_in_any(open_facts["other_piece_cells"], center):
				retired_skipped += 1
				continue
			retired += 1
			var piece_opaque := _silhouette_texel_opaque(piece_facts, center, SilhouetteRevealScript.OPAQUE_TEXEL_ALPHA)
			if piece_opaque:
				retired_piece_opaque += 1
			if _color_error(cover.get_pixel(px, py), off.get_pixel(px, py)) > SIL_TOLERANCE:
				retired_fails += 1
				if retired_fails <= 6:
					failures.append("%s: stale clear left behind at retired hero pixel (%d,%d)%s" % [label, px, py, " (opaque piece texel)" if piece_opaque else ""])
	_expect(retired >= 8, label + ": retired strip too small to prove the hole closed: %d" % retired)
	_expect(retired_piece_opaque >= 8, label + ": retired strip carried no opaque foreground texels: %d" % retired_piece_opaque)
	_expect(retired_fails == 0, "%s: %d retired pixels kept a stale clear" % [label, retired_fails])
	print("SILHOUETTE_GPU stage '", label, "' retired=", retired, " retired_piece_opaque=", retired_piece_opaque,
		" skipped_other_pieces=", retired_skipped, " retired_fails=", retired_fails)


## After protection removal the resident must sit fully behind the restored
## piece again - verified against pixels, never assumed from a count. Every
## piece-opaque texel where the RESIDENT draws at/above threshold and the
## still-eligible hero does not (outside the hero's active silhouette mask)
## must equal the same-stage intact reference exactly; texels where BOTH draw
## are legitimately revealed and must match the piece-hidden reference
## separately. Both classes carry their own failure lines; the closed class
## needs a positive verified count.
func _silhouette_check_resident_closed(stage: String, images: Dictionary, piece: Sprite2D, hero: Sprite2D, resident: Sprite2D, other_piece_cells: Array) -> void:
	var cover: Image = images["cover"]
	var off: Image = images["off"]
	var nopiece: Image = images["nopiece"]
	var piece_facts: Dictionary = _silhouette_actor_facts([piece])[0]
	var hero_facts: Dictionary = _silhouette_actor_facts([hero])[0]
	var resident_facts: Dictionary = _silhouette_actor_facts([resident])[0]
	var piece_cell: Rect2 = SilhouetteRevealScript.viewport_cell_rect(piece)
	var closed := 0
	var closed_fails := 0
	var revealed_overlap := 0
	var overlap_fails := 0
	for py in range(maxi(int(floor(piece_cell.position.y)), 0), mini(int(ceil(piece_cell.end.y)), cover.get_height())):
		for px in range(maxi(int(floor(piece_cell.position.x)), 0), mini(int(ceil(piece_cell.end.x)), cover.get_width())):
			var center := Vector2(float(px) + 0.5, float(py) + 0.5)
			if not piece_cell.has_point(center):
				continue
			if not _silhouette_texel_opaque(piece_facts, center, SilhouetteRevealScript.OPAQUE_TEXEL_ALPHA):
				continue
			if not _silhouette_texel_opaque(resident_facts, center, SilhouetteRevealScript.OPAQUE_TEXEL_ALPHA):
				continue
			if _silhouette_texel_opaque(hero_facts, center, SilhouetteRevealScript.OPAQUE_TEXEL_ALPHA):
				revealed_overlap += 1
				if _color_error(cover.get_pixel(px, py), nopiece.get_pixel(px, py)) > SIL_TOLERANCE:
					overlap_fails += 1
					if overlap_fails <= 6:
						failures.append("%s: revealed hero/resident overlap texel (%d,%d) must match the piece-hidden reference (cover=%s nopiece=%s)" % [stage, px, py, str(cover.get_pixel(px, py)), str(nopiece.get_pixel(px, py))])
				continue
			if _silhouette_in_any(other_piece_cells, center):
				continue
			closed += 1
			if _color_error(cover.get_pixel(px, py), off.get_pixel(px, py)) > SIL_TOLERANCE:
				closed_fails += 1
				if closed_fails <= 6:
					failures.append("%s: resident texel (%d,%d) shows through the closed piece (cover=%s off=%s)" % [stage, px, py, str(cover.get_pixel(px, py)), str(off.get_pixel(px, py))])
	_expect(closed >= 30, "%s: too few resident texels proved the piece closed over the resident: %d" % [stage, closed])
	_expect(closed_fails == 0, "%s: %d resident texels show through the closed piece" % [stage, closed_fails])
	_expect(overlap_fails == 0, "%s: %d revealed overlap texels missed the piece-hidden reference" % [stage, overlap_fails])
	print("SILHOUETTE_GPU stage '", stage, "' resident_closed=", closed, "/", closed_fails,
		" revealed_overlap=", revealed_overlap, "/", overlap_fails)


## Per-actor draw facts with the atlas image decoded exactly once.
func _silhouette_actor_facts(actors: Array) -> Array:
	var result: Array = []
	for actor: Sprite2D in actors:
		result.append({"sprite": actor,
			"cell": SilhouetteRevealScript.viewport_cell_rect(actor),
			"region": SilhouetteRevealScript.cell_region(actor),
			"image": actor.texture.get_image() if actor.texture != null else null})
	return result


## Actor cells from every OPEN reveal row (all of them feed the global
## outside-change check) and the cells of OTHER open pieces - the tested
## binding itself is deliberately omitted, otherwise the kept/retired audits
## would skip every pixel of the piece under test and pass vacuously.
func _silhouette_open_facts(view, target_piece: Sprite2D) -> Dictionary:
	var actor_cells: Array = []
	var other_piece_cells: Array = []
	var report: Dictionary = view.occlusion_report()
	for occluder_id: String in (report.get("silhouette_reveal", {}) as Dictionary).keys():
		var row: Dictionary = (report.get("silhouette_reveal", {}) as Dictionary)[occluder_id]
		if not bool(row.get("open", false)):
			continue
		for actor_id: String in (row.get("actors", {}) as Dictionary).keys():
			var sprite := _silhouette_actor_sprite(view, actor_id)
			if sprite != null:
				var cell: Rect2 = SilhouetteRevealScript.viewport_cell_rect(sprite)
				if cell.has_area():
					actor_cells.append(cell)
		var piece: Sprite2D = view.world_presenter.native_binding_node(occluder_id) as Sprite2D
		if piece != null and piece != target_piece:
			var piece_cell: Rect2 = SilhouetteRevealScript.viewport_cell_rect(piece)
			if piece_cell.has_area():
				other_piece_cells.append(piece_cell)
	return {"actor_cells": actor_cells, "other_piece_cells": other_piece_cells}


func _silhouette_actor_sprite(view, actor_id: String) -> Sprite2D:
	if actor_id == "town/ranger":
		return view._hero_sprite
	if actor_id.begins_with("town/npc/"):
		var entry: Variant = view._resident_views.get(actor_id.trim_prefix("town/npc/"))
		if entry is Dictionary:
			return (entry as Dictionary)["node"] as Sprite2D
	return null


## Classifies viewport pixel centers under the piece cell by the shared
## floor-then-mirror texel convention: "cleared" where ANY slot actor draws a
## texel at or above the shader's opacity threshold, "kept" where every slot
## actor draws below it. After protection removal the resident is not a slot
## actor, so its opaque texels are kept - exactly the restored-piece proof.
func _silhouette_classification(slot_actors: Array, piece: Sprite2D) -> Dictionary:
	var cleared: Array = []
	var kept: Array = []
	var piece_cell: Rect2 = SilhouetteRevealScript.viewport_cell_rect(piece)
	var actors := _silhouette_actor_facts(slot_actors)
	for py in range(int(floor(piece_cell.position.y)), int(ceil(piece_cell.end.y))):
		for px in range(int(floor(piece_cell.position.x)), int(ceil(piece_cell.end.x))):
			var center := Vector2(float(px) + 0.5, float(py) + 0.5)
			if not piece_cell.has_point(center):
				continue
			var any_opaque := false
			var in_any_cell := false
			for facts: Dictionary in actors:
				var cell: Rect2 = facts["cell"]
				if not cell.has_point(center):
					continue
				in_any_cell = true
				var image: Image = facts["image"]
				var texel: Vector2i = SilhouetteRevealScript.texel_at(cell, facts["region"], facts["sprite"], center)
				if image != null and texel.x >= 0 and texel.y >= 0 and texel.x < image.get_width() and texel.y < image.get_height() \
						and image.get_pixel(texel.x, texel.y).a >= SilhouetteRevealScript.OPAQUE_TEXEL_ALPHA:
					any_opaque = true
			if not in_any_cell:
				continue
			if any_opaque:
				cleared.append(center)
			else:
				kept.append(center)
	return {"cleared": cleared, "kept": kept}


## The texel alpha facts one pixel center samples from one sprite, or -1 when
## the center sits outside its cell / the atlas.
func _silhouette_texel_alpha(facts: Dictionary, center: Vector2) -> float:
	if not (facts["cell"] as Rect2).has_point(center):
		return -1.0
	var image: Image = facts["image"]
	if image == null:
		return -1.0
	var texel: Vector2i = SilhouetteRevealScript.texel_at(facts["cell"], facts["region"], facts["sprite"], center)
	if texel.x < 0 or texel.y < 0 or texel.x >= image.get_width() or texel.y >= image.get_height():
		return -1.0
	return image.get_pixel(texel.x, texel.y).a


func _silhouette_texel_opaque(facts: Dictionary, center: Vector2, threshold: float) -> bool:
	return _silhouette_texel_alpha(facts, center) >= threshold


## The intact-backed identity domain: piece cell pixel centers where the
## PIECE's own texel is opaque and some SLOT actor draws an at-threshold texel
## (those and only those does the reveal clear to backing). Each entry carries
## the combined opacity a_eff = 1-(1-a1)*(1-a2)*... over EVERY pair actor's
## texel alpha at that center - sub-threshold partners still composite in both
## the revealed frame and the lifted reference, and the product form keeps
## overlap pixels inside the identity instead of excluding them - plus how
## many pair actors are at/above threshold there (>=2 marks a verified
## overlap pixel, so the protected-pair stages can demand a positive overlap
## count instead of trusting the domain size). Transparent piece texels are
## deliberately outside the domain: their exactness error
## (1-a_eff)*(1-piece_alpha)*(B-L) is a nonexistent backing correction; they
## are verified unchanged against the intact scene instead.
func _silhouette_identity_domain(slot_actors: Array, pair_actors: Array, piece: Sprite2D) -> Array:
	var result: Array = []
	var piece_cell: Rect2 = SilhouetteRevealScript.viewport_cell_rect(piece)
	var piece_facts: Dictionary = _silhouette_actor_facts([piece])[0]
	var slots := _silhouette_actor_facts(slot_actors)
	var pair := _silhouette_actor_facts(pair_actors)
	for py in range(int(floor(piece_cell.position.y)), int(ceil(piece_cell.end.y))):
		for px in range(int(floor(piece_cell.position.x)), int(ceil(piece_cell.end.x))):
			var center := Vector2(float(px) + 0.5, float(py) + 0.5)
			if not piece_cell.has_point(center):
				continue
			if not _silhouette_texel_opaque(piece_facts, center, SilhouetteRevealScript.OPAQUE_TEXEL_ALPHA):
				continue
			var slot_opaque := false
			for facts: Dictionary in slots:
				if _silhouette_texel_opaque(facts, center, SilhouetteRevealScript.OPAQUE_TEXEL_ALPHA):
					slot_opaque = true
					break
			if not slot_opaque:
				continue
			var combined := 1.0
			var opaque_actors := 0
			for facts: Dictionary in pair:
				var alpha := _silhouette_texel_alpha(facts, center)
				if alpha >= SilhouetteRevealScript.OPAQUE_TEXEL_ALPHA:
					opaque_actors += 1
				if alpha > 0.0:
					combined *= (1.0 - alpha)
			result.append([center, 1.0 - combined, opaque_actors])
	return result


func _silhouette_in_any(cells: Array, center: Vector2) -> bool:
	for cell: Rect2 in cells:
		if cell.has_point(center):
			return true
	return false


## Count and first differing pixel of |a-b| over a bounds rect, optionally
## skipping pixels inside any of the given cells.
func _silhouette_diff_in(a: Image, b: Image, bounds: Rect2, skip: Array = []) -> Dictionary:
	var count := 0
	var first := ""
	for py in range(maxi(int(floor(bounds.position.y)), 0), mini(int(ceil(bounds.end.y)), a.get_height())):
		for px in range(maxi(int(floor(bounds.position.x)), 0), mini(int(ceil(bounds.end.x)), a.get_width())):
			var center := Vector2(float(px) + 0.5, float(py) + 0.5)
			if not bounds.has_point(center) or _silhouette_in_any(skip, center):
				continue
			if _color_error(a.get_pixel(px, py), b.get_pixel(px, py)) > SIL_TOLERANCE:
				count += 1
				if first == "":
					first = "(%d,%d)" % [px, py]
	return {"count": count, "first": first}


func _silhouette_merge_all(cells: Array) -> Rect2:
	var merged := Rect2()
	for cell: Rect2 in cells:
		merged = cell if merged == Rect2() else merged.merge(cell)
	return merged


## Detaches every silhouette reveal material; returns the pairs for restore.
func _silhouette_detach_materials(view) -> Array:
	var detached: Array = []
	var walk: Array[Node] = [view.world_presenter]
	while not walk.is_empty():
		var node: Node = walk.pop_back()
		if node is Sprite2D and (node as Sprite2D).material is ShaderMaterial \
				and ((node as Sprite2D).material as ShaderMaterial).shader == SilhouetteRevealScript.RevealShader:
			detached.append([node, (node as Sprite2D).material])
			(node as Sprite2D).material = null
		for child: Node in node.get_children():
			walk.push_back(child)
	return detached


func _silhouette_restore_materials(pairs: Array) -> void:
	for pair: Array in pairs:
		var sprite: Sprite2D = pair[0]
		var material: Material = pair[1]
		if is_instance_valid(sprite):
			sprite.material = material


## Explicit ordering evidence for the lifted R reference: every visible
## canvas item under the world presenter (SortRoot siblings included - the
## foreground marker lives in a sibling layer, not under SortRoot) whose
## EFFECTIVE inherited z is at/above the lift line and whose drawn geometry
## overlaps the piece cell. Effective z sums z_index up the CanvasItem chain
## while z_as_relative holds (the Godot default), so the marker's children -
## local z 0 nested under Foreground z 20 - inherit ~22 and are reported;
## a local-z scan would silently omit them. Sprite2D cells come from the
## shared helper; Line2D/Polygon2D markers expose their control points,
## transformed by the same canvas-inclusive transform. The R capture lifts
## the pair actors to the piece's local z + 1 - the actors share the piece's
## ancestor chain, so that is effective(piece) + 1 - and every layer listed
## here legitimately stays in front of the actors; an empty list means no
## overlay at all was found, and the line says so explicitly.
func _silhouette_diag_front_layers(view, piece: Sprite2D, stage: String) -> void:
	var lift := _silhouette_effective_z(piece, view.world_presenter) + 1
	var piece_cell: Rect2 = SilhouetteRevealScript.viewport_cell_rect(piece)
	var names: Array[String] = []
	var walk: Array[Node] = [view.world_presenter]
	while not walk.is_empty():
		var node: Node = walk.pop_back()
		var item := node as CanvasItem
		if item != null and item != piece and item.is_visible_in_tree():
			var effective := _silhouette_effective_z(item, view.world_presenter)
			if effective >= lift:
				var bounds := _silhouette_canvas_bounds(item)
				if bounds.has_area() and piece_cell.intersects(bounds):
					names.append("%s:%s(z=%d,eff=%d)" % [item.name, item.get_class(), item.z_index, effective])
		for child: Node in node.get_children():
			walk.push_back(child)
	print("SILHOUETTE_GPU diag ", stage, " lift=", lift, " front_overlays=", names.size(),
		" layers=", str(names))


## The item's z as the canvas actually sorts it: z_index summed along the
## CanvasItem ancestors (non-CanvasItem nodes contribute nothing) while
## z_as_relative holds; an ancestor with z_as_relative=false makes its own z
## absolute and ends the chain. The walk stops after including `stop`, so
## everything under the world presenter is compared on the same scale.
func _silhouette_effective_z(item: CanvasItem, stop: CanvasItem) -> int:
	var total := 0
	var node: Node = item
	while node != null:
		var canvas := node as CanvasItem
		if canvas != null:
			total += canvas.z_index
			if not canvas.z_as_relative or canvas == stop:
				break
		node = node.get_parent()
	return total


## The viewport-pixel bounds a canvas item draws: the shared sprite cell, or
## the transformed control points of a line/polygon marker; empty when the
## item exposes no geometry (an overlay class this diagnostic cannot bound).
func _silhouette_canvas_bounds(item: CanvasItem) -> Rect2:
	var sprite := item as Sprite2D
	if sprite != null:
		return SilhouetteRevealScript.viewport_cell_rect(sprite)
	var points: PackedVector2Array = []
	if item is Line2D:
		points = (item as Line2D).points
	elif item is Polygon2D:
		points = (item as Polygon2D).polygon
	else:
		return Rect2()
	if points.is_empty():
		return Rect2()
	var transform := item.get_global_transform_with_canvas()
	var bounds := Rect2(transform * points[0], Vector2.ZERO)
	for index in range(1, points.size()):
		bounds = bounds.expand(transform * points[index])
	return bounds


## Normal-scale crop of the pair piece cell plus 2x and 4x nearest
## enlargements, so the parent can inspect resident readability directly.
func _silhouette_save_crop(cover: Image, piece: Sprite2D, stage: String) -> void:
	var cell: Rect2 = SilhouetteRevealScript.viewport_cell_rect(piece)
	if not cell.has_area():
		return
	var rect := Rect2i(Vector2i(cell.position.floor()), Vector2i(ceil(cell.size)) + Vector2i(8, 8))
	rect = rect.intersection(Rect2i(Vector2i.ZERO, cover.get_size()))
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var crop := cover.get_region(rect)
	var path := output_dir.path_join(stage + "_pair_crop.png")
	_expect(crop.save_png(path) == OK, "silhouette GPU: pair crop write failed: " + stage)
	captures.append({"name": stage + "_pair_crop.png", "sha256": FileAccess.get_sha256(path)})
	for scale in [2, 4]:
		var enlarged := crop.duplicate()
		enlarged.resize(rect.size.x * scale, rect.size.y * scale, Image.INTERPOLATE_NEAREST)
		var scaled_path := output_dir.path_join("%s_pair_crop_x%d.png" % [stage, scale])
		_expect(enlarged.save_png(scaled_path) == OK, "silhouette GPU: enlarged crop write failed: " + stage)
		captures.append({"name": "%s_pair_crop_x%d.png" % [stage, scale], "sha256": FileAccess.get_sha256(scaled_path)})


## One diagnostic line per stage: live cells, regions, flips, sort order and
## texture sources, so any pixel failure can be reproduced by hand.
func _silhouette_diag(label: String, actors: Array, piece: Sprite2D, view) -> void:
	var parts := PackedStringArray()
	for actor: Sprite2D in actors:
		parts.append("%s cell=%s region=%s flips=%s,%s idx=%d modulate=%s tex=%s" % [actor.name,
			str(SilhouetteRevealScript.viewport_cell_rect(actor)), str(SilhouetteRevealScript.cell_region(actor)),
			str(actor.flip_h), str(actor.flip_v), actor.get_index(), str(actor.modulate), actor.texture.resource_path])
	if piece != null:
		parts.append("piece cell=%s region=%s idx=%d modulate=%s" % [str(SilhouetteRevealScript.viewport_cell_rect(piece)), str(SilhouetteRevealScript.cell_region(piece)), piece.get_index(), str(piece.modulate)])
	print("SILHOUETTE_GPU diag ", label, " camera=", view.camera_world_offset(), " ", " | ".join(parts))


func _color_error(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))

func _run_authored_reveal_gpu() -> void:
	if DisplayServer.get_name().to_lower().contains("headless"):
		printerr("GPU SKIP: authored reveal requires a rendering display")
		quit(2)
		return
	output_dir = _arg("--output=")
	if not output_dir.is_absolute_path() or DirAccess.dir_exists_absolute(output_dir):
		printerr("GPU REJECTED: fresh absolute --output directory required")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		printerr("GPU REJECTED: cannot create output directory")
		quit(2)
		return
	await _test_authored_reveal_gpu()
	var report := {"status": "pass" if failures.is_empty() else "fail",
		"errors": failures, "captures": captures,
		"fixture_note": "Synthetic renderer fixture only; NOT production art acceptance. Panels left to right: native full, controller, native revealed, native premultiplied midpoint."}
	var file := FileAccess.open(output_dir.path_join("REPORT.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	for failure in failures:
		printerr("- %s" % failure)
	print("AUTHORED_REVEAL_GPU ", report.status)
	quit(0 if failures.is_empty() else 1)

func _reveal_subject(id: String, baseline: float, rank: int, box: Rect2) -> Dictionary:
	return {"stable_id": id, "baseline_y": baseline, "rank": rank, "readability_box": box}

func _test_authored_reveal_gpu() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(384, 64)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var controller := AuthoredReveal.new()
	var entries: Array = []
	var masks: Array[Image] = []
	var plane := Image.create(96, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(96):
			plane.set_pixel(x, y, Color(0.22, 0.38, 0.56) if (x / 8 + y / 8) % 2 == 0 else Color(0.38, 0.55, 0.67))
	var base := Image.create(96, 64, false, Image.FORMAT_RGBA8)
	base.fill(Color.TRANSPARENT)
	base.fill_rect(Rect2i(34, 40, 8, 18), Color(0.72, 0.48, 0.23))
	for panel in range(4):
		_reveal_sprite(viewport, ImageTexture.create_from_image(plane), Vector2(panel * 96, 0), false)
		_reveal_sprite(viewport, ImageTexture.create_from_image(base), Vector2(panel * 96, 0), false)
	for part in range(2):
		var full := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		# Saturated RGB in transparent texels catches straight-alpha crossfades.
		full.fill(Color(1, 0, 1, 0))
		var color := Color(0.8, 0.35, 0.25) if part == 0 else Color(0.3, 0.75, 0.4)
		full.fill_rect(Rect2i(2, 2, 28, 28), color)
		full.fill_rect(Rect2i(2, 2, 6, 28), Color(color.r, color.g, color.b, 0.45))
		full.fill_rect(Rect2i(12, 0, 8, 32), Color(1, 0, 1, 0))
		var revealed := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		revealed.fill(Color(0, 0, 1, 0))
		revealed.fill_rect(Rect2i(2, 2, 4, 28), Color(color.r, color.g, color.b, 0.45))
		var midpoint := _reveal_midpoint(full, revealed)
		var position := Vector2(12, 8) if part == 0 else Vector2(28, 16)
		var id := "part/a" if part == 0 else "part/b"
		entries.append({"stable_id": id, "baseline_y": 50.0 + part * 10,
			"rank": 0, "art_box": Rect2(position, Vector2(32, 32))})
		masks.append(full)
		for panel in range(4):
			var image := full if panel < 2 else (revealed if panel == 2 else midpoint)
			var sprite := _reveal_sprite(viewport, ImageTexture.create_from_image(image), position + Vector2(panel * 96, 0), true)
			if panel == 1:
				var result := controller.register_piece(id, sprite, ImageTexture.create_from_image(revealed), full)
				_expect(bool(result.ok), "authored reveal registration failed: %s" % result)

	var hero := _reveal_subject("hero", 0.0, 0, Rect2(36, 26, 4, 4))
	var graze := _reveal_subject("graze", 0.0, 0, Rect2(41, 35, 40, 40))
	controller.update(entries, [], 1.0)
	var full_capture := await _reveal_capture(viewport, "authored_full.png")
	var identity_error := _reveal_panel_error(full_capture, 0)
	_expect(identity_error <= 2.0 / 255.0, "authored full/native RGBA identity error=%f" % identity_error)

	# AABB overlap inside a transparent mask gap must never request reveal.
	var gap := _reveal_subject("hero", 0.0, 0, Rect2(25, 12, 3, 4))
	controller.update(entries, [gap], 1.0)
	for state: Dictionary in controller.report().values():
		_expect(not state.open and state.coverage == 0.0, "transparent mask gap opened a reveal part")
	# Behind, equal-key, and exact equal-baseline tie-breaks use the shared sort relation.
	for case: Dictionary in [
		{"id": "hero", "y": 70.0, "rank": 0, "open": false},
		{"id": "part/a", "y": 50.0, "rank": 0, "open": false},
		{"id": "zzz", "y": 50.0, "rank": 0, "open": false},
		{"id": "aaa", "y": 50.0, "rank": 0, "open": true},
		{"id": "zzz", "y": 50.0, "rank": -1, "open": true},
		{"id": "aaa", "y": 50.0, "rank": 1, "open": false},
	]:
		controller.reset()
		controller.update(entries, [_reveal_subject(case.id, case.y, case.rank, hero.readability_box)], 1.0)
		_expect(bool(controller.report()["part/a"].open) == bool(case.open), "front/equal-baseline semantics failed: %s" % case)
	controller.reset()
	controller.update(entries, [hero, graze], AuthoredReveal.TRANSITION_SECONDS * 0.5)
	for state: Dictionary in controller.report().values():
		_expect(state.open and is_equal_approx(state.weight, 0.5) and state.coverage == 1.0, "hero plus graze must open both overlapping parts halfway")
	var transition := await _reveal_capture(viewport, "authored_transition.png")
	var midpoint_error := _reveal_panel_error(transition, 3)
	_expect(midpoint_error <= 3.0 / 255.0, "premultiplied midpoint/native reference error=%f" % midpoint_error)
	controller.update(entries, [hero, graze], AuthoredReveal.TRANSITION_SECONDS * 0.5)
	var revealed_capture := await _reveal_capture(viewport, "authored_revealed.png")
	var revealed_error := _reveal_panel_error(revealed_capture, 2)
	_expect(revealed_error <= 2.0 / 255.0, "revealed/native RGBA reference error=%f" % revealed_error)
	var under := revealed_capture.get_pixel(96 + 38, 28)
	_expect(_color_error(under, plane.get_pixel(38, 28)) <= 2.0 / 255.0, "two overlapping revealed parts did not expose underlying plane")
	for image: Image in [full_capture, transition, revealed_capture]:
		_expect(_color_error(image.get_pixel(96 + 38, 54), image.get_pixel(38, 54)) <= 2.0 / 255.0, "common base darkened during transition")
	# Mutate the caller's mask, then hold the actual transparent variant for
	# three wall-clock seconds. Coverage must still use the cached FULL mask.
	for mask: Image in masks:
		mask.fill(Color.TRANSPARENT)
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		controller.update(entries, [graze, hero], 1.0 / 60.0)
		for state: Dictionary in controller.report().values():
			_expect(state.open and state.weight == 1.0 and state.coverage == 1.0, "revealed state oscillated or lost immutable full-mask coverage")
		await process_frame
	var held := await _reveal_capture(viewport, "authored_held.png")
	_expect(_reveal_panel_error(held, 2) <= 2.0 / 255.0, "revealed render changed during three-second hold")
	print("AUTHORED_REVEAL_GPU synthetic_only identity_error=", identity_error,
		" midpoint_error=", midpoint_error, " revealed_error=", revealed_error,
		" hold_seconds=3 final_state=", controller.report())
	controller.clear()
	viewport.queue_free()
	await process_frame

func _reveal_sprite(viewport: SubViewport, texture: Texture2D, position: Vector2, tinted: bool) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = position
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if tinted:
		sprite.modulate = Color(0.8, 0.7, 0.9, 0.85)
		sprite.self_modulate = Color(0.9, 0.8, 0.7, 0.75)
	viewport.add_child(sprite)
	return sprite

func _reveal_midpoint(full: Image, revealed: Image) -> Image:
	var result := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var a := full.get_pixel(x, y)
			var b := revealed.get_pixel(x, y)
			var alpha := (a.a + b.a) * 0.5
			var rgb := (Vector3(a.r, a.g, a.b) * a.a + Vector3(b.r, b.g, b.b) * b.a) * 0.5
			rgb = rgb / alpha if alpha > 0.00001 else Vector3.ZERO
			result.set_pixel(x, y, Color(rgb.x, rgb.y, rgb.z, alpha))
	return result

func _reveal_panel_error(image: Image, reference: int) -> float:
	var error := 0.0
	for y in range(64):
		for x in range(96):
			error = maxf(error, _color_error(image.get_pixel(96 + x, y), image.get_pixel(reference * 96 + x, y)))
	return error

func _reveal_capture(viewport: SubViewport, name: String) -> Image:
	await _settle()
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	_expect(image != null and not image.is_empty(), "authored reveal capture returned no pixels")
	if image != null and not image.is_empty() and not output_dir.is_empty():
		var enlarged := image.duplicate() as Image
		enlarged.resize(image.get_width() * 3, image.get_height() * 3, Image.INTERPOLATE_NEAREST)
		var path := output_dir.path_join(name)
		_expect(enlarged.save_png(path) == OK, "authored reveal capture write failed: " + name)
		captures.append({"name": name, "sha256": FileAccess.get_sha256(path)})
	return image

func _capture_hamlet() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var hub := BaseHubScript.new()
	viewport.add_child(hub)
	hub._ready()
	var view := hub.get_hub_view()
	_expect(bool(hub.town_load_report.get("ok", false)), "GPU town must load native layers and actual actors")
	view.set_world_scale(2, Vector2(1280, 720))
	await _settle()
	await _save(viewport, "hamlet_before.png")
	view._process(0.51)
	await _save(viewport, "hamlet_after.png")
	viewport.queue_free()

func _capture_hearth() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view = HearthReturnViewScript.new()
	viewport.add_child(view)
	view.size = Vector2(640, 360)
	view.scale = Vector2(2.0, 2.0)
	view.set_review_time(0.0)
	await _settle()
	view._atmosphere_layer.visible = false
	var plate: CanvasItem = view.get_node_or_null("AtmosphereBackground")
	if plate != null:
		plate.visible = false
	await _save(viewport, "hearth_before.png")
	view._atmosphere_layer.visible = true
	if plate != null:
		plate.visible = true
	await _save(viewport, "hearth_after.png")
	viewport.queue_free()

func _capture_arena() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var preview := ArenaPreview.new()
	viewport.add_child(preview)
	await _settle()
	preview.atmosphere = false
	preview.queue_redraw()
	await _save(viewport, "arena_before.png")
	preview.atmosphere = true
	preview.queue_redraw()
	await _save(viewport, "arena_after.png")
	viewport.queue_free()

func _settle() -> void:
	await process_frame
	await process_frame

func _save(viewport: SubViewport, file_name: String) -> void:
	await _settle()
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	var path := output_dir.path_join(file_name)
	_expect(not image.is_empty() and image.save_png(path) == OK, "capture " + file_name)
	captures.append({"name":file_name, "width":image.get_width(), "height":image.get_height(), "sha256":FileAccess.get_sha256(path)})

func _arg(prefix: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if String(argument).begins_with(prefix):
			return String(argument).substr(prefix.length())
	return ""

func _has_arg(name: String) -> bool:
	for argument in OS.get_cmdline_user_args():
		if String(argument) == name:
			return true
	return false

class ArenaPreview:
	extends Node2D
	var view = ArenaWorldViewScript.new()
	var atmosphere := true
	var ground := load("res://art/production/p1/ground_refine_v01/ground.png") as Texture2D

	func _init() -> void:
		view.load_assets()
		view.begin_frame(Rect2(Vector2.ZERO, Vector2(1280, 720)), Vector2(430, 360), Rect2(Vector2(42, 190), Vector2(1196, 488)))

	func _draw() -> void:
		draw_set_transform_matrix(view.world_transform())
		if atmosphere:
			view.draw_ground(self)
		else:
			var region := view.visible_world_region().intersection(Rect2(Vector2.ZERO, Vector2(1024, 640)))
			draw_texture_rect_region(ground, Rect2(region.position.round(), region.size), region)
		view.draw_decals(self)
		view.draw_structure_shadows(self)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _test_presets() -> void:
	for preset in ["arena", "hamlet", "hearth"]:
		_expect(Atmosphere.preset_is_valid(preset), "preset %s is not registered" % preset)
	_expect(not Atmosphere.preset_is_valid("debug"), "unknown presets must not draw")
	var light := Atmosphere.warm_light(Vector2(10, 20), -2.0, 2.0)
	_expect(Vector2(light.position) == Vector2(10, 20), "warm light lost its position")
	_expect(float(light.radius) >= 4.0, "warm light radius is not floored")
	_expect(float(light.strength) <= 0.32, "warm light strength exceeds the restraint ceiling")
	var report := Atmosphere.atmosphere_report("arena", Rect2(Vector2.ZERO, Vector2(640, 360)), [light, {}, light])
	_expect(int(report.warm_lights.size()) == 2, "warm light report did not cap or reject malformed entries")

func _test_layer() -> void:
	var layer = AtmosphereLayerScript.new()
	layer.preset = "hamlet"
	layer.bounds = Rect2(Vector2.ZERO, Vector2(1024, 640))
	layer.warm_lights = [Atmosphere.warm_light(Vector2(504, 371), 53.0, 0.18)]
	root.add_child(layer)
	var report: Dictionary = layer.atmosphere_report()
	_expect(bool(report.valid), "layer did not accept a registered preset")
	_expect(layer.get_child_count() == 0, "atmosphere layer must not create children")
	_expect(layer is Node2D, "atmosphere layer must remain a Node2D drawing primitive")

func _test_hamlet() -> void:
	var hub := BaseHubScript.new()
	root.add_child(hub)
	hub._ready()
	var view := hub.get_hub_view()
	_expect(bool(hub.town_load_report.get("ok", false)), "town: native assets did not load")
	var audit := view.render_audit()
	_expect(audit.runtime_background_patches == 0 and audit.native_count == (TownExpectations.load_expectations().sort_ids as Array).size(), "town: native environmental art count must equal the scene-authored SortRoot visuals")
	_expect(view.world_presenter.get_parent().get_parent() == view.world_viewport, "town: shared world layers escaped the SubViewport")
	_expect(view.world_presenter.ground_layer.z_index < view.world_presenter.sort_root.z_index, "town: ground covered native buildings")
	_expect(audit.unknown_underplate == "opaque" and not audit.supports_fade and audit.supports_cutaway,
		"town: opaque whole-object underplate capabilities changed")
	hub.free()

func _test_arena() -> void:
	var view = ArenaWorldViewScript.new()
	_expect(view.load_assets(), "arena: published assets did not load")
	view.begin_frame(Rect2(Vector2.ZERO, Vector2(1280, 720)), Vector2(430, 360), Rect2(Vector2(42, 190), Vector2(1196, 488)))
	var lights: Array = view.atmosphere_warm_lights()
	var report: Dictionary = view.atmosphere_report()
	_expect(lights.size() == 2, "arena: expected tower and ruin light sources")
	_expect(lights[0].position == view.tower_feet_world(), "arena: tower light must follow authored placement")
	_expect(lights[1].position == view.ruin_light_feet_world(), "arena: ruin light must follow authored placement")
	_expect(bool(report.world_lights_clipped), "arena: a light source leaves the authored world")
	_expect(Rect2(Vector2.ZERO, Vector2(1024, 640)).encloses(report.rect), "arena: atmosphere report leaves the world")
	for light in lights:
		_expect(float(light.strength) <= 0.20, "arena: warm strength exceeds the restrained combat budget")

func _test_hearth() -> void:
	var view = HearthReturnViewScript.new()
	root.add_child(view)
	_expect(view.load_scene(), "hearth: published return scene did not load")
	var scene: Dictionary = view.scene_report()
	var atmosphere: Dictionary = scene.atmosphere
	_expect(bool(atmosphere.valid), "hearth: atmosphere is invalid")
	_expect(int(atmosphere.warm_lights.size()) == 1, "hearth: expected exactly one fire-side warm light")
	_expect(view._atmosphere_layer.get_child_count() == 0, "hearth: atmosphere layer created children")
	_expect(view._atmosphere_layer.z_index == 0, "hearth: atmosphere must stay above the parent background")
	for layer: Dictionary in view._layers:
		_expect(layer.node.z_index > view._atmosphere_layer.z_index, "hearth: published actor must stay above atmosphere")
	_expect(view.get_child(0) == view._art_root, "hearth: all artwork must share the aspect-preserving root")
	_expect(view._art_root.get_child(0) == view._atmosphere_layer, "hearth: atmosphere was not inserted before published sprites")
	for layer: Dictionary in view._layers:
		_expect(layer.node.get_parent() == view._art_root, "hearth: actors must use the same transform as atmosphere")
