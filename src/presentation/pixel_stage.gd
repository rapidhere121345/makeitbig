class_name PixelStage
extends Control
## Whole-window presentation surface. Pixel-authored routes keep the fixed 1280x720
## canvas and whole world-pixel tiers; information-heavy shell routes may instead use
## the real window as their logical canvas so a larger display buys layout space.
##
## Contract:
##  * Pixel-authored routes use a 640x360 native world and a fixed 1280x720 logical
##    canvas, so one world pixel is exactly two logical pixels at the base tier.
##  * Information-heavy shell routes use the physical window as their logical canvas
##    through 1600x900. Larger ordinary monitors keep roughly that much logical room
##    and spend their extra pixels on a uniform readability scale, so 1920x1080 does
##    not turn the same Chinese copy into physically smaller text.
##  * The stage owns the window: it fills its parent, paints the empty area in ink and
##    centres the presented canvas inside that rect. The host adds it to the root window
##    and turns the root stretch mode off, because the stage reads its own rect as
##    physical window pixels.
##  * Fixed-canvas routes keep their 1280x720 authority rectangle but fit it uniformly
##    into ordinary monitors. Exact world-pixel tiers remain exact; intermediate desktop
##    sizes such as 1366x768 and 1600x900 use nearest-filtered display fitting instead of
##    wasting hundreds of pixels in oversized ink bars.
##  * The smallest tier is world 2, which is 1280x720. A smaller window is served by the
##    small_window_readability_fallback instead of the world 1 / UI 0.5 tier, because that
##    tier draws the approved 18px Chinese body copy at 9px: the logical canvas is fitted to
##    the window as-is. At 1024x576 that keeps UI scale 0.8. The fallback is deliberately
##    not pixel-exact, never resizes the OS window, and names itself in every snapshot.
##  * The empty area never passes input through: the ink rect ignores input while the
##    stage itself stops it, so only the centred container reaches the mounted viewport.
##
## Fixed-pixel presentation table:
##   1280x720  -> stage 1280x720,  UI 1,   world 2, full
##   1600x900  -> stage 1600x900,  UI 1.25, world 2.5 (display fit), full
##   1600x1000 -> stage 1600x900,  UI 1.25, bars above and below
##   1920x1080 -> stage 1920x1080, UI 1.5, world 3, full
##   2560x1440 -> stage 2560x1440, UI 2,   world 4, full
##   3440x1440 -> stage 2560x1440, UI 2,   world 4, side bars
##   3840x2160 -> stage 3840x2160, UI 3,   world 6, full
##   1024x576  -> stage 1024x576,  UI 0.8, world 1.6, readability fallback
##
## Mounting a scene is `stage.viewport.add_child(screen)` plus the screen's CanvasLayer.
## The viewport keeps the project clear colour and no transparency of its own, so a
## mounted fixed-pixel screen is expected to cover its own 1280x720 canvas. An
## adaptive shell covers the ui_logic_size reported by its current layout.

## Fixed logical canvas. SubViewport.size_2d_override holds get_visible_rect() here for
## every physical tier, so mounted screens are written once against 1280x720.
const UI_LOGIC_SIZE := Vector2i(1280, 720)
const POLICY_FIXED_PIXEL := "fixed_pixel"
const POLICY_ADAPTIVE_SHELL := "adaptive_shell"
## Shell pages grow from the 1280x720 floor to this useful desktop workspace. Above
## it, the stage scales the logical page uniformly while preserving the window's
## actual aspect ratio; 16:10 therefore becomes 1600x1000 rather than being cropped.
const ADAPTIVE_REFERENCE_SIZE := Vector2i(1600, 900)
## Native world grid. The world is authored on this grid and scaled by the mount.
const WORLD_NATIVE_SIZE := Vector2i(640, 360)
## Smallest tier the stage presents 1:1, in whole world pixels. World 1 (UI 0.5) is where
## the approved 18px Chinese body copy lands on 9px, so it is never a tier.
const MIN_TIER_WORLD_PIXELS := 2
## Why a snapshot is not a whole world-pixel tier. The only fallback so far.
const SMALL_WINDOW_FALLBACK_REASON := "small_window_readability_fallback"
const COMMON_DISPLAY_FIT_REASON := "common_display_fit"
## A degenerate window must not collapse the target to nothing. This floor is far below
## anything readable; it only keeps the node graph and the target valid.
const MIN_STAGE_SIZE := 2
## Exact-fit windows (1024x576 must not land on 1023x575) fight float dust with this.
const SCALE_EPSILON := 0.000001
## Child names; the host and the gates address the hierarchy through them.
const INK_BACKGROUND_NAME := "InkBackground"
const STAGE_CONTAINER_NAME := "StageContainer"
const PRESENTATION_VIEWPORT_NAME := "PresentationViewport"

## The presented canvas. Hosts mount their screen root and CanvasLayer in here.
var viewport: SubViewport = null
## Stretched host of `viewport`. Its rect is the physical footprint on the window.
var stage_container: SubViewportContainer = null

var _ink_background: ColorRect = null
var _applied_layout: Dictionary = {}
var _presentation_policy := POLICY_FIXED_PIXEL

## Empty-area colour. Defaults to the shared ink token: the stage owns no colour of its
## own, and no screen is expected to letterbox itself.
@export var ink_color: Color = ShellTheme.INK:
	set(value):
		ink_color = value
		if _ink_background != null:
			_ink_background.color = value


## Physical stage size for a UI scale: the logical canvas times that scale. Because the
## canvas is even, every half-step scale lands on whole pixels (UI 1.5 -> 1920x1080, UI 3
## -> 3840x2160), so a tier can be named by either of its two numbers.
static func stage_size_for_ui_scale(ui_scale: float) -> Vector2i:
	return Vector2i(
		int(roundf(float(UI_LOGIC_SIZE.x) * ui_scale)),
		int(roundf(float(UI_LOGIC_SIZE.y) * ui_scale))
	)


## Physical pixels per native world pixel, or 0 when that number is not whole. The
## fallback ratios are free, so this is how a caller proves a layout is pixel-exact.
static func world_pixels_for_ui_scale(ui_scale: float) -> int:
	var world_pixels := ui_scale * (float(UI_LOGIC_SIZE.x) / float(WORLD_NATIVE_SIZE.x))
	if not is_equal_approx(world_pixels, roundf(world_pixels)):
		return 0
	return int(roundf(world_pixels))


## Whole world-pixel step a window can hold: floor(min(window / world)), with no top end,
## because extra window pixels should buy world pixels rather than ink. The binding axis
## decides, so 16:9 and every other aspect ratio take the same route.
static func world_pixel_tier_for_window(window_size: Vector2i) -> int:
	var window := Vector2i(maxi(window_size.x, 0), maxi(window_size.y, 0))
	# Both operands are non-negative, so integer division is exactly floor().
	return mini(window.x / WORLD_NATIVE_SIZE.x, window.y / WORLD_NATIVE_SIZE.y)


## The presentation plan for a window of this size. Pure: it reads no node, no window and
## no OS state, so this is the one piece of the layout a headless gate can prove. The
## authority canvas never changes; only its uniform display footprint does.
##
## Keys:
##  * window_size: the input, echoed for caller diagnostics.
##  * stage_size: physical target, which is also the SubViewportContainer rect.
##  * origin: centred top-left of the stage inside the window.
##  * ui_logic_size: the canvas mounted screens are laid out in; 1280x720 for
##    fixed routes and the available window for a full adaptive shell.
##  * ui_scale: physical pixels per logical pixel.
##  * integer_ui_scale: whether that scale is whole (false at the UI 1.5 half-step).
##  * integer_world_pixels: physical pixels per world pixel, 0 when not whole. Whole here is
##    not the same as a tier: the fallback can land on a whole ratio (a 640x360 window fits
##    world 1), which is what fallback_reason is for.
##  * letterboxed: whether any window pixel is left as ink.
##  * fallback_reason: empty when the plan is a whole world-pixel tier, else why it is not.
static func layout_for_window(window_size: Vector2i) -> Dictionary:
	var window := Vector2i(maxi(window_size.x, 0), maxi(window_size.y, 0))
	var fit := minf(
		float(window.x) / float(UI_LOGIC_SIZE.x),
		float(window.y) / float(UI_LOGIC_SIZE.y)
	)
	# Fit every conventional desktop size instead of stepping all the way down to the
	# previous integer tier. Exact 2x/3x world-pixel windows still report no fallback;
	# intermediate sizes explicitly name the nearest-filtered display fit.
	var fitted := Vector2i(
		maxi(int(floorf(float(UI_LOGIC_SIZE.x) * fit + SCALE_EPSILON)), MIN_STAGE_SIZE),
		maxi(int(floorf(float(UI_LOGIC_SIZE.y) * fit + SCALE_EPSILON)), MIN_STAGE_SIZE)
	)
	var fallback_reason := ""
	if fit < 1.0:
		fallback_reason = SMALL_WINDOW_FALLBACK_REASON
	elif world_pixels_for_ui_scale(fit) == 0:
		fallback_reason = COMMON_DISPLAY_FIT_REASON
	return _snapshot(window, fitted, fit, fallback_reason, UI_LOGIC_SIZE, POLICY_FIXED_PIXEL)


## Shell pages use every available pixel and gain logical workspace up to the ordinary
## 1600x900 desktop reference. Beyond that reference the shortest ratio becomes a
## readability scale: 1920x1080 is a 1600x900 logical page at 1.2x, while 1920x1200 is
## a 1600x1000 page at the same scale. This keeps wide/16:10 space useful without making
## body copy smaller on a larger monitor. Smaller windows keep the fixed-canvas fallback.
static func adaptive_layout_for_window(window_size: Vector2i) -> Dictionary:
	var window := Vector2i(maxi(window_size.x, 0), maxi(window_size.y, 0))
	if window.x >= UI_LOGIC_SIZE.x and window.y >= UI_LOGIC_SIZE.y:
		var readability_scale := maxf(1.0, minf(
			float(window.x) / float(ADAPTIVE_REFERENCE_SIZE.x),
			float(window.y) / float(ADAPTIVE_REFERENCE_SIZE.y)
		))
		var logical_size := Vector2i(
			maxi(1, int(roundf(float(window.x) / readability_scale))),
			maxi(1, int(roundf(float(window.y) / readability_scale)))
		)
		return _snapshot(window, window, readability_scale, "", logical_size, POLICY_ADAPTIVE_SHELL)
	var fallback := layout_for_window(window)
	fallback["policy"] = POLICY_ADAPTIVE_SHELL
	fallback["adaptive_fallback"] = true
	return fallback


static func layout_for_policy(window_size: Vector2i, policy: String) -> Dictionary:
	if policy == POLICY_ADAPTIVE_SHELL:
		return adaptive_layout_for_window(window_size)
	return layout_for_window(window_size)


static func _snapshot(
	window_size: Vector2i,
	stage_size: Vector2i,
	ui_scale: float,
	fallback_reason: String,
	ui_logic_size: Vector2i,
	policy: String
) -> Dictionary:
	return {
		"window_size": window_size,
		"stage_size": stage_size,
		"origin": Vector2i(
			(window_size.x - stage_size.x) / 2,
			(window_size.y - stage_size.y) / 2
		),
		"ui_logic_size": ui_logic_size,
		"ui_scale": ui_scale,
		"integer_ui_scale": is_equal_approx(ui_scale, roundf(ui_scale)),
		"integer_world_pixels": world_pixels_for_ui_scale(ui_scale),
		"letterboxed": stage_size != window_size,
		"fallback_reason": fallback_reason,
		"policy": policy,
		"adaptive_fallback": false,
	}


func _ready() -> void:
	# The stage is the window surface: it takes the parent rect and never lets a bar
	# click through to whatever sits behind it.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_children()
	refresh_from_window()


func _notification(what: int) -> void:
	if what != NOTIFICATION_RESIZED or not is_inside_tree():
		return
	# Only ever re-plan a stage that is already built. Building from here would add a
	# SubViewport to the tree in the middle of a layout pass, so the same resize that
	# triggered the notification would be walking a hierarchy that is still being
	# assembled. _ready() does the building, so waiting for it costs nothing.
	if viewport != null:
		refresh_from_window()


## Re-applies the plan for the rect the stage currently occupies (its parent, or the root
## window when the host adds it there). Hosts that resize something by hand call this;
## a window resize reaches it on its own.
func refresh_from_window() -> Dictionary:
	return apply_window_size(Vector2i(size))


func set_presentation_policy(policy: String) -> Dictionary:
	if policy != POLICY_FIXED_PIXEL and policy != POLICY_ADAPTIVE_SHELL:
		return {"ok": false, "error": "unknown_presentation_policy", "policy": policy}
	_presentation_policy = policy
	if is_inside_tree():
		apply_window_size(Vector2i(size))
	return {"ok": true, "policy": _presentation_policy, "layout": layout_snapshot()}


func get_presentation_policy() -> String:
	return _presentation_policy


## Applies the plan for `window_size` and returns it. The physical target is set to the
## container size on purpose: a stretched SubViewportContainer draws the mounted canvas
## without a second transform, so the stage never resamples what it was handed.
func apply_window_size(window_size: Vector2i) -> Dictionary:
	_build_children()
	var layout := layout_for_policy(window_size, _presentation_policy)
	var origin := Vector2(layout.origin)
	var stage_size := Vector2(layout.stage_size)
	# Write only what changed. The container answers a size write by resizing its target,
	# and the engine refuses a manual SubViewport.size while stretch is on, so the physical
	# target cannot drift from the footprint the stage asked for. Skipping a redundant write
	# keeps the resize chain from doing per-notification work that a resize did not ask for.
	if stage_container.position != origin:
		stage_container.position = origin
	if stage_container.size != stage_size:
		stage_container.size = stage_size
	var logical_size := Vector2i(layout.ui_logic_size)
	if viewport.size_2d_override != logical_size:
		viewport.size_2d_override = logical_size
	_applied_layout = layout
	return layout


## The viewport a host mounts its route roots and their CanvasLayers into. It builds the
## hierarchy when asked before the stage entered the tree, so mounting order never
## matters: the same viewport is handed out before and after _ready.
func get_presentation_viewport() -> SubViewport:
	_build_children()
	return viewport


## The plan the stage is presenting, or the plan for its current rect when nothing has
## been applied yet. Always a copy: callers may diff it, not edit it.
func layout_snapshot() -> Dictionary:
	if _applied_layout.is_empty():
		return layout_for_policy(Vector2i(size), _presentation_policy)
	return _applied_layout.duplicate()


func _build_children() -> void:
	if viewport != null:
		return

	_ink_background = ColorRect.new()
	_ink_background.name = INK_BACKGROUND_NAME
	_ink_background.color = ink_color
	# Ink is decoration: the stage behind it is what stops the click.
	_ink_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_ink_background)

	stage_container = SubViewportContainer.new()
	stage_container.name = STAGE_CONTAINER_NAME
	# Stretch keeps the container and its target the same size (a 1:1 blit) and is what
	# forwards mouse and touch into the mounted viewport.
	stage_container.stretch = true
	stage_container.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(stage_container)

	viewport = SubViewport.new()
	viewport.name = PRESENTATION_VIEWPORT_NAME
	# SubViewport defaults to LINEAR independently of the root project setting.
	# World draw calls inherit this filter (UI icons set their own); without it
	# strict source pixels blur even at an otherwise exact 2x or 3x world scale.
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	# Fixed routes override this target to 1280x720; adaptive shell routes replace it
	# with the available logical window size in apply_window_size().
	viewport.size_2d_override = UI_LOGIC_SIZE
	viewport.size_2d_override_stretch = true
	viewport.transparent_bg = false
	stage_container.add_child(viewport)
