extends SceneTree

const View = preload("res://src/presentation/arena_world_view.gd")
const Presenter = preload("res://src/presentation/arena_actor_presenter.gd")
const Enemy = preload("res://src/runtime/world/combat_enemy_state.gd")
const Domain = preload("res://src/runtime/world/world_presenter.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var view = View.new()
	## Historical fixture: these assertions cover the legacy upper/base band
	## contract. Pin the generated pack away so this test stays on the
	## historical atlas path it was written for; the live whole-object
	## contract is covered by the paired-pack test in test_world_occlusion.
	view.generated_world_path = "res://build/current/legacy_fixture_no_generated_pack.json"
	_expect(view.load_assets(), "approved art must load: " + view.pending_reason)
	if not view.is_ready():
		_finish()
		return
	var viewport := Rect2(0, 0, 1280, 720)
	var arena := Rect2(42, 190, 1196, 488)
	var placement: Dictionary = view.structure_placements()[0]
	var feet_gp := Vector2(placement.feet[0], placement.feet[1])
	var hero_gp := feet_gp - Vector2(0, 85)
	view.begin_frame(viewport, hero_gp, arena)
	var presenter = Presenter.new()
	var frame := {"presentation_enabled": true, "in_arena": true, "sim_tick": 1,
		"player_position": hero_gp, "player_facing": Vector2.DOWN, "ranger_visual_time": 0.0,
		"ranger_frame": {}, "enemy_frames": {}, "enemies": [], "enemy_corpses": [], "boss_health_ratio": 1.0}
	var domain = Domain.new()
	root.add_child(domain)
	var result: Dictionary = presenter.sync_sort_views(domain, frame, view, 0.09)
	_expect(result.ok, "real sort submission failed")
	var feet: Vector2 = view.gameplay_to_world(feet_gp)
	var id := String(placement.id)
	var state: Dictionary = view.structure_fade_state(id, feet)
	_expect(state.open and is_equal_approx(state.alpha, 0.625), "half transition must be 0.625 after 0.09s")
	_expect(is_equal_approx(view.structure_geometry(id, feet)[1].alpha, 1.0), "base must remain opaque mid-transition")
	for _index in 3:
		view.structure_geometry(id, feet)
		view.occlusion_report(view.gameplay_to_world(hero_gp))
	_expect(view.structure_fade_state(id, feet) == state, "drawing/querying must not advance the fade clock")
	presenter.sync_sort_views(domain, frame, view, 0.09)
	state = view.structure_fade_state(id, feet)
	_expect(state.open and is_equal_approx(state.alpha, 0.25), "settled upper must use independent quarter-opacity contract")
	_expect(state.actors.has("ranger/body"), "hero subject missing")
	_expect(is_equal_approx(presenter.drawn_alpha("ranger/body"), 1.0), "hero sort view must stay opaque")
	_expect(view.cutaway_front(view.gameplay_to_world(hero_gp)).is_empty(), "structures must not enter the actor cutout budget")
	# Enemy-only coverage: the hero is far away, but a live enemy behind the
	# same upper still reveals its windup. No simulation position is changed.
	frame.player_position = Vector2(430, 600)
	var enemy = Enemy.new(hero_gp, 100.0, false, 42)
	frame.enemies = [enemy]
	view.begin_frame(viewport, frame.player_position, arena)
	view.reset_structure_fades()
	presenter.sync_sort_views(domain, frame, view, 0.2)
	state = view.structure_fade_state(id, feet)
	_expect(state.open and state.actors.has("enemy/42/body"), "enemy-only overlap must reveal the upper")
	_expect(is_equal_approx(presenter.drawn_alpha("enemy/42/body"), 1.0), "enemy must remain opaque")
	frame.enemies = []
	frame.player_position = feet_gp + Vector2(0, 80)
	view.begin_frame(viewport, frame.player_position, arena)
	presenter.sync_sort_views(domain, frame, view, 0.2)
	_expect(is_equal_approx(view.structure_fade_state(id, feet).alpha, 1.0), "front exit must restore upper")
	view.reset_structure_fades()
	_expect(view.structure_fade_report().is_empty(), "detach/reset must clear all cached structure state")
	for band: Dictionary in view.structure_geometry(id, feet):
		_expect(is_equal_approx(band.alpha, 1.0), "reset left a dim band")
	# The three ring moves must reach the actual render list, not only the
	# collision manifest. Changing rooms must clear state from the old mount.
	frame.player_position = hero_gp
	view.begin_frame(viewport, hero_gp, arena)
	presenter.sync_sort_views(domain, frame, view, 0.2)
	_expect(not view.structure_fade_report().is_empty(), "room reset setup has no fade state")
	view.set_layout_id("ring")
	_expect(view.structure_fade_report().is_empty(), "room change retained old fade state")
	var ring_drawables: Array = view.structure_draw_list()
	_expect((ring_drawables[4].feet_world as Vector2).is_equal_approx(view.gameplay_to_world(Vector2(832, 326))), "ring pier render placement differs from authored collider")
	_expect((ring_drawables[6].feet_world as Vector2).is_equal_approx(view.gameplay_to_world(Vector2(814.1, 663.2))), "ring wall render placement differs from authored collider")
	_expect((ring_drawables[7].feet_world as Vector2).is_equal_approx(view.gameplay_to_world(Vector2(563.8, 666.1))), "ring south pier render placement differs from authored collider")
	view.set_layout_id("corridor")
	_expect((view.structure_draw_list()[4].feet_world as Vector2).is_equal_approx(view.gameplay_to_world(Vector2(762, 365))), "ring placement leaked into corridor")
	presenter.release_sort_views()
	domain.free()
	_finish()

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _finish() -> void:
	for failure: String in failures:
		printerr("ARENA_PRIMITIVE_FADE_FAIL: " + failure)
	if failures.is_empty():
		print("ARENA_PRIMITIVE_FADE_PASS")
	quit(0 if failures.is_empty() else 1)
