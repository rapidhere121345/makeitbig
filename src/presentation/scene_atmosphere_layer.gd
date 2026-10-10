class_name SceneAtmosphereLayer
extends Node2D
## One atmosphere node for SubViewport scenes. It has no input and no children,
## and draws only through the fixed preset contract in SceneAtmosphere.

const Atmosphere = preload("res://src/presentation/scene_atmosphere.gd")

var preset := "hamlet":
	set(value):
		preset = value
		queue_redraw()
var front := false:
	set(value):
		front = value
		queue_redraw()
var bounds := Rect2(Vector2.ZERO, Vector2(1024.0, 640.0)):
	set(value):
		bounds = value
		queue_redraw()
var warm_lights: Array = []:
	set(value):
		warm_lights = value
		queue_redraw()
var include_ground := false:
	set(value):
		include_ground = value
		queue_redraw()
var additive := false:
	set(value):
		additive = value
		_apply_blend_mode()
var light_only := false:
	set(value):
		light_only = value
		queue_redraw()
var fire_only := false:
	set(value):
		fire_only = value
		queue_redraw()
var fire_sockets: Array = []:
	set(value):
		fire_sockets = value
		queue_redraw()
var fire_time := 0.0:
	set(value):
		fire_time = value
		if not fire_sockets.is_empty():
			queue_redraw()

func _draw() -> void:
	if fire_only:
		Atmosphere.draw_fire(self, fire_sockets, fire_time)
		return
	if light_only:
		Atmosphere.draw_lights(self, bounds, warm_lights)
		return
	if front:
		if include_ground:
			Atmosphere.draw_ground(self, bounds, preset, warm_lights, true)
		else:
			Atmosphere.draw_fore(self, bounds, preset)
		return
	Atmosphere.draw_base(self, bounds, preset)
	Atmosphere.draw_ground(self, bounds, preset, warm_lights)
	if not fire_sockets.is_empty():
		Atmosphere.draw_fire(self, fire_sockets, fire_time)

func atmosphere_report() -> Dictionary:
	var report := Atmosphere.atmosphere_report(preset, bounds, warm_lights)
	report["additive"] = additive
	report["fire_sockets"] = fire_sockets.size()
	return report

func _apply_blend_mode() -> void:
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD if additive else CanvasItemMaterial.BLEND_MODE_MIX
	self.material = material
