extends SceneTree
## Contract checks for the shared enemy action reader/controller and its arena
## integration (2026-09-14 hand-off: three roles published east, mirrored west).
##
## Standalone SceneTree suite, deliberately outside tests/run_all.gd so a pack that
## has not been delivered yet can be checked without gating the full suite:
##   /data/tools/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64 --headless --path . \
##     --script res://tests/unit/test_enemy_animation.gd
##
## The suite passes in the current state without ever letting a silent fallback
## pass: while art/production/p1/enemy_actions_v01/atlas.json is missing the
## explicit ASSETS PENDING diagnostic is mandatory, and the moment the file exists
## the whole production matrix is required strictly -- 39 east IDs, 21 clips, the
## agreed timings, the (24,44) anchor and the imported texture bounds.

const EnemyAnimationScript = preload("res://src/presentation/enemy_animation.gd")
const PlayerFixture = preload("res://tests/helpers/player_domain_fixture.gd")
const Assert := preload("res://tests/helpers/assert.gd")
## A published sheet used as fixture pixels. No art or placeholder atlas is
## created by this test.
const FIXTURE_SHEET := "res://art/production/p1/calibration_v01/enemies.png"
const FIXTURE_SHEET_SIZE := Vector2i(192, 144)

var failures: Array[String] = []
var fixture := PlayerFixture.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_contract_constants()
	_test_production_state()
	_test_state_mapping()
	_test_masking()
	_test_timing()
	_test_frame_independence()
	_test_fixture_matrix()
	_test_mirroring()
	_test_declared_west()
	_test_broken_deliveries()
	_test_imported_texture_bounds()
	await _test_arena_integration()
	if failures.is_empty():
		print("PASS  tests/unit/test_enemy_animation.gd: enemy action atlas contract")
		quit(0)
		return
	printerr("%d check(s) failed:" % failures.size())
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _test_contract_constants() -> void:
	## The 48x48 cell with a (24,44) foot anchor keeps the calibration ground
## contact and makes the west mirror exactly the old flip axis.
	_expect(EnemyAnimationScript.CELL == Vector2i(48, 48), "animation: the action cell is no longer 48x48")
	_expect(EnemyAnimationScript.DEFAULT_ANCHOR == Vector2i(24, 44), "animation: the action anchor is no longer (24,44)")
	_expect(EnemyAnimationScript.DEFAULT_ANCHOR.x * 2 == EnemyAnimationScript.CELL.x, "animation: the anchor left the cell centre, so the west mirror moved the feet")
	_expect(EnemyAnimationScript.SIM_TICKS_PER_SECOND == 30, "animation: the tick base moved away from the 30Hz sim")
	_expect(EnemyAnimationScript.ROLES == ["melee", "charger", "ranged"], "animation: the three published roles changed")
	_expect(EnemyAnimationScript.FACINGS == ["east", "west"], "animation: the published facings changed")
	_expect(EnemyAnimationScript.ACTIONS == ["idle", "walk", "windup", "active", "recover", "hit", "death"], "animation: the action set changed")
	_expect(EnemyAnimationScript.ACTION_PRIORITY == ["death", "windup", "active", "hit", "recover", "walk", "idle"], "animation: the authority-first priority order changed")
	_expect(EnemyAnimationScript.required_id_count() == 13, "animation: one role no longer publishes 13 IDs")
	_expect(EnemyAnimationScript.ATLAS_PATH == "res://art/production/p1/enemy_actions_v01/atlas.json", "animation: the atlas moved away from the agreed package")
	_expect(EnemyAnimationScript.TEXTURE_PATH == "res://art/production/p1/enemy_actions_v01/enemies.png", "animation: the sheet moved away from the agreed path")
	_expect(EnemyAnimationScript.TEXTURE_KEY == "enemies", "animation: the texture key changed")
	_expect(EnemyAnimationScript.CORPSE_HOLD_TICKS == 60, "animation: the detached corpse hold changed")
	for role: String in EnemyAnimationScript.ROLES:
		var ids: Array[String] = EnemyAnimationScript.required_east_ids(role)
		_expect(ids.size() == 13, "animation: %s publishes %d required IDs instead of 13" % [role, ids.size()])
		_expect(ids[0] == "%s.east.idle.0" % role, "animation: %s does not start its matrix at the idle cell" % role)
		_expect(ids[12] == "%s.east.death.2" % role, "animation: %s does not close its matrix at the third death frame" % role)
	_expect(EnemyAnimationScript.clip_id("melee", "west", "walk") == "melee.west.walk", "animation: clip ids stopped being <role>.<facing>.<action>")
	_expect(EnemyAnimationScript.fallback_sprite_id("charger", "recovery") == "enemy.charger.recover", "animation: the pending fallback is not the calibration recovery cell")
	_expect(EnemyAnimationScript.fallback_sprite_id("ranged", "windup") == "enemy.ranged.windup", "animation: the pending fallback is not the calibration windup cell")
	_expect(EnemyAnimationScript.role_key("melee_pursuer") == "melee", "animation: the melee kind stopped mapping to the melee role")
	_expect(EnemyAnimationScript.role_key("charging_raider") == "charger", "animation: the raider kind stopped mapping to the charger role")
	_expect(EnemyAnimationScript.role_key("fan_ranged") == "ranged", "animation: the fan kind stopped mapping to the ranged role")
	_expect(EnemyAnimationScript.facing_key(Vector2.RIGHT) == "east", "animation: +x no longer reads as the east cell")
	_expect(EnemyAnimationScript.facing_key(Vector2.LEFT) == "west", "animation: -x no longer reads as the west cell")
	_expect(EnemyAnimationScript.facing_key(Vector2.ZERO) == "east", "animation: a standing enemy no longer keeps the calibration cell")
	_expect(EnemyAnimationScript.facing_key(Vector2(-0.0005, -3.0)) == "east", "animation: the flip threshold drifted away from the calibration read")
	_expect(EnemyAnimationScript.duration_ticks_for(4, 8) == 15, "animation: the 4-frame walk no longer lasts 15 ticks at 8fps")
	_expect(EnemyAnimationScript.agreed_duration_ticks("death") == 15, "animation: the agreed 3-frame death clip is not 15 ticks at 6fps")
	_expect(EnemyAnimationScript.agreed_duration_ticks("hit") == 4, "animation: the brief hit reaction is not the agreed one-frame window")


func _test_production_state() -> void:
	var reader = EnemyAnimationScript.new()
	if not FileAccess.file_exists(EnemyAnimationScript.ATLAS_PATH):
		## The pack is still being produced. That must be explicit, never a silent
		## fallback: the reason names the missing file and nothing claims real art.
		_expect(reader.asset_state() == EnemyAnimationScript.STATE_PENDING, "production: a missing pack reported %s instead of pending" % reader.asset_state())
		_expect(not reader.has_real_art(), "production: a missing pack claimed real art")
		_expect(reader.using_fallback(), "production: a missing pack did not declare its fallback")
		_expect(reader.pending_reason().begins_with("ASSETS PENDING:"), "production: the pending reason is not explicit: %s" % reader.pending_reason())
		_expect(reader.pending_reason().contains("actors_v02/enemy_atlas.json"), "production: the pending reason does not name the missing atlas: %s" % reader.pending_reason())
		_expect(reader.resolve({"role": "melee"}).get("fallback", false), "production: a pending reader did not resolve to its explicit fallback")
		return
	## The pack exists: the gate turns strict. A partial or drifted delivery fails
	## here instead of passing as finished art.
	_expect(reader.has_real_art(), "production: the delivered atlas did not load: %s" % reader.pending_reason())
	_expect(reader.asset_state() == EnemyAnimationScript.STATE_READY, "production: the delivered atlas reports %s: %s" % [reader.asset_state(), reader.pending_reason()])
	_expect(reader.pending_reason().is_empty(), "production: the healthy delivery reported problems: %s" % reader.pending_reason())
	_expect(reader.texture_path() == EnemyAnimationScript.TEXTURE_PATH, "production: the delivered sheet is not the agreed enemies.png: %s" % reader.texture_path())
	_expect(reader.contract_notes().is_empty(), "production: the delivered timing disagrees with the hand-off: %s" % str(reader.contract_notes()))
	var production: Dictionary = reader.production_report()
	_expect((production["missing_east_ids"] as Array).is_empty(), "production: the delivered atlas is missing %s" % str(production["missing_east_ids"]))
	var covered: int = (production["loaded_east_ids"] as Array).size() + (production["alias_ids"] as Array).size()
	_expect(covered == 39, "production: the delivered atlas covers %d of 39 production IDs" % covered)
	_expect(String(production["idle_alias_mode"]) in [EnemyAnimationScript.IDLE_ALIAS_MODE_DECLARED, EnemyAnimationScript.IDLE_ALIAS_MODE_IMPLICIT], "production: the idle alias is not declared or implicit: %s" % String(production["idle_alias_mode"]))
	_expect((production["declared_clips"] as Array).size() >= 21, "production: the delivered atlas declares %d clips, fewer than the 21 required" % (production["declared_clips"] as Array).size())
	for role: String in EnemyAnimationScript.ROLES:
		for action: String in EnemyAnimationScript.ACTIONS:
			var agreed: Dictionary = EnemyAnimationScript.ACTION_CONTRACT[action]
			var clip := EnemyAnimationScript.clip_id(role, "east", action)
			_expect(reader.frame_count(clip) == int(agreed["frames"]), "production: %s publishes %d frames, the hand-off agreed %d" % [clip, reader.frame_count(clip), int(agreed["frames"])])
			var frame: Dictionary = reader.resolve(_sample_state(role, action, 7))
			_expect(not frame.get("fallback", true), "production: %s resolved to a fallback: %s" % [clip, String(frame.get("reason", ""))])
			_expect(String(frame["action"]) == action, "production: %s resolved as %s" % [clip, String(frame["action"])])
			_expect((frame["rect"] as Rect2i).size == EnemyAnimationScript.CELL, "production: %s read a %s frame" % [clip, str(frame["rect"])])
			_expect((frame["anchor"] as Vector2i) == EnemyAnimationScript.DEFAULT_ANCHOR, "production: %s read anchor %s" % [clip, str(frame["anchor"])])
			_expect(frame["texture"] != null, "production: %s resolved without a texture" % clip)
			var texture: Texture2D = frame["texture"]
			if texture != null:
				_expect(Rect2i(Vector2i.ZERO, texture.get_size()).encloses(frame["rect"] as Rect2i), "production: %s reads outside the published sheet" % clip)
	var west: Dictionary = reader.resolve(_sample_state("melee", "walk", 7, "west"))
	_expect(bool(west["flip_x"]), "production: the west read stopped mirroring the east cell")


func _test_state_mapping() -> void:
	## The trigger contract every caller shares, checked against the agreed numbers
	## while the pack is pending (the reader falls back to contract timings).
	var reader = EnemyAnimationScript.new(false)
	_expect(String(reader.resolve({"role": "melee"}).get("action", "")) == "idle", "animation: a standing enemy did not fall back to idle")
	_expect(String(reader.resolve({"role": "melee", "moving": true}).get("action", "")) == "walk", "animation: movement did not select the walk clip")
	_expect(String(reader.resolve({"role": "melee", "action_state": "windup"}).get("action", "")) == "windup", "animation: the authoritative windup was not selected")
	_expect(String(reader.resolve({"role": "melee", "action_state": "active"}).get("action", "")) == "active", "animation: the authoritative active state was not selected")
	_expect(String(reader.resolve({"role": "melee", "action_state": "recovery"}).get("action", "")) == "recover", "animation: the authoritative recovery was not selected")
	_expect(String(reader.resolve({"role": "melee", "hit_ticks": 0}).get("action", "")) == "hit", "animation: a live hp drop did not select the hit reaction")
	_expect(String(reader.resolve({"role": "melee", "dead": true, "death_ticks": 0}).get("action", "")) == "death", "animation: a detached corpse did not select the death clip")
	_expect(String(reader.resolve({"role": "unknown_kind"}).get("role", "")) == "melee", "animation: an unknown role did not read as the melee silhouette")
	_expect(reader.resolve({"role": "melee"}).get("fallback", false), "animation: a pending reader did not report its fallback")
	_expect(String(reader.resolve({"role": "melee", "facing": Vector2.LEFT}).get("facing", "")) == "west", "animation: a west-facing enemy did not read the west cell")
	## One-shot reactions expire on their published length and fall through.
	_expect(String(reader.resolve({"role": "melee", "hit_ticks": 3}).get("action", "")) == "hit", "animation: the hit reaction ended before its published length")
	_expect(String(reader.resolve({"role": "melee", "hit_ticks": 4}).get("action", "")) == "idle", "animation: an expired hit counter stayed selected")
	_expect(String(reader.resolve({"role": "melee", "hit_ticks": 99, "moving": true}).get("action", "")) == "walk", "animation: an expired reaction did not fall through to walk")
	_expect(String(reader.resolve({"role": "melee", "hit_ticks": 99}).get("action", "")) == "idle", "animation: an expired reaction did not fall through to idle")
	_expect(String(reader.resolve({"role": "melee", "dead": true, "death_ticks": 99}).get("action", "")) == "death", "animation: the death clip stopped holding")


func _test_masking() -> void:
	## A hit reaction may never hide the telegraph the player is dodging, and it may
	## never mask the one-tick active state that resolves the damage.
	var reader = EnemyAnimationScript.new(false)
	for role: String in EnemyAnimationScript.ROLES:
		_expect(reader.live_action({"role": role, "action_state": "windup", "hit_ticks": 0}) == "windup", "masking: a hit reaction masked the %s windup" % role)
		_expect(reader.live_action({"role": role, "action_state": "active", "hit_ticks": 0}) == "active", "masking: a hit reaction masked the %s active tick" % role)
		_expect(reader.live_action({"role": role, "action_state": "windup", "hit_ticks": 0, "moving": true}) == "windup", "masking: walking masked the %s windup" % role)
		_expect(reader.live_action({"role": role, "dead": true, "hit_ticks": 0, "action_state": "active"}) == "death", "masking: a live reaction masked the %s death clip" % role)
		_expect(reader.live_action({"role": role, "action_state": "recovery", "hit_ticks": 0}) == "hit", "masking: the %s recovery no longer accepts a flinch" % role)
		_expect(reader.live_action({"role": role, "hit_ticks": 0, "moving": true}) == "hit", "masking: walking outranked the %s flinch" % role)
	## The masking rule is a priority table, not an accident of one call site.
	_expect(EnemyAnimationScript.ACTION_PRIORITY.find("windup") < EnemyAnimationScript.ACTION_PRIORITY.find("hit"), "masking: hit outranks windup in the priority table")
	_expect(EnemyAnimationScript.ACTION_PRIORITY.find("active") < EnemyAnimationScript.ACTION_PRIORITY.find("hit"), "masking: hit outranks active in the priority table")
	_expect(EnemyAnimationScript.ACTION_PRIORITY.find("death") == 0, "masking: death no longer outranks everything")


func _test_timing() -> void:
	var walk: Dictionary = EnemyAnimationScript.ACTION_CONTRACT["walk"]
	var death: Dictionary = EnemyAnimationScript.ACTION_CONTRACT["death"]
	var windup: Dictionary = EnemyAnimationScript.ACTION_CONTRACT["windup"]
	_expect(int(walk["frames"]) == 4 and int(walk["fps"]) == 8 and bool(walk["loop"]), "timing: the walk contract is no longer 4 frames at 8fps looping")
	_expect(int(death["frames"]) == 3 and int(death["fps"]) == 6 and not bool(death["loop"]), "timing: the death contract is no longer 3 frames at 6fps non-looping")
	_expect(int(windup["frames"]) == 2 and bool(windup.get("phase_normalized", false)), "timing: the windup contract is no longer two phase-normalized frames")
	## Looping clips wrap; one-shot clips hold their last published frame.
	_expect(EnemyAnimationScript.frame_index_for(4, 8, 0.0, true) == 0, "timing: the walk loop does not start on frame 0")
	_expect(EnemyAnimationScript.frame_index_for(4, 8, 0.125, true) == 1, "timing: one 8fps step did not advance one walk frame")
	_expect(EnemyAnimationScript.frame_index_for(4, 8, 0.5, true) == 0, "timing: the four-frame walk loop did not wrap after 0.5s")
	_expect(EnemyAnimationScript.frame_index_for(3, 6, 0.166, false) == 0, "timing: the death clip advanced before its first frame ended")
	_expect(EnemyAnimationScript.frame_index_for(3, 6, 0.5, false) == 2, "timing: the death clip did not reach its horizontal last frame")
	_expect(EnemyAnimationScript.frame_index_for(3, 6, 60.0, false) == 2, "timing: the death clip stopped holding its last frame")
	## Windup is phase-normalized across the authoritative window: a longer
	## telegraph holds each pose longer instead of speeding the clip up.
	_expect(EnemyAnimationScript.phase_frame_index(2, 100, 110, 100) == 0, "timing: the windup did not start on its first pose")
	_expect(EnemyAnimationScript.phase_frame_index(2, 100, 110, 104) == 0, "timing: the windup left its first pose before the window midpoint")
	_expect(EnemyAnimationScript.phase_frame_index(2, 100, 110, 105) == 1, "timing: the windup did not commit at the window midpoint")
	_expect(EnemyAnimationScript.phase_frame_index(2, 100, 110, 110) == 1, "timing: the closed end of the windup window left the committed pose")
	_expect(EnemyAnimationScript.phase_frame_index(2, 100, 110, 999) == 1, "timing: the windup pose did not clamp after the window")
	_expect(EnemyAnimationScript.phase_frame_index(2, 100, 100, 100) == 0, "timing: a degenerate windup window did not read frame 0")
	_expect(EnemyAnimationScript.phase_frame_index(2, 0, 20, 9) == 0 and EnemyAnimationScript.phase_frame_index(2, 0, 20, 10) == 1, "timing: an 18-tick charger windup did not hold each pose for 9 ticks")
	_expect(EnemyAnimationScript.phase_frame_index(2, 0, 42, 20) == 0 and EnemyAnimationScript.phase_frame_index(2, 0, 42, 21) == 1, "timing: a 42-tick fan windup did not normalize across its own window")
	## The resolved frame really reads the window, not a free clock: the same tick
	## with different telegraph lengths reads different frames.
	var reader = EnemyAnimationScript.new(true, {}, _fixture_atlas())
	var early: Dictionary = reader.resolve({"role": "melee", "action_state": "windup", "state_started_tick": 0, "state_ends_tick": 20, "tick": 5})
	var late: Dictionary = reader.resolve({"role": "melee", "action_state": "windup", "state_started_tick": 0, "state_ends_tick": 20, "tick": 15})
	_expect(int(early["frame"]) == 0 and int(late["frame"]) == 1, "timing: the windup clip does not follow the authoritative window")
	_expect(bool(early["phase_normalized"]) and int(early["frame_count"]) == 2, "timing: the windup clip lost its phase normalization")
	var long_early: Dictionary = reader.resolve({"role": "melee", "action_state": "windup", "state_started_tick": 0, "state_ends_tick": 42, "tick": 5})
	_expect(int(long_early["frame"]) == 0, "timing: a long telegraph did not keep its opening pose")


func _test_frame_independence() -> void:
	## The frame is a pure function of the clock the caller hands over, and that
	## clock is authoritative ticks (main.gd counts the ticks an enemy really
	## moved), never a per-render delta: a redraw and a different render rate read
	## the same frame for the same authority tick.
	var reader = EnemyAnimationScript.new(false)
	var first: Dictionary = reader.resolve({"role": "charger", "moving": true, "phase_ticks": 37, "tick": 37})
	var stable := true
	for repeat in 40:
		var again: Dictionary = reader.resolve({"role": "charger", "moving": true, "phase_ticks": 37, "tick": 37})
		if String(again["action"]) != String(first["action"]) or String(again["facing"]) != String(first["facing"]):
			stable = false
	_expect(stable, "frame independence: repeated resolves drifted")
	## Resolving another enemy in between cannot change this enemy's frame.
	var walk: Dictionary = reader.resolve({"role": "melee", "moving": true, "phase_ticks": 40, "tick": 40})
	var interleaved: Dictionary = {}
	for step in 6:
		reader.resolve({"role": "ranged", "action_state": "windup", "state_started_tick": 0, "state_ends_tick": 9, "tick": step})
		interleaved = reader.resolve({"role": "melee", "moving": true, "phase_ticks": 40, "tick": 40})
	_expect(int(interleaved["frame"]) == int(walk["frame"]) and String(interleaved["action"]) == String(walk["action"]), "frame independence: another enemy's resolve changed this enemy's frame")
	## The 8fps walk rides the reader's 30Hz authority base with an exact four-frame
	## period of 15 ticks, so one tick can never read two different frames.
	var period_holds := true
	for tick in range(0, 90):
		var here := EnemyAnimationScript.frame_index_for(4, 8, float(tick) / float(EnemyAnimationScript.SIM_TICKS_PER_SECOND), true)
		var later := EnemyAnimationScript.frame_index_for(4, 8, float(tick + 15) / float(EnemyAnimationScript.SIM_TICKS_PER_SECOND), true)
		if here != later:
			period_holds = false
			break
	_expect(period_holds, "frame independence: the walk loop is not 15 ticks long")
	var at_tick: Dictionary = reader.resolve({"role": "ranged", "moving": true, "phase_ticks": 45, "tick": 45})
	var later_tick: Dictionary = reader.resolve({"role": "ranged", "moving": true, "phase_ticks": 60, "tick": 60})
	_expect(int(at_tick["frame"]) == int(later_tick["frame"]), "frame independence: 15 ticks of walking did not return the loop to the same frame")


func _test_fixture_matrix() -> void:
	## A complete published matrix must validate and draw every action of all three
	## roles, with rect and anchor read per frame from the manifest.
	var reader = EnemyAnimationScript.new(true, {}, _fixture_atlas())
	_expect(reader.asset_state() == EnemyAnimationScript.STATE_READY, "fixture: a complete matrix was rejected: %s" % reader.pending_reason())
	_expect(reader.has_real_art(), "fixture: the published sheet did not load")
	## The fixture reads the calibration sheet as fixture pixels, so the only drift
	## it may report is that disclosed path; a delivery gate wants it empty.
	for note: String in reader.contract_notes():
		_expect(note.contains("is published at"), "fixture: unexpected drift note: %s" % note)
	_expect(reader.contract_notes().size() <= 1, "fixture: %d drift notes: %s" % [reader.contract_notes().size(), str(reader.contract_notes())])
	var production: Dictionary = reader.production_report()
	_expect((production["missing_east_ids"] as Array).is_empty(), "fixture: %s" % str(production["missing_east_ids"]))
	_expect(String(production["idle_alias_mode"]) == EnemyAnimationScript.IDLE_ALIAS_MODE_DECLARED, "fixture: the declared idle alias was not recognized")
	_expect(reader.sprite_ids().size() == 39, "fixture: %d sprite ids instead of 39" % reader.sprite_ids().size())
	_expect(reader.declared_clip_ids().size() == 21, "fixture: %d declared clips instead of 21" % reader.declared_clip_ids().size())
	_expect(reader.mirrored_clip_ids().size() == 21, "fixture: %d mirrored clips instead of 21" % reader.mirrored_clip_ids().size())
	for clip: String in reader.clip_ids():
		_expect(reader.frame_count(clip) > 0 or String(clip).contains(".west."), "fixture: %s published no frames" % clip)
	for role: String in EnemyAnimationScript.ROLES:
		for action: String in EnemyAnimationScript.ACTIONS:
			var frame: Dictionary = reader.resolve(_sample_state(role, action, 5))
			_expect(not frame.get("fallback", true), "fixture: %s.%s resolved to a fallback: %s" % [role, action, str(frame.get("reason", ""))])
			_expect(String(frame["action"]) == action, "fixture: %s.%s resolved as %s" % [role, action, String(frame["action"])])
			_expect((frame["rect"] as Rect2i).size == EnemyAnimationScript.CELL, "fixture: %s.%s read a %s frame" % [role, action, str(frame["rect"])])
			_expect((frame["anchor"] as Vector2i) == EnemyAnimationScript.DEFAULT_ANCHOR, "fixture: %s.%s read anchor %s" % [role, action, str(frame["anchor"])])
			_expect(frame["texture"] != null, "fixture: %s.%s resolved without a texture" % [role, action])
	## The published lengths the arena reads back.
	_expect(reader.clip_duration_ticks("melee", "death") == 15, "fixture: the delivered death clip is not 15 ticks")
	_expect(reader.clip_duration_ticks("melee", "hit") == 4, "fixture: the delivered hit window is not brief")
	_expect(reader.clip_duration_ticks("melee", "walk") == 0, "fixture: a looping clip claimed a one-shot window")
	var explicit_frame: Dictionary = reader.frame_for("melee.east.death", 2)
	_expect(int(explicit_frame.get("frame", -1)) == 2 and (explicit_frame.get("rect", Rect2i()) as Rect2i).size == EnemyAnimationScript.CELL, "fixture: explicit frame access lost the last death pose")


func _test_mirroring() -> void:
	## West is never authored: it is the east cell mirrored about the published
	## anchor, which is the calibration flip the arena already used.
	var reader = EnemyAnimationScript.new(true, {}, _fixture_atlas())
	var east: Dictionary = reader.resolve({"role": "ranged", "action_state": "none", "moving": true, "phase_ticks": 0, "tick": 3})
	var west: Dictionary = reader.resolve({"role": "ranged", "facing": Vector2.LEFT, "action_state": "none", "moving": true, "phase_ticks": 0, "tick": 3})
	_expect(String(east["facing"]) == "east" and not bool(east["flip_x"]), "mirror: the east read is flipped")
	_expect(String(west["facing"]) == "west" and bool(west["flip_x"]), "mirror: the west read is not the mirrored cell")
	_expect(bool(west["mirrored"]) and not bool(east["mirrored"]), "mirror: the mirror provenance is not reported")
	_expect(String(west["clip"]) == "ranged.east.walk", "mirror: the west read did not name the east clip it mirrors: %s" % String(west["clip"]))
	## Position transform preserved: same rect, same anchor, same frame index.
	_expect(west["rect"] == east["rect"] and west["anchor"] == east["anchor"], "mirror: the west cell moved away from the east cell")
	_expect(int(west["frame"]) == int(east["frame"]), "mirror: the west read sampled another frame")
	var west_hit: Dictionary = reader.resolve({"role": "melee", "facing": "west", "hit_ticks": 0})
	var east_hit: Dictionary = reader.resolve({"role": "melee", "facing": "east", "hit_ticks": 0})
	_expect(bool(west_hit["flip_x"]) and west_hit["rect"] == east_hit["rect"], "mirror: the west reaction cell drifted")


func _test_declared_west() -> void:
	## A pack that really publishes west cells is used as declared instead of being
	## mirrored a second time.
	var reader = EnemyAnimationScript.new(true, {}, _fixture_atlas_with_declared_west())
	_expect(reader.asset_state() == EnemyAnimationScript.STATE_READY, "west: a declared west matrix was rejected: %s" % reader.pending_reason())
	_expect(reader.mirrored_clip_ids().is_empty(), "west: declared west clips were still reported as mirrored")
	_expect(reader.declared_clip_ids().size() == 42, "west: %d declared clips instead of 42" % reader.declared_clip_ids().size())
	var west: Dictionary = reader.resolve({"role": "melee", "facing": "west", "action_state": "none", "moving": true, "phase_ticks": 0, "tick": 1})
	_expect(String(west["clip"]) == "melee.west.walk", "west: the declared west clip was not used: %s" % String(west["clip"]))
	_expect(not bool(west["flip_x"]) and not bool(west["mirrored"]), "west: a declared west cell was mirrored again")


func _test_broken_deliveries() -> void:
	## A broken pack is reported and never drawn; a disclosed drift is drawn and
	## reported. Neither may pass silently.
	var missing_ids := _fixture_atlas()
	for index in 3:
		(missing_ids["sprites"] as Dictionary).erase("charger.east.death.%d" % index)
	var missing_reader = EnemyAnimationScript.new(false, {}, missing_ids)
	_expect(missing_reader.asset_state() == EnemyAnimationScript.STATE_INVALID, "broken: a pack missing a role's death frames passed")
	_expect(missing_reader.pending_reason().contains("charger.east.death.0"), "broken: the missing IDs are not named: %s" % missing_reader.pending_reason())

	var unknown_frame := _fixture_atlas()
	((unknown_frame["animations"] as Dictionary)["ranged.east.hit"] as Dictionary)["frames"] = ["ranged.east.hit.9"]
	var unknown_reader = EnemyAnimationScript.new(false, {}, unknown_frame)
	_expect(unknown_reader.asset_state() == EnemyAnimationScript.STATE_INVALID and unknown_reader.pending_reason().contains("ranged.east.hit.9"), "broken: an unvalidated frame id passed: %s" % unknown_reader.pending_reason())

	var wrong_role := _fixture_atlas()
	((wrong_role["sprites"] as Dictionary)["melee.east.walk.0"] as Dictionary)["role"] = "ranged"
	var wrong_reader = EnemyAnimationScript.new(false, {}, wrong_role)
	_expect(wrong_reader.asset_state() == EnemyAnimationScript.STATE_INVALID, "broken: a frame declaring another role passed")
	_expect(wrong_reader.pending_reason().contains("declares role ranged"), "broken: the role mismatch is not named: %s" % wrong_reader.pending_reason())

	var undeclared_reuse := _fixture_atlas()
	((undeclared_reuse["sprites"] as Dictionary)["charger.east.walk.1"] as Dictionary)["state"] = "recover"
	var undeclared_reader = EnemyAnimationScript.new(false, {}, undeclared_reuse)
	_expect(undeclared_reader.asset_state() == EnemyAnimationScript.STATE_INVALID, "broken: an undeclared pose mismatch passed")
	_expect(undeclared_reader.pending_reason().contains("declares state recover"), "broken: the undeclared mismatch is not named: %s" % undeclared_reader.pending_reason())

	for mutation: Array in [
		["schema_version", 2],
		["native_view", [320, 180]],
		["cell_size", [32, 32]],
		["anchor", [16, 24]],
	]:
		var drifted := _fixture_atlas()
		drifted[String(mutation[0])] = mutation[1]
		var drifted_reader = EnemyAnimationScript.new(false, {}, drifted)
		_expect(drifted_reader.asset_state() == EnemyAnimationScript.STATE_INVALID, "broken: a %s of %s passed" % [String(mutation[0]), str(mutation[1])])

	var no_texture := _fixture_atlas()
	(no_texture["textures"] as Dictionary).erase("enemies")
	var no_texture_reader = EnemyAnimationScript.new(false, {}, no_texture)
	_expect(no_texture_reader.asset_state() == EnemyAnimationScript.STATE_INVALID, "broken: a pack without the enemies texture passed")
	_expect(no_texture_reader.pending_reason().contains("must declare the enemies texture"), "broken: the missing texture is not named: %s" % no_texture_reader.pending_reason())

	## The implicit alias form (no idle.0 cell at all) is the published contract too.
	var implicit_reader = EnemyAnimationScript.new(true, {}, _fixture_atlas_implicit_idle())
	_expect(implicit_reader.asset_state() == EnemyAnimationScript.STATE_READY, "alias: the implicit recover alias was rejected: %s" % implicit_reader.pending_reason())
	for note: String in implicit_reader.contract_notes():
		_expect(note.contains("is published at"), "alias: the published alias form reported drift: %s" % note)
	_expect(String(implicit_reader.production_report()["idle_alias_mode"]) == EnemyAnimationScript.IDLE_ALIAS_MODE_IMPLICIT, "alias: the implicit alias was not disclosed")
	var implicit_covered: int = (implicit_reader.production_report()["loaded_east_ids"] as Array).size() + (implicit_reader.production_report()["alias_ids"] as Array).size()
	_expect(implicit_covered == 39, "alias: the implicit alias covered %d of 39 production IDs" % implicit_covered)
	_expect(String(implicit_reader.resolve({"role": "melee"}).get("action", "")) == "idle", "alias: the implicit alias changed the standing action")

	## A distinct standing pose is art drift, not a broken pack: it draws and it is
	## named.
	var distinct_idle := _fixture_atlas()
	((distinct_idle["sprites"] as Dictionary)["charger.east.idle.0"] as Dictionary)["rect"] = [48, 0, 48, 48]
	var distinct_reader = EnemyAnimationScript.new(true, {}, distinct_idle)
	_expect(distinct_reader.asset_state() == EnemyAnimationScript.STATE_READY, "alias: a distinct idle pose was rejected instead of reported")
	var drift_named := false
	for note: String in distinct_reader.contract_notes():
		if note.contains("charger.east.idle.0"):
			drift_named = true
	_expect(drift_named, "alias: the distinct idle pose was not reported: %s" % str(distinct_reader.contract_notes()))

	## A timing drift stays drawable and is reported.
	var timing_drift := _fixture_atlas()
	((timing_drift["animations"] as Dictionary)["melee.east.walk"] as Dictionary)["fps"] = 12
	var timing_reader = EnemyAnimationScript.new(false, {}, timing_drift)
	_expect(timing_reader.asset_state() == EnemyAnimationScript.STATE_READY, "broken: a timing drift should stay drawable")
	var fps_named := false
	for note: String in timing_reader.contract_notes():
		if note.contains("12fps"):
			fps_named = true
	_expect(fps_named, "broken: the timing drift was not reported: %s" % str(timing_reader.contract_notes()))


func _test_imported_texture_bounds() -> void:
	## The published pixels are the fixture sheet. Imported bounds are the contract:
	## a cell that leaves the sheet is a broken delivery, never a clipped draw.
	var right_overflow := _fixture_atlas()
	((right_overflow["sprites"] as Dictionary)["melee.east.walk.1"] as Dictionary)["rect"] = [168, 0, 48, 48]
	var right_reader = EnemyAnimationScript.new(false, {}, right_overflow)
	_expect(right_reader.asset_state() == EnemyAnimationScript.STATE_INVALID, "bounds: a cell past the right edge passed")
	_expect(right_reader.pending_reason().contains("outside texture"), "bounds: the overflow is not named: %s" % right_reader.pending_reason())
	var bottom_overflow := _fixture_atlas()
	((bottom_overflow["sprites"] as Dictionary)["ranged.east.death.2"] as Dictionary)["rect"] = [0, 120, 48, 48]
	var bottom_reader = EnemyAnimationScript.new(false, {}, bottom_overflow)
	_expect(bottom_reader.asset_state() == EnemyAnimationScript.STATE_INVALID, "bounds: a cell past the bottom edge passed")
	## Imported metadata that disagrees with the real PNG bytes is reported.
	var stale := _fixture_atlas()
	(stale["textures"] as Dictionary)["enemies"] = {"path": FIXTURE_SHEET, "width": FIXTURE_SHEET_SIZE.x, "height": FIXTURE_SHEET_SIZE.y + 1}
	var stale_reader = EnemyAnimationScript.new(true, {}, stale)
	_expect(not stale_reader.has_real_art(), "bounds: a texture-size mismatch still claimed real art")
	_expect(stale_reader.pending_reason().contains("stale metadata"), "bounds: the size mismatch is not named: %s" % stale_reader.pending_reason())
	## A healthy fixture loads the published sheet and every drawn frame stays
	## inside its real imported bounds.
	var reader = EnemyAnimationScript.new(true, {}, _fixture_atlas())
	_expect(reader.has_real_art(), "bounds: the healthy fixture did not load: %s" % reader.pending_reason())
	var bounds := Rect2i(Vector2i.ZERO, FIXTURE_SHEET_SIZE)
	for role: String in EnemyAnimationScript.ROLES:
		for action: String in EnemyAnimationScript.ACTIONS:
			var frame: Dictionary = reader.resolve(_sample_state(role, action, 0, "west"))
			var rect: Rect2i = frame.get("rect", Rect2i())
			_expect(bounds.encloses(rect), "bounds: %s.%s west reads %s outside %s" % [role, action, str(rect), str(bounds)])
	var texture: Texture2D = reader.resolve(_sample_state("melee", "idle", 0))["texture"]
	_expect(texture != null and Vector2i(texture.get_size()) == FIXTURE_SHEET_SIZE, "bounds: the reader handed over another sheet than the imported one")


func _test_arena_integration() -> void:
	## The live arena: one reader, inferred movement, event-driven hits, detached
	## corpses and a presentation pass that never writes an authoritative field.
	var session := fixture.mount(_room(["melee_pursuer", "charging_raider", "fan_ranged"]), fixture.build(), true)
	var arena = session.arena
	await process_frame
	_expect(arena.presentation.world_view != null, "arena: the approved arena art must load for the enemy pass")
	_expect(arena.presentation.animations.enemy_animation != null, "arena: the enemy action reader was not created")
	if arena.presentation.animations.enemy_animation == null or arena.presentation.world_view == null:
		fixture.free_session(session)
		return
	var reader = arena.presentation.animations.enemy_animation
	## The delivery state is always explicit, never a silent substitution.
	if not reader.has_real_art():
		_expect(reader.asset_state() == EnemyAnimationScript.STATE_PENDING, "arena: a missing pack reports %s" % reader.asset_state())
		_expect(String(arena.presentation.animations.enemy_animation_pending_reason).begins_with("ASSETS PENDING:"), "arena: the pending diagnostic is not explicit: %s" % String(arena.presentation.animations.enemy_animation_pending_reason))
		_expect(String(arena.presentation.animations.enemy_animation_pending_reason).contains("actors_v02"), "arena: the pending diagnostic does not name the package: %s" % String(arena.presentation.animations.enemy_animation_pending_reason))
	else:
		_expect(String(arena.presentation.animations.enemy_animation_pending_reason).is_empty(), "arena: a healthy pack still reports a pending reason: %s" % String(arena.presentation.animations.enemy_animation_pending_reason))
	_configure_room(arena, ["melee_pursuer", "charging_raider", "fan_ranged"])
	arena.presentation.animations._refresh_enemy_frames(arena.gameplay_snapshot())
	_expect(arena.presentation.animations.enemy_frames.size() == arena.enemies.size(), "arena: %d frames for %d enemies" % [arena.presentation.animations.enemy_frames.size(), arena.enemies.size()])
	var live_report: Array = arena.enemy_animation_report()["live"] as Array
	_expect(live_report.size() == arena.enemies.size(), "arena: the report lost live enemies: %d of %d" % [live_report.size(), arena.enemies.size()])
	for entry: Dictionary in live_report:
		_expect(EnemyAnimationScript.ROLES.has(String(entry["role"])), "arena: %s is not a published role" % String(entry["role"]))
		_expect(String(entry["action"]) in EnemyAnimationScript.ACTIONS, "arena: %s is not a published action" % String(entry["action"]))
	_expect(String(arena.enemy_animation_report()["asset_state"]) in [EnemyAnimationScript.STATE_READY, EnemyAnimationScript.STATE_PENDING], "arena: the report lost the asset state")
	## Repeated commits read the same frames: drawing is never a clock.
	var before: String = str(arena.enemy_animation_report()["live"])
	arena.presentation.animations._refresh_enemy_frames(arena.gameplay_snapshot())
	arena.refresh_presentation(0.0)
	_expect(str(arena.enemy_animation_report()["live"]) == before, "arena: a redraw changed the resolved frames")

	## Movement is inferred from the position the simulation really moved, and only
	## on the render frames where the authoritative tick advanced.
	var walker = arena.enemies[0]
	_expect(bool(arena.teleport_actor("ranger", Vector2(420.0, 600.0)).get("ok", false)),
		"arena: the player parking pose was rejected")
	arena.presentation.animations._observe_enemy_animation(arena.gameplay_snapshot(), 0.0)
	_expect(not bool(arena.presentation.animations.enemy_state(arena.gameplay_snapshot(), walker)["moving"]), "arena: a standing enemy read as moving")
	var redraw_snapshot: Dictionary = arena.gameplay_snapshot()
	redraw_snapshot.enemies[0].position += Vector2(16.0, 0.0)
	var before_redraw: String = _authoritative_fingerprint(arena)
	arena.presentation.animations._observe_enemy_animation(redraw_snapshot, 1.0 / 30.0)
	_expect(_authoritative_fingerprint(arena) == before_redraw, "arena: a detached no-tick observation changed authority")
	_expect(not bool(arena.presentation.animations.enemy_state(arena.gameplay_snapshot(), walker)["moving"]), "arena: a render frame that ran no tick was read as motion")
	fixture.drive(arena, {"enemy_step": func() -> void:
		_expect(bool(arena._actor_setup._move_enemy_actor(walker, Vector2(16.0, 0.0)).get("ok", false)),
			"arena: the real enemy motor rejected the walking tick")
	})
	fixture.step(arena)
	arena.presentation.animations._observe_enemy_animation(arena.gameplay_snapshot(), 1.0 / 30.0)
	_expect(bool(arena.presentation.animations.enemy_state(arena.gameplay_snapshot(), walker)["moving"]), "arena: a moved enemy was not inferred as moving on the tick it moved")
	_expect(int(arena.presentation.animations.enemy_state(arena.gameplay_snapshot(), walker)["phase_ticks"]) == 1, "arena: the walk loop clock did not advance one authoritative tick")
	fixture.drive(arena)
	fixture.step(arena)
	arena.presentation.animations._observe_enemy_animation(arena.gameplay_snapshot(), 1.0 / 30.0)
	_expect(int(arena.presentation.animations.enemy_state(arena.gameplay_snapshot(), walker)["phase_ticks"]) == 0, "arena: standing still did not reset the walk loop")
	_expect(EnemyAnimationScript.facing_key(arena.presentation.animations.enemy_state(arena.gameplay_snapshot(), walker)["facing"]) in EnemyAnimationScript.FACINGS, "arena: the inferred facing left the published cells")

	## The same authority ticks must read the same walk frames at every render rate:
	## the clock is the ticks an enemy really moved, not the render delta.
	var rate_states := {}
	for rate in [30, 60, 144]:
		_configure_room(arena, ["melee_pursuer", "charging_raider", "fan_ranged"])
		var runner = arena.enemies[0]
		## Keep the complete 36-tick eastward run (and the redraw tick) clear of
		## whole scenery and other bodies; movement speed and clock stay unchanged.
		_expect(bool(arena.teleport_actor("ranger", Vector2(420.0, 600.0)).get("ok", false)),
			"rate: the player parking pose was rejected")
		for index in range(1, arena.enemies.size()):
			_expect(bool(arena.teleport_actor("enemy/%d" % arena.enemies[index].entity_id,
				Vector2(1100.0, 360.0 + float(index - 1) * 260.0)).get("ok", false)),
				"rate: another enemy's parking pose was rejected")
		_expect(bool(arena.teleport_actor("enemy/%d" % runner.entity_id, Vector2(430.0, 360.0)).get("ok", false)),
			"rate: the clear walk lane was rejected by teleport")
		arena.presentation.animations._observe_enemy_animation(arena.gameplay_snapshot(), 0.0)
		rate_states[rate] = _drive_render_rate(arena, runner, rate, 1.2)
	var reference: Dictionary = rate_states[30]
	var compared := 0
	var seen_frames := {}
	for tick: int in (reference.keys() as Array):
		if tick <= 0:
			continue
		compared += 1
		var expected: Dictionary = reference[tick]
		_expect(bool(expected["moving"]), "rate: authority tick %d lost the inferred motion" % tick)
		_expect(String(expected["action"]) == "walk", "rate: authority tick %d read action %s" % [tick, String(expected["action"])])
		_expect(int(expected["phase_ticks"]) == tick, "rate: authority tick %d read walk clock %d" % [tick, int(expected["phase_ticks"])])
		seen_frames[int(expected["frame"])] = true
		for rate in [60, 144]:
			var other: Dictionary = rate_states[rate]
			if not other.has(tick):
				continue
			if not _same_walk_state(expected, other[tick]):
				_expect(false, "rate: authority tick %d reads %s at 30Hz but %s at %dHz" % [tick, str(expected), str(other[tick]), rate])
				break
	_expect(compared >= 30, "rate: only %d authority ticks were compared over 1.2s of movement" % compared)
	_expect(seen_frames.size() >= 4, "rate: 1.2s of walking only ever read %d walk frames" % seen_frames.size())
	## A zero-tick redraw is what most 144Hz frames are: it must keep both the
	## inferred motion and the frame it already read.
	var redraw_enemy = arena.enemies[0]
	## Capture the held state mid-walk: one real authority tick through the
	## motor re-establishes the inferred motion the redraws must preserve.
	fixture.drive(arena, {"enemy_step": func() -> void:
		_expect(bool(arena._actor_setup._move_enemy_actor(redraw_enemy, Vector2(4.0, 0.0)).get("ok", false)),
			"rate: the redraw drive rejected the walking tick")
	})
	fixture.step(arena)
	arena.presentation.animations._observe_enemy_animation(arena.gameplay_snapshot(), 1.0 / 30.0)
	arena.presentation.animations._refresh_enemy_frames(arena.gameplay_snapshot())
	var held_state: Dictionary = arena.presentation.animations.enemy_state(arena.gameplay_snapshot(), redraw_enemy)
	var held_frame: Dictionary = (arena.presentation.animations.enemy_frames[redraw_enemy.entity_id] as Dictionary).duplicate(true)
	for redraw in 8:
		arena.refresh_presentation(1.0 / 144.0)
	var after_state: Dictionary = arena.presentation.animations.enemy_state(arena.gameplay_snapshot(), redraw_enemy)
	var after_frame: Dictionary = arena.presentation.animations.enemy_frames[redraw_enemy.entity_id] as Dictionary
	_expect(bool(held_state["moving"]) and bool(after_state["moving"]), "rate: a zero-tick redraw cleared the inferred motion")
	_expect(int(held_state["phase_ticks"]) == int(after_state["phase_ticks"]), "rate: a zero-tick redraw moved the walk clock")
	_expect(String(after_frame.get("action", "")) == String(held_frame.get("action", "")), "rate: a zero-tick redraw flickered the walk clip")
	_expect(int(after_frame.get("frame", -1)) == int(held_frame.get("frame", -1)), "rate: a zero-tick redraw changed the resolved frame")

	## A health delta alone is not presentation evidence. The authoritative damage
	## event latches the reaction exactly once and carries its stable event id.
	var reacted = arena.enemies[1]
	fixture.drive(arena)
	fixture.step(arena)
	reacted.health -= 5.0
	arena.presentation.animations._observe_enemy_animation(arena.gameplay_snapshot(), 0.0)
	var hit_kind: String = "enemy/%d/hit" % reacted.entity_id
	_expect(reader.latched_ticks(hit_kind, arena.sim_tick) == -1, "arena: a bare hp delta still fabricated a hit event")
	var damage_event: Dictionary = arena.combat_event_stream.emit(arena.sim_tick, "damage_applied", {
		"source_id": "ranger/piercing_arrow",
		"target_id": "enemy/%d" % reacted.entity_id,
		"target_entity_id": reacted.entity_id,
		"amount": "5",
		"contact_point": reacted.position,
	})
	arena.refresh_presentation()
	_expect(reader.latched_ticks(hit_kind, arena.sim_tick) == 0, "arena: the authority damage event was not latched on its tick")
	_expect(reader.latched_event_id(hit_kind) == "combat:%d" % int(damage_event.event_id), "arena: the latched token is not the combat event identity")
	fixture.advance_to(arena, int(arena.sim_tick) + 2)
	_expect(reader.latched_ticks(hit_kind, arena.sim_tick) == 2, "arena: the latched reaction did not age")
	arena.presentation.animations._observe_enemy_animation(arena.gameplay_snapshot(), 0.0)
	arena.presentation.animations._refresh_enemy_frames(arena.gameplay_snapshot())
	_expect(reader.latched_ticks(hit_kind, arena.sim_tick) == 2, "arena: a redraw re-latched the same event")
	_expect(reader.live_action(arena.presentation.animations.enemy_state(arena.gameplay_snapshot(), reacted)) == "hit", "arena: a live damage event did not select the hit reaction")
	## ... and the authoritative telegraph still outranks it.
	reacted.action_state = "windup"
	reacted.state_started_tick = arena.sim_tick
	reacted.state_ends_tick = arena.sim_tick + 18
	_expect(reader.live_action(arena.presentation.animations.enemy_state(arena.gameplay_snapshot(), reacted)) == "windup", "arena: the hit reaction masked the authoritative windup")
	reacted.action_state = "active"
	_expect(reader.live_action(arena.presentation.animations.enemy_state(arena.gameplay_snapshot(), reacted)) == "active", "arena: the hit reaction masked the authoritative active tick")
	reacted.action_state = "none"

	## The authoritative projectile contact detaches a corpse and does not delay
	## despawn beyond the contact tick.
	_configure_room(arena, ["melee_pursuer", "charging_raider", "fan_ranged"], "",
		fixture.build({"d": 5000.0, "damage": 1.0e9}))
	var victim = arena.enemies[0]
	var victim_id: int = victim.entity_id
	var victim_position: Vector2 = victim.position
	_expect(bool(arena.teleport_actor("ranger", victim.position).get("ok", false)),
		"arena: the lethal projectile setup pose was rejected")
	var contact_resolved := _cast_and_resolve_arrow(arena, victim_id)
	_expect(contact_resolved and victim.health <= 0.0, "arena: the lethal projectile contact did not resolve")
	_expect(_enemy_index(arena, victim_id) < 0, "arena: the kill did not despawn on its contact tick")
	_expect(arena.presentation.animations.enemy_corpses.size() == 1, "arena: the kill detached %d corpses instead of one" % arena.presentation.animations.enemy_corpses.size())
	if not arena.presentation.animations.enemy_corpses.is_empty():
		var corpse: Dictionary = arena.presentation.animations.enemy_corpses[0]
		_expect(int(corpse["entity_id"]) == victim_id and (corpse["position"] as Vector2) == victim_position, "arena: the corpse did not stay where the kill happened")
		_expect(String(corpse["role"]) == "melee", "arena: the corpse lost its published role: %s" % String(corpse["role"]))
		_expect(arena.presentation.animations.corpse_window_ticks(corpse) == 15 + EnemyAnimationScript.CORPSE_HOLD_TICKS, "arena: the corpse window is not the published clip plus the agreed hold")
	arena.presentation.animations._advance_enemy_corpses(0.6)
	_expect(arena.presentation.animations.enemy_corpses.size() == 1, "arena: the corpse was dropped before its clip finished")
	arena.presentation.animations._advance_enemy_corpses(2.0)
	_expect(arena.presentation.animations.enemy_corpses.is_empty(), "arena: the corpse outlived its window")
	arena.presentation.animations._refresh_enemy_frames(arena.gameplay_snapshot())
	_expect((arena.enemy_animation_report()["corpses"] as Array).is_empty(), "arena: the report kept an expired corpse")

	## Reset discrimination: a route reset drops the corpses, and a despawn that is
	## not a kill never creates one.
	_configure_room(arena, ["melee_pursuer", "charging_raider", "fan_ranged"])
	_expect(arena.presentation.animations.enemy_corpses.is_empty(), "arena: a route reset kept a corpse")
	_expect(_watch_is_reset(arena), "arena: a route reset kept an inferred record")
	_expect(reader.latched_ticks("enemy/1/hit", arena.sim_tick) == -1, "arena: a route reset kept a latched reaction")
	arena.presentation.animations._observe_enemy_animation(arena.gameplay_snapshot(), 1.0 / 30.0)
	_expect(arena.presentation.animations.enemy_corpses.is_empty(), "arena: freshly spawned enemies became corpses")
	var removed = arena.enemies[0]
	var removed_id: int = removed.entity_id
	arena.enemies.erase(removed)
	arena.presentation.animations._observe_enemy_animation(arena.gameplay_snapshot(), 1.0 / 30.0)
	_expect(arena.presentation.animations.enemy_corpses.is_empty(), "arena: a silent despawn played a death clip")
	_expect(not arena.presentation.animations.enemy_watch.has(removed_id), "arena: a despawn kept its inferred record")
	## The colossus has its own art lane: it never detaches an enemy corpse.
	_configure_room(arena, ["melee_pursuer"], "threshold_colossus")
	_expect(arena.boss != null and arena.boss.is_boss, "arena: the probe room has no colossus")
	arena.presentation.animations.detach_corpse({"entity_id": arena.boss.entity_id, "position": arena.boss.position, "is_boss": arena.boss.is_boss})
	_expect(arena.presentation.animations.enemy_corpses.is_empty(), "arena: the colossus detached an enemy corpse")

	## The pass is presentation only: it never writes an authoritative field.
	_configure_room(arena, ["melee_pursuer", "charging_raider", "fan_ranged"])
	var fingerprint: String = _authoritative_fingerprint(arena)
	for step in 12:
		arena.presentation.animations._observe_enemy_animation(arena.gameplay_snapshot(), 1.0 / 60.0)
		arena.presentation.animations._refresh_enemy_frames(arena.gameplay_snapshot())
	arena.refresh_presentation(1.0 / 60.0)
	_expect(_authoritative_fingerprint(arena) == fingerprint, "arena: the enemy presentation pass changed authoritative state")
	fixture.free_session(session)


## --- fixtures ---------------------------------------------------------------


## One state per published action, so a loop over the matrix resolves the action
## it means instead of whatever the priority table would otherwise pick.
func _sample_state(role: String, action: String, tick: int, facing := "east") -> Dictionary:
	var state := {
		"role": role,
		"facing": facing,
		"action_state": "none",
		"state_started_tick": 0,
		"state_ends_tick": 0,
		"moving": false,
		"phase_ticks": 0,
		"hit_ticks": -1,
		"dead": false,
		"death_ticks": 0,
		"tick": tick,
	}
	match action:
		"walk":
			state["moving"] = true
		"windup":
			state["action_state"] = "windup"
			state["state_ends_tick"] = tick + 2
		"active":
			state["action_state"] = "active"
		"recover":
			state["action_state"] = "recovery"
		"hit":
			state["hit_ticks"] = 0
		"death":
			state["dead"] = true
	return state


## The published sheet as fixture pixels: 12 cells of one role laid out 4 columns
## by 3 rows, exactly like the delivered source set (walk 4, windup 2, active 1,
## recover 1, hit 1, death 3), with the idle slot on the recover cell as the
## hand-off declares. No atlas and no image is created here.
func _fixture_atlas(idle_form := "declared", texture_path := FIXTURE_SHEET, texture_size := FIXTURE_SHEET_SIZE) -> Dictionary:
	var sprites := {}
	var animations := {}
	for role: String in EnemyAnimationScript.ROLES:
		## The published sheet holds one role's 12 drawings; every role reads the
		## same fixture cells, exactly like the three-role source set repeats its
		## own 4x3 layout.
		var slot := 0
		for action: String in ["walk", "windup", "active", "recover", "hit", "death"]:
			var ids: Array[String] = []
			for index in int(EnemyAnimationScript.ACTION_FRAME_COUNTS[action]):
				var id := "%s.east.%s.%d" % [role, action, index]
				sprites[id] = _fixture_cell(slot)
				slot += 1
				ids.append(id)
			animations["%s.east.%s" % [role, action]] = _fixture_clip(ids, action)
		if idle_form == "declared":
			var idle_id := "%s.east.idle.0" % role
			sprites[idle_id] = ((sprites["%s.east.recover.0" % role] as Dictionary) as Dictionary).duplicate(true)
			animations["%s.east.idle" % role] = _fixture_clip([idle_id], "idle")
		else:
			animations["%s.east.idle" % role] = _fixture_clip(["%s.east.recover.0" % role], "idle")
	return {
		"schema_version": 1,
		"native_view": [640, 360],
		"cell_size": [48, 48],
		"anchor": [24, 44],
		"textures": {"enemies": {"path": texture_path, "width": texture_size.x, "height": texture_size.y}},
		"sprites": sprites,
		"animations": animations,
	}


func _fixture_atlas_implicit_idle() -> Dictionary:
	return _fixture_atlas("implicit")


func _fixture_atlas_with_declared_west() -> Dictionary:
	var atlas: Dictionary = _fixture_atlas()
	for role: String in EnemyAnimationScript.ROLES:
		for action: String in EnemyAnimationScript.ACTIONS:
			var east := "%s.east.%s" % [role, action]
			var east_clip: Dictionary = atlas["animations"][east]
			var west_frames: Array[String] = []
			for frame_id: String in east_clip["frames"] as Array:
				var west_id: String = frame_id.replace(".east.", ".west.")
				var entry: Dictionary = ((atlas["sprites"] as Dictionary)[frame_id] as Dictionary).duplicate(true)
				entry["facing"] = "west"
				(atlas["sprites"] as Dictionary)[west_id] = entry
				west_frames.append(west_id)
			(atlas["animations"] as Dictionary)["%s.west.%s" % [role, action]] = {"frames": west_frames, "fps": int(east_clip["fps"]), "loop": bool(east_clip["loop"])}
	return atlas


func _fixture_cell(slot: int) -> Dictionary:
	return {"texture": "enemies", "rect": [(slot % 4) * 48, (slot / 4) * 48, 48, 48], "anchor": [24, 44]}


func _fixture_clip(ids: Array[String], action: String) -> Dictionary:
	var agreed: Dictionary = EnemyAnimationScript.ACTION_CONTRACT[action]
	return {"frames": ids, "fps": int(agreed["fps"]), "loop": bool(agreed["loop"])}


## --- helpers ----------------------------------------------------------------


## One render loop standing in for _process() at a given rate: every frame takes
## its share of the 30Hz authority from the arena's own clock, one authoritative
## tick moves the registered enemy through its real motor, and presentation observes and resolves
## exactly like the commit path does. Returns the resolved walk state keyed by
## the authority tick it belongs to, so two render rates can be compared tick for
## tick instead of frame for frame.
func _drive_render_rate(arena: Node, enemy, rate: int, seconds: float) -> Dictionary:
	var states := {}
	var delta := 1.0 / float(rate)
	fixture.drive(arena, {"enemy_step": func() -> void:
		_expect(bool(arena._actor_setup._move_enemy_actor(enemy, Vector2(4.0, 0.0)).get("ok", false)),
			"rate: the real enemy motor rejected the walking tick")
	})
	for frame in int(round(float(rate) * seconds)):
		for step in arena.simulation_world.ticks_for_frame(delta):
			fixture.step(arena)
		arena.presentation.animations._observe_enemy_animation(arena.gameplay_snapshot(), delta)
		arena.presentation.animations._refresh_enemy_frames(arena.gameplay_snapshot())
		var state: Dictionary = arena.presentation.animations.enemy_state(arena.gameplay_snapshot(), enemy)
		var frame_data: Dictionary = arena.presentation.animations.enemy_frames.get(enemy.entity_id, {})
		states[arena.sim_tick] = {
			"moving": bool(state["moving"]),
			"phase_ticks": int(state["phase_ticks"]),
			"action": String(frame_data.get("action", "")),
			"frame": int(frame_data.get("frame", -1)),
		}
	return states


## Two render rates are rate-independent exactly when the same authority tick
## reads the same motion, the same walk clock, the same clip and the same frame.
func _same_walk_state(left: Dictionary, right: Dictionary) -> bool:
	return (
		bool(left["moving"]) == bool(right["moving"])
		and int(left["phase_ticks"]) == int(right["phase_ticks"])
		and String(left["action"]) == String(right["action"])
		and int(left["frame"]) == int(right["frame"])
	)


func _configure_room(arena: Node, enemy_ids: Array, boss_id: String = "", resolved: Dictionary = {}) -> void:
	fixture.reset(arena, _room(enemy_ids, boss_id), resolved if not resolved.is_empty() else fixture.build())
	fixture.drive(arena)


func _room(enemy_ids: Array, boss_id: String = "") -> Dictionary:
	return {
		"room_id": "test.presentation.animations.enemy_animation",
		"layout_id": "rectangle_arena",
		"layout": "rectangle_arena",
		"objective_id": "clear",
		"objective": "clear",
		"hazard_ids": [],
		"enemy_ids": enemy_ids.duplicate(),
		"elite_rule_ids": [],
		"boss_id": boss_id,
		"drop_tags": ["equipment_general"],
	}


func _watch_is_reset(arena: Node) -> bool:
	# start_room publishes the new room immediately. Its watch may already hold
	# fresh tick-zero observations, but cannot retain motion from the old room.
	for entity_id: int in arena.presentation.animations.enemy_watch:
		var index := _enemy_index(arena, entity_id)
		if index < 0:
			return false
		var record: Dictionary = arena.presentation.animations.enemy_watch[entity_id]
		if int(record.get("tick", -1)) != 0 or bool(record.get("moving", true)) or int(record.get("walk_ticks", -1)) != 0:
			return false
		if record.get("position", Vector2.ZERO) != arena.enemies[index].position or float(record.get("health", -1.0)) != arena.enemies[index].health:
			return false
	return true


func _enemy_index(arena: Node, entity_id: int) -> int:
	for index in arena.enemies.size():
		if int(arena.enemies[index].entity_id) == entity_id:
			return index
	return -1


func _cast_and_resolve_arrow(arena: Node, target_id: int) -> bool:
	var shots_before: int = arena.shots
	var receipt := fixture.cast(arena, "piercing_arrow", target_id)
	if not bool(receipt.get("accepted", false)):
		return false
	var action: Dictionary = fixture.player(arena).timeline.active
	fixture.advance_to(arena, int(action.start_tick) + int(action.windup_ticks))
	if int(arena.shots) != shots_before + 1:
		return false
	# The real simulation can resolve a nearby contact on the release tick.
	if arena.projectiles.is_empty():
		return true
	for _flight_tick in range(32):
		fixture.step(arena)
		if arena.projectiles.is_empty():
			return true
	return false


## Everything authoritative the enemy pass could accidentally touch: the clock,
## the player, the settlement counters, every live enemy's health, position and
## authoritative action state.
func _authoritative_fingerprint(arena: Node) -> String:
	var parts: Array[String] = [
		"state=%s" % arena._semantic_state_hash("enemy-animation"),
		"tick=%d" % arena.sim_tick,
		"hp=%.3f" % arena.player_health,
		"pos=%s" % str(arena.player_position),
		"defeated=%d" % arena.defeated,
		"shots=%d" % arena.shots,
		"over=%s" % str(arena.battle_over),
	]
	for enemy in arena.enemies:
		parts.append("%d:%s:%.3f:%s:%s:%d:%d" % [enemy.entity_id, enemy.kind_id, enemy.health, str(enemy.position), enemy.action_state, enemy.state_started_tick, enemy.state_ends_tick])
	return "|".join(PackedStringArray(parts))


func _expect(condition: bool, message: String) -> void: Assert.expect(condition, message, failures)
