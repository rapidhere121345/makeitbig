class_name ClassKit
extends RefCounted

## The single place a player class lives (docs/rebuild/ROOM_SESSION_DESIGN.md,
## "ClassKit"). This is the room half: the class-specific rules RoomSession
## needs while a contract runs, including its slice of the state hash. The
## progression half (talents, growth model outside the room) is
## ClassProgression (src/systems/class_progression.gd). Combat resolution
## (CombatSystem's arrow lifecycle) is still the Ranger's own code and gets a
## kit seam when the second class is built.
##
## A kit holds no room state and no RoomSession reference: the session owns
## the kit, so a back-reference would form a RefCounted cycle. Every method that
## needs room state receives the session. Kits must keep the order of the
## session calls they make; that order is part of the replay contract.
##
## Kits may define their own ability ids and command kinds (the melee class adds
## charge-and-release and combos); the session only routes receipts and action
## events to the kit and never inspects ability ids itself. Summons are light
## effects owned by the kit, not kernel entities.


## Stable class id, used in saves and content ("ranger").
func class_id() -> String:
	return ""


## Actor id of the player in the actor registry and kernel ("ranger").
func actor_id() -> String:
	return class_id()


## Skills a room build falls back to when the resolved build lists none.
func default_skill_ids() -> Array[String]:
	return []


## Freezes the contract's build into the session: writes `locked_build` and the
## derived `locked_p`, `locked_payload` and `locked_targeting_distance`.
func freeze_build(_session: RoomSession) -> void:
	push_error("class_kit_freeze_build_unimplemented:%s" % class_id())


## Growth model of the frozen build as the combat system consumes it.
func growth_model(_session: RoomSession) -> Dictionary:
	return {}


## Travel speed pushed into the combat context. Kits without projectiles keep
## the neutral 1.0.
func projectile_speed(_session: RoomSession) -> float:
	return 1.0


## Applies the authority side of one accepted-or-rejected command receipt from
## the player domain tick. Returns true when the kit bound the command's input
## feedback; otherwise the session logs the command as discarded.
func handle_receipt(_session: RoomSession, _receipt: Dictionary, _player: Dictionary) -> bool:
	return false


## Applies the receipt of an explicit diagnostic cast (test console, smoke).
func handle_diagnostic_receipt(_session: RoomSession, _ability_id: String, _receipt: Dictionary, _source: String) -> void:
	pass


## Resolves an `action_impact` event of the player's action timeline.
func resolve_action_impact(_session: RoomSession, _action_event: Dictionary, _action_player: Dictionary) -> void:
	pass


## True when a combat event stream entry is one of this kit's own attacks, so
## the session adopts the combat system's report for it.
func owns_attack_event(_event: Dictionary) -> bool:
	return false


## The class-owned keys of the authoritative state hash, merged at the top level
## of CombatStateSnapshotBuilder's state. `player` is the player domain snapshot
## and `outcome` the combat system's outcome snapshot of the same tick. Keys must
## not collide with the builder's generic keys; the codec sorts keys, so moving
## a key between the builder and a kit leaves the hash unchanged.
func hash_slice(_player: Dictionary, _outcome: Dictionary) -> Dictionary:
	return {}
