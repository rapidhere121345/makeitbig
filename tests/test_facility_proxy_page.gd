extends "res://tests/test_facility_screen.gd"


func _run() -> void:
	var failures: Array[String] = []
	var screen = FacilityScreenScript.new()
	var icon_fixture := _progression_icon_fixture()
	icon_fixture.load_icons()
	root.add_child(screen)
	await process_frame
	screen.set_progression_icons(icon_fixture)
	var actions: Array[Dictionary] = []
	screen.action_requested.connect(func(facility_id: String, action_id: String, payload: Dictionary) -> void:
		actions.append({"facility": facility_id, "action": action_id, "payload": payload.duplicate(true)})
	)
	var text: String = ""
	actions.clear()
	screen.present("proxy", {}, {}, "", _proxy_snapshot(false, false))
	text = screen.get_visible_text()
	_expect(text.contains("Proxy Bay · Core Assembly") and text.contains("Assemble four slots") and text.contains("freezes when the contract starts")
		and text.contains("Unlock requirement: defeat the Threshold Colossus in Manual") and text.contains("first-kill reward")
		and text.contains("Near-Enemy Sight") and text.contains("retreat at close range"),
		"facility: locked proxy copy or reward preview is incorrect", failures)
	_expect(screen.find_children("ProxyCoreCell_*", "PanelContainer", true, false).size() == 4
		and screen.find_children("ProxyEquip_*", "Button", true, false).is_empty()
		and screen.find_children("ProxyDistanceBand_*", "Button", true, false).is_empty(),
		"facility: locked proxy did not keep four preview cells and zero operations", failures)

	screen.present("proxy", {}, {}, "", _proxy_snapshot(false, true))
	text = screen.get_visible_text()
	_expect(text.contains("Current Assembly · Perception -> Action -> Execution -> Memory") and text.contains("Near-Enemy Sight · Perception")
		and text.contains("Direct-Approach Legs · Action") and text.count("Connected") == 4 and text.contains("Auto Available")
		and text.contains("Auto Wins: 2") and text.contains("Early Chapter Complete: Yes") and text.contains("Attachments Not Yet Available"),
		"facility: unlocked proxy state or dynamic slot strip was not rendered", failures)
	_expect(not text.contains("Semantic fingerprint") and not text.contains("0123456789abcdef"),
		"facility: proxy fingerprint escaped the test console", failures)
	_expect(text.contains("Core Inventory and Protocols") and text.contains("Mark Prism · Perception Slot · Not Owned")
		and text.contains("Range-Keeping Legs · Action Slot · In Storage")
		and text.contains("Protocol: Continuously maintain the player's near, medium, or far range band; bands follow Piercing Arrow's actual range and avoid oscillation at their edges"),
		"facility: proxy inventory lost ownership, slot, or full protocol copy", failures)
	_expect(screen.get_action_button("ProxyEquip_distance_keeping_gait") != null
		and screen.get_action_button("ProxyEquip_marking_prism") == null,
		"facility: owned and unowned proxy cores exposed the wrong install actions", failures)
	var equip_distance: Button = screen.get_action_button("ProxyEquip_distance_keeping_gait")
	if equip_distance != null:
		equip_distance.pressed.emit()
	_expect(actions == [{"facility": "proxy", "action": "equip_proxy_core", "payload": {"core_id": "distance_keeping_gait"}}],
		"facility: proxy core install emitted the wrong action payload", failures)
	_expect(screen.find_child("ProxyDistanceBand", true, false) == null and not text.contains("Distance Band"),
		"facility: direct gait rendered distance-band controls", failures)
	_expect(not text.contains("State Parser") and not text.contains("Circling Hunt Legs") and not text.contains("Danger Forewarning"),
		"facility: unimplemented proxy cores leaked onto the player surface", failures)

	actions.clear()
	screen.present("proxy", {}, {}, "", _proxy_snapshot(true, true))
	text = screen.get_visible_text()
	_expect(text.contains("Range-Keeping Legs · Action") and text.contains("Distance Band")
		and text.contains("follow Piercing Arrow's actual range") and not text.contains("targeting_distance") and not text.contains("absolute meters"),
		"facility: installed distance gait did not render relative-only distance controls", failures)
	var near_band: Button = screen.get_action_button("ProxyDistanceBand_near")
	var mid_band: Button = screen.get_action_button("ProxyDistanceBand_mid")
	var far_band: Button = screen.get_action_button("ProxyDistanceBand_far")
	_expect(near_band != null and mid_band != null and far_band != null and mid_band.disabled
		and mid_band.text.contains("Current") and not near_band.disabled and not far_band.disabled,
		"facility: distance-band current state or stable buttons are wrong", failures)
	if far_band != null:
		far_band.pressed.emit()
	_expect(actions == [{"facility": "proxy", "action": "configure_proxy_core", "payload": {"core_id": "distance_keeping_gait", "settings": {"distance_band": "far"}}}],
		"facility: distance-band selection emitted the wrong action payload", failures)

	root.remove_child(screen)
	screen.free()
	for child in root.get_children():
		child.free()
	await process_frame
	await process_frame
	_finish(failures, "test_facility_proxy_page.gd")
