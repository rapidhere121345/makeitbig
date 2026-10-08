extends SceneTree
## Contract check for the settlement route view
## (src/presentation/settlement_route_view.gd).
##
## Run it on its own:
##   godot --headless --path . --script res://tests/unit/test_settlement_route_view.gd
##
## The view is a pure renderer for the sequential room results of one settlement,
## so this gate drives it with hand-written steps and checks what it really drew:
## every supplied step becomes exactly one node in order, the caller's array is
## never aliased or merged, a missing or unfamiliar state stays the open question
## it is, empty input is stated in words instead of being drawn as an empty
## corridor, and the drawn nodes are reported apart from the supplied ones. The
## real-Control pass puts the view inside a SubViewport at the 600px report width
## and at 320px and measures the Labels and the drawn geometry instead of trusting
## the code's own constants.

const RouteView = preload("res://src/presentation/settlement_route_view.gd")

## The approved Chinese UI floor (VISUAL_BASELINE.md: 正文 18-22 显示像素).
const FONT_FLOOR := 18
const EDGE_EPSILON := 0.5
## The settlement summary row the route has to live in, the inner report width
## main hands to it, and the narrow host the same view has to survive.
const SUMMARY_ROW_HEIGHT := 190.0
const REPORT_PANE_WIDTH := 600.0
const SMALL_WIDTH := 320.0
const BLOCK_FLOOR := 72.0
const BLOCK_CEILING := 104.0
const ROW_PITCH := 32.0
const FULL_ROUTE_COUNT := 12

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_empty_input_is_stated_not_drawn()
	_test_states_are_mirrored_and_success_is_never_inferred()
	_test_missing_fields_do_not_fabricate_nodes()
	_test_input_is_mirrored_not_aliased()
	await _test_short_route_reads_left_to_right()
	await _test_narrow_and_long_routes_fall_back_vertically()
	await _test_long_copy_wraps_only_when_needed()
	await _test_real_control_under_viewport()
	if failures.is_empty():
		print("PASS  test_settlement_route_view.gd: settlement route view contract")
		quit(0)
		return
	printerr("%d route check(s) failed:" % failures.size())
	for failure: String in failures:
		printerr("- %s" % failure)
	quit(1)

## Nothing to draw is not an empty corridor: the settlement did not record a
## route, and the view says exactly that, without a node of its own invention.
func _test_empty_input_is_stated_not_drawn() -> void:
	var view = _view(REPORT_PANE_WIDTH, SUMMARY_ROW_HEIGHT)
	view.present([])
	var report := view.frame_report()
	_expect(bool(report["empty"]) and int(report["step_count"]) == 0, "empty input: the route is not empty")
	_expect(String(report["empty_text"]) == RouteView.EMPTY_TEXT and not String(report["empty_text"]).is_empty(), "empty input: the unrecorded route is not stated in words")
	_expect(String(report["empty_text"]).contains("未记录"), "empty input: the note must say 未记录")
	_expect((report["states"] as Array).is_empty() and (report["marker_tops"] as Array).is_empty(), "empty input: nodes were fabricated for a route that was never reported")
	_expect(int(report["segments_solid"]) == 0 and int(report["segments_dashed"]) == 0, "empty input: connectors were drawn between nodes that do not exist")
	_expect(String(report["orientation"]) == RouteView.ORIENTATION_EMPTY, "empty input: the view claims an orientation")
	var labels := _labels(view)
	_expect(labels.size() == 1 and labels[0].text == RouteView.EMPTY_TEXT, "empty input: expected the one unrecorded note, got %d labels" % labels.size())
	for label in labels:
		_expect(label.get_theme_font_size("font_size") >= FONT_FLOOR, "empty input: %s is under the %dpx floor" % [label.name, FONT_FLOOR])
	# Junk entries are not steps, and they do not become nodes either.
	view.present([1, "completed", null, [], {"title": "无状态"}])
	report = view.frame_report()
	_expect(int(report["step_count"]) == 1 and int((report["state_counts"] as Dictionary)[RouteView.STATE_UNKNOWN]) == 1, "junk entries became route steps")
	_expect(_labels(view).size() == 1, "a step with no subtitle must produce one label, not an invented second one")
	view.present([])
	_expect(int(view.frame_report()["step_count"]) == 0, "clearing the report left stale steps behind")
	view.free()

## Only the four reported states, failed included, are understood. Anything else -
## including a success word the settlement never used - reads as unknown, because
## the view never infers that a room was cleared.
func _test_states_are_mirrored_and_success_is_never_inferred() -> void:
	var view = _view(REPORT_PANE_WIDTH, SUMMARY_ROW_HEIGHT)
	view.present([
		{"title": "一", "state": "completed"},
		{"title": "二", "state": "current"},
		{"title": "三", "state": "unreached"},
		{"title": "四", "state": "unknown"},
		{"title": "五", "state": "failed"},
		{"title": "六", "state": "success"},
		{"title": "七", "state": "victory"},
		{"title": "八", "state": "Completed"},
		{"title": "九", "state": ""},
		{"title": "十"},
		{"title": "十一", "state": 3},
	])
	var report := view.frame_report()
	_expect(_joined(report["states"]) == "completed|current|unreached|unknown|failed|unknown|unknown|completed|unknown|unknown|unknown", "state normalisation drifted: %s" % _joined(report["states"]))
	var counts: Dictionary = report["state_counts"]
	_expect(int(counts[RouteView.STATE_COMPLETED]) == 2, "only the exact completed token may count as cleared, got %d" % int(counts[RouteView.STATE_COMPLETED]))
	_expect(int(counts[RouteView.STATE_UNKNOWN]) == 6, "an unfamiliar state must read as unknown, got %d" % int(counts[RouteView.STATE_UNKNOWN]))
	_expect(int(counts[RouteView.STATE_FAILED]) == 1, "a reported failure must stay a failure")
	_expect(int(report["red_markers"]) == 1, "red is reserved for the one failed node, got %d" % int(report["red_markers"]))
	_expect(int(report["segments_dashed"]) >= 1, "unwalked connectors were drawn as walked")
	view.present([{"title": "唯一一间", "state": "completed"}, {"title": "下一间", "state": "completed"}])
	_expect(int(view.frame_report()["red_markers"]) == 0, "a route without a failure must not use red at all")
	view.present([{"title": "唯一一间", "state": "unreached"}])
	_expect(int(view.frame_report()["red_markers"]) == 0, "an unreached room is not a failure and must not be painted as one")
	view.free()

## A field the settlement did not carry stays empty or unknown; it never turns
## into copy the step did not have.
func _test_missing_fields_do_not_fabricate_nodes() -> void:
	var view = _view(REPORT_PANE_WIDTH, SUMMARY_ROW_HEIGHT)
	view.present([{"state": "completed"}, {"title": "只有标题"}, {}])
	var report := view.frame_report()
	_expect(int(report["step_count"]) == 3, "a step is a step even when its copy is missing")
	_expect(_joined(report["states"]) == "completed|unknown|unknown", "a missing state must read as unknown: %s" % _joined(report["states"]))
	_expect(_joined(report["titles"]) == "|只有标题|", "missing titles were invented: %s" % _joined(report["titles"]))
	_expect(_labels(view).size() == 3, "expected one label per supplied step, got %d" % _labels(view).size())
	view.free()

## The view mirrors the array it was handed at present() time. Later edits to the
## caller's dictionaries, the caller's array, or the returned report cannot move
## the picture, and duplicate input stays duplicate instead of being merged.
func _test_input_is_mirrored_not_aliased() -> void:
	var view = _view(REPORT_PANE_WIDTH, SUMMARY_ROW_HEIGHT)
	var steps: Array = [{"title": "甲间", "state": "completed", "subtitle": "报告"}]
	view.present(steps)
	var before := JSON.stringify(view.frame_report())
	steps[0]["title"] = "被改过的标题"
	steps[0]["state"] = "failed"
	steps.append({"title": "伪造的一间", "state": "completed"})
	steps.clear()
	_expect(JSON.stringify(view.frame_report()) == before, "the view aliased the caller's input array")
	var report := view.frame_report()
	(report["titles"] as Array).append("注入的标题")
	(report["states"] as Array).append("failed")
	(report["state_counts"] as Dictionary)[RouteView.STATE_FAILED] = 99
	var again := view.frame_report()
	_expect(_joined(again["titles"]) == "甲间", "frame_report() handed out the view's own array")
	_expect(int((again["state_counts"] as Dictionary)[RouteView.STATE_FAILED]) == 0, "frame_report() handed out the view's own counts")
	view.present([{"title": "甲间", "state": "completed", "subtitle": "报告"}])
	_expect(JSON.stringify(view.frame_report()) == before, "re-presenting the same route changed the picture")
	_expect(_labels(view).size() == 2, "re-presenting the same route accumulated labels")
	view.present([
		{"title": "重复的一间", "state": "completed"},
		{"title": "重复的一间", "state": "completed"},
	])
	var duplicated := view.frame_report()
	_expect(int(duplicated["step_count"]) == 2 and int((duplicated["state_counts"] as Dictionary)[RouteView.STATE_COMPLETED]) == 2, "duplicate steps were merged instead of mirrored")
	_expect(not bool(duplicated["empty"]), "a duplicated route is not an empty one")
	view.free()

## 1-3 short nodes in the wide report column read left to right, banded in the
## block the settlement summary row reserves.
func _test_short_route_reads_left_to_right() -> void:
	var view = _view(REPORT_PANE_WIDTH, SUMMARY_ROW_HEIGHT)
	for count in [1, 2, 3]:
		view.present(_short_route(count))
		await _frames(1)
		var report := view.frame_report()
		var required := float(report["required_height"])
		_expect(String(report["orientation"]) == RouteView.ORIENTATION_HORIZONTAL, "%d node(s): a wide short route must read left to right, got %s" % [count, String(report["orientation"])])
		_expect(required >= BLOCK_FLOOR - EDGE_EPSILON and required <= BLOCK_CEILING + EDGE_EPSILON,
			"%d node(s): the block is %.1fpx, outside the %.0f-%.0fpx band" % [count, required, BLOCK_FLOOR, BLOCK_CEILING])
		_expect(required <= SUMMARY_ROW_HEIGHT, "%d node(s): %.1fpx does not fit the %.0fpx summary row" % [count, required, SUMMARY_ROW_HEIGHT])
		_expect(is_equal_approx(float(report["min_height"]), required), "%d node(s): the view does not report its height to the host" % count)
		_expect(int(report["supplied_nodes"]) == count and int(report["drawn_nodes"]) == count and int(report["clipped_rows"]) == 0, "%d node(s): the drawn count does not match the supplied count" % count)
		_expect(int(report["segments_solid"]) + int(report["segments_dashed"]) == count - 1, "%d node(s): expected one arrow between consecutive nodes" % count)
		var lefts: Array = report["marker_lefts"]
		var tops: Array = report["marker_tops"]
		_expect(lefts.size() == count and tops.size() == count, "%d node(s): marker geometry is missing for a drawn node" % count)
		for index in count:
			_expect(is_equal_approx(float(lefts[index]), roundf(float(lefts[index]))), "%d node(s): node %d is off the pixel grid" % [count, index])
			_expect(is_equal_approx(float(tops[index]), roundf(float(tops[index]))), "%d node(s): node %d is off the pixel grid" % [count, index])
			if index > 0:
				_expect(float(lefts[index]) > float(lefts[index - 1]), "%d node(s): node %d is not to the right of node %d" % [count, index, index - 1])
				_expect(is_equal_approx(float(tops[index]), float(tops[index - 1])), "%d node(s): the left-to-right nodes are not on one line" % count)
		_expect(float(report["content_width"]) <= REPORT_PANE_WIDTH + EDGE_EPSILON, "%d node(s): the node run is wider than the report column" % count)
		_expect(not bool(report["overflow_x"]), "%d node(s): the route overflows its width" % count)
	view.free()

## The same view stays honest when left-to-right is not possible: a narrow host, a
## chain of 4+ nodes and copy that cannot sit on one node line all read top to
## bottom, and a route longer than its host reports the split instead of pretending.
func _test_narrow_and_long_routes_fall_back_vertically() -> void:
	var narrow = _view(SMALL_WIDTH, 0.0)
	narrow.present(_short_route(3))
	await _frames(1)
	var narrow_report := narrow.frame_report()
	_expect(String(narrow_report["orientation"]) == RouteView.ORIENTATION_VERTICAL, "narrow host: expected the vertical fallback, got %s" % String(narrow_report["orientation"]))
	_expect(float(narrow_report["required_height"]) <= BLOCK_CEILING + EDGE_EPSILON, "narrow host: the short block is %.1fpx, above the %.0fpx ceiling" % [float(narrow_report["required_height"]), BLOCK_CEILING])
	_expect(not bool(narrow_report["overflow_x"]), "narrow host: the route overflows 320px")
	narrow.present(_short_route(4))
	await _frames(1)
	_expect(String(narrow.frame_report()["orientation"]) == RouteView.ORIENTATION_VERTICAL, "narrow host: 4 nodes stopped using the vertical fallback")
	narrow.free()
	var wide = _view(REPORT_PANE_WIDTH, 0.0)
	wide.present(_short_route(4))
	await _frames(1)
	_expect(String(wide.frame_report()["orientation"]) == RouteView.ORIENTATION_VERTICAL, "a 4-node chain must fall back to the vertical reading")
	wide.present(_full_route())
	await _frames(1)
	var full := wide.frame_report()
	var native := float(full["required_height"])
	_expect(String(full["orientation"]) == RouteView.ORIENTATION_VERTICAL, "a full route must not be squeezed into the left-to-right reading")
	_expect(int(full["supplied_nodes"]) == FULL_ROUTE_COUNT, "full route: %d steps were mirrored" % int(full["supplied_nodes"]))
	_expect(native > SUMMARY_ROW_HEIGHT, "full route: %d nodes claim to fit the summary row (%.1fpx)" % [FULL_ROUTE_COUNT, native])
	var measured_rows := 0.0
	for row_height: Variant in full["row_heights"]:
		measured_rows += float(row_height)
	_expect(is_equal_approx(native, measured_rows), "full route: native height %.1fpx does not match its measured rows %.1fpx" % [native, measured_rows])
	wide.size = Vector2(REPORT_PANE_WIDTH, native)
	await _frames(2)
	full = wide.frame_report()
	_expect(int(full["drawn_nodes"]) == FULL_ROUTE_COUNT and int(full["clipped_rows"]) == 0, "full route: nodes were lost at its own height")
	_expect((full["marker_lefts"] as Array).size() == FULL_ROUTE_COUNT and (full["marker_tops"] as Array).size() == FULL_ROUTE_COUNT, "full route: drawn-node geometry does not cover every node")
	var tops: Array = full["marker_tops"]
	for index in range(1, tops.size()):
		_expect(float(tops[index]) > float(tops[index - 1]), "full route: node %d is not below node %d" % [index, index - 1])
	# A shorter host draws only what fits and reports the split: the supplied list
	# still holds every step, the drawn geometry holds only the drawn nodes.
	wide.size = Vector2(REPORT_PANE_WIDTH, SUMMARY_ROW_HEIGHT)
	await _frames(2)
	full = wide.frame_report()
	var drawn := int(full["drawn_nodes"])
	_expect(drawn > 0 and drawn < FULL_ROUTE_COUNT, "short host: expected a partial route, got %d of %d nodes" % [drawn, FULL_ROUTE_COUNT])
	_expect(drawn + int(full["clipped_rows"]) == FULL_ROUTE_COUNT, "short host: %d drawn + %d clipped is not %d supplied nodes" % [drawn, int(full["clipped_rows"]), FULL_ROUTE_COUNT])
	_expect(int(full["supplied_nodes"]) == FULL_ROUTE_COUNT and _joined(full["states"]).split("|").size() == FULL_ROUTE_COUNT, "short host: the supplied nodes were dropped from the report")
	_expect((full["marker_tops"] as Array).size() == drawn and (full["marker_lefts"] as Array).size() == drawn, "short host: the report claims geometry for nodes that were not drawn")
	for top in (full["marker_tops"] as Array):
		_expect(float(top) + float(full["marker_size"]) <= SUMMARY_ROW_HEIGHT + EDGE_EPSILON, "short host: a marker reaches past the control")
	wide.free()

## Copy that does not fit grows its own node and nothing else: the block gets
## taller, the width never overflows, and a wide column needs fewer lines than a
## narrow one.
func _test_long_copy_wraps_only_when_needed() -> void:
	var long_title := "第七回收段：守夜人残响与无编号接线盒在风暴中持续作响，样本需要分两段带回"
	var wide = _view(REPORT_PANE_WIDTH, 0.0)
	wide.present([{"title": long_title, "state": "completed", "subtitle": "报告完整"}])
	await _frames(1)
	var wide_report := wide.frame_report()
	_expect(String(wide_report["orientation"]) == RouteView.ORIENTATION_VERTICAL, "copy too wide for one node line must fall back to the vertical reading")
	_expect(int(wide_report["wrapped_rows"]) == 1, "a title wider than the column did not wrap")
	_expect(float((wide_report["row_heights"] as Array)[0]) > ROW_PITCH, "a wrapped node kept its single-line height")
	_expect(not bool(wide_report["overflow_x"]), "wrapped copy overflows the report width")
	var narrow = _view(SMALL_WIDTH, 0.0)
	narrow.present([{"title": long_title, "state": "completed", "subtitle": "报告完整"}])
	await _frames(1)
	var narrow_report := narrow.frame_report()
	_expect(float(narrow_report["required_height"]) >= float(wide_report["required_height"]), "the narrow column needs fewer lines than the wide one")
	_expect(not bool(narrow_report["overflow_x"]), "narrow route: wrapped copy overflows the 320px width")
	var drops = _view(SMALL_WIDTH, 0.0)
	drops.present([{"title": "短标题", "state": "completed", "subtitle": "这是一条足够长的副标题，用来确认它不会再挤在同一行里造成溢出"}])
	await _frames(1)
	var drops_report := drops.frame_report()
	_expect(int(drops_report["inline_subtitle_rows"]) == 0, "an overlong subtitle was forced onto the title's line")
	_expect(float((drops_report["row_heights"] as Array)[0]) > ROW_PITCH, "a two-line node kept the one-line height")
	_expect(not bool(drops_report["overflow_x"]), "a dropped subtitle overflows the 320px width")
	wide.free()
	narrow.free()
	drops.free()

## The real control inside a real SubViewport: the 600px report pane and the small
## 320px host, with the Labels and the drawn geometry measured after real frames.
func _test_real_control_under_viewport() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var pane := Control.new()
	pane.name = "RoutePane"
	pane.size = Vector2(REPORT_PANE_WIDTH, SUMMARY_ROW_HEIGHT)
	viewport.add_child(pane)
	var view = RouteView.new()
	view.name = "RouteView"
	pane.add_child(view)
	view.size = Vector2(REPORT_PANE_WIDTH, SUMMARY_ROW_HEIGHT)
	view.present(_full_route())
	await _frames(4)
	var report := view.frame_report()
	_expect(float(report["width"]) == REPORT_PANE_WIDTH, "viewport: the pane did not hand the report width to the route (%s)" % str(report["width"]))
	_expect(int(report["draw_passes"]) >= 1, "viewport: the view never reached a draw pass")
	_expect(int(report["red_markers_drawn"]) == int(report["red_markers"]), "viewport: %d failed node(s) reported, %d drawn in the last pass" % [int(report["red_markers"]), int(report["red_markers_drawn"])])
	_expect(_joined(report["states"]).contains("failed"), "viewport: the fixture lost its failed step")
	_check_bounds_and_fonts(view, "viewport 600px")
	# The same settlement as a short chain in the same pane, read left to right.
	view.present(_short_route(3))
	await _frames(3)
	report = view.frame_report()
	_expect(String(report["orientation"]) == RouteView.ORIENTATION_HORIZONTAL and int(report["drawn_nodes"]) == 3, "viewport: the short chain did not read left to right")
	_check_bounds_and_fonts(view, "viewport short chain")
	# The small host: everything stays inside, nothing overflows.
	view.size = Vector2(SMALL_WIDTH, SUMMARY_ROW_HEIGHT)
	await _frames(3)
	report = view.frame_report()
	_expect(float(report["width"]) == SMALL_WIDTH, "small host: the route did not follow its host width (%s)" % str(report["width"]))
	_expect(String(report["orientation"]) == RouteView.ORIENTATION_VERTICAL, "small host: the route claims the wide reading")
	_expect(not bool(report["overflow_x"]) and float(report["max_right"]) <= SMALL_WIDTH + EDGE_EPSILON, "small host: the route reaches past 320px (max_right %s)" % str(report["max_right"]))
	_check_bounds_and_fonts(view, "small host 320px")
	# The empty route is stated in words under the same host, still with no nodes.
	view.present([])
	await _frames(2)
	report = view.frame_report()
	_expect(bool(report["empty"]) and _labels(view).size() == 1, "viewport: the empty route did not collapse to its note")
	_expect(float(report["required_height"]) <= SUMMARY_ROW_HEIGHT, "viewport: the empty note does not fit the summary row")
	_check_bounds_and_fonts(view, "empty route")
	view.free()
	viewport.queue_free()

## Every visible Label stays inside the route rect and keeps the CJK floor.
func _check_bounds_and_fonts(view: RouteView, tag: String) -> void:
	var bounds := view.get_global_rect()
	for label in _labels(view):
		if not label.visible or label.text.strip_edges().is_empty():
			continue
		var rect := label.get_global_rect()
		_expect(rect.position.x >= bounds.position.x - EDGE_EPSILON, "%s: %s starts left of the route rect" % [tag, label.name])
		_expect(rect.end.x <= bounds.end.x + EDGE_EPSILON, "%s: %s overflows the route width (%s vs %s)" % [tag, label.name, str(rect.end.x), str(bounds.end.x)])
		_expect(rect.end.y <= bounds.end.y + EDGE_EPSILON, "%s: %s reaches below the route rect" % [tag, label.name])
		_expect(label.get_theme_font_size("font_size") >= FONT_FLOOR, "%s: %s is drawn at %dpx, under the %dpx floor" % [tag, label.name, label.get_theme_font_size("font_size"), FONT_FLOOR])
		_expect(label.get_theme_font("font") != null, "%s: %s has no packaged font" % [tag, label.name])

func _view(width: float, height: float) -> RouteView:
	var view = RouteView.new()
	view.size = Vector2(width, height)
	return view

func _short_route(count: int) -> Array:
	var steps: Array = []
	for index in count:
		steps.append({
			"title": "第%d间" % [index + 1],
			"state": "completed" if index < count - 1 else "current",
			"subtitle": "胜利" if index < count - 1 else "进行中",
		})
	return steps

## Twelve rooms, exactly as a finished contract would hand them over: cleared
## rooms, one that ended the run, and the part of the chain that was never reached
## or never recorded.
func _full_route() -> Array:
	var steps: Array = []
	for index in FULL_ROUTE_COUNT:
		var state := "completed"
		if index == FULL_ROUTE_COUNT - 3:
			state = "failed"
		elif index == FULL_ROUTE_COUNT - 2:
			state = "unreached"
		elif index == FULL_ROUTE_COUNT - 1:
			state = "unknown"
		steps.append({
			"title": "第%d间" % [index + 1],
			"state": state,
			"subtitle": "%d 秒" % [8 + index],
		})
	return steps

func _labels(node: Node) -> Array[Label]:
	var found: Array[Label] = []
	for child in node.get_children():
		if child is Label:
			found.append(child)
		found.append_array(_labels(child))
	return found

func _joined(values: Variant) -> String:
	var parts: Array[String] = []
	for value: Variant in values:
		parts.append(String(value))
	return "|".join(parts)

func _frames(count: int) -> void:
	for _index in count:
		await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
