class_name RoomSession
extends RefCounted

## Authoritative state of one combat room. MainArena creates and owns the
## session and keeps every historical property name as a forwarding property, so
## the state hash builder, the room helpers, the ports and the tests keep
## reading `arena.<name>`. The session is never a Node and imports no
## presentation code; it holds no MainArena reference. Fixed-tick behavior still
## lives in MainArena and its collaborators (see
## docs/rebuild/ROOM_SESSION_DESIGN.md, migration items 3 and 4).

## Build lock: the rule inputs frozen when a contract starts.
var selected_preset: String = "convergent"
var selected_mode: String = "Manual"
var locked_p: float = PiercingArrowModel.BASE_P
var locked_payload: float = MainArena.BASE_PAYLOAD
var locked_targeting_distance: float = MainArena.AUTO_RANGE
var locked_build: Dictionary = {}

## Contract run state: whether a contract is live, the elapsed clock, the
## command sequence and receipts, the battle report and the automation verdict.
var in_arena: bool = false
var elapsed: float = 0.0
var battle_report: String = ""
var command_sequence: int = 0
var last_command_receipts: Array[Dictionary] = []
var last_loot_pickup_command_receipt: Dictionary = {}
var automation_smoke: bool = false
var automation_smoke_failure: String = ""
