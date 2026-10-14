class_name ArenaActorPresenter
extends RefCounted

## Read-only actor projection.
##
## This service owns actor draw order, sprite placement, Boss part assembly,
## corpse playback and the shared occlusion prepass. It consumes authoritative
## positions plus already-resolved presentation frames. It never reads input,
## moves a body, chooses an animation state, or writes back to room state.

const ArenaWorldViewScript := preload("res://src/presentation/arena_world_view.gd")
const RangerAnimationScript := preload("res://src/presentation/ranger_animation.gd")
const RangerMotionOverlayScript := preload("res://src/presentation/ranger_motion_overlay.gd")
const EnemyAnimationScript := preload("res://src/presentation/enemy_animation.gd")
const BossActionPoseScript := preload("res://src/presentation/boss_action_pose.gd")
const Snapshot := preload("res://src/presentation/combat_presentation_snapshot.gd")
const PaletteScript := preload("res://src/presentation/combat_palette.gd")
const SortRelation := preload("res://src/presentation/occlusion_query.gd")

const FRAME_KEYS := {
	"presentation_enabled": "bool",
	"in_arena": "bool",
	"sim_tick": "int",
	"player_position": "Vector2",
	"player_facing": "Vector2",
	"ranger_visual_time": "float",
	"ranger_frame": "Dictionary",
	"enemy_frames": "Dictionary",
	"enemies": "Array",
	"enemy_corpses": "Array",
	"boss_health_ratio": "float",
}

var _last_report: Dictionary = {}
var _sort_domain: WeakRef
var _sort_views: Dictionary = {}


## This node owns only draw commands; its identity is never used for combat.
class SortView extends Node2D:
	var renderer: WeakRef
	var frame: Dictionary
	var drawable: Dictionary
	var world_view: RefCounted
	var art_to_native: Transform2D

	func _draw() -> void:
		var owner_value: Variant = renderer.get_ref() if renderer != null else null
		if owner_value == null:
			return
		var matrix := Transform2D(0.0, -position) * art_to_native
		set_meta("actor_world_transform", matrix)
		draw_set_transform_matrix(matrix)
		owner_value.draw_entry(self, frame, world_view, drawable)



func contract_report() -> Dictionary:
	return {
		"frame_keys": FRAME_KEYS.duplicate(true),
		"authority": "parent-owned read-only actor frame",
		"canvas_owner": "caller owns world transform",
		"draw_layers": ["actor_shadows", "authored_structure", "actors", "corpses"],
		"writes_gameplay_state": false,
		"fallback_art": false,
		"native_sort_interface": "sync_sort_views(WorldPresenter, detached actor frame, ArenaWorldView); host uses gameplay_transform on WorldPresenter",
		"sort_identity": "stable entity/part IDs; no Node instance IDs",
		"sort_relation": "baseline/y, rank, stable id shared by draw and occlusion",
	}


func presentation_report() -> Dictionary:
	return _last_report.duplicate(true)


func validate_frame(frame: Dictionary) -> String:
	for key in FRAME_KEYS:
		if not frame.has(key):
			return "frame missing required key: %s" % key
	if not frame["presentation_enabled"] is bool:
		return "frame key presentation_enabled must be bool"
	if not frame["in_arena"] is bool:
		return "frame key in_arena must be bool"
	if not frame["sim_tick"] is int:
		return "frame key sim_tick must be int"
	if int(frame["sim_tick"]) < 0:
		return "frame key sim_tick must be non-negative"
	if not frame["player_position"] is Vector2:
		return "frame key player_position must be Vector2"
	if not frame["player_facing"] is Vector2:
		return "frame key player_facing must be Vector2"
	if not (frame["player_position"] as Vector2).is_finite() or not (frame["player_facing"] as Vector2).is_finite():
		return "frame key player position/facing must be finite"
	if not frame["ranger_visual_time"] is float and not frame["ranger_visual_time"] is int:
		return "frame key ranger_visual_time must be numeric"
	if not is_finite(float(frame["ranger_visual_time"])):
		return "frame key ranger_visual_time must be finite"
	if not frame["ranger_frame"] is Dictionary:
		return "frame key ranger_frame must be Dictionary"
	if not frame["enemy_frames"] is Dictionary:
		return "frame key enemy_frames must be Dictionary"
	if not frame["enemies"] is Array:
		return "frame key enemies must be Array"
	if not frame["enemy_corpses"] is Array:
		return "frame key enemy_corpses must be Array"
	if not frame["boss_health_ratio"] is float and not frame["boss_health_ratio"] is int:
		return "frame key boss_health_ratio must be numeric"
	var boss_health_ratio := float(frame["boss_health_ratio"])
	if not is_finite(boss_health_ratio) or boss_health_ratio < 0.0 or boss_health_ratio > 1.0:
		return "frame key boss_health_ratio must be finite in [0, 1]"
	for enemy_value: Variant in frame["enemies"]:
		if not enemy_value is CombatEnemyState:
			return "frame enemies must contain CombatEnemyState values"
		var enemy: CombatEnemyState = enemy_value
		if enemy.entity_id <= 0 or not enemy.position.is_finite() or not is_finite(enemy.health) or not is_finite(enemy.maximum_health):
			return "frame enemy state is invalid"
	for corpse_value: Variant in frame["enemy_corpses"]:
		if not corpse_value is Dictionary:
			return "frame enemy_corpses must contain Dictionary values"
		var corpse: Dictionary = corpse_value
		if corpse.has("position") and not corpse["position"] is Vector2:
			return "frame corpse position must be Vector2"
		if corpse.has("position") and not (corpse["position"] as Vector2).is_finite():
			return "frame corpse position must be finite"
	return ""


func draw_shadows(canvas: CanvasItem, frame: Dictionary, world_view: RefCounted) -> void:
	if canvas == null or world_view == null or not _frame_is_drawable(frame):
		return
	world_view.draw_shadow(canvas, world_view.gameplay_to_world(frame["player_position"]), 30.0, 12.0, 0.24)
	for enemy: CombatEnemyState in frame["enemies"]:
		if enemy.is_boss:
			world_view.draw_shadow(canvas, world_view.gameplay_to_world(enemy.position), 92.0, 28.0, 0.34)
		else:
			world_view.draw_shadow(canvas, world_view.gameplay_to_world(enemy.position), 38.0, 14.0, 0.24)
	_record_report(frame, "actor_shadows")


## Pure authored draw projection. No separately authored visual-parts schema.
## Body/core use one enemy record and one phase; each hand uses its gameplay pose.
func draw_list(frame: Dictionary, world_view: RefCounted) -> Array[Dictionary]:
	var drawables: Array[Dictionary] = []
	var structure_list: Array[Dictionary] = world_view.structure_draw_list()
	for structure_index: int in structure_list.size():
		var entry: Dictionary = structure_list[structure_index]
		var feet: Vector2 = entry.feet_world
		var sprite_id := String(entry.sprite_id)
		var stable_id := "structure/%d/%s" % [structure_index, sprite_id]
		drawables.append({"id": stable_id, "stable_id": stable_id, "baseline_y": feet.y, "y": feet.y, "rank": 0, "kind": "structure", "sprite": sprite_id, "world": feet})
	var tower_feet: Vector2 = world_view.tower_feet_world()
	drawables.append({"id": "structure/tower", "stable_id": "structure/tower", "baseline_y": tower_feet.y, "y": tower_feet.y, "rank": 0, "kind": "tower", "world": tower_feet})
	for enemy: CombatEnemyState in frame["enemies"]:
		var feet: Vector2 = world_view.gameplay_to_world(enemy.position)
		if enemy.is_boss:
			var awakened := enemy.phase_id == "awakened"
			var left_base := enemy.position + Vector2(-43.0 if awakened else -34.0, -8.0 if awakened else 0.0)
			var right_base := enemy.position + Vector2(38.0 if awakened else 34.0, 12.0 if awakened else 0.0)
			for part: Dictionary in world_view.boss_draw_parts(feet, 2 if awakened else 1, enemy.left_hand_position - left_base, enemy.right_hand_position - right_base, boss_visual_pose(enemy, int(frame["sim_tick"]))):
				var anchor: Vector2 = part.sort_feet
				var stable_id := "enemy/%d/%s" % [enemy.entity_id, part.part_id]
				drawables.append({"id": stable_id, "stable_id": stable_id, "entity_id": enemy.entity_id, "part_id": part.part_id, "baseline_y": anchor.y, "y": anchor.y, "rank": 3, "kind": "boss_part", "world": anchor, "enemy": enemy, "part": part})
		else:
			var stable_id := "enemy/%d/body" % enemy.entity_id
			drawables.append({"id": stable_id, "stable_id": stable_id, "entity_id": enemy.entity_id, "part_id": "body", "baseline_y": feet.y, "y": feet.y, "rank": 1, "kind": "enemy", "world": feet, "enemy": enemy})
	for corpse: Dictionary in frame["enemy_corpses"]:
		var feet: Vector2 = world_view.gameplay_to_world(corpse.get("position", Vector2.ZERO) as Vector2)
		var stable_id := "corpse/%d" % int(corpse.get("entity_id", 0))
		drawables.append({"id": stable_id, "stable_id": stable_id, "baseline_y": feet.y, "y": feet.y, "rank": 1, "kind": "corpse", "world": feet, "corpse": corpse})
	var hero_world: Vector2 = world_view.gameplay_to_world(frame["player_position"])
	drawables.append({"id": "ranger/body", "stable_id": "ranger/body", "entity_id": "ranger", "part_id": "body", "baseline_y": hero_world.y, "y": hero_world.y, "rank": 2, "kind": "player", "world": hero_world})
	drawables.sort_custom(_drawable_precedes)
	return drawables


func draw(canvas: CanvasItem, frame: Dictionary, world_view: RefCounted) -> void:
	if canvas == null or world_view == null or not _frame_is_drawable(frame):
		return
	_set_hero_occlusion_box(frame, world_view)
	var drawables := draw_list(frame, world_view)
	_prepare_occlusion(drawables, frame, world_view)
	for drawable: Dictionary in drawables:
		draw_entry(canvas, frame, world_view, drawable)
	_record_report(frame, "actors")
	_last_report["draw_ids"] = drawables.map(func(entry: Dictionary) -> String: return String(entry.id))
	_last_report["sort_domain"] = "actor_canvas"


func _prepare_occlusion(drawables: Array[Dictionary], frame: Dictionary, world_view: RefCounted) -> void:
	var front_cells: Array[Dictionary] = []
	var hero_drawable: Dictionary = {}
	for drawable: Dictionary in drawables:
		if drawable.kind == "player":
			hero_drawable = drawable
			break
	if hero_drawable.is_empty():
		world_view.prepare_actor_occlusion([], world_view.gameplay_to_world(frame["player_position"]))
		return
	for drawable: Dictionary in drawables:
		if drawable.kind != "player" and SortRelation.is_front(drawable, hero_drawable):
			var feet: Vector2 = drawable.world
			if drawable.kind == "boss_part":
				var part: Dictionary = drawable.part
				var visibility: Dictionary = world_view.sprite_occlusion_descriptor(String(part.sprite_id), part.feet)
				front_cells.append({"id": drawable.id, "stable_id": drawable.stable_id, "sort_rank": int(drawable.rank), "baseline_y": float(drawable.baseline_y), "feet_world": feet, "art_box": visibility.get("art_box", Rect2()), "visibility": visibility, "base_alpha": 1.0})
			elif drawable.kind == "corpse":
				var corpse_frame: Dictionary = drawable.corpse.get("frame", {})
				if not corpse_frame.is_empty() and not bool(corpse_frame.get("fallback", true)):
					var corpse_visibility := _enemy_frame_occlusion_descriptor(corpse_frame, feet, world_view)
					front_cells.append({"id": drawable.id, "stable_id": drawable.stable_id, "sort_rank": int(drawable.rank), "baseline_y": float(drawable.baseline_y), "feet_world": feet, "art_box": corpse_visibility.get("art_box", Rect2()), "visibility": corpse_visibility, "base_alpha": 1.0})
			elif drawable.kind == "enemy":
				var enemy_visibility := _enemy_occlusion_descriptor(frame, drawable.enemy, feet, world_view)
				front_cells.append({"id": drawable.id, "stable_id": drawable.stable_id, "sort_rank": int(drawable.rank), "baseline_y": float(drawable.baseline_y), "feet_world": feet, "art_box": enemy_visibility.get("art_box", Rect2()), "visibility": enemy_visibility, "base_alpha": 1.0})
	world_view.prepare_actor_occlusion(front_cells, world_view.gameplay_to_world(frame["player_position"]))


func draw_entry(canvas: CanvasItem, frame: Dictionary, world_view: RefCounted, drawable: Dictionary) -> void:
	var hero: Vector2 = world_view.gameplay_to_world(frame["player_position"])
	match String(drawable.kind):
		"structure":
			world_view.draw_structure(canvas, String(drawable.sprite), drawable.world, hero)
		"tower":
			world_view.draw_tower(canvas, hero)
		"boss_part":
			world_view.draw_boss_part(canvas, drawable.part, hero, int(drawable.rank), String(drawable.id))
			if String(drawable.part_id) == "body":
				_draw_boss_world_bar(canvas, frame, world_view, drawable.enemy)
		"enemy":
			_draw_enemy(canvas, frame, world_view, drawable.enemy, int(drawable.rank), String(drawable.id))
		"corpse":
			_draw_enemy_corpse(canvas, frame, world_view, drawable.corpse, int(drawable.rank), String(drawable.id))
		"player":
			_draw_player(canvas, frame, world_view)


## Narrow native integration seam. The caller supplies the existing room
## WorldPresenter and places it under world_view.gameplay_transform(). Each cell
## becomes a direct sibling of native SortRoot children, with z_index left at 0.
## This submits view state outside a CanvasItem _draw; do not also call draw().
func sync_sort_views(domain: WorldPresenter, frame: Dictionary, world_view: RefCounted) -> Dictionary:
	if domain == null or world_view == null:
		return {"ok": false, "error": "sort_domain_unavailable"}
	var error := validate_frame(frame)
	if not error.is_empty():
		return {"ok": false, "error": error}
	if _sort_domain == null or _sort_domain.get_ref() != domain:
		release_sort_views()
		_sort_domain = weakref(domain)
	if not bool(frame.presentation_enabled) or not bool(frame.in_arena):
		release_sort_views()
		return {"ok": true, "error": "", "ids": []}
	_set_hero_occlusion_box(frame, world_view)
	var detached := frame.duplicate(true)
	var enemies: Array[CombatEnemyState] = []
	for enemy: CombatEnemyState in frame.enemies:
		enemies.append(Snapshot.enemy_record(enemy))
	detached["enemies"] = enemies
	var drawables := draw_list(detached, world_view)
	_prepare_occlusion(drawables, detached, world_view)
	var ids: Array[String] = []
	for drawable: Dictionary in drawables:
		ids.append(String(drawable.id))
	for id: String in _sort_views.keys():
		if not ids.has(id):
			domain.unregister_actor_view(id)
			_sort_views.erase(id)
	var art_to_native: Transform2D = world_view.gameplay_transform().affine_inverse() * world_view.world_transform()
	for drawable: Dictionary in drawables:
		var id := String(drawable.id)
		var view: SortView = _sort_views.get(id)
		if not is_instance_valid(view):
			view = SortView.new()
			view.name = id.replace("/", "_")
			view.renderer = weakref(self)
			var registration := domain.register_actor_view(id, view)
			if not bool(registration.ok):
				view.free()
				return registration
			_sort_views[id] = view
		view.frame = detached
		view.drawable = drawable
		view.world_view = world_view
		view.art_to_native = art_to_native
		domain.sync_actor(id, art_to_native * (drawable.world as Vector2), Vector2.ZERO, int(drawable.rank), id)
		view.queue_redraw()
	_record_report(detached, "actors")
	_last_report["sort_domain"] = "shared_sort_root"
	_last_report["draw_ids"] = ids
	return {"ok": true, "error": "", "ids": ids}


func release_sort_views() -> void:
	var domain: Variant = _sort_domain.get_ref() if _sort_domain != null else null
	if domain != null:
		for id: String in _sort_views.keys():
			domain.unregister_actor_view(id)
	_sort_views.clear()
	_sort_domain = null


func _frame_is_drawable(frame: Dictionary) -> bool:
	var error := validate_frame(frame)
	if not error.is_empty():
		_last_report = {"state": "presentation_error", "error": error, "contract": contract_report()}
		return false
	if not bool(frame["presentation_enabled"]) or not bool(frame["in_arena"]):
		_record_report(frame, "disabled")
		return false
	return true


func _record_report(frame: Dictionary, pass_name: String) -> void:
	_last_report = {
		"state": "disabled" if pass_name == "disabled" else "ready",
		"pass": pass_name,
		"sim_tick": int(frame.get("sim_tick", 0)),
		"enemy_count": (frame.get("enemies", []) as Array).size(),
		"corpse_count": (frame.get("enemy_corpses", []) as Array).size(),
		"contract": contract_report(),
	}


func _drawable_precedes(left: Dictionary, right: Dictionary) -> bool:
	return SortRelation.precedes(left, right)


## Keep the cutaway envelope tied to the same destination rectangle as the live
## ranger draw.  The fallback remains the conservative 48x48 cell; resolved
## action frames additionally carry their authored draw offset.
func _set_hero_occlusion_box(frame: Dictionary, world_view: RefCounted) -> void:
	if not world_view.has_method("set_hero_occlusion_box"):
		return
	var feet: Vector2 = world_view.gameplay_to_world(frame["player_position"])
	var action_frame: Dictionary = frame.get("ranger_frame", {})
	if action_frame.is_empty() or bool(action_frame.get("fallback", true)):
		var facing := _player_facing_name(frame.get("player_facing", Vector2.DOWN))
		var idle_box: Rect2 = world_view.sprite_art_box("ranger.%s.idle" % facing, feet) if world_view.has_method("sprite_art_box") else Rect2()
		world_view.set_hero_occlusion_box(idle_box if idle_box.size.x > 0.0 and idle_box.size.y > 0.0 else Rect2(feet - Vector2(24.0, 44.0), Vector2(48.0, 48.0)))
		return
	var rect: Rect2i = action_frame.get("rect", Rect2i())
	var anchor: Vector2i = action_frame.get("anchor", RangerAnimationScript.DEFAULT_ANCHOR)
	var draw_offset: Vector2i = action_frame.get("draw_offset", Vector2i.ZERO)
	var texture: Texture2D = action_frame.get("texture")
	if texture != null and world_view.has_method("frame_art_box"):
		var visible_box: Rect2 = world_view.frame_art_box(texture, Rect2(rect), feet, Vector2(anchor), Vector2(draw_offset), bool(action_frame.get("flip_x", false)))
		if visible_box.size.x > 0.0 and visible_box.size.y > 0.0:
			world_view.set_hero_occlusion_box(visible_box)
			return
	var destination := Rect2((feet - Vector2(anchor) + Vector2(draw_offset)).round(), Vector2(rect.size))
	world_view.set_hero_occlusion_box(destination)


func _draw_player(canvas: CanvasItem, frame: Dictionary, world_view: RefCounted) -> void:
	var action_frame: Dictionary = frame["ranger_frame"]
	var feet: Vector2 = world_view.gameplay_to_world(frame["player_position"])
	if not action_frame.is_empty():
		_draw_ranger_frame(canvas, frame, world_view, action_frame, feet)
		return
	var facing := _player_facing_name(frame["player_facing"])
	RangerMotionOverlayScript.draw_back(canvas, feet, facing, "idle", 0, float(frame["ranger_visual_time"]))
	world_view.draw_sprite(canvas, "ranger.%s.idle" % facing, feet)
	RangerMotionOverlayScript.draw_front(canvas, feet, facing, "idle", 0, float(frame["ranger_visual_time"]))


func _draw_ranger_frame(canvas: CanvasItem, frame: Dictionary, world_view: RefCounted, action_frame: Dictionary, feet_world: Vector2) -> void:
	var texture: Texture2D = action_frame.get("texture")
	var rect: Rect2i = action_frame.get("rect", Rect2i())
	if texture == null or rect.size.x <= 0 or rect.size.y <= 0:
		return
	var anchor: Vector2i = action_frame.get("anchor", RangerAnimationScript.DEFAULT_ANCHOR)
	var draw_offset: Vector2i = action_frame.get("draw_offset", Vector2i.ZERO)
	var facing := String(action_frame.get("facing", _player_facing_name(frame["player_facing"])))
	var action := String(action_frame.get("action", "idle"))
	var frame_index := int(action_frame.get("frame", 0))
	RangerMotionOverlayScript.draw_back(canvas, feet_world, facing, action, frame_index, float(frame["ranger_visual_time"]))
	canvas.draw_texture_rect_region(texture, Rect2((feet_world - Vector2(anchor) + Vector2(draw_offset)).round(), Vector2(rect.size)), Rect2(rect))
	RangerMotionOverlayScript.draw_front(canvas, feet_world, facing, action, frame_index, float(frame["ranger_visual_time"]))


func _draw_enemy(canvas: CanvasItem, frame: Dictionary, world_view: RefCounted, enemy: CombatEnemyState, sort_rank: int = 1, stable_id: String = "") -> void:
	var feet: Vector2 = world_view.gameplay_to_world(enemy.position)
	var role_tint := Color(1.20, 1.18, 1.14, 1.0)
	match enemy.kind_id:
		"charging_raider": role_tint = Color(1.22, 1.16, 1.10, 1.0)
		"fan_ranged": role_tint = Color(1.14, 1.20, 1.24, 1.0)
	var modulate := Color(1.6, 1.6, 1.6, 1.0) if int(frame["sim_tick"]) < enemy.hit_flash_until_tick else role_tint
	var action_frame := _enemy_action_frame(frame, enemy.entity_id)
	if not action_frame.is_empty():
		var visibility := _enemy_frame_occlusion_descriptor(action_frame, feet, world_view)
		var cut: Dictionary = world_view.cutaway_for(visibility.get("art_box", Rect2()), feet, world_view.gameplay_to_world(frame["player_position"]), sort_rank, stable_id, visibility)
		_draw_enemy_action_frame(canvas, world_view, action_frame, feet, modulate, cut["window"] if cut["in_front"] else Rect2(), float(cut["local_alpha"]))
	else:
		var sprite_id := "enemy.%s.%s" % [_enemy_role_id(enemy), _enemy_pose_id(enemy)]
		var visibility: Dictionary = world_view.sprite_occlusion_descriptor(sprite_id, feet, enemy.facing.x < -0.001)
		var cut: Dictionary = world_view.cutaway_for(visibility.get("art_box", Rect2()), feet, world_view.gameplay_to_world(frame["player_position"]), sort_rank, stable_id, visibility)
		world_view.draw_sprite(canvas, sprite_id, feet, enemy.facing.x < -0.001, modulate, cut["window"] if cut["in_front"] else Rect2(), float(cut["local_alpha"]))


func _draw_enemy_corpse(canvas: CanvasItem, frame: Dictionary, world_view: RefCounted, corpse: Dictionary, sort_rank: int = 1, stable_id: String = "") -> void:
	var action_frame: Dictionary = corpse.get("frame", {})
	if action_frame.is_empty() or bool(action_frame.get("fallback", true)):
		return
	var feet: Vector2 = world_view.gameplay_to_world(corpse.get("position", Vector2.ZERO) as Vector2)
	var visibility := _enemy_frame_occlusion_descriptor(action_frame, feet, world_view)
	var cut: Dictionary = world_view.cutaway_for(visibility.get("art_box", Rect2()), feet, world_view.gameplay_to_world(frame["player_position"]), sort_rank, stable_id, visibility)
	_draw_enemy_action_frame(canvas, world_view, action_frame, feet, Color.WHITE, cut["window"] if cut["in_front"] else Rect2(), float(cut["local_alpha"]))


func _enemy_action_frame(frame: Dictionary, entity_id: int) -> Dictionary:
	var action_frame: Dictionary = frame["enemy_frames"].get(entity_id, {})
	return {} if bool(action_frame.get("fallback", true)) else action_frame


func _enemy_frame_art_box(action_frame: Dictionary, feet_world: Vector2, world_view: RefCounted = null) -> Rect2:
	var rect: Rect2i = action_frame.get("rect", Rect2i())
	if rect.size.x <= 0 or rect.size.y <= 0:
		return Rect2()
	var anchor: Vector2i = action_frame.get("anchor", EnemyAnimationScript.DEFAULT_ANCHOR)
	if world_view != null and world_view.has_method("frame_occlusion_descriptor"):
		var visibility := _enemy_frame_occlusion_descriptor(action_frame, feet_world, world_view)
		var visible_box: Rect2 = visibility.get("art_box", Rect2())
		if visible_box.size.x > 0.0 and visible_box.size.y > 0.0:
			return visible_box
	return Rect2((feet_world - Vector2(anchor)).round(), Vector2(rect.size))


func _enemy_frame_occlusion_descriptor(action_frame: Dictionary, feet_world: Vector2, world_view: RefCounted) -> Dictionary:
	var rect: Rect2i = action_frame.get("rect", Rect2i())
	var anchor: Vector2i = action_frame.get("anchor", EnemyAnimationScript.DEFAULT_ANCHOR)
	var texture: Texture2D = action_frame.get("texture")
	if world_view != null and world_view.has_method("frame_occlusion_descriptor"):
		return world_view.frame_occlusion_descriptor(texture, Rect2(rect), feet_world, Vector2(anchor), Vector2.ZERO, bool(action_frame.get("flip_x", false)))
	return {"art_box": Rect2((feet_world - Vector2(anchor)).round(), Vector2(rect.size)), "conservative": true}


func _enemy_occlusion_descriptor(frame: Dictionary, enemy: CombatEnemyState, feet_world: Vector2, world_view: RefCounted) -> Dictionary:
	var action_frame := _enemy_action_frame(frame, enemy.entity_id)
	if not action_frame.is_empty():
		return _enemy_frame_occlusion_descriptor(action_frame, feet_world, world_view)
	var sprite_id := "enemy.%s.%s" % [_enemy_role_id(enemy), _enemy_pose_id(enemy)]
	if world_view != null and world_view.has_method("sprite_occlusion_descriptor"):
		return world_view.sprite_occlusion_descriptor(sprite_id, feet_world, enemy.facing.x < -0.001)
	return {"art_box": Rect2(feet_world - Vector2(24.0, 44.0), Vector2(48.0, 48.0)), "conservative": true}


func _enemy_art_box(frame: Dictionary, enemy: CombatEnemyState, feet_world: Vector2, world_view: RefCounted) -> Rect2:
	return _enemy_occlusion_descriptor(frame, enemy, feet_world, world_view).get("art_box", Rect2())


func _draw_enemy_action_frame(canvas: CanvasItem, world_view: RefCounted, action_frame: Dictionary, feet_world: Vector2, modulate: Color, cut: Rect2, cut_alpha: float) -> void:
	var texture: Texture2D = action_frame.get("texture")
	var rect: Rect2i = action_frame.get("rect", Rect2i())
	if texture == null or rect.size.x <= 0 or rect.size.y <= 0:
		return
	var anchor := Vector2(action_frame.get("anchor", EnemyAnimationScript.DEFAULT_ANCHOR))
	var region := Rect2(rect)
	var destination := Rect2((feet_world - anchor).round(), region.size)
	var visible: Rect2 = destination.intersection(world_view.visible_world_region())
	if visible.size.x <= 0.0 or visible.size.y <= 0.0:
		return
	var core := _enemy_frame_cut_core(destination, cut, cut_alpha)
	if bool(action_frame.get("flip_x", false)):
		var center := destination.position + destination.size * 0.5
		var pieces: Array[Dictionary] = [{"dest": visible, "alpha": modulate.a}]
		if core.has_area():
			pieces = world_view.cut_pieces(destination, region, core, modulate.a, cut_alpha)
		canvas.draw_set_transform_matrix(_canvas_world_transform(canvas, world_view) * Transform2D(0.0, Vector2(-1.0, 1.0), 0.0, center))
		for piece: Dictionary in pieces:
			var piece_dest: Rect2 = piece["dest"]
			var mirrored_local := Rect2(Vector2(center.x - piece_dest.end.x, piece_dest.position.y - center.y), piece_dest.size)
			var mirrored_source := Rect2(region.position + Vector2(destination.size.x - (piece_dest.end.x - destination.position.x), piece_dest.position.y - destination.position.y), piece_dest.size)
			canvas.draw_texture_rect_region(texture, mirrored_local, mirrored_source, Color(modulate.r, modulate.g, modulate.b, float(piece["alpha"])))
		canvas.draw_set_transform_matrix(_canvas_world_transform(canvas, world_view))
		return
	if core.has_area():
		for piece: Dictionary in world_view.cut_pieces(destination, region, core, modulate.a, cut_alpha, false):
			var piece_dest: Rect2 = piece["dest"]
			var clipped: Rect2 = piece_dest.intersection(world_view.visible_world_region())
			if clipped.size.x <= 0.0 or clipped.size.y <= 0.0:
				continue
			var piece_source := Rect2(region.position + (clipped.position - destination.position), clipped.size)
			canvas.draw_texture_rect_region(texture, clipped, piece_source, Color(modulate.r, modulate.g, modulate.b, float(piece["alpha"])))
		return
	var source := Rect2(region.position + (visible.position - destination.position), visible.size)
	canvas.draw_texture_rect_region(texture, visible, source, modulate)


func _enemy_frame_cut_core(destination: Rect2, cut: Rect2, cut_alpha: float) -> Rect2:
	if cut.size.x <= 0.0 or cut.size.y <= 0.0 or cut_alpha >= 0.999:
		return Rect2()
	var local := Rect2((cut.position - destination.position).round(), cut.size.round())
	return local.intersection(Rect2(Vector2.ZERO, destination.size))


## Public pure projection used by the focused pose contract. It reads the
## authoritative Boss fields and returns a presentation frame without mutating
## the enemy or the presenter.
func boss_visual_pose(enemy: CombatEnemyState, sim_tick: int) -> Dictionary:
	var pose_frame: Dictionary = BossActionPoseScript.pose(
		String(enemy.action_id),
		String(enemy.action_state),
		sim_tick,
		enemy.state_started_tick,
		enemy.state_ends_tick,
		2 if enemy.phase_id == "awakened" else 1,
		enemy.facing,
		String(enemy.phase_state)
	)
	var bridge: Dictionary = BossActionPoseScript.authority_recovery_hand_offsets(
		String(enemy.action_id),
		String(enemy.action_state),
		sim_tick,
		enemy.state_started_tick,
		enemy.state_ends_tick,
		enemy.facing,
		ArenaWorldViewScript.GAMEPLAY_TO_WORLD
	)
	var pose_left: Vector2 = Vector2(pose_frame["left_hand_offset_px"] as Vector2i)
	var pose_right: Vector2 = Vector2(pose_frame["right_hand_offset_px"] as Vector2i)
	var left_total: Vector2 = pose_left + (bridge["left"] as Vector2)
	var right_total: Vector2 = pose_right + (bridge["right"] as Vector2)
	if left_total != pose_left or right_total != pose_right:
		pose_frame["left_hand_offset_px"] = Vector2i(roundi(left_total.x), roundi(left_total.y))
		pose_frame["right_hand_offset_px"] = Vector2i(roundi(right_total.x), roundi(right_total.y))
	return pose_frame


func _draw_boss_world_bar(canvas: CanvasItem, frame: Dictionary, world_view: RefCounted, enemy: CombatEnemyState) -> void:
	var feet: Vector2 = world_view.gameplay_to_world(enemy.position)
	var top_left := feet + Vector2(-32.0, -134.0)
	var width := 64.0
	var height := 3.0
	var ratio := clampf(float(frame["boss_health_ratio"]), 0.0, 1.0)
	canvas.draw_rect(Rect2(top_left, Vector2(width, height)), PaletteScript.SLATE_0)
	canvas.draw_rect(Rect2(top_left, Vector2(width * ratio, height)), PaletteScript.DANGER_BRIGHT)
	canvas.draw_rect(Rect2(top_left, Vector2(width, height)), PaletteScript.BONE, false, maxf(1.0, height / 6.0))


func _player_facing_name(facing: Vector2) -> String:
	if absf(facing.x) > absf(facing.y):
		return "east" if facing.x >= 0.0 else "west"
	return "south" if facing.y >= 0.0 else "north"


func _enemy_role_id(enemy: CombatEnemyState) -> String:
	match enemy.kind_id:
		"charging_raider": return "charger"
		"fan_ranged": return "ranged"
		_: return "melee"


func _enemy_pose_id(enemy: CombatEnemyState) -> String:
	match enemy.action_state:
		"windup": return "windup"
		"active": return "active"
		"recovery": return "recover"
		_: return "idle"


func _canvas_world_transform(canvas: CanvasItem, world_view: RefCounted) -> Transform2D:
	return canvas.get_meta("actor_world_transform", world_view.world_transform()) as Transform2D
