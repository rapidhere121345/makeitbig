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
	var training_fingerprint := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	var stale_fingerprint := "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100"
	var unverified_training := _training_snapshot(false, training_fingerprint, {})
	screen.present("training", {}, {}, "", unverified_training)
	text = screen.get_visible_text()
	_expect(text.contains("Current Build"), "facility: training view did not identify the current build", failures)
	# The first screen is the four readable cards. The parameter wall, the fingerprint
	# and the raw report are the reference layer and stay folded until they are asked for.
	_expect(text.contains("Growth Conclusion\nUnverified") and not text.contains("exponential") and not text.contains("Exponential"),
		"facility: unverified training view leaked its growth classification", failures)
	_expect(text.contains("Connected Interfaces\nBreedable Child Arrows, Branch Target History")
		and text.contains("Missing Interfaces\nLineage Lifetime Pause"),
		"facility: training view did not render the resolved interfaces as readable cards", failures)
	_expect(not text.contains("Final Stats") and not text.contains("p: 0.61") and not text.contains("Build Fingerprint"),
		"facility: the unverified training page opened with its raw parameter block", failures)
	_expect(text.contains("Current build not yet trained") and not text.contains("Training readings: ") and not text.contains("Total Events"),
		"facility: unverified training view leaked report numbers", failures)
	var unverified_identity: Label = screen.find_child("TrainingReportIdentity", true, false) as Label
	_expect(unverified_identity != null and unverified_identity.text.contains("Status: Not Yet Trained")
		and unverified_identity.text.contains("Next Step: Run Training Trial"),
		"facility: unverified training did not name the current build, status, and next action", failures)
	_expect_no_calibration_copy(text, failures)
	var unverified_toggle: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(unverified_toggle != null and unverified_toggle.text.contains("Show"),
		"facility: the training reference data is not folded by default", failures)
	if unverified_toggle != null:
		unverified_toggle.pressed.emit()
	text = screen.get_visible_text()
	_expect(text.contains("Piercing Arrow Continuation Chance: 61%") and text.contains("Shared Lineage Lifetime: 34 s")
		and text.contains("Projectile Speed: 682 units/s") and text.contains("Turn Time (Lower Is Better): 0.16 s")
		and text.contains("Carrier Damage: 160") and text.contains("Maximum Health: 112"),
		"facility: the training reference data did not restore the public parameters", failures)
	_expect(not text.contains("Build Fingerprint") and not text.contains(training_fingerprint),
		"facility: build fingerprint escaped the test console", failures)
	_expect(not text.contains("breedable_event") and not text.contains("branch_target_history")
		and not text.contains("lineage_lifetime_pause"),
		"facility: raw interface ids escaped the test console", failures)
	_expect(screen._training_interface_text(["future_interface"]) == "Unknown Interface (future_interface)",
		"facility: an unknown interface must stay readable while preserving its raw id", failures)
	_expect(screen._training_interface_text(["piercing_continuation"]) == "Piercing Continuation",
		"facility: the real ranger's base interface must have readable copy", failures)
	_expect(text.contains("Current build not yet trained") and not text.contains("Training readings: "),
		"facility: the unverified reference block did not keep its stand-in sentence", failures)
	_expect_no_calibration_copy(text, failures)
	var unverified_fold: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(unverified_fold != null and unverified_fold.text.contains("Hide"),
		"facility: the open training reference block lost its toggle", failures)
	if unverified_fold != null:
		unverified_fold.pressed.emit()
	text = screen.get_visible_text()
	_expect(not text.contains("p: 0.61") and not text.contains("Build Fingerprint"),
		"facility: folding the training reference data did not hide the raw fields again", failures)
	var training_button: Button = screen.get_action_button("RunTrainingTrial")
	_expect(training_button != null, "facility: training trial action is missing", failures)
	if training_button != null:
		training_button.pressed.emit()
	_expect(actions.size() == 1 and actions[0] == {"facility": "training", "action": "run_training_trial", "payload": {}},
		"facility: training trial emitted the wrong action", failures)

	var verified_training := _training_snapshot(true, training_fingerprint, _training_report(training_fingerprint))
	screen.present("training", {}, {}, "", verified_training)
	text = screen.get_visible_text()
	_expect(text.contains("Growth Conclusion\nExponential"), "facility: verified current Build did not reveal its growth classification", failures)
	_expect(text.contains("Training readings: R 1.22 · g 3 · Total Events 12") and not text.contains("summary: ")
		and not text.contains("Growth State") and not text.contains("Event Growth Curve"),
		"facility: the matching report's first-screen reading is wrong, or the main reading repeats the raw curve", failures)
	_expect(not text.contains("Current build not yet trained"), "facility: matching training report was replaced by the unverified copy", failures)
	_expect(text.contains("Next Step\nKeep forecasting with this build"), "facility: matching report did not render the action sentence as its own card", failures)
	# The trace draws exactly the matching report's generations, and names the value
	# axis it really used.
	var trace_report: Dictionary = screen.training_trace_report()
	_expect(bool(trace_report.get("present", false)) and bool(trace_report.get("drawing", false)),
		"facility: the verified training report drew no generational trace", failures)
	_expect(trace_report.get("generations") == [0, 20] and trace_report.get("events_display") == ["1", "12"],
		"facility: the trace did not draw exactly the matching report's generations: %s" % str(trace_report), failures)
	_expect(String(trace_report.get("mode", "")) == "log10" and String(trace_report.get("axis_caption", "")).contains("log10 scale"),
		"facility: a value axis was used without being named a log axis: %s" % String(trace_report.get("axis_caption", "")), failures)
	var trace_axis: Label = screen.find_child("TrainingGrowthTraceAxis", true, false) as Label
	_expect(trace_axis != null and trace_axis.visible and trace_axis.text.contains("log10 scale")
		and trace_axis.get_theme_font_size("font_size") >= 18,
		"facility: the drawn axis was not labeled in 18px page copy", failures)
	var trace_node: Control = screen.find_child("TrainingGrowthTrace", true, false)
	_expect(trace_node != null and trace_node.custom_minimum_size.y >= 100.0,
		"facility: the trace control has no room to draw its points", failures)
	_expect(text.contains("The curve retains every sample from this trial."),
		"facility: the trace did not say where its numbers and copy come from", failures)
	_expect_no_calibration_copy(text, failures)

	# Each fingerprint owns its report. Switching A to B and back to A restores A's
	# conclusion and reading without borrowing B's report or showing a contradiction.
	var fingerprint_b := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	var report_b := _training_report(fingerprint_b)
	report_b["state"] = "critical"
	report_b["R"] = 1.0
	report_b["event_count_display"] = "81"
	var switch_snapshot := verified_training.duplicate(true)
	(switch_snapshot.training.reports_by_fingerprint as Dictionary)[fingerprint_b] = report_b
	screen.present("training", {}, {}, "", switch_snapshot)
	_expect(screen.get_visible_text().contains("Growth Conclusion\nExponential") and screen.get_visible_text().contains("Total Events 12"),
		"facility: A report was not shown before A to B switch", failures)
	switch_snapshot.resolved_build.build_fingerprint = fingerprint_b
	screen.present("training", {}, {}, "", switch_snapshot)
	_expect(screen.get_visible_text().contains("Growth Conclusion\nCritical") and screen.get_visible_text().contains("Total Events 81")
		and not screen.get_visible_text().contains("Total Events 12"),
		"facility: B did not show only B's matching report", failures)
	switch_snapshot.resolved_build.build_fingerprint = training_fingerprint
	screen.present("training", {}, {}, "", switch_snapshot)
	text = screen.get_visible_text()
	_expect(text.contains("Growth Conclusion\nExponential") and text.contains("Total Events 12")
		and not text.contains("Total Events 81") and not text.contains("Current build not yet trained"),
		"facility: A to B to A did not restore A's report cleanly", failures)

	# The raw report is the reference layer, not the reading: the seed, the complete
	# generational string and the untranslated state word all come back when the
	# training page's own fold is opened, and folding it again leaves the page as it
	# started. The fold never changes what the page reads, only what it shows.
	var verified_toggle: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(verified_toggle != null and verified_toggle.text.contains("Show"),
		"facility: the verified training page did not start with its reference data folded", failures)
	if verified_toggle != null:
		verified_toggle.pressed.emit()
	text = screen.get_visible_text()
	_expect(not text.contains("Replay Seed") and not text.contains("42"),
		"facility: training seed escaped the test console", failures)
	_expect(text.contains("Event Growth Curve: G0:1 → G20:12"),
		"facility: the training reference data did not render the complete growth curve", failures)
	_expect(text.contains("Growth Classification: Exponential") and text.contains("Piercing Arrow Continuation Chance: 61%") and not text.contains("exponential"),
		"facility: the training reference data lost the readable classification or public parameters", failures)
	_expect_no_calibration_copy(text, failures)
	var verified_fold: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(verified_fold != null and verified_fold.text.contains("Hide"),
		"facility: the open training reference block lost its fold label", failures)
	if verified_fold != null:
		verified_fold.pressed.emit()
	text = screen.get_visible_text()
	_expect(not text.contains("Event Growth Curve") and not text.contains("Replay Seed"),
		"facility: folding the training reference data left the raw report on the page", failures)

	# Readings that are not comparable decimals drop the value axis instead of getting
	# an invented height, and every value string still comes from the report.
	var tower_report := _training_report(training_fingerprint)
	tower_report["growth_curve"] = [
		{"generation": 0, "events_display": "1"},
		{"generation": 5, "events_display": "10^^2(3.5)"},
		{"generation": 10, "events_display": "10^^3(1.25)"},
	]
	screen.present("training", {}, {}, "", _training_snapshot(true, training_fingerprint, tower_report))
	text = screen.get_visible_text()
	var tower_trace: Dictionary = screen.training_trace_report()
	_expect(String(tower_trace.get("mode", "")) == "order" and bool(tower_trace.get("drawing", false))
		and int(tower_trace.get("point_count", 0)) == 3,
		"facility: a tower reading was placed on a value axis instead of the order-only form", failures)
	_expect(String(tower_trace.get("axis_caption", "")).contains("not used"),
		"facility: the order-only trace did not say that no value axis was drawn", failures)
	var tower_toggle: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(tower_toggle != null and tower_toggle.text.contains("Show"),
		"facility: the tower reading did not start with its reference data folded", failures)
	if tower_toggle != null:
		tower_toggle.pressed.emit()
	text = screen.get_visible_text()
	_expect(text.contains("Event Growth Curve: G0:1 → G5:10^^2(3.5) → G10:10^^3(1.25)"),
		"facility: the order-only trace lost the report's own value strings", failures)
	_expect_no_calibration_copy(text, failures)
	var tower_fold: Button = screen.get_action_button("TrainingDetailsToggle")
	if tower_fold != null:
		tower_fold.pressed.emit()

	var stale_report := _training_report(stale_fingerprint)
	stale_report["p"] = 0.99
	stale_report["R"] = 9.99
	stale_report["event_count"] = 777.0
	stale_report["report"] = "stale sentinel"
	stale_report["training_seed"] = 999
	stale_report["growth_curve"] = [{"generation": 999, "events_display": "777"}]
	stale_report["action"] = "stale action sentinel"
	var stale_verified := _training_snapshot(true, training_fingerprint, stale_report)
	screen.present("training", {}, {}, "", stale_verified)
	text = screen.get_visible_text()
	_expect(text.contains("Growth Conclusion\nUnverified") and not text.contains("Growth Conclusion\nExponential"),
		"facility: stale-only report incorrectly verified the current Build", failures)
	_expect(text.contains("Current build not yet trained") and not text.contains("0.99") and not text.contains("9.99")
		and not text.contains("777") and not text.contains("stale sentinel")
		and not text.contains("Replay Seed") and not text.contains("G999")
		and not text.contains("stale action sentinel") and text.contains("Next Step: Run Training Trial"),
		"facility: a report from an old Build masqueraded as the current Build's report", failures)
	_expect(not bool(screen.training_trace_report().get("present", false))
		and screen.find_child("TrainingGrowthTrace", true, false) == null
		and not text.contains("Numeric Y-axis"),
		"facility: a stale report drew a trace, or the previous valid curve stood in for it", failures)
	_expect_no_calibration_copy(text, failures)
	# The fold is not a loophole: even the reference layer of a verified Build with a
	# stale report may not reprint one field of the old report.
	var stale_toggle: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(stale_toggle != null, "facility: the stale training page lost its reference toggle", failures)
	if stale_toggle != null:
		stale_toggle.pressed.emit()
	text = screen.get_visible_text()
	_expect(text.contains("Current build not yet trained") and not text.contains("0.99") and not text.contains("9.99")
		and not text.contains("777") and not text.contains("stale sentinel")
		and not text.contains("Replay Seed") and not text.contains("G999")
		and not text.contains("stale action sentinel") and text.contains("Next Step: Run Training Trial"),
		"facility: the training reference layer reprinted a stale report's fields", failures)
	_expect_no_calibration_copy(text, failures)
	var stale_fold: Button = screen.get_action_button("TrainingDetailsToggle")
	if stale_fold != null:
		stale_fold.pressed.emit()

	var unverified_stale := _training_snapshot(false, training_fingerprint, stale_report)
	screen.present("training", {}, {}, "", unverified_stale)
	text = screen.get_visible_text()
	_expect(text.contains("Growth Conclusion\nUnverified") and not text.contains("exponential") and not text.contains("Exponential"),
		"facility: unverified Build with a stale report leaked its classification", failures)
	_expect(text.contains("Current build not yet trained") and not text.contains("0.99") and not text.contains("9.99")
		and not text.contains("777") and not text.contains("stale sentinel")
		and not text.contains("Replay Seed") and not text.contains("G999") and text.contains("Next Step: Run Training Trial"),
		"facility: unverified Build displayed an old Build's report", failures)
	_expect_no_calibration_copy(text, failures)

	var unverified_match := _training_snapshot(false, training_fingerprint, _training_report(training_fingerprint))
	screen.present("training", {}, {}, "", unverified_match)
	text = screen.get_visible_text()
	_expect(text.contains("Current build not yet trained") and not text.contains("Replay Seed") and not text.contains("42")
		and not text.contains("Event Growth Curve") and text.contains("Next Step: Run Training Trial") and not text.contains("Keep forecasting with this build"),
		"facility: unverified Build leaked the new report fields despite a matching fingerprint", failures)
	_expect(not bool(screen.training_trace_report().get("present", false))
		and screen.find_child("TrainingGrowthTrace", true, false) == null,
		"facility: an unverified Build drew the matching report's trace anyway", failures)
	_expect_no_calibration_copy(text, failures)
	var match_toggle: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(match_toggle != null, "facility: the unverified training page lost its reference toggle", failures)
	if match_toggle != null:
		match_toggle.pressed.emit()
	text = screen.get_visible_text()
	_expect(text.contains("Current build not yet trained") and not text.contains("Replay Seed") and not text.contains("42")
		and not text.contains("Event Growth Curve") and text.contains("Next Step: Run Training Trial") and not text.contains("Keep forecasting with this build"),
		"facility: the unverified reference layer leaked the matching report's fields", failures)
	_expect_no_calibration_copy(text, failures)
	var match_fold: Button = screen.get_action_button("TrainingDetailsToggle")
	if match_fold != null:
		match_fold.pressed.emit()

	var legacy_report := {
		"preset_id": "exponential",
		"build_fingerprint": training_fingerprint,
		"p": 0.61,
		"R": 1.22,
		"g": 3,
		"event_count": 12.0,
		"state": "exponential",
		"report": "p=0.61, R=1.22, g=3, events=12: exponential",
	}
	screen.present("training", {}, {}, "", _training_snapshot(true, training_fingerprint, legacy_report))
	text = screen.get_visible_text()
	_expect(text.contains("Training readings: R 1.22 · g 3 · Total Events 12"),
		"facility: legacy report without the new fields was not rendered", failures)
	var legacy_toggle: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(legacy_toggle != null, "facility: the legacy training page lost its reference toggle", failures)
	if legacy_toggle != null:
		legacy_toggle.pressed.emit()
	text = screen.get_visible_text()
	_expect(text.contains("Growth Classification: Exponential") and not text.contains("exponential"),
		"facility: the legacy report lost its readable classification", failures)
	_expect(not text.contains("Replay Seed") and not text.contains("Event Growth Curve") and not text.contains("Next Step"),
		"facility: legacy report invented placeholder sections for missing fields", failures)
	_expect_no_calibration_copy(text, failures)
	var legacy_fold: Button = screen.get_action_button("TrainingDetailsToggle")
	if legacy_fold != null:
		legacy_fold.pressed.emit()

	var malformed_report := _training_report(training_fingerprint)
	malformed_report["training_seed"] = 7
	malformed_report["growth_curve"] = [
		{"generation": 20.0, "events_display": "20.0 sentinel"},
		{"generation": "30", "events_display": "30 sentinel"},
		{"events_display": "no generation sentinel"},
		{"generation": 5, "events_display": ""},
		{"generation": 6, "events_display": "   "},
		{"generation": 7, "events_display": 999},
		42, "junk", {},
		{"generation": 20, "events_display": "12"},
		{"generation": 0, "events_display": "1"},
	]
	malformed_report["action"] = ""
	screen.present("training", {}, {}, "", _training_snapshot(true, training_fingerprint, malformed_report))
	text = screen.get_visible_text()
	_expect(not text.contains("Replay Seed") and not text.contains("Event Growth Curve") and not text.contains("Next Step"),
		"facility: the first screen of the malformed report showed raw reference fields", failures)
	var malformed_toggle: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(malformed_toggle != null, "facility: the malformed training page lost its reference toggle", failures)
	if malformed_toggle != null:
		malformed_toggle.pressed.emit()
	text = screen.get_visible_text()
	_expect(not text.contains("Replay Seed") and text.contains("Event Growth Curve: G0:1 → G20:12"),
		"facility: malformed curve was not filtered down to its valid points", failures)
	_expect(not text.contains("G20.0") and not text.contains("G30") and not text.contains("G5") and not text.contains("G6")
		and not text.contains("G7") and not text.contains("sentinel") and not text.contains("junk") and not text.contains("Next Step"),
		"facility: malformed curve entries or an empty action leaked into the report", failures)
	_expect_no_calibration_copy(text, failures)
	var malformed_fold: Button = screen.get_action_button("TrainingDetailsToggle")
	if malformed_fold != null:
		malformed_fold.pressed.emit()

	var empty_curve_report := _training_report(training_fingerprint)
	empty_curve_report["training_seed"] = 99.0
	empty_curve_report["growth_curve"] = [{"generation": 1.0, "events_display": "x"}, "junk"]
	empty_curve_report["action"] = ""
	screen.present("training", {}, {}, "", _training_snapshot(true, training_fingerprint, empty_curve_report))
	text = screen.get_visible_text()
	_expect(not text.contains("Event Growth Curve") and not text.contains("Replay Seed") and not text.contains("Next Step"),
		"facility: a curve with no valid points or a non-int seed was still displayed", failures)
	_expect(not bool(screen.training_trace_report().get("present", false))
		and screen.find_child("TrainingGrowthTrace", true, false) == null,
		"facility: a curve with no valid points still produced a trace", failures)
	_expect_no_calibration_copy(text, failures)
	var empty_toggle: Button = screen.get_action_button("TrainingDetailsToggle")
	_expect(empty_toggle != null, "facility: the empty-curve training page lost its reference toggle", failures)
	if empty_toggle != null:
		empty_toggle.pressed.emit()
	text = screen.get_visible_text()
	_expect(text.contains("Training readings: R 1.22 · g 3 · Total Events 12") and not text.contains("Event Growth Curve")
		and not text.contains("Replay Seed") and not text.contains("Next Step"),
		"facility: the reference layer invented a curve or a seed the report does not carry", failures)
	_expect(not bool(screen.training_trace_report().get("present", false))
		and screen.find_child("TrainingGrowthTrace", true, false) == null,
		"facility: opening the reference layer drew a trace for a curve with no valid points", failures)
	_expect_no_calibration_copy(text, failures)
	var empty_fold: Button = screen.get_action_button("TrainingDetailsToggle")
	if empty_fold != null:
		empty_fold.pressed.emit()

	var missing_resolved := _training_snapshot(false, training_fingerprint, {})
	missing_resolved.erase("resolved_build")
	screen.present("training", {}, {}, "", missing_resolved)
	text = screen.get_visible_text()
	_expect(text.contains("Training Data Unavailable"), "facility: missing resolved Build was not reported as unavailable", failures)
	_expect(not text.contains("exponential") and not text.contains("Exponential"),
		"facility: missing resolved Build leaked growth copy", failures)
	_expect_no_calibration_copy(text, failures)
	_expect(screen.get_action_button("RunTrainingTrial") != null, "facility: unavailable training view dropped the trial action", failures)

	var bad_resolved := _training_snapshot(false, training_fingerprint, {})
	bad_resolved["resolved_build"] = {"ok": false, "error": "invalid_active_build", "growth_classification": "invalid", "final_parameters": {}}
	screen.present("training", {}, {}, "", bad_resolved)
	text = screen.get_visible_text()
	_expect(text.contains("Training Data Unavailable") and not text.contains("invalid") and not text.contains("Exponential"),
		"facility: bad resolved Build leaked an error or growth classification", failures)
	_expect_no_calibration_copy(text, failures)

	var isolation_snapshot := _training_snapshot(true, training_fingerprint, _training_report(training_fingerprint))
	var isolation_before := isolation_snapshot.duplicate(true)
	screen.present("training", {}, {}, "", isolation_snapshot)
	_expect(isolation_snapshot == isolation_before, "facility: presenting training mutated the caller's snapshot", failures)
	root.remove_child(screen)
	screen.free()
	for child in root.get_children():
		child.free()
	await process_frame
	await process_frame
	_finish(failures, "test_facility_training_page.gd")
