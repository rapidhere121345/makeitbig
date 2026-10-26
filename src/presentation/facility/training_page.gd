class_name FacilityTrainingPage
extends RefCounted

## Training page extracted from FacilityScreen. This collaborator owns the
## training page build, its reference-data disclosure, the growth trace, and the
## trace report, reaching owner state and presentation through the untyped owner
## reference.
const PlayerReadableBuildScript = preload("res://src/presentation/player_readable_build.gd")
const TrainingTraceViewScript = preload("res://src/presentation/training_trace_view.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")
const FacilityItemText := preload("res://src/presentation/facility/item_text.gd")

var _screen


func _init(screen) -> void:
	_screen = screen


## Two coherent columns: what the current build actually is, and what the last
## matching report actually says. The first screen is the four readable cards — the
## growth conclusion, the interfaces that are wired, the ones that are missing and
## the next step — and then the matched report's R / g / event count over its trace.
## The parameter wall, the fingerprint and the untranslated report line wait behind
## the page's own reference toggle. A fingerprint that has not passed the range
## shows Unverified on both sides; unknown is never written as a failure, and a report
## from another build is never drawn as this build's reading.
func _build_training() -> void:
	var resolved := _training_resolved_build()
	if resolved.is_empty():
		var unavailable: VBoxContainer = _screen._section("Training Data Unavailable", "TrainingUnavailable")
		unavailable.add_child(_screen._body_label("The current build cannot be resolved: stats, connected interfaces, and growth conclusions are unavailable."))
		_screen._add_payload_action("Run Training Trial", "run_training_trial", {}, "RunTrainingTrial")
		return
	var training := UiKit.as_dictionary(_screen._facility_data.get("training", {}))
	var fingerprint := String(resolved.get("build_fingerprint", "")).strip_edges()
	var matched := FacilityItemText.matched_training_report(training, fingerprint)
	var verified := not matched.is_empty()
	var row: HBoxContainer = _screen._page_lead_row()
	var current_panel: VBoxContainer = _screen._section_in(row, "Current Build", "TrainingActiveBuild")
	var growth_conclusion := "Unverified"
	if verified:
		var classification := String(matched.get("state", "")).strip_edges()
		if not classification.is_empty():
			growth_conclusion = String(_screen.TRAINING_GROWTH_NAMES.get(classification, classification))
	_training_card(current_panel, "Growth Conclusion", growth_conclusion, true, "TrainingConclusionCard")
	current_panel.add_child(_screen._note_label("Growth conclusions appear only after this fingerprint passes Training; unverified does not mean failure."))
	_training_card(current_panel, "Connected Interfaces", FacilityItemText.training_interface_text(resolved.get("connected_interfaces", [])), false, "TrainingConnectedCard")
	_training_card(current_panel, "Missing Interfaces", FacilityItemText.training_interface_text(resolved.get("missing_interfaces", [])), false, "TrainingMissingCard")
	var report_panel: VBoxContainer = _screen._section_in(row, "Current Build Training Report", "TrainingLastReport")
	var identity: Label = _screen._note_label("Status: Complete · This report belongs to the current build") if verified else _screen._note_label("Status: Not Yet Trained\nNext Step: Run Training Trial")
	identity.name = "TrainingReportIdentity"
	report_panel.add_child(identity)
	var action := String(matched.get("action", "")).strip_edges()
	if not action.is_empty():
		_training_card(report_panel, "Next Step", action, false, "TrainingNextStepCard")
	var readings: Label = _screen._body_label(FacilityItemText.training_readings_text(matched))
	readings.name = "TrainingReading"
	report_panel.add_child(readings)
	_add_growth_trace(report_panel, matched)
	if matched.is_empty():
		report_panel.add_child(_screen._note_label("Unknown does not mean failure: no growth conclusion is given until training completes."))
	else:
		report_panel.add_child(_screen._note_label("These readings come from the current build's training results."))
	_build_training_details(resolved, training, fingerprint, verified)
	_screen._add_payload_action("Run Training Trial", "run_training_trial", {}, "RunTrainingTrial")


func _training_card(parent: Container, title_text: String, value_text: String, focused: bool, node_name: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = node_name
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _screen._slot_cell_box(focused, not focused))
	parent.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	card.add_child(content)
	content.add_child(_screen._note_label(title_text))
	content.add_child(_screen._body_label(value_text))
	return card


## The page's reference layer: the complete public parameters, the build fingerprint
## and the raw report line, which carries the seed, the complete generational string
## and every untranslated field. It is folded by default and owns its own toggle, so
## unfolding the loadout's detail block never unfolds this one. Nothing is removed
## from the page: the surface states the conclusion, the fold keeps the evidence.
func _build_training_details(resolved: Dictionary, training: Dictionary, fingerprint: String, verified: bool) -> void:
	var section: VBoxContainer = _screen._section("Reference Data", "TrainingReferenceData")
	var toggle := Button.new()
	toggle.name = "TrainingDetailsToggle"
	toggle.text = "Hide Training Details" if _screen._training_details_open else "Show Training Details (Final Stats / Full Curve)"
	toggle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.pressed.connect(_on_training_details_toggled)
	section.add_child(toggle)
	if not _screen._training_details_open:
		return
	var parameters := UiKit.as_dictionary(resolved.get("final_parameters", {}))
	var parameter_lines: Array[String] = []
	for parameter in PlayerReadableBuildScript.PARAMETER_ORDER:
		parameter_lines.append(_screen._readable_build.format_parameter(parameter, parameters.get(parameter, null)))
	_screen._fact_label(section, "Final Stats", "  ·  ".join(parameter_lines))
	_screen._fact_label(section, "Connected Interfaces", FacilityItemText.training_interface_text(resolved.get("connected_interfaces", [])))
	_screen._fact_label(section, "Missing Interfaces", FacilityItemText.training_interface_text(resolved.get("missing_interfaces", [])))
	section.add_child(_screen._body_label(FacilityItemText.training_report_text(training, fingerprint, verified)))


func _on_training_details_toggled() -> void:
	_screen._training_details_open = not _screen._training_details_open
	if _screen._built:
		_screen._apply_presentation()


## The generational trace of the matching report and nothing else. No report, a
## report from another build, or an unverified build leaves the page with its text
## only: an earlier valid curve is never redrawn as if it were the current one.
func _add_growth_trace(parent: Container, matched: Dictionary) -> void:
	if matched.is_empty():
		return
	var points := FacilityItemText.growth_curve_points(matched.get("growth_curve", []))
	if points.size() < 2:
		return
	var trace := TrainingTraceViewScript.new()
	trace.name = "TrainingGrowthTrace"
	parent.add_child(trace)
	trace.present(points)
	_screen._training_trace = trace
	var axis: Label = _screen._note_label(trace.axis_caption())
	axis.name = "TrainingGrowthTraceAxis"
	parent.add_child(axis)
	# The trace always draws every point of the reading line; only its labels thin out
	# when they would collide, so the rule is stated instead of implied.
	parent.add_child(_screen._note_label("The curve retains every sample from this trial."))


## The generational trace the training page really drew, for tests and the report.
func training_trace_report() -> Dictionary:
	if _screen._training_trace == null:
		return {"present": false, "drawing": false}
	var report: Dictionary = _screen._training_trace.trace_report()
	report["present"] = true
	return report


## The training page only consumes the snapshot's resolved_build plus the
## training verification/report fields. It never reads available_builds,
## last_result, or the profile, and it never recomputes a Build.
func _training_resolved_build() -> Dictionary:
	var value: Variant = _screen._facility_data.get("resolved_build", null)
	if not value is Dictionary:
		return {}
	var resolved: Dictionary = value
	if not bool(resolved.get("ok", true)):
		return {}
	if String(resolved.get("build_fingerprint", "")).strip_edges().is_empty():
		return {}
	return resolved
