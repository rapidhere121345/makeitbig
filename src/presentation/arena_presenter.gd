class_name ArenaPresenter
extends Node2D

## First presentation boundary for the arena.
##
## ArenaPresenter is deliberately a projection node. It never advances time,
## moves an actor, queries collision, mutates combat state, or invents an intent.
## The parent remains the owner of those concerns and supplies a read-only frame
## snapshot through frame_provider.
##
## Callback direction:
##   parent -> configure(frame_provider, dependency_provider)
##   presenter -> frame_provider.call() during _draw()
##   presenter -> dependency_provider.call() when the presentation dependencies
##                are needed
##
## The presenter never calls back into the parent with a command. A parent may
## call request_redraw() after publishing a new frame, or rely on the normal
## CanvasItem redraw lifecycle.
##
## Required frame keys (Dictionary returned by frame_provider):
##   presentation_enabled: bool
##   in_arena: bool
##   viewport_rect: Rect2       Canvas coordinates used for the frame.
##   arena_rect: Rect2          Authoritative gameplay arena rectangle.
##   focus_gameplay: Vector2    Camera focus in gameplay coordinates.
##   layout_id: String          Presentation room identity.
##   sim_tick: int              Stable phase value for room concept art.
##   pending_reason: String     Optional diagnostic used by the error surface.
##
## Dependency keys (Dictionary returned by dependency_provider):
##   world_view: ArenaWorldView
##       The existing presentation reader. It must already have its approved
##       art loaded; the presenter reports its pending_reason when it is not
##       ready. The presenter does not substitute another atlas or draw proxy
##       actor art.
##   font: Font (optional)
##       Font for the presentation error surface. ThemeDB's fallback font is
##       used only for that diagnostic text when this optional key is absent.
##
## Transform ownership is explicit:
##   world_view.world_transform()    native art / ground / room concept
##   world_view.gameplay_transform() authoritative gameplay overlays (reserved
##                                   for the actor/telegraph extension seam)
##   Transform2D.IDENTITY             screen-space error and boundary surfaces
##
## Actor and telegraph drawing intentionally remains an extension seam. The
## parent can add a later read-only drawing pass using the same frame and the
## published transforms without giving this node a second movement authority.

const PaletteScript := preload("res://src/presentation/combat_palette.gd")
const ArenaWorldViewScript := preload("res://src/presentation/arena_world_view.gd")
const RoomCatalogScript := preload("res://src/runtime/world/room_catalog.gd")

const STATE_UNCONFIGURED := "unconfigured"
const STATE_READY := "ready"
const STATE_PRESENTATION_ERROR := "presentation_error"
const STATE_DISABLED := "disabled"

const FRAME_KEYS := {
	"presentation_enabled": "bool",
	"in_arena": "bool",
	"viewport_rect": "Rect2",
	"arena_rect": "Rect2",
	"focus_gameplay": "Vector2",
	"layout_id": "String",
	"sim_tick": "int",
	"pending_reason": "String (optional)",
}
const DEPENDENCY_KEYS := {
	"world_view": "ArenaWorldView",
	"font": "Font (optional)",
}

var _frame_provider: Callable
var _dependency_provider: Callable
var _configured := false
var _world_view: RefCounted
var _font: Font
var _last_frame: Dictionary = {}
var _last_report: Dictionary = {}
var _last_draw_state := STATE_UNCONFIGURED
var _last_error := ""
var _dependency_read := false
var _room_catalog: RefCounted


func _init() -> void:
	_room_catalog = RoomCatalogScript.new()


func configure(frame_provider: Callable, dependency_provider: Callable = Callable()) -> void:
	## The callbacks are retained as read-only pull sources. Neither callback is
	## invoked during configure(), so configuration cannot advance simulation.
	_frame_provider = frame_provider
	_dependency_provider = dependency_provider
	_configured = frame_provider.is_valid()
	_world_view = null
	_font = null
	_last_frame.clear()
	_last_error = "" if _configured else "frame_provider is not callable"
	_last_draw_state = STATE_READY if _configured else STATE_UNCONFIGURED
	_dependency_read = false
	request_redraw()


func request_redraw() -> void:
	queue_redraw()


func is_configured() -> bool:
	return _configured


func contract_report() -> Dictionary:
	return {
		"frame_keys": FRAME_KEYS.duplicate(true),
		"dependency_keys": DEPENDENCY_KEYS.duplicate(true),
		"callback_direction": "presenter pulls frame and dependencies; parent never receives commands",
		"draw_layers": ["base_backdrop", "presentation_error", "world_ground", "room_concept", "decals", "structure_shadows", "actor_telegraph_extension"],
		"transforms": {
			"world": "world_view.world_transform()",
			"gameplay": "world_view.gameplay_transform()",
			"screen": "Transform2D.IDENTITY",
		},
		"fallback_art": false,
	}


func presentation_report() -> Dictionary:
	var report := {
		"state": _last_draw_state,
		"configured": _configured,
		"error": _last_error,
		"fallback_art": false,
		"dependencies_read": _dependency_read,
		"frame": _last_frame.duplicate(true),
		"contract": contract_report(),
		"extension": {
			"actors": "reserved",
			"telegraphs": "reserved",
			"authority": "parent-owned read-only frame projection",
		},
	}
	if _world_view != null and _world_view.has_method("is_ready"):
		report["world_view_ready"] = bool(_world_view.call("is_ready"))
	if _world_view != null and "pending_reason" in _world_view:
		report["world_pending_reason"] = String(_world_view.get("pending_reason"))
	_last_report = report.duplicate(true)
	return report


func report() -> Dictionary:
	return presentation_report()


func _draw() -> void:
	_last_draw_state = STATE_UNCONFIGURED
	_last_error = ""
	_last_frame.clear()
	_reset_canvas_transform()
	if not _configured:
		_last_error = "frame_provider is not callable"
		return

	var frame_variant: Variant = _frame_provider.call()
	if not frame_variant is Dictionary:
		_last_draw_state = STATE_PRESENTATION_ERROR
		_last_error = "frame_provider must return Dictionary"
		_draw_presentation_error(_viewport_rect({}))
		return
	var frame := (frame_variant as Dictionary).duplicate(true)
	_last_frame = frame
	var frame_error := _validate_frame(frame)
	if not frame_error.is_empty():
		_last_draw_state = STATE_PRESENTATION_ERROR
		_last_error = frame_error
		_draw_presentation_error(_viewport_rect(frame))
		return
	if not bool(frame["presentation_enabled"]):
		_last_draw_state = STATE_DISABLED
		return

	var viewport_rect: Rect2 = frame["viewport_rect"]
	if not bool(frame["in_arena"]):
		_last_draw_state = STATE_READY
		_draw_base_backdrop(viewport_rect)
		return

	if not _read_dependencies():
		_last_draw_state = STATE_PRESENTATION_ERROR
		_draw_presentation_error(viewport_rect)
		return
	if _world_view == null or not _world_view.has_method("is_ready") or not bool(_world_view.call("is_ready")):
		_last_draw_state = STATE_PRESENTATION_ERROR
		_last_error = _world_pending_reason()
		_draw_presentation_error(viewport_rect)
		return

	var arena_rect: Rect2 = frame["arena_rect"]
	var focus_gameplay: Vector2 = frame["focus_gameplay"]
	if not bool(frame.get("camera_prepared", false)):
		_world_view.call("begin_frame", viewport_rect, focus_gameplay, arena_rect)
	_reset_canvas_transform()
	var world_transform: Transform2D = _world_view.call("world_transform")
	draw_set_transform_matrix(world_transform)
	_world_view.call("draw_ground", self)
	_world_view.call("draw_room_concept", self, String(frame["layout_id"]), int(frame["sim_tick"]), frame.get("walkable_geometry", {}))
	_world_view.call("draw_decals", self)
	_world_view.call("draw_structure_shadows", self)
	## Actors and telegraphs remain outside this first boundary. Their future pass
	## must consume the same frame and use the transforms above.
	_reset_canvas_transform()
	_last_draw_state = STATE_READY


func _read_dependencies() -> bool:
	if _dependency_read:
		return _world_view != null
	_dependency_read = true
	if not _dependency_provider.is_valid():
		_last_error = "dependency_provider is not callable"
		return false
	var dependency_variant: Variant = _dependency_provider.call()
	if not dependency_variant is Dictionary:
		_last_error = "dependency_provider must return Dictionary"
		return false
	var dependencies := dependency_variant as Dictionary
	var world_variant: Variant = dependencies.get("world_view")
	if world_variant is ArenaWorldViewScript:
		_world_view = world_variant as RefCounted
	else:
		_last_error = "dependency_provider missing world_view"
		return false
	var font_variant: Variant = dependencies.get("font")
	if font_variant is Font:
		_font = font_variant as Font
	return true


func _validate_frame(frame: Dictionary) -> String:
	for key in ["presentation_enabled", "in_arena", "viewport_rect", "arena_rect", "focus_gameplay", "layout_id", "sim_tick"]:
		if not frame.has(key):
			return "frame missing required key: %s" % key
	if not frame["presentation_enabled"] is bool:
		return "frame key presentation_enabled must be bool"
	if not frame["in_arena"] is bool:
		return "frame key in_arena must be bool"
	if not frame["viewport_rect"] is Rect2:
		return "frame key viewport_rect must be Rect2"
	if not frame["arena_rect"] is Rect2:
		return "frame key arena_rect must be Rect2"
	if not frame["focus_gameplay"] is Vector2:
		return "frame key focus_gameplay must be Vector2"
	if not _valid_rect(frame["viewport_rect"] as Rect2) or (frame["viewport_rect"] as Rect2).size.x <= 0.0 or (frame["viewport_rect"] as Rect2).size.y <= 0.0:
		return "frame key viewport_rect must be a finite positive rect"
	if not _valid_rect(frame["arena_rect"] as Rect2) or (frame["arena_rect"] as Rect2).size.x <= 0.0 or (frame["arena_rect"] as Rect2).size.y <= 0.0:
		return "frame key arena_rect must be a finite positive rect"
	if not (frame["focus_gameplay"] as Vector2).is_finite():
		return "frame key focus_gameplay must be finite"
	if not frame["layout_id"] is String:
		return "frame key layout_id must be String"
	var layout_id := String(frame["layout_id"]).strip_edges()
	if layout_id.is_empty():
		return "frame key layout_id must be non-empty"
	if _room_catalog == null or not bool(_room_catalog.resolve({"layout_id": layout_id}).get("ok", false)):
		return "unknown_layout_id:%s" % layout_id
	if not frame["sim_tick"] is int:
		return "frame key sim_tick must be int"
	if int(frame["sim_tick"]) < 0:
		return "frame key sim_tick must be non-negative"
	if frame.has("pending_reason") and not frame["pending_reason"] is String:
		return "frame key pending_reason must be String"
	return ""


func _valid_rect(value: Rect2) -> bool:
	return value.position.is_finite() and value.size.is_finite()


func _viewport_rect(frame: Dictionary) -> Rect2:
	if frame.get("viewport_rect") is Rect2:
		return frame["viewport_rect"] as Rect2
	return Rect2(Vector2.ZERO, get_viewport_rect().size)


func _draw_base_backdrop(viewport_rect: Rect2) -> void:
	## This is the non-arena shell surface, not actor fallback art. It contains no
	## gameplay-shaped rectangles and does not run when the frame is invalid.
	draw_rect(viewport_rect, PaletteScript.INK, true)
	var center := viewport_rect.position + Vector2(viewport_rect.size.x * 0.84, viewport_rect.size.y * 0.78)
	draw_circle(center, minf(viewport_rect.size.x, viewport_rect.size.y) * 0.17, PaletteScript.SLATE_1)
	draw_circle(center, minf(viewport_rect.size.x, viewport_rect.size.y) * 0.11, PaletteScript.INK)
	draw_line(center - Vector2(76.0, -34.0), center + Vector2(76.0, -34.0), PaletteScript.COLD, 6.0)
	draw_line(center - Vector2(52.0, 52.0), center + Vector2(52.0, 52.0), PaletteScript.COPPER_DULL, 2.0)


func _draw_presentation_error(viewport_rect: Rect2) -> void:
	_reset_canvas_transform()
	draw_rect(viewport_rect, PaletteScript.INK, true)
	var font := _font
	if font == null:
		font = ThemeDB.fallback_font
	if font == null:
		return
	draw_string(font, viewport_rect.position + Vector2(32.0, 48.0), "ARENA ART UNAVAILABLE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24, PaletteScript.DANGER_BRIGHT)
	draw_string(font, viewport_rect.position + Vector2(32.0, 78.0), _last_error, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, PaletteScript.SLATE_3)


func _world_pending_reason() -> String:
	if not _last_frame.get("pending_reason", "").is_empty():
		return String(_last_frame.get("pending_reason"))
	if _world_view != null and "pending_reason" in _world_view:
		var reason := String(_world_view.get("pending_reason"))
		if not reason.is_empty():
			return reason
	return "world_view art is not ready"


func _reset_canvas_transform() -> void:
	draw_set_transform_matrix(Transform2D.IDENTITY)
