class_name RoomSession
extends RefCounted

## Authoritative state of one combat room. MainArena creates and owns the
## session and keeps every historical property name as a forwarding property, so
## the state hash builder, the room helpers, the ports and the tests keep
## reading `arena.<name>`. The session is never a Node and imports no
## presentation code; it holds no MainArena reference. Fixed-tick behavior still
## lives in MainArena and its collaborators (see
## docs/rebuild/ROOM_SESSION_DESIGN.md, migration items 3 and 4).
