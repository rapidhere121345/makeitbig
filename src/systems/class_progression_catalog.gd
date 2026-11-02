class_name ClassProgressionCatalog
extends RefCounted

## Maps a stable class id to its ClassProgression implementation. Callers that
## only know the profile's `initial_class` ask here instead of naming a class.
## Unknown or not-yet-implemented classes have no progression and return null.


static func for_class(id: String) -> ClassProgression:
	match id:
		"ranger":
			return RangerProgression.new()
	return null
