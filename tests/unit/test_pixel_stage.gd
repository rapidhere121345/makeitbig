extends SceneTree
## Presentation gate for the whole-window pixel stage (src/presentation/pixel_stage.gd).
##
## Run it on its own:
##   godot --headless --path . --script res://tests/unit/test_pixel_stage.gd
##
## What a headless run can prove: the pure layout math for the windows the shell must
## that the built node tree applies exactly that math, and the configuration that keeps
## ink bars from passing input through. What it cannot prove: that the compositor really
## lands on whole pixels, that SubViewportContainer really forwards mouse and touch, and
## how the bars look beside a real frame — headless has no rendering device and no real
## window, so those stay a real-device check and are not claimed here.
##
## Nothing in this gate resizes the root window or the OS window; the hosts below are
## plain Controls that stand in for a window of a given size.
##
## A runtime error inside an expression aborts the function that holds it, so a broken
## comparison would leave this gate green with every later check silently skipped. The
## check floor below turns that hole into a failure instead of a pass.

const Stage = preload("res://src/presentation/pixel_stage.gd")
const CHECK_FLOOR := 225

## The presentation table, keyed by windows a host might really have. Exact world-pixel
## tiers stay exact; intermediate desktop sizes uniformly fit the fixed authority canvas
## and name that nearest-filtered display fit.
const LAYOUT_CASES: Array[Dictionary] = [
	{"window": Vector2i(1280, 720), "stage": Vector2i(1280, 720), "origin": Vector2i(0, 0), "ui_scale": 1.0, "world": 2, "letterboxed": false, "fallback": ""},
	{"window": Vector2i(1920, 1080), "stage": Vector2i(1920, 1080), "origin": Vector2i(0, 0), "ui_scale": 1.5, "world": 3, "letterboxed": false, "fallback": ""},
	{"window": Vector2i(2560, 1440), "stage": Vector2i(2560, 1440), "origin": Vector2i(0, 0), "ui_scale": 2.0, "world": 4, "letterboxed": false, "fallback": ""},
	# Common 900p and 16:10 desktops use their full width instead of falling back to
	# a 1280px island. Their non-integer world pixels are explicit display fitting.
	{"window": Vector2i(1600, 900), "stage": Vector2i(1600, 900), "origin": Vector2i(0, 0), "ui_scale": 1.25, "world": 0, "letterboxed": false, "fallback": "common_display_fit"},
	{"window": Vector2i(1600, 1000), "stage": Vector2i(1600, 900), "origin": Vector2i(0, 50), "ui_scale": 1.25, "world": 0, "letterboxed": true, "fallback": "common_display_fit"},
	# A window just under an exact tier fits as closely as possible instead of dropping
	# an entire tier.
	{"window": Vector2i(1919, 1079), "stage": Vector2i(1918, 1079), "origin": Vector2i(0, 0), "ui_scale": 1079.0 / 720.0, "world": 0, "letterboxed": true, "fallback": "common_display_fit"},
	# A wide window is bound by its height, so it gets the taller-stage tier and side bars.
	{"window": Vector2i(3440, 1440), "stage": Vector2i(2560, 1440), "origin": Vector2i(440, 0), "ui_scale": 2.0, "world": 4, "letterboxed": true, "fallback": ""},
	# There is no top tier: 4K spends itself on world 6 and 8K on world 12, full frame.
	{"window": Vector2i(3840, 2160), "stage": Vector2i(3840, 2160), "origin": Vector2i(0, 0), "ui_scale": 3.0, "world": 6, "letterboxed": false, "fallback": ""},
	{"window": Vector2i(7680, 4320), "stage": Vector2i(7680, 4320), "origin": Vector2i(0, 0), "ui_scale": 6.0, "world": 12, "letterboxed": false, "fallback": ""},
	# Below 1280x720 the readability fallback fits the canvas to the window rather than
	# dropping to a UI 0.5 tier, which would draw 18px body copy at 9px. 1024x576 keeps
	# its own 0.8 ratio.
	{"window": Vector2i(1024, 576), "stage": Vector2i(1024, 576), "origin": Vector2i(0, 0), "ui_scale": 0.8, "world": 0, "letterboxed": false, "fallback": "small_window_readability_fallback"},
	{"window": Vector2i(1024, 768), "stage": Vector2i(1024, 576), "origin": Vector2i(0, 96), "ui_scale": 0.8, "world": 0, "letterboxed": true, "fallback": "small_window_readability_fallback"},
	# 640x360 happens to fit at a whole world pixel, but it is still the fallback and not
	# an approved tier: whole world pixels alone do not make a plan pixel-exact for UI.
	{"window": Vector2i(640, 360), "stage": Vector2i(640, 360), "origin": Vector2i(0, 0), "ui_scale": 0.5, "world": 1, "letterboxed": false, "fallback": "small_window_readability_fallback"},
	{"window": Vector2i(100, 50), "stage": Vector2i(88, 50), "origin": Vector2i(6, 0), "ui_scale": 50.0 / 720.0, "world": 0, "letterboxed": true, "fallback": "small_window_readability_fallback"},
	# Nothing readable is left at 1x1, but the target must not collapse to nothing either.
	{"window": Vector2i(1, 1), "stage": Vector2i(2, 2), "origin": Vector2i(0, 0), "ui_scale": 1.0 / 1280.0, "world": 0, "letterboxed": true, "fallback": "small_window_readability_fallback"},
]

## Window sizes the built hierarchy is exercised at: an exact tier, a common fitted
## desktop and the readability fallback.
const HOST_CASES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1024, 576)]

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var window_before := root.size
	_expect(int(ProjectSettings.get_setting("display/window/size/window_width_override", 0)) == 1600
		and int(ProjectSettings.get_setting("display/window/size/window_height_override", 0)) == 900,
		"desktop build opens at the bounded 1600x900 presentation size")
	_expect(
		Stage.SMALL_WINDOW_FALLBACK_REASON == "small_window_readability_fallback",
		"the fallback must keep the name hosts and docs quote"
	)
	_expect(Stage.COMMON_DISPLAY_FIT_REASON == "common_display_fit",
		"ordinary non-integer desktop fitting has a stable diagnostic name")
	_check_layout_table()
	_check_scale_policy()
	await _check_adaptive_policy()
	for host_size: Vector2i in HOST_CASES:
		await _check_built_stage(host_size)
	await _check_mounting()
	await _check_parent_resize_follow()
	await _check_root_window_host()
	_expect(root.size == window_before, "the gate must not touch root window settings")
	_expect(checks >= CHECK_FLOOR,
		"the gate ran %d checks, expected at least %d: an aborted check is a silent hole" % [checks, CHECK_FLOOR])
	if failures.is_empty():
		print("PASS  tests/unit/test_pixel_stage.gd: whole-window pixel stage (%d checks)" % checks)
		quit(0)
		return
	printerr("%d check(s) failed:" % failures.size())
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)


func _check_layout_table() -> void:
	for entry: Dictionary in LAYOUT_CASES:
		var window: Vector2i = entry.window
		var layout := Stage.layout_for_window(window)
		var tag := "%dx%d" % [window.x, window.y]
		_expect(layout.stage_size == entry.stage,
			"%s: stage must be %s, got %s" % [tag, str(entry.stage), str(layout.stage_size)])
		_expect(layout.origin == entry.origin,
			"%s: origin must be %s, got %s" % [tag, str(entry.origin), str(layout.origin)])
		_expect(is_equal_approx(float(layout.ui_scale), float(entry.ui_scale)),
			"%s: ui scale must be %f, got %f" % [tag, float(entry.ui_scale), float(layout.ui_scale)])
		_expect(layout.integer_world_pixels == int(entry.world),
			"%s: whole world pixels must be %d, got %d" % [tag, int(entry.world), int(layout.integer_world_pixels)])
		_expect(layout.letterboxed == bool(entry.letterboxed),
			"%s: letterboxed must be %s" % [tag, str(entry.letterboxed)])
		_expect(String(layout.fallback_reason) == String(entry.fallback),
			"%s: fallback reason must be \"%s\", got \"%s\"" % [tag, String(entry.fallback), String(layout.fallback_reason)])
		# The mounted canvas is the one thing that never moves.
		_expect(layout.ui_logic_size == Vector2i(1280, 720),
			"%s: the mounted canvas must stay 1280x720, got %s" % [tag, str(layout.ui_logic_size)])
		# Centred to within the pixel that integer division eats on odd remainders.
		_expect(absi((window.x - Vector2i(layout.stage_size).x) - 2 * Vector2i(layout.origin).x) <= 1,
			"%s: the stage must be centred horizontally" % tag)
		_expect(absi((window.y - Vector2i(layout.stage_size).y) - 2 * Vector2i(layout.origin).y) <= 1,
			"%s: the stage must be centred vertically" % tag)


func _check_scale_policy() -> void:
	# The half-step is the point of the tier list: UI 1.5 spends a 1080p window without
	# leaving the world grid. It is not an integer UI scale and must not claim to be one.
	var half_step := Stage.layout_for_window(Vector2i(1920, 1080))
	_expect(half_step.integer_world_pixels == 3 and not half_step.integer_ui_scale,
		"UI 1.5 must keep world pixels whole while admitting its UI pixels are not")
	var whole := Stage.layout_for_window(Vector2i(1280, 720))
	_expect(whole.integer_world_pixels == 2 and whole.integer_ui_scale,
		"UI 1 must report whole pixels on both grids")
	# The tier is derived, so it has no top end: a window with room for more world pixels
	# must take them, and the stage size must still be that step times the world grid.
	var uhd := Stage.layout_for_window(Vector2i(3840, 2160))
	_expect(uhd.stage_size == Vector2i(3840, 2160) and uhd.integer_world_pixels == 6 and not uhd.letterboxed,
		"a 3840x2160 window must present world 6 full frame, not a capped stage with ink")
	_expect(Stage.world_pixel_tier_for_window(Vector2i(3840, 2160)) == 6
		and Stage.world_pixel_tier_for_window(Vector2i(1919, 1079)) == 2
		and Stage.world_pixel_tier_for_window(Vector2i(3440, 1440)) == 4,
		"the tier must be floor(min(window / world)) on the binding axis")
	_expect(Stage.WORLD_NATIVE_SIZE * 6 == Stage.stage_size_for_ui_scale(3.0),
		"a tier stage must be exactly the world grid times the tier")
	# The plan is a pure function of the window: no node, no history, no window settings.
	_expect(Stage.layout_for_window(Vector2i(1600, 900)) == Stage.layout_for_window(Vector2i(1600, 900)),
		"the same window must always produce the same plan")
	_expect(Stage.layout_for_window(Vector2i(0, 0)).fallback_reason == Stage.SMALL_WINDOW_FALLBACK_REASON,
		"a window with no room at all is still the fallback, not an approved tier")


func _check_adaptive_policy() -> void:
	var cases: Array[Dictionary] = [
		{"window": Vector2i(1280, 720), "logical": Vector2i(1280, 720), "scale": 1.0},
		{"window": Vector2i(1366, 768), "logical": Vector2i(1366, 768), "scale": 1.0},
		{"window": Vector2i(1600, 900), "logical": Vector2i(1600, 900), "scale": 1.0},
		{"window": Vector2i(1600, 1000), "logical": Vector2i(1600, 1000), "scale": 1.0},
		{"window": Vector2i(1920, 1080), "logical": Vector2i(1600, 900), "scale": 1.2},
		{"window": Vector2i(1920, 1200), "logical": Vector2i(1600, 1000), "scale": 1.2},
		{"window": Vector2i(2560, 1440), "logical": Vector2i(1600, 900), "scale": 1.6},
	]
	for entry: Dictionary in cases:
		var window: Vector2i = entry.window
		var layout := Stage.adaptive_layout_for_window(window)
		var tag := "%dx%d adaptive" % [window.x, window.y]
		_expect(layout.policy == Stage.POLICY_ADAPTIVE_SHELL, tag + ": policy is explicit")
		_expect(layout.stage_size == window and layout.origin == Vector2i.ZERO, tag + ": shell fills the window")
		_expect(layout.ui_logic_size == entry.logical, tag + ": logical workspace stays inside the readable desktop range")
		_expect(is_equal_approx(float(layout.ui_scale), float(entry.scale)) and not bool(layout.letterboxed), tag + ": shell fills the window at the expected readable scale")
		_expect(not bool(layout.adaptive_fallback), tag + ": readable windows do not use fallback")
	var small := Stage.adaptive_layout_for_window(Vector2i(1024, 576))
	_expect(small.policy == Stage.POLICY_ADAPTIVE_SHELL and bool(small.adaptive_fallback),
		"small adaptive shell names its fixed-canvas fallback")
	_expect(small.ui_logic_size == Vector2i(1280, 720) and small.stage_size == Vector2i(1024, 576),
		"small adaptive shell preserves the established readability fit")

	var host := Control.new()
	host.size = Vector2(1600, 900)
	root.add_child(host)
	var stage = Stage.new()
	host.add_child(stage)
	await _frames(2)
	_expect(stage.get_presentation_policy() == Stage.POLICY_FIXED_PIXEL,
		"pixel stage starts in fixed-pixel policy")
	_expect(stage.viewport.get_visible_rect() == Rect2(0, 0, 1280, 720),
		"fixed policy keeps the 1280x720 logical canvas")
	var switched: Dictionary = stage.set_presentation_policy(Stage.POLICY_ADAPTIVE_SHELL)
	await _frames(2)
	_expect(bool(switched.ok) and stage.get_presentation_policy() == Stage.POLICY_ADAPTIVE_SHELL,
		"live stage accepts the adaptive shell policy")
	_expect(stage.viewport.get_visible_rect() == Rect2(0, 0, 1600, 900),
		"live adaptive shell retargets the logical viewport")
	_expect(stage.stage_container.position == Vector2.ZERO and stage.stage_container.size == Vector2(1600, 900),
		"live adaptive shell fills its host without ink bars")
	var rejected: Dictionary = stage.set_presentation_policy("bogus")
	_expect(not bool(rejected.ok) and stage.get_presentation_policy() == Stage.POLICY_ADAPTIVE_SHELL,
		"unknown policy fails without changing the live stage")
	stage.set_presentation_policy(Stage.POLICY_FIXED_PIXEL)
	await _frames(2)
	_expect(stage.viewport.get_visible_rect() == Rect2(0, 0, 1280, 720),
		"returning to fixed policy restores the authored canvas")
	_dispose(host)


func _check_built_stage(host_size: Vector2i) -> void:
	var host := Control.new()
	host.name = "PixelStageHost"
	host.size = Vector2(host_size)
	root.add_child(host)
	var stage = Stage.new()
	host.add_child(stage)
	await _frames(2)

	var tag := "%dx%d host" % [host_size.x, host_size.y]
	var plan := Stage.layout_for_window(host_size)
	_expect(stage.size == Vector2(host_size),
		"%s: the stage must take the whole parent rect, got %s" % [tag, str(stage.size)])
	_expect(stage.viewport != null and stage.stage_container != null,
		"%s: _ready must build the container and the presentation viewport" % tag)
	if stage.viewport == null or stage.stage_container == null:
		_dispose(host)
		return
	_expect(stage.get_presentation_viewport() == stage.viewport,
		"%s: get_presentation_viewport must hand out the built viewport" % tag)
	_expect(stage.viewport.get_parent() == stage.stage_container,
		"%s: the viewport must be the container's direct child, or stretch and input forwarding cannot work" % tag)

	# The container is the physical window footprint, and the target matches it exactly:
	# that equality is what keeps the blit from resampling a second time.
	_expect(stage.stage_container.stretch, "%s: the container must stretch its viewport" % tag)
	# A stretch container must not advertise a minimum size: one would clamp the rect the
	# stage asks for and turn a resize into a size negotiation.
	_expect(stage.stage_container.get_combined_minimum_size() == Vector2.ZERO,
		"%s: a stretch container must not report a minimum size, got %s" % [tag, str(stage.stage_container.get_combined_minimum_size())])
	_expect(stage.stage_container.size == Vector2(plan.stage_size),
		"%s: the container must be %s, got %s" % [tag, str(Vector2(plan.stage_size)), str(stage.stage_container.size)])
	_expect(stage.stage_container.position == Vector2(plan.origin),
		"%s: the container must sit at %s, got %s" % [tag, str(Vector2(plan.origin)), str(stage.stage_container.position)])
	_expect(Vector2(stage.viewport.size) == stage.stage_container.size,
		"%s: the physical target %s must equal the container %s" % [tag, str(stage.viewport.size), str(stage.stage_container.size)])
	_expect(stage.viewport.size_2d_override == Vector2i(1280, 720) and stage.viewport.size_2d_override_stretch,
		"%s: the 2D override must pin the canvas to 1280x720 with stretch on" % tag)
	_expect(stage.viewport.get_visible_rect() == Rect2(0.0, 0.0, 1280.0, 720.0),
		"%s: the presented canvas must see 1280x720, got %s" % [tag, str(stage.viewport.get_visible_rect())])

	# Input configuration: the ink is decoration, the stage is the wall.
	_expect(stage.mouse_filter == Control.MOUSE_FILTER_STOP,
		"%s: the stage must stop input so bar clicks never reach what is behind it" % tag)
	_expect(stage.stage_container.mouse_filter == Control.MOUSE_FILTER_STOP,
		"%s: the container must receive input to forward it into the viewport" % tag)
	_expect(stage.clip_contents, "%s: the stage must not paint outside its own rect" % tag)
	var ink := stage.find_child("InkBackground", true, false)
	_expect(ink is ColorRect, "%s: the stage must paint its empty area" % tag)
	if ink is ColorRect:
		_expect(ink.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"%s: the ink rect itself must not consume input" % tag)
		_expect(ink.color == ShellTheme.INK, "%s: the empty area must default to the ink token" % tag)
		_expect(ink.get_rect().encloses(Rect2(Vector2.ZERO, stage.size)),
			"%s: the ink must cover the whole window behind the presented rect" % tag)

	# A mounted full-rect screen is laid out at the logical size, not at the physical one.
	var mounted := Control.new()
	mounted.name = "MountedScreen"
	mounted.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.get_presentation_viewport().add_child(mounted)
	await _frames(2)
	_expect(mounted.get_viewport() == stage.viewport,
		"%s: a mounted screen must live in the presentation viewport" % tag)
	_expect(mounted.size == Vector2(1280.0, 720.0),
		"%s: a full-rect mounted screen must be laid out at 1280x720, got %s" % [tag, str(mounted.size)])

	# Re-planning a live stage keeps the canvas and the mount while it retargets pixels.
	var replanned: Dictionary = stage.apply_window_size(Vector2i(1024, 576))
	# A stretch container drives its target on the spot; a stale target for even one frame
	# would be a wrong-size blit, so this equality is checked before any frame passes.
	_expect(Vector2(stage.viewport.size) == stage.stage_container.size,
		"%s: replanning must retarget the container and its target in the same call" % tag)
	await _frames(2)
	_expect(replanned.stage_size == Vector2i(1024, 576),
		"%s: replanning must follow the new window size" % tag)
	_expect(stage.stage_container.size == Vector2(1024.0, 576.0),
		"%s: replanning must resize the container to 1024x576, got %s" % [tag, str(stage.stage_container.size)])
	_expect(stage.viewport.get_visible_rect() == Rect2(0.0, 0.0, 1280.0, 720.0),
		"%s: the logical canvas must survive a resize" % tag)
	_expect(mounted.size == Vector2(1280.0, 720.0),
		"%s: mounted content must keep its logical size across a resize" % tag)
	_expect(stage.layout_snapshot() == replanned,
		"%s: layout_snapshot must report the plan that was applied" % tag)
	var leaked := stage.layout_snapshot()
	leaked["stage_size"] = Vector2i(1, 1)
	_expect(Vector2i(stage.layout_snapshot().stage_size) == Vector2i(1024, 576),
		"%s: layout_snapshot must hand out a copy, not its own state" % tag)
	_dispose(host)


func _check_mounting() -> void:
	# Mounting order: a host that asks for the viewport before the stage entered the tree
	# must get the same viewport, because GameRoot mounts route roots that way.
	var host := Control.new()
	host.name = "EarlyMountHost"
	host.size = Vector2(1600.0, 900.0)
	root.add_child(host)
	var stage = Stage.new()
	var early: SubViewport = stage.get_presentation_viewport()
	_expect(early != null, "a host must be able to mount before the stage is in the tree")
	host.add_child(stage)
	await _frames(2)
	_expect(stage.viewport == early and stage.get_presentation_viewport() == early,
		"the viewport handed out before _ready must stay the presented one")
	var layer := CanvasLayer.new()
	layer.name = "RouteLayer"
	early.add_child(layer)
	await _frames(1)
	_expect(layer.get_viewport() == early,
		"a route CanvasLayer must land in the presentation viewport")
	_expect(early.get_visible_rect() == Rect2(0.0, 0.0, 1280.0, 720.0),
		"mounting must not disturb the logical canvas")
	_expect(stage.layout_snapshot().stage_size == Vector2i(1600, 900),
		"a 1600x900 host must use the full common display")

	# An ink override must land whether it is set before or after the children exist.
	var tinted = Stage.new()
	tinted.ink_color = Color("ff0000")
	host.add_child(tinted)
	await _frames(1)
	var tinted_ink := tinted.find_child("InkBackground", true, false)
	_expect(tinted_ink is ColorRect and tinted_ink.color == Color("ff0000"),
		"an ink override set before the build must be used")
	tinted.ink_color = Color("00ff00")
	_expect(tinted_ink is ColorRect and tinted_ink.color == Color("00ff00"),
		"an ink override set after the build must repaint the rect")
	_dispose(host)


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _check_parent_resize_follow() -> void:
	# The stage has to follow its host on its own: anchors plus the resize notification are
	# the whole mechanism, and a stage that only re-plans when a host asks would keep a
	# 1280 target inside a bigger window.
	var host := Control.new()
	host.name = "ResizeHost"
	host.size = Vector2(1280.0, 720.0)
	root.add_child(host)
	var stage = Stage.new()
	host.add_child(stage)
	await _frames(2)
	_expect(stage.layout_snapshot().stage_size == Vector2i(1280, 720),
		"a 1280x720 host must start on the 1280x720 tier")
	host.size = Vector2(1920.0, 1080.0)
	await _frames(2)
	_expect(stage.size == Vector2(1920.0, 1080.0),
		"the stage must take the resized host rect, got %s" % str(stage.size))
	_expect(stage.stage_container.size == Vector2(1920.0, 1080.0),
		"the container must follow a host resize, got %s" % str(stage.stage_container.size))
	_expect(Vector2(stage.viewport.size) == stage.stage_container.size,
		"the target must follow a host resize, got %s in %s" % [str(stage.viewport.size), str(stage.stage_container.size)])
	_expect(stage.layout_snapshot().stage_size == Vector2i(1920, 1080),
		"the plan must follow a host resize, got %s" % str(stage.layout_snapshot().stage_size))
	host.size = Vector2(1024.0, 576.0)
	await _frames(2)
	_expect(stage.layout_snapshot().stage_size == Vector2i(1024, 576)
		and String(stage.layout_snapshot().fallback_reason) == "small_window_readability_fallback",
		"shrinking into the readability fallback must re-plan too, got %s" % str(stage.layout_snapshot()))
	_expect(stage.viewport.get_visible_rect() == Rect2(0.0, 0.0, 1280.0, 720.0),
		"the canvas must stay 1280x720 across host resizes")
	_dispose(host)


func _check_root_window_host() -> void:
	# GameRoot's path: the stage is a child of the root Window, not of a Control, so the
	# anchors have to resolve against the window rect for the stage to size itself at all.
	# The rect that decides this is the root's visible rect, which is what the engine lays
	# root-level Controls into. Headless is happy to report a stub root Window whose own
	# size is not that rect, so this compares against the rect rather than against Window.size;
	# with the root stretch mode off the two are the same on a real display.
	var window_size := Vector2i(root.get_visible_rect().size)
	var stage = Stage.new()
	root.add_child(stage)
	await _frames(2)
	_expect(stage.size == Vector2(window_size),
		"a stage parented to the root window must take the window rect %s, got %s" % [str(Vector2(window_size)), str(stage.size)])
	_expect(Vector2i(stage.layout_snapshot().window_size) == window_size,
		"a stage parented to the root window must plan for the window it is in")
	_expect(stage.layout_snapshot().ui_logic_size == Vector2i(1280, 720),
		"the canvas stays 1280x720 under the root window too")
	_expect(Vector2(stage.viewport.size) == stage.stage_container.size,
		"the root-window stage must still keep the target equal to the container")
	_dispose(stage)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
