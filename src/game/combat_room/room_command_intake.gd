class_name RoomCommandIntake
extends RefCounted

## Where the fixed tick gets player commands that originate outside the
## authority (device input today). The room authority calls this interface at
## the collect phase and never imports or reads presentation; the view hands in
## an implementation that owns the input adapter and the snapshot it reads. The
## default implementation yields no commands, which is what a room without a
## view sees.


## Manual-mode device commands for this tick.
func collect_commands() -> Array[Dictionary]:
	return []


## A queued loot-pickup request, or an empty dictionary.
func collect_loot_pickup_command() -> Dictionary:
	return {}
