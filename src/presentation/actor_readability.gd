class_name ActorReadability
extends RefCounted
## Shared materials add local silhouette contrast without touching source art,
## simulation, collision bounds, actor sorting, or occluder reveal materials.
const OutlineShader = preload("res://src/presentation/actor_readability.gdshader")
const RIMS := {"hero": Color("eed69a"), "resident": Color("9cd9ce"), "hostile": Color("e69b86")}
static var _materials: Dictionary = {}

static func material_for(role: String) -> ShaderMaterial:
	var key := role if RIMS.has(role) else "hostile"
	if not _materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = OutlineShader
		material.set_shader_parameter("rim_color", RIMS[key])
		_materials[key] = material
	return _materials[key] as ShaderMaterial


static func apply_unique(canvas: CanvasItem, role: String) -> void:
	if canvas.material is ShaderMaterial and (canvas.material as ShaderMaterial).shader == OutlineShader:
		return
	canvas.material = material_for(role).duplicate() as ShaderMaterial


## A cutaway draws one actor in several rectangles. Keep the full frame's atlas
## bounds on that actor's material so those artificial tile seams get no rim.
static func bind_region(canvas: CanvasItem, texture: Texture2D, region: Rect2) -> void:
	if not canvas.material is ShaderMaterial or (canvas.material as ShaderMaterial).shader != OutlineShader:
		return
	var extent := texture.get_size()
	var bounds := Vector4(region.position.x / extent.x, region.position.y / extent.y,
		region.size.x / extent.x, region.size.y / extent.y)
	if canvas.get_meta("readability_region", Vector4.ZERO) != bounds:
		(canvas.material as ShaderMaterial).set_shader_parameter("source_region", bounds)
		canvas.set_meta("readability_region", bounds)
