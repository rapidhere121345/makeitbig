extends SceneTree
## Standalone contract check for the hamlet life runtime pass: the published
## resident work cycles (src/presentation/hamlet_life_animation.gd) rendered by
## the hub view (src/presentation/town_presenter.gd).
##
## Run it on its own:
##   godot --headless --path . --script res://tests/unit/test_hamlet_life_animation.gd
##
## It reads the published package from disk, drives the view with the same calls
## the hub makes, and never starts a run, ticks a sim or writes gameplay state.
## The exact approved numbers - five 48x48 cycles, 4 distinct frames, integer
## work speeds 3/2/2/2/4, the three socket offsets and bands, the 12 + 2 amber
## palette - are pinned here on purpose: this file is the gate that catches a
## drifted sheet before the hub draws it.

const TownExpectations = preload("res://tests/helpers/town_scene_expectations.gd")
const HamletLifeAnimationScript = preload("res://src/presentation/hamlet_life_animation.gd")
const BaseHubScript = preload("res://src/presentation/base_hub_screen.gd")

const LIFE_DIR := "res://art/production/p1/hamlet_life_v01/"
const LIFE_ATLAS_PATH := LIFE_DIR + "atlas.json"
const LIFE_MANIFEST_PATH := LIFE_DIR + "life.json"
const RESIDENTS_PNG := LIFE_DIR + "residents.png"
const EFFECT_ATLAS_PATH := "res://art/production/p1/title_life_v01/atlas.json"
const EFFECT_TEXTURES := {
	"life.fire": "res://art/production/p1/title_life_v01/fire.png",
	"life.steam": "res://art/production/p1/title_life_v01/steam.png",
}

## The published resident contracts: work speed, layout feet and published phase.
const RESIDENT_FPS := {"mira": 3.0, "iven": 2.0, "taren": 2.0, "leia": 2.0, "oren": 4.0}
const RESIDENT_FEET := {
	"mira": Vector2(655, 426),
	"iven": Vector2(322, 333),
	"taren": Vector2(330, 494),
	"leia": Vector2(459, 406),
	"oren": Vector2(763, 477),
}
const RESIDENT_PLACEMENTS: Array[String] = ["mira", "iven", "taren", "leia", "oren"]
const RESIDENT_FRAMES := 4

## The three approved sockets, as life.json publishes them.
const SOCKETS := [
	{"id": "hearth_cook_fire", "owner": "hearth", "clip": "life.fire", "offset": Vector2(-80, -31), "layer": "lower"},
	{"id": "tower_exhaust", "owner": "hearth", "clip": "life.steam", "offset": Vector2(136, -101), "layer": "upper"},
	## The forge's live flame spans its authored rows 93..102, north of the
	## stand's split row 102, so the socket rides the upper band with the owner.
	{"id": "forge_fire", "owner": "forge", "clip": "life.fire", "offset": Vector2(28, -34), "layer": "upper"},
]
const STATION_FEET := {"hearth": Vector2(584, 402), "forge": Vector2(756, 468)}
const EFFECT_FPS := {"life.fire": 4.0, "life.steam": 2.0}
const EFFECT_CELLS := {"life.fire": Vector2i(8, 10), "life.steam": Vector2i(12, 18)}
const EFFECT_ANCHORS := {"life.fire": Vector2i(4, 9), "life.steam": Vector2i(6, 17)}
const EFFECT_FRAMES := 4
## Twelve approved colours plus the two amber accents the concept carries.
const PALETTE_SIZE := 14
const RENDER_RATES: Array[int] = [30, 60, 144]
## The published sheet, in cells, and the world field the hub draws into.
const SHEET_SIZE := Vector2i(192, 240)
const RESIDENT_CELL := Vector2i(48, 48)
const RESIDENT_ANCHOR := Vector2i(24, 44)
const FIXTURE_CELL := Vector2i(40, 48)
const FIXTURE_ANCHOR := Vector2i(20, 44)

var failures: Array[String] = []
var _package: Dictionary = {}


func _initialize() -> void:
	_package = _read_package()
	_test_published_package()
	_test_frame_wrap()
	_test_render_rates()
	_test_loader_and_palette()
	_test_formal_town_residents()
	_test_strict_refusals()
	_test_no_gameplay_writes()
	_print_harness_report()
	if failures.is_empty():
		print("PASS  test_hamlet_life_animation.gd: five work cycles and three sockets")
		quit(0)
		return
	printerr("%d life check(s) failed:" % failures.size())
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


## ---------------------------------------------------------------- the package

func _test_formal_town_residents() -> void:
	var hub := BaseHubScript.new()
	root.add_child(hub)
	hub._ready()
	var view := hub.get_hub_view()
	var town = hub.get_town_runtime()
	_expect(bool(hub.town_load_report.get("ok", false)), "town life: native scene failed to load")
	var report: Dictionary = view.life_report()
	_expect(report.residents.size() == 5 and report.effects.is_empty(), "town life: actual five residents missing or old socket overlay survived")
	var frames := {}
	for resident: Dictionary in report.residents:
		var id := String(resident.id)
		_expect(resident.feet == town.resident_positions()[id], "town life: registry feet and drawn feet differ " + id)
		_expect(resident.clip == "%s.south.work" % id and resident.frames == 4 and String(resident.texture).begins_with(HamletLifeAnimationScript.LIFE_DIR), "town life: resident uses a static substitute " + id)
		var node := view.world_presenter._actor_views.get("town/npc/" + id) as Sprite2D
		_expect(node != null and node.get_parent() == view.world_presenter.sort_root and node.scale == Vector2.ONE, "town life: resident left shared feet sort " + id)
		_expect(node.offset == -Vector2(RESIDENT_ANCHOR) and node.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "town life: resident anchor/filter changed " + id)
		frames[id] = resident.frame
	view._process(0.51)
	var changed := 0
	for resident: Dictionary in view.life_report().residents:
		if resident.frame != frames[resident.id]: changed += 1
	_expect(changed == 5, "town life: every resident must advance its actual cycle")
	var audit := view.render_audit()
	_expect(audit.native_count == (TownExpectations.load_expectations().sort_ids as Array).size() and audit.runtime_background_patches == 0, "town life: whole-object count must equal the scene-authored SortRoot visuals, or backing changed")
	for person: String in RESIDENT_PLACEMENTS:
		var generated_clip := person + ".south.work"
		_expect(view.life_animation.clip_unique_frames(generated_clip) == 4, "generated town resident needs four distinct work poses: " + person)
	_shutdown_hub(hub)


func _read_package() -> Dictionary:
	return {
		"atlas": _read_json(LIFE_ATLAS_PATH),
		"manifest": _read_json(LIFE_MANIFEST_PATH),
		"effects": _read_json(EFFECT_ATLAS_PATH),
	}


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	_expect(file != null, "package: %s is not published" % path)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _new_life():
	var life = HamletLifeAnimationScript.new()
	life.configure(_package.atlas, _package.manifest, _package.effects)
	return life


func _test_published_package() -> void:
	var life = _new_life()
	_expect(life.has_real_art(), "package: the published resident sheet did not load")
	_expect(life.life_ready(), "package: the published socket sheet did not load")
	_expect(life.pending_reasons().is_empty(), "package: a published package reports %s" % [life.pending_reasons()])
	if not life.has_real_art():
		return

	for placement: String in RESIDENT_PLACEMENTS:
		var clip := "%s.south.work" % placement
		var fps: float = RESIDENT_FPS[placement]
		_expect(life.clip_frame_count(clip) == RESIDENT_FRAMES, "%s publishes %d frames, the approved cycle is %d" % [clip, life.clip_frame_count(clip), RESIDENT_FRAMES])
		_expect(life.clip_unique_frames(clip) == RESIDENT_FRAMES, "%s publishes %d distinct cells, the approved cycle is %d real poses" % [clip, life.clip_unique_frames(clip), RESIDENT_FRAMES])
		_expect(is_equal_approx(life.clip_fps(clip), fps), "%s runs at %.2f fps, the approved work speed is %.0f" % [clip, life.clip_fps(clip), fps])
		_expect(Vector2i(life.clip_entry(clip).get("cell", Vector2i.ZERO)) == RESIDENT_CELL, "%s is cut from %s cells, the approved cell is %s" % [clip, life.clip_entry(clip).get("cell", Vector2i.ZERO), RESIDENT_CELL])
		_expect(life.clip_entry(clip).get("anchor", Vector2.ZERO) == Vector2(RESIDENT_ANCHOR), "%s is anchored at %s, the approved anchor is %s" % [clip, life.clip_entry(clip).get("anchor", Vector2.ZERO), Vector2(RESIDENT_ANCHOR)])
		_expect(life.clip_texture_path(clip) == RESIDENTS_PNG, "%s is cut from %s" % [clip, life.clip_texture_path(clip)])
		var seen := {}
		for index in RESIDENT_FRAMES:
			var frame := life.frame_at(clip, (float(index) + 0.5) / fps)
			_expect(not frame.is_empty(), "%s shows nothing in its own frame window %d" % [clip, index])
			if frame.is_empty():
				continue
			_expect(int(frame["index"]) == index, "%s shows frame %d where %d belongs" % [clip, int(frame["index"]), index])
			var cell: Rect2 = frame["rect"]
			seen[cell] = true
			_expect(Rect2(Vector2.ZERO, Vector2(SHEET_SIZE)).encloses(cell), "%s samples %s outside the published sheet" % [clip, cell])
		_expect(seen.size() == RESIDENT_FRAMES, "%s draws %d distinct cells across its cycle" % [clip, seen.size()])

	var residents: Array = life.life_report()["residents"]
	_expect(residents.size() == RESIDENT_PLACEMENTS.size(), "package: %d residents are published" % residents.size())
	var phase_values := {}
	for entry: Dictionary in residents:
		var placement := String(entry["id"])
		_expect(RESIDENT_FEET.has(placement), "package: %s is not a published hamlet resident" % placement)
		if not RESIDENT_FEET.has(placement):
			continue
		var clip := String(entry["clip"])
		_expect(clip == "%s.south.work" % placement, "package: %s runs %s" % [placement, clip])
		phase_values[float(entry["phase"])] = true
		# The published phase is what the cycle is offset by, no more and no less.
		var expected := int(floor(float(entry["phase"]) * RESIDENT_FPS[placement])) % RESIDENT_FRAMES
		_expect(int(entry["frame"]) == expected, "package: %s reports frame %d at time zero, its phase %s starts it on frame %d" % [placement, int(entry["frame"]), entry["phase"], expected])
		_expect(life.frame_index(clip, float(entry["phase"])) == expected, "%s must start its cycle at phase %s (frame %d, got %d)" % [clip, entry["phase"], expected, life.frame_index(clip, float(entry["phase"]))])
	_expect(phase_values.size() >= 3, "package: the residents are published on %d phases, so they pulse in lockstep" % phase_values.size())

	var effects: Array = life.life_report()["effects"]
	_expect(effects.size() == SOCKETS.size(), "package: %d sockets are published, the approved count is %d" % [effects.size(), SOCKETS.size()])
	var by_id := {}
	for entry: Dictionary in effects:
		by_id[String(entry["id"])] = entry
	for published: Dictionary in SOCKETS:
		var entry: Dictionary = by_id.get(String(published.id), {})
		_expect(not entry.is_empty(), "package: socket %s is not published" % published.id)
		if entry.is_empty():
			continue
		_expect(String(entry["owner"]) == String(published.owner), "socket %s belongs to %s, the approved owner is %s" % [published.id, entry["owner"], published.owner])
		_expect(String(entry["clip"]) == String(published.clip), "socket %s plays %s, the approved clip is %s" % [published.id, entry["clip"], published.clip])
		_expect(entry["offset"] == published.offset, "socket %s stands %s from its owner's feet, the approved offset is %s" % [published.id, entry["offset"], published.offset])
		_expect(String(entry["layer"]) == String(published.layer), "socket %s is drawn on the %s band, the approved band is %s" % [published.id, entry["layer"], published.layer])
		var clip := String(published.clip)
		_expect((entry["rect"] as Rect2).size == Vector2(EFFECT_CELLS[clip]), "socket %s reads a %s cell, the approved cell is %s" % [published.id, (entry["rect"] as Rect2).size, EFFECT_CELLS[clip]])
		_expect(entry["anchor"] == Vector2(EFFECT_ANCHORS[clip]), "socket %s is anchored at %s, the approved anchor is %s" % [published.id, entry["anchor"], Vector2(EFFECT_ANCHORS[clip])])
		_expect(is_equal_approx(float(entry["fps"]), EFFECT_FPS[clip]), "socket %s runs at %.2f fps, the approved sheet runs at %.0f" % [published.id, float(entry["fps"]), EFFECT_FPS[clip]])
		_expect(int(entry["frames"]) == EFFECT_FRAMES and int(entry["unique_frames"]) == EFFECT_FRAMES, "socket %s publishes %d frames of which %d are distinct" % [published.id, int(entry["frames"]), int(entry["unique_frames"])])
		_expect(String(entry["texture"]) == EFFECT_TEXTURES[clip], "socket %s is cut from %s" % [published.id, entry["texture"]])


func _test_frame_wrap() -> void:
	var life = _new_life()
	_expect(life.frame_index("nosuch.south.work", 1.0) == -1, "wrap: an unpublished clip must report no frame")
	_expect(life.frame_at("nosuch.south.work", 1.0).is_empty(), "wrap: an unpublished clip must show nothing")
	for placement: String in RESIDENT_PLACEMENTS:
		var clip := "%s.south.work" % placement
		var fps: float = RESIDENT_FPS[placement]
		var count := life.clip_frame_count(clip)
		_expect(life.frame_index(clip, 0.0) == 0, "%s must open on its first frame" % clip)
		_expect(life.frame_index(clip, -12.5) == 0, "%s must clamp a clock before its first frame instead of wrapping backwards" % clip)
		_expect(life.frame_index(clip, (float(count) - 0.001) / fps) == count - 1, "%s must hold its last frame to the end of the period" % clip)
		for period in range(1, 5):
			for step in count:
				var centre := float(period * count + step) / fps + 0.5 / fps
				_expect(life.frame_index(clip, centre) == step, "%s wraps to frame %d where %d belongs (period %d)" % [clip, life.frame_index(clip, centre), step, period])
		# An exactly binary cadence lands on its boundaries without a push.
		if is_equal_approx(fps, 2.0) or is_equal_approx(fps, 4.0):
			for step in range(1, 5):
				_expect(life.frame_index(clip, float(step) / fps) == step % count, "%s must advance on the exact %s s boundary" % [clip, float(step) / fps])
	# Purity: a caller may not reach the reader's own frame state.
	var shared := life.frame_at("oren.south.work", 0.5)
	shared["index"] = 99
	_expect(int(life.frame_at("oren.south.work", 0.5)["index"]) != 99, "wrap: frame_at handed out shared state")
	var clock = _new_life()
	clock.tick(-4.0)
	_expect(is_equal_approx(clock.life_time(), 0.0), "wrap: a negative delta must not rewind the life clock")
	clock.tick(0.25)
	_expect(is_equal_approx(clock.life_time(), 0.25), "wrap: the life clock must follow delta")


func _test_render_rates() -> void:
	var clip := "oren.south.work"
	var fps: float = RESIDENT_FPS["oren"]
	var count := RESIDENT_FRAMES
	for rate: int in RENDER_RATES:
		var life = _new_life()
		var delta := 1.0 / float(rate)
		var previous := -1
		var advances := 0
		for frame in range(rate * 3):
			life.tick(delta)
			var index := life.frame_index(clip, life.life_time())
			if previous >= 0:
				# A frame may be held across samples or advance by exactly one
				# step: no rate may ever skip a pose or run backwards.
				_expect(index == previous or index == (previous + 1) % count, "%dHz: %s jumped from frame %d to %d" % [rate, clip, previous, index])
				if index != previous:
					advances += 1
			previous = index
		# Three seconds of a 4 fps cycle is twelve steps, whatever the render rate.
		_expect(absi(advances - int(round(3.0 * fps))) <= 1, "%dHz: three seconds advanced the cycle %d times, the cadence is %d" % [rate, advances, int(round(3.0 * fps))])
		# And the frame depends on the clock alone, so the same instant draws the
		# same pose at every rate.
		life.set_life_time_for_test(2.0)
		_expect(life.frame_index(clip, life.life_time()) == 0, "%dHz: 2.000 s of a 4 fps cycle must land on its first frame" % rate)
		life.set_life_time_for_test(1.25)
		_expect(life.frame_index(clip, life.life_time()) == 1, "%dHz: 1.250 s of a 4 fps cycle must land on its second frame" % rate)
		# The accumulated clock must cross the same boundaries the exact clock
		# does: a full second of 1/rate steps may never sit a hair short of the
		# boundary and hold a pose the render rate alone decided to hold.
		var accumulated = _new_life()
		for step in rate:
			accumulated.tick(delta)
		_expect(accumulated.frame_index(clip, accumulated.life_time()) == accumulated.frame_index(clip, 1.0), "%dHz: one accumulated second reads frame %d, the exact second reads frame %d" % [rate, accumulated.frame_index(clip, accumulated.life_time()), accumulated.frame_index(clip, 1.0)])


func _test_loader_and_palette() -> void:
	var life = _new_life()
	var sheet := life.load_texture_at(RESIDENTS_PNG, SHEET_SIZE)
	_expect(sheet != null, "loader: the published sheet does not load at its declared size")
	if sheet != null:
		_expect(Vector2i(sheet.get_size()) == SHEET_SIZE, "loader: the sheet loads at %s, the atlas declares %s" % [sheet.get_size(), SHEET_SIZE])
		# A shipped build keeps only the imported texture: the loader has to ask
		# ResourceLoader first, and the raw decode is only the same-machine path.
		if ResourceLoader.exists(RESIDENTS_PNG):
			_expect(not String(sheet.resource_path).is_empty(), "loader: the sheet must come from the imported resource, not a raw decode")
	_expect(life.load_texture_at(RESIDENTS_PNG, Vector2i(96, 240)) == null, "loader: a size mismatch must be refused, never rescaled")
	_expect(life.load_texture_at(LIFE_DIR + "missing.png", SHEET_SIZE) == null, "loader: a missing sheet must be refused")

	# The raw decode still serves a tree that has not imported a PNG yet.
	var probe_path := "user://hamlet_life_probe.png"
	var probe := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	probe.fill(Color(1.0, 0.5, 0.0, 1.0))
	_expect(probe.save_png(probe_path) == OK, "loader: the probe PNG could not be written")
	_expect(life.load_texture_at(probe_path, Vector2i(16, 16)) != null, "loader: an unimported PNG must still decode at its declared size")
	_expect(life.load_texture_at(probe_path, Vector2i(32, 16)) == null, "loader: the raw path must refuse a size mismatch too")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(probe_path))

	# Native 1x and the approved palette: the sheet is never resampled, tinted or
	# recoloured on its way into the hub.
	var file := FileAccess.open(RESIDENTS_PNG, FileAccess.READ)
	var image := Image.new()
	if file != null:
		var bytes := file.get_buffer(file.get_length())
		file.close()
		_expect(image.load_png_from_buffer(bytes) == OK, "palette: the published sheet is not a decodable PNG")
	var colours := {}
	if image.get_width() > 0:
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				if pixel.a > 0.0:
					colours[pixel] = true
		_expect(Vector2i(image.get_width(), image.get_height()) == SHEET_SIZE, "palette: the sheet is %sx%s" % [image.get_width(), image.get_height()])
		_expect(colours.size() == PALETTE_SIZE, "palette: the sheet carries %d colours, the approved sheet is 12 plus 2 amber" % colours.size())


func _test_strict_refusals() -> void:
	var atlas := _synthetic_atlas()
	var manifest := {
		"schema_version": 1,
		"residents": [{"placement": "mira", "clip": "mira.south.work", "phase": 0.0}],
	}
	var sound = _synthetic_life(atlas, manifest, _package.effects)
	_expect(sound.has_real_art(), "strict: the synthetic control package must load")

	_expect(_refuses(_synthetic_atlas(2.5), manifest, _package.effects), "strict: a fractional work cadence must be refused")
	_expect(_refuses(_synthetic_atlas(3.0, 0.0), manifest, _package.effects), "strict: a zero cadence must be refused")
	_expect(_refuses(_synthetic_atlas(3.0, 3.0, false), manifest, _package.effects), "strict: a one-shot published as a life cycle must be refused")
	var repeated := _synthetic_atlas()
	for index in 4:
		repeated["sprites"]["mira.south.work.%d" % index] = {"rect": [0, 0, 48, 48], "anchor": [24, 44], "texture": "residents"}
	_expect(_refuses(repeated, manifest, _package.effects), "strict: a cycle that repeats one cell must be refused")
	var short := _synthetic_atlas()
	short["animations"]["mira.south.work"]["frames"] = ["mira.south.work.0"]
	_expect(_refuses(short, manifest, _package.effects), "strict: a single-frame cycle must be refused")
	var outside := _synthetic_atlas()
	outside["sprites"]["mira.south.work.1"]["rect"] = [180, 0, 48, 48]
	_expect(_refuses(outside, manifest, _package.effects), "strict: a cell outside its own sheet must be refused")
	var drifted := _synthetic_atlas()
	drifted["sprites"]["mira.south.work.2"]["anchor"] = [24, 43]
	_expect(_refuses(drifted, manifest, _package.effects), "strict: a frame on another anchor must be refused")
	var untextured := _synthetic_atlas()
	untextured["textures"]["residents"]["path"] = LIFE_DIR + "missing.png"
	_expect(_refuses(untextured, manifest, _package.effects), "strict: a sheet that is not on disk must be refused")
	var resized := _synthetic_atlas()
	resized["textures"]["residents"]["width"] = 96
	_expect(_refuses(resized, manifest, _package.effects), "strict: a sheet whose size contradicts its file must be refused")
	_expect(_refuses(atlas, {"schema_version": 1}, _package.effects), "strict: a manifest without residents must be refused")
	_expect(_refuses(atlas, {"schema_version": 1, "residents": [], "effects": []}, _package.effects), "strict: a manifest without residents must be refused")
	_expect(_refuses({}, {}, {}), "strict: a completely absent package must be refused")

	var sockets := [
		{"id": "a", "owner": "hearth", "clip": "life.fire", "offset": [-8, -4], "layer": "lower"},
		{"id": "b", "owner": "forge", "clip": "life.steam", "offset": [8, -4]},
	]
	var sound_sockets = _synthetic_life(atlas, {"schema_version": 1, "residents": manifest["residents"], "effects": sockets}, _package.effects)
	_expect(sound_sockets.has_real_art(), "strict: the synthetic socket control must load")
	_expect(sound_sockets.life_ready(), "strict: the synthetic socket control must be ready")
	var bad_offset := sockets.duplicate(true)
	bad_offset[0]["offset"] = [-8, -4, 0]
	_expect(_refuses_effects(atlas, manifest, bad_offset), "strict: an offset that is not a pair must be refused")
	var unknown_band := sockets.duplicate(true)
	unknown_band[0]["layer"] = "middle"
	_expect(_refuses_effects(atlas, manifest, unknown_band), "strict: an unpublished band must be refused")
	var unknown_clip := sockets.duplicate(true)
	unknown_clip[0]["clip"] = "life.smoke"
	_expect(_refuses_effects(atlas, manifest, unknown_clip), "strict: a clip the approved sheet does not publish must be refused")
	var unnamed := sockets.duplicate(true)
	unnamed[1]["id"] = ""
	_expect(_refuses_effects(atlas, manifest, unnamed), "strict: a socket without an id must be refused")
	var orphaned := sockets.duplicate(true)
	orphaned[1]["owner"] = ""
	_expect(_refuses_effects(atlas, manifest, orphaned), "strict: a socket without an owner must be refused")


func _test_no_gameplay_writes() -> void:
	var hub := BaseHubScript.new()
	root.add_child(hub)
	hub._ready()
	var view := hub.get_hub_view()
	var town = hub.get_town_runtime()
	var before: Dictionary = town.snapshot()
	var actors: Dictionary = town.registry.snapshot()
	var before_user := _user_state()
	var nodes: int = view.world_presenter.sort_root.get_child_count()
	for frame: int in 432:
		view._process(1.0 / 144.0)
	_expect(town.snapshot() == before and town.registry.snapshot() == actors and town.simulation.tick == before.tick, "town life: presentation wrote gameplay or moved authority clock")
	_expect(view.world_presenter.sort_root.get_child_count() == nodes, "town life: animation generated background/cutaway nodes")
	_expect(_user_state() == before_user, "town life: presentation wrote saves")
	_shutdown_hub(hub)


func _shutdown_hub(hub: Node) -> void:
	if hub == null or not is_instance_valid(hub):
		return
	var controller: Variant = hub.get("_town_controller")
	if controller != null:
		var runtime: Variant = controller.get("scene_runtime")
		if runtime != null and runtime.has_method("unmount"):
			runtime.unmount()
	if hub.get_parent() != null:
		hub.get_parent().remove_child(hub)
	hub.free()


func _synthetic_atlas(fps: float = 3.0, distinct: float = 4.0, loop: bool = true) -> Dictionary:
	var sprites := {}
	for index in 4:
		var cell := index if float(index) < distinct else 0
		sprites["mira.south.work.%d" % index] = {"rect": [cell * 48, 0, 48, 48], "anchor": [24, 44], "texture": "residents"}
	return {
		"schema_version": 1,
		"native_view": [640, 360],
		"textures": {"residents": {"path": RESIDENTS_PNG, "width": SHEET_SIZE.x, "height": SHEET_SIZE.y}},
		"sprites": sprites,
		"animations": {
			"mira.south.work": {"fps": fps, "loop": loop, "frames": ["mira.south.work.0", "mira.south.work.1", "mira.south.work.2", "mira.south.work.3"]},
		},
	}


func _synthetic_life(atlas: Dictionary, manifest: Dictionary, effects: Dictionary):
	var life = HamletLifeAnimationScript.new()
	life.configure(atlas, manifest, effects)
	return life


## True when the package was refused with a reason, which is the only acceptable
## answer for a half-authored sheet: a refusal is never silent.
func _refuses(atlas: Dictionary, manifest: Dictionary, effects: Dictionary) -> bool:
	var life = _synthetic_life(atlas, manifest, effects)
	return not life.has_real_art() and not life.pending_reasons().is_empty()


func _refuses_effects(atlas: Dictionary, manifest: Dictionary, sockets: Array) -> bool:
	var life = _synthetic_life(atlas, manifest, _package.effects)
	var rejected: Dictionary = manifest.duplicate(true)
	rejected["effects"] = sockets
	var broken = _synthetic_life(atlas, rejected, _package.effects)
	return not broken.life_ready() and not broken.pending_reasons().is_empty() and life.has_real_art()


## Every file the run could have touched, by size and digest.
func _user_state() -> Dictionary:
	var state := {}
	_collect_files("user://", state)
	return state


func _collect_files(directory: String, state: Dictionary) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var path := directory.path_join(entry)
		if dir.current_is_dir():
			_collect_files(path, state)
		else:
			var file := FileAccess.open(path, FileAccess.READ)
			if file != null:
				var bytes := file.get_buffer(file.get_length())
				file.close()
				var digest := HashingContext.new()
				digest.start(HashingContext.HASH_SHA256)
				digest.update(bytes)
				state[path] = [bytes.size(), digest.finish().hex_encode()]
		entry = dir.get_next()
	dir.list_dir_end()


## The harness digest: one line per resident and socket with everything a GPU
## check needs to name the frame that is on screen.
func _print_harness_report() -> void:
	var report: Dictionary = _new_life().life_report()
	print("  published life reader: ready=%s residents=%d sockets=%d" % [report.ready, report.residents.size(), report.effects.size()])
