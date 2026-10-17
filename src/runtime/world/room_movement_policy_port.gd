class_name RoomMovementPolicyPort
extends RefCounted

## Typed room-owned movement policy lookup.
##
## RoomActorAccess remains the movement commit authority.  This port only
## supplies an optional policy when a caller did not provide one explicitly.
## A null result means that the resolver's default movement policy applies.

func resolve(_actor_id: String) -> Variant:
	return null
