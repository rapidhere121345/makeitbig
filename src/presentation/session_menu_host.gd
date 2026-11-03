class_name SessionMenuHost
extends Node

## Ancestor that owns the in-session menu. Screens walk up the tree to the
## first SessionMenuHost to open settings; GameRoot is the production host.


## The session menu, or null when this host has none.
func get_session_menu() -> Node:
	return null
