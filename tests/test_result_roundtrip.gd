extends SceneTree

const GameRootScript = preload("res://src/game/game_root.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var game = GameRootScript.new()
	game.save_directory_path = "user://result-roundtrip-%d" % Time.get_ticks_usec()
	game.playtest_logging_enabled = false
	game.flow_error.connect(func(code: String, message: String) -> void: failures.append("flow: " + code + " " + message))
	game.initialize(PackedStringArray(["--game-flow-smoke"]))
	root.add_child(game)
	_expect(game.start_new_game("ranger").get("ok", false), "fresh ranger profile failed", failures)
	_expect(game.complete_tutorial().get("ok", false), "tutorial completion failed", failures)
	_expect(game.open_contract().get("ok", false), "contract preparation failed", failures)
	_expect(game.launch_contract({"contract_id": "mainline_01_first_hunt", "mode": "Manual", "seed": 52969, "room_count": 1}).get("ok", false),
		"real first-hunt launch failed", failures)
	if game.current_route != "arena":
		_finish(game, failures)
		return
	# Existing smoke commands move/cast through the real combat simulation. No
	# fabricated victory, injected drops, or direct profile equipment mutation.
	var room_count := int(game.current_screen.get("room_count"))
	for _room in room_count:
		if game.current_route != "arena":
			break
		var arena: Node = game.current_screen.get("_current_adapter").get("_legacy")
		arena.set("automation_smoke", true)
		for _tick in 1800:
			if bool(arena.get("battle_over")):
				break
			arena.call("_simulate_tick")
		_expect(bool(arena.get("battle_victory")), "real first-hunt room did not reach victory", failures)
		await _frames(4)
	_expect(game.current_route == "result", "real combat did not settle all authored rooms", failures)
	if game.current_route != "result":
		_finish(game, failures)
		return
	var receipt: Dictionary = game.application_state.last_result.duplicate(true)
	var drops: Array = receipt.get("rewards", {}).get("equipment_drops", [])
	_expect(receipt.get("outcome") == "victory" and int(receipt.get("casts", 0)) > 0 and drops.size() == 2,
		"real first victory did not grant the expected two drops", failures)
	if drops.is_empty():
		_finish(game, failures)
		return
	var item: Dictionary = drops[0]
	var instance_id := String(item.instance_id)
	var slot := String(item.slot)
	var result: Control = game.current_screen
	var review := result.find_children("ReviewDrop_*", "Button", true, false)[0] as Button
	_expect(review.text == "比较（尚未装备）" and result.get_equipment_card_summaries()[0].contains("当前在行囊中，尚未装备"),
		"fresh drop state/action is wrong", failures)
	review.pressed.emit()
	await _frames(3)
	_expect(game.current_route == "loadout", "comparison did not open loadout", failures)
	var equip: Array[Node] = game.current_screen.find_children("Equip_*", "Button", true, false)
	_expect(equip.size() == 1, "focused reward did not offer one equipment action", failures)
	if equip.size() != 1:
		_finish(game, failures)
		return
	(equip[0] as Button).pressed.emit()
	await _frames(3)
	_expect(String(game.application_state.profile.active_build.equipped_item_ids.get(slot, "")) == instance_id,
		"loadout equipment action did not equip the actual drop", failures)
	_return_to_result(game, failures)
	await _frames(3)
	result = game.current_screen
	review = result.find_children("ReviewDrop_*", "Button", true, false)[0] as Button
	_expect(review.text == "查看（已装备）" and not review.disabled
		and result.get_equipment_card_summaries()[0].contains("当前已装备，正在使用"),
		"return from equipment retained stale uninstalled state", failures)
	_expect(game.application_state.last_result == receipt and result.get_presented_result() == receipt,
		"equipping rewrote the acquisition receipt", failures)
	(result.find_child("EquipmentDetailButton", true, false) as Button).pressed.emit()
	var detail := result.find_child("EquipmentDetailBody", true, false) as Label
	_expect(detail.text.contains("获得时：已收入装备库存") and detail.text.contains("当前已装备，正在使用")
		and not detail.text.contains("尚未装备，当前构筑不变"),
		"equipment detail mixed historical reward and current equipment state", failures)
	(result.find_child("EquipmentDetailClose", true, false) as Button).pressed.emit()
	review.pressed.emit()
	await _frames(3)
	var unequip := game.current_screen.find_child("Unequip_" + slot, true, false) as Button
	_expect(unequip != null and not unequip.disabled, "equipped reward cannot be inspected/unequipped", failures)
	if unequip != null:
		unequip.pressed.emit()
		await _frames(3)
		_return_to_result(game, failures)
		await _frames(3)
		result = game.current_screen
		_expect(result.get_equipment_card_summaries()[0].contains("当前在行囊中，尚未装备")
			and (result.find_children("ReviewDrop_*", "Button", true, false)[0] as Button).text == "比较（尚未装备）"
			and game.application_state.last_result == receipt,
			"unequip return failed to refresh status or changed reward facts", failures)
	_finish(game, failures)


func _return_to_result(game: Node, failures: Array[String]) -> void:
	var back := game.current_screen.find_child("ReturnToBaseButton", true, false) as Button
	_expect(back != null and back.text == "返回结算", "loadout lost its settlement return action", failures)
	if back != null:
		back.pressed.emit()
	_expect(game.current_route == "result", "loadout did not return to settlement", failures)


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(game: Node, failures: Array[String]) -> void:
	root.remove_child(game)
	game.free()
	if failures.is_empty():
		print("PASS  test_result_roundtrip.gd (real first victory → equip → return → unequip → return; receipt unchanged)")
		quit(0)
	else:
		for failure in failures:
			printerr("- " + failure)
		quit(1)
