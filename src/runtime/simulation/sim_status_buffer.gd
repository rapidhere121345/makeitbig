class_name SimStatusBuffer
extends RefCounted

## Per-tick status application collection, cleared by the begin-tick phase.

var _applications: Array[SimStatusApplication] = []


func append(application: SimStatusApplication) -> void:
	if application != null and application.target != null:
		_applications.append(application)


func applications() -> Array[SimStatusApplication]:
	return _applications


func clear() -> void:
	_applications.clear()
