class_name EnvironmentObjectPlacement
extends Node2D

const Definition := preload("res://src/runtime/world/environment_object_definition.gd")

@export var placement_id := ""
@export var definition: Definition


func validate() -> Array[String]:
	var errors: Array[String] = []
	if not Definition.valid_id(placement_id):
		errors.append("invalid_environment_placement_id:" + placement_id)
	if is_set_as_top_level() or transform.x != Vector2.RIGHT or transform.y != Vector2.DOWN or not position.is_finite():
		errors.append("unsupported_environment_transform:" + placement_id)
	if definition == null:
		errors.append("missing_environment_definition:" + placement_id)
	else:
		errors.append_array(definition.validate())
	if get_child_count() != 0:
		errors.append("unsupported_environment_placement_children:" + placement_id)
	return errors
