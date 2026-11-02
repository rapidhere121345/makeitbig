class_name RangerKit
extends ClassKit

## The Ranger's room half of the player-class seam: piercing-arrow and hunter's
## mark receipts, the frozen-build growth model, the projectile speed and the
## arrow-impact resolution, moved verbatim out of RoomSession
## (docs/rebuild/ROOM_SESSION_DESIGN.md, migration item 7). Every method
## receives the session; the order of the session calls below is part of the
## replay contract.

const BuildResolution := preload("res://src/game/application/build_resolution.gd")


func class_id() -> String:
	return "ranger"


func actor_id() -> String:
	return "ranger"


func default_skill_ids() -> Array[String]:
	return ["piercing_arrow"]


## Freezes the rule inputs of the contract: the resolved build (or the
## calibrated preset model), its payload, probability and targeting range.
func freeze_build(session: RoomSession) -> void:
	if BuildResolution.is_valid_resolved_build(session.framework_resolved_build):
		session.locked_build = session.framework_resolved_build.duplicate(true)
		session.locked_build["skills"] = (session.framework_active_build.get("skills", [String(session.locked_build.get("skill_id", "piercing_arrow"))]) as Array).duplicate()
	else:
		# The diagnostic model keeps its historical calibrated generation count;
		# its gameplay range remains the old Main AUTO_RANGE, frozen for Rules.
		var equipped: Dictionary = session.content_registry.preset_equipped_parameters
		var preset_p := float(session.content_registry.presets[session.selected_preset].p)
		var model: Dictionary = PiercingArrowModel.evaluate(preset_p, float(equipped.shared_lifetime), float(equipped.distance), float(equipped.speed), float(equipped.minimum_turn_time), true, true)
		var events: BigValue = model.total_events
		session.locked_build = {
			"skills": ["piercing_arrow"], "talent_capabilities": {},
			"final_parameters": {"p": preset_p, "T": float(equipped.shared_lifetime), "d": session.AUTO_RANGE, "v": float(equipped.speed), "turn": float(equipped.minimum_turn_time), "damage": session.BASE_PAYLOAD, "max_health": 100.0},
			"total_events": {"layer": events.layer, "magnitude": events.magnitude},
			"total_events_float": model.total_events_float, "generation_count": model.g,
			"R": model.R, "generation_time": model.generation_time, "growth_classification": model.state,
		}
	var parameters: Dictionary = session.locked_build.final_parameters
	session.locked_p = float(parameters.p)
	session.locked_payload = float(parameters.damage)
	session.locked_targeting_distance = float(parameters.d)


## Growth model of the frozen build (or the calibrated preset when no build is
## locked), as the combat system consumes it.
func growth_model(session: RoomSession) -> Dictionary:
	var player := session.player_combat_state.snapshot(session.sim_tick)
	if not session.locked_build.is_empty():
		var event_value: Dictionary = session.locked_build.get("total_events", {})
		var total_events := BigValue.from_components(
			int(event_value.get("layer", 0)),
			float(event_value.get("magnitude", 0.0))
		)
		if total_events != null:
			var generations := int(session.locked_build.generation_count)
			return {
				"p": float(session.locked_build.final_parameters.p),
				"R": float(session.locked_build.R),
				"g": generations,
				"generation_time": float(session.locked_build.generation_time),
				"state": String(session.locked_build.growth_classification),
				"total_events": total_events,
				"total_events_float": float(session.locked_build.total_events_float),
				"growth_snapshot_details": bool((player.get("talent_capabilities", {}) as Dictionary).get("growth_snapshot_details", false)),
			}
	var equipped: Dictionary = session.content_registry.preset_equipped_parameters
	return PiercingArrowModel.evaluate(
		session.locked_p,
		float(equipped.shared_lifetime),
		float(equipped.distance),
		float(equipped.speed),
		float(equipped.minimum_turn_time),
		true,
		true
	)


## Projectile speed the Ranger's arrows fly at: the frozen build's, else the
## calibrated preset's. Never zero or non-finite.
func projectile_speed(session: RoomSession) -> float:
	var speed := 0.0
	if not session.locked_build.is_empty():
		speed = float((session.locked_build.get("final_parameters", {}) as Dictionary).get("v", 0.0))
	elif session.content_registry != null:
		speed = float(session.content_registry.preset_equipped_parameters.get("speed", 0.0))
	if not is_finite(speed) or speed <= 0.0:
		return 1.0
	return speed


## Applies the authority side of one command receipt from the player domain
## tick: the piercing-arrow receipt presents its cast receipt with the
## Auto/Manual default source and the command sequence, and binds the command's
## input feedback. Hunter's Mark only presents its receipt; the session records
## the command as discarded.
func handle_receipt(session: RoomSession, receipt: Dictionary, player: Dictionary) -> bool:
	var command: Dictionary = receipt.get("command", {})
	if String(command.get("ability_id", "")) == "piercing_arrow":
		var default_source := session.ATTACK_SOURCE_PROXY if session.selected_mode == "Auto" else session.ATTACK_SOURCE_ASSISTED
		present_cast_receipt(session, receipt, default_source, int(command.get("sequence", -1)), true)
		return true
	if String(command.get("ability_id", "")) == "hunter_mark":
		present_mark_receipt(session, receipt, player)
	return false


## Applies the receipt of an explicit diagnostic cast (test console, smoke).
func handle_diagnostic_receipt(session: RoomSession, ability_id: String, receipt: Dictionary, source: String) -> void:
	if ability_id == "piercing_arrow":
		present_cast_receipt(session, receipt, source)
	elif ability_id == "hunter_mark":
		present_mark_receipt(session, receipt, session.player_combat_state.snapshot(session.sim_tick))


## Resolves one released arrow against the combat system.
func resolve_action_impact(session: RoomSession, action_event: Dictionary, action_player: Dictionary) -> void:
	session.sync_combat_context(action_player)
	var previous_report := String(session.combat_system.battle_report)
	var previous_event_id: int = session.combat_event_stream.latest_event_id()
	session.combat_system.resolve_piercing_arrow(action_event)
	session.adopt_combat_report(previous_report, previous_event_id)


## True when a combat event stream entry is one of this kit's own attacks.
func owns_attack_event(event: Dictionary) -> bool:
	return String(event.get("type", "")) == "attack_resolved" and String(event.get("source_id", "")) == "ranger/piercing_arrow"


## Records the Piercing Arrow receipt: the report text is authority, the input
## feedback and request-source bookkeeping travel as a presentation event. When
## `resolve_source` is set the view swaps `source` (the fallback) for the source
## its input adapter registered for `sequence`.
func present_cast_receipt(session: RoomSession, receipt: Dictionary, source: String, sequence: int = -1, resolve_source: bool = false) -> void:
	var accepted := bool(receipt.get("accepted", false))
	var status := String(receipt.get("status", ""))
	if accepted:
		session.battle_report = "Piercing Arrow buffered; waiting for an action window." if status in ["buffered", "replaced"] else "Drawing Piercing Arrow."
	session.record_event(RoomPresentationEvent.cast_receipt(
		session.sim_tick, sequence, source, resolve_source, accepted, status == "started",
		not accepted and String(receipt.get("reason", "")) == "target_out_of_range" and session.selected_mode == "Manual",
		int(receipt.get("request_id", 0)), int(receipt.get("replaced_request_id", 0)), int(receipt.get("action_instance_id", 0))))


func present_mark_receipt(session: RoomSession, receipt: Dictionary, player: Dictionary) -> void:
	if not bool(receipt.get("accepted", false)):
		return
	var target := session.enemy_by_entity_id(int(player["marked_entity_id"]))
	if target != null and target.health > 0.0:
		session.battle_report = "Hunter's Mark locked: %s." % target.public_label()
