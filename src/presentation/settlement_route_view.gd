class_name SettlementRouteView
extends Control

## Sequential room-result journey of one settlement, drawn from nothing but the
## steps the settlement hands over (concept source10/06: a left-to-right process
## of node, then node, then node).
##
## The view is a pure renderer and owns no authority: it mirrors the steps it is
## given, in the order they arrive, and derives nothing further - no room, no
## branch, no progress, no success. A step that was never supplied is never drawn,
## an unrecognised state becomes the open question it is, and the only red in the
## control is the semantic failure colour of a step that main reported as failed.
##
## Input contract (main owns the data): every entry of the array passed to
## present() is {title: String, state: "completed" | "current" | "unreached" |
## "unknown" | "failed", subtitle: String}. Title and subtitle are drawn exactly
## as handed over; duplicate entries stay duplicate nodes, because the view never
## merges, sorts, re-labels or re-states a settlement. Empty input is stated in
## words instead of being drawn as an empty corridor: the settlement did not
## record a route, and the view fabricates no node for it.
##
## Layout contract: 1-3 short nodes at >= 500px read left to right, one node per
## step with its own marker and its title over its subtitle, joined by a single
## rightward arrow - the whole band is 72-104px tall, which is the block the
## settlement summary row is sized for. A narrow host, a longer route (4+ steps)
## or copy that cannot sit on one node line falls back to an honest vertical run
## of the same nodes, where a row grows only when its own copy cannot fit one
## line. A route longer than its host reports its full height through
## custom_minimum_size so a scrolling body can expand to it, and inside a shorter
## host the view stops after the last node that fits and reports that split
## instead of pretending the unseen nodes were drawn. The view never assumes a
## screen size, and mouse_filter is off so a scrolling host keeps its drag.
##
## Drawing contract: markers are hard-corner squares and connectors are straight
## arrows between consecutive nodes - reading order, never a causal branch - all
## on whole pixels, with no glow and no gradient. Text lives in real Labels (a
## title, and a subtitle only when the step carries one) so the copy stays
## inspectable and keeps the 18px CJK floor, while markers and connectors stay in
## _draw().

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")

## Accepted states, exactly as main reports them. Any other token - including a
## success word the settlement never used - normalises to unknown; the view never
## infers that a room was cleared.
const STATE_COMPLETED := "completed"
const STATE_CURRENT := "current"
const STATE_UNREACHED := "unreached"
const STATE_UNKNOWN := "unknown"
const STATE_FAILED := "failed"
const STATE_KEYS: Array[String] = [
	STATE_COMPLETED, STATE_CURRENT, STATE_UNREACHED, STATE_UNKNOWN, STATE_FAILED,
]
## States that say the run really stood in that room. They only choose the shape
## of one connector; they never turn an unknown or unreached step into progress.
const REACHED_STATES: Array[String] = [STATE_COMPLETED, STATE_CURRENT, STATE_FAILED]

## The two readings of the same journey. A view that cannot lay the nodes out
## left to right says so instead of squeezing them.
const ORIENTATION_EMPTY := "empty"
const ORIENTATION_HORIZONTAL := "horizontal"
const ORIENTATION_VERTICAL := "vertical"

## The only copy the view owns. Every other string on screen is main's text.
const EMPTY_TEXT := "本次结算未记录房间路线。"

const TITLE_FONT_SIZE: int = ShellThemeScript.BODY_FONT_SIZE
const SUBTITLE_FONT_SIZE: int = ShellThemeScript.MIN_FONT_SIZE
const GLYPH_FONT_SIZE: int = ShellThemeScript.MIN_FONT_SIZE
const WRAP_FLAGS := TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND

## One compact node: an 18px+ text line inside a 32px row, so a short route fits
## the settlement summary row without pushing it apart.
const ROW_PITCH := 32.0
## The block a short route keeps. The upper allowance includes the packaged
## Chinese font's real 22px body line instead of assuming a 20px face.
const MIN_BLOCK_HEIGHT := 72.0
const BLOCK_CEILING := 104.0
## Left-to-right nodes need a wide report column and a short chain; anything else
## is read top to bottom in the same shape language.
const HORIZONTAL_MIN_WIDTH := 500.0
const HORIZONTAL_MAX_NODES := 3
const NODE_GAP := 28.0
const MARKER_TEXT_GAP := 10.0

const MARKER_SIZE := 20.0
const MARKER_COLUMN_WIDTH := 32.0
const MARKER_CENTER_X := 16.0
const MARKER_LEFT := MARKER_CENTER_X - MARKER_SIZE * 0.5
const BORDER_WIDTH := 2.0
const CURRENT_CORE_SIZE := 6.0
const FAILED_GLYPH_INSET := 6.0

const TEXT_LEFT := 44.0
const PAD_RIGHT := 2.0
const MIN_TEXT_WIDTH := 60.0
## Gap between an inline title and its subtitle on the same row line.
const INLINE_GAP := 10.0
## Gap used when the subtitle sits on its own line under the title.
const SUBTITLE_GAP := 4.0

const CONNECTOR_WIDTH := 2.0
const DASH_LENGTH := 4.0
const ARROW_LENGTH := 5.0
const ARROW_HALF_WIDTH := 3.0
# get_multiline_string_size already reports the packaged font's complete line
# box. Extra height here would make the final label extend past the measured row.
const LABEL_HEIGHT_PADDING := 0.0
const EDGE_EPSILON := 0.5

var _steps: Array[Dictionary] = []
var _rows: Array[Dictionary] = []
var _title_labels: Array[Label] = []
var _subtitle_labels: Array[Label] = []
var _empty_label: Label = null
var _orientation := ORIENTATION_EMPTY
var _required_height := 0.0
var _content_width := 0.0
var _text_width := 0.0
var _empty_text_width := 0.0
var _text_visible := false
var _markers_visible := false
var _visible_rows := 0
var _wrapped_rows := 0
var _inline_subtitle_rows := 0
var _draw_passes := 0
var _red_markers_drawn := 0
var _stale := true
var _layout_width := -1.0
var _layout_height := -1.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_mark_stale)

## Mirrors the steps of one settlement, in order. Entries that are not
## dictionaries are not steps and never become nodes; title and subtitle accept a
## String (or StringName) only, and every other state token reads as unknown.
## Calling it again replaces the whole picture - it never appends to the previous
## one, so the same input always produces the same view.
func present(steps: Array) -> void:
	_steps = []
	for raw: Variant in steps:
		if not (raw is Dictionary):
			continue
		var step: Dictionary = raw
		_steps.append({
			"title": _text(step.get("title", "")),
			"subtitle": _text(step.get("subtitle", "")),
			"state": _normalize_state(step.get("state", null)),
		})
	_rebuild_labels()
	_stale = true
	_layout()
	queue_redraw()

## Everything a test, the settlement screen or the art pass may quote about the
## route that is on the control right now. Plain, freshly built data - no live
## reference to the input and no writable handle on the view's own nodes. The
## supplied lists always keep every step main handed over; visible_rows and
## clipped_rows describe the drawing, and marker geometry exists only for the
## nodes that were really drawn.
func frame_report() -> Dictionary:
	_ensure_layout()
	var font := _ui_font()
	var titles: Array[String] = []
	var subtitles: Array[String] = []
	var states: Array[String] = []
	var counts: Dictionary = {}
	for key in STATE_KEYS:
		counts[key] = 0
	for step in _steps:
		titles.append(String(step.get("title", "")))
		subtitles.append(String(step.get("subtitle", "")))
		var state := String(step.get("state", STATE_UNKNOWN))
		states.append(state)
		counts[state] = int(counts.get(state, 0)) + 1
	var row_tops: Array[float] = []
	var row_heights: Array[float] = []
	var node_widths: Array[float] = []
	var marker_lefts: Array[float] = []
	var marker_tops: Array[float] = []
	var visible_failed := 0
	for index in _rows.size():
		var row: Dictionary = _rows[index]
		row_tops.append(float(row.get("top", 0.0)))
		row_heights.append(float(row.get("height", 0.0)))
		node_widths.append(float(row.get("width", 0.0)))
		if index >= _visible_rows:
			continue
		marker_lefts.append(_marker_left(index))
		marker_tops.append(_marker_top(index))
		if _state_at(index) == STATE_FAILED:
			visible_failed += 1
	var solid := 0
	var dashed := 0
	for index in range(0, maxi(_visible_rows - 1, 0)):
		if _segment_is_reached(index):
			solid += 1
		else:
			dashed += 1
	var laid_out := size.x > 0.0
	var max_right := 0.0
	if _steps.is_empty():
		if _text_visible:
			max_right = _empty_text_width
	elif laid_out and _markers_visible:
		max_right = _content_width
	return {
		"empty": _steps.is_empty(),
		"empty_text": EMPTY_TEXT if _steps.is_empty() else "",
		"orientation": _orientation,
		"connector_axis": "none" if _steps.is_empty() else _orientation,
		"supplied_nodes": _steps.size(),
		"drawn_nodes": _visible_rows,
		"step_count": _steps.size(),
		"titles": titles,
		"subtitles": subtitles,
		"states": states,
		"state_counts": counts,
		"row_tops": row_tops,
		"row_heights": row_heights,
		"node_widths": node_widths,
		"marker_lefts": marker_lefts,
		"marker_tops": marker_tops,
		"visible_rows": _visible_rows,
		"clipped_rows": maxi(_steps.size() - _visible_rows, 0),
		"wrapped_rows": _wrapped_rows,
		"inline_subtitle_rows": _inline_subtitle_rows,
		"segments_solid": solid,
		"segments_dashed": dashed,
		"red_markers": visible_failed,
		"red_markers_drawn": _red_markers_drawn,
		"required_height": _required_height,
		"min_height": custom_minimum_size.y,
		"min_block_height": MIN_BLOCK_HEIGHT,
		"block_ceiling": BLOCK_CEILING,
		"row_pitch": ROW_PITCH,
		"marker_size": MARKER_SIZE,
		"marker_x": MARKER_LEFT,
		"connector_x": MARKER_CENTER_X,
		"line_width": CONNECTOR_WIDTH,
		"dash_length": DASH_LENGTH,
		"font": font.get_class() if font != null else "",
		"title_font_size": TITLE_FONT_SIZE,
		"subtitle_font_size": SUBTITLE_FONT_SIZE,
		"text_width": _text_width,
		"empty_text_width": _empty_text_width,
		"content_width": _content_width,
		"text_visible": _text_visible,
		"markers_visible": _markers_visible,
		"max_right": max_right,
		"overflow_x": laid_out and max_right > size.x + EDGE_EPSILON,
		"laid_out": laid_out,
		"width": size.x,
		"height": size.y,
		"label_count": _title_labels.size() + _subtitle_labels.size() + (1 if _empty_label != null else 0),
		"draw_passes": _draw_passes,
	}

func _mark_stale() -> void:
	_stale = true

func _ensure_layout() -> void:
	if _stale or not is_equal_approx(size.x, _layout_width) or not is_equal_approx(size.y, _layout_height):
		_layout()

## Recomputes the whole picture from the mirrored steps and the current width: the
## orientation this width supports, node geometry, label boxes, the height the
## view needs and how many nodes fit the host it was given. Nothing here reads or
## writes anything but the copy it was handed.
func _layout() -> void:
	_stale = false
	_layout_width = size.x
	_layout_height = size.y
	var font := _ui_font()
	_text_width = maxf(size.x - TEXT_LEFT - PAD_RIGHT, 0.0)
	_empty_text_width = maxf(size.x - PAD_RIGHT, 0.0)
	_text_visible = _text_width >= MIN_TEXT_WIDTH
	_markers_visible = size.x >= MARKER_COLUMN_WIDTH + PAD_RIGHT
	_rows = []
	_wrapped_rows = 0
	_inline_subtitle_rows = 0
	_orientation = ORIENTATION_EMPTY
	_content_width = 0.0
	var content_height := 0.0
	if _steps.is_empty():
		content_height = _layout_empty(font)
	elif _horizontal_fits(font):
		content_height = _layout_horizontal(font)
	else:
		content_height = _layout_vertical(font)
	_required_height = content_height if _steps.is_empty() else maxf(content_height, MIN_BLOCK_HEIGHT)
	var pad := floorf(maxf(_required_height - content_height, 0.0) * 0.5)
	for row in _rows:
		row["top"] = roundf(float(row.get("top", 0.0)) + pad)
	_visible_rows = _count_visible_rows()
	_place_labels()
	custom_minimum_size = Vector2(0.0, _required_height)

## The empty route is one line of copy and nothing else. Its block keeps the same
## presence as a short route so the summary row does not jump.
func _layout_empty(font: Font) -> float:
	if _empty_label == null:
		return MIN_BLOCK_HEIGHT
	var text_height := 0.0
	if _text_visible:
		text_height = _text_height(font, EMPTY_TEXT, _empty_text_width, SUBTITLE_FONT_SIZE)
	_empty_label.visible = _text_visible and text_height > 0.0
	_set_label_box(_empty_label, Vector2(0.0, 0.0), Vector2(_empty_text_width, text_height + LABEL_HEIGHT_PADDING))
	return maxf(text_height, MIN_BLOCK_HEIGHT)

## Left-to-right is the reading of concept source10/06, but only where it is
## honest: a wide column, at most three nodes, and every node's own copy on one
## line. Anything else keeps the same nodes in a vertical run instead.
func _horizontal_fits(font: Font) -> bool:
	if not _text_visible or not _markers_visible:
		return false
	if _steps.size() > HORIZONTAL_MAX_NODES or size.x < HORIZONTAL_MIN_WIDTH:
		return false
	var total := 0.0
	for index in _steps.size():
		var title := String(_steps[index].get("title", ""))
		var subtitle := String(_steps[index].get("subtitle", ""))
		var title_width := _line_width(font, title, TITLE_FONT_SIZE)
		var subtitle_width := _line_width(font, subtitle, SUBTITLE_FONT_SIZE)
		if title_width > _text_width or subtitle_width > _text_width:
			return false
		total += MARKER_SIZE + MARKER_TEXT_GAP + maxf(title_width, subtitle_width)
		if index < _steps.size() - 1:
			total += NODE_GAP
	return total <= size.x - PAD_RIGHT - 2.0

func _layout_horizontal(font: Font) -> float:
	_orientation = ORIENTATION_HORIZONTAL
	var nodes: Array[Dictionary] = []
	var content_height := 0.0
	for index in _steps.size():
		var node := _measure_node(font, index)
		content_height = maxf(content_height, float(node.get("height", MARKER_SIZE)))
		nodes.append(node)
	var left := 0.0
	for index in nodes.size():
		var node: Dictionary = nodes[index]
		node["top"] = roundf((content_height - float(node.get("height", MARKER_SIZE))) * 0.5)
		node["left"] = left
		node["text_left"] = left + MARKER_SIZE + MARKER_TEXT_GAP
		left += roundf(float(node.get("width", MARKER_SIZE)))
		_content_width = left
		if index < nodes.size() - 1:
			left += NODE_GAP
		_rows.append(node)
	return content_height

## One left-to-right node: its marker, then its title over its subtitle. The node
## carries its own copy and nothing else.
func _measure_node(font: Font, index: int) -> Dictionary:
	var step: Dictionary = _steps[index]
	var title := String(step.get("title", ""))
	var subtitle := String(step.get("subtitle", ""))
	var title_height := 0.0
	var subtitle_height := 0.0
	var title_width := 0.0
	var subtitle_width := 0.0
	if _text_visible:
		title_height = _text_height(font, title, _text_width, TITLE_FONT_SIZE)
		title_width = _line_width(font, title, TITLE_FONT_SIZE)
		subtitle_height = _text_height(font, subtitle, _text_width, SUBTITLE_FONT_SIZE)
		subtitle_width = _line_width(font, subtitle, SUBTITLE_FONT_SIZE)
	var text_height := title_height
	if subtitle_height > 0.0:
		text_height += (SUBTITLE_GAP if title_height > 0.0 else 0.0) + subtitle_height
	var height := maxf(text_height, MARKER_SIZE)
	var first_line := _first_line_height(font, title, subtitle, title_height, subtitle_height)
	return {
		"height": height,
		"top": 0.0,
		"left": MARKER_LEFT,
		"width": MARKER_SIZE + MARKER_TEXT_GAP + maxf(title_width, subtitle_width),
		"text_left": TEXT_LEFT,
		"text_top": 0.0,
		"title_height": title_height,
		"subtitle_height": subtitle_height,
		"title_width": maxf(title_width + 1.0, 1.0),
		"subtitle_width": maxf(subtitle_width + 1.0, 1.0),
		"subtitle_inline": false,
		"first_line": first_line,
		"wrapped": false,
	}

func _layout_vertical(font: Font) -> float:
	_orientation = ORIENTATION_VERTICAL
	var content_height := 0.0
	for index in _steps.size():
		var row := _measure_row(font, index)
		if bool(row.get("wrapped", false)):
			_wrapped_rows += 1
		if bool(row.get("subtitle_inline", false)):
			_inline_subtitle_rows += 1
		row["top"] = content_height
		_rows.append(row)
		content_height += float(row.get("height", ROW_PITCH))
	_content_width = MARKER_SIZE + MARKER_TEXT_GAP + minf(_text_width, maxf(_text_width, 0.0))
	return content_height

## One vertical row: the marker column plus a single text line whenever the copy
## fits in it. The subtitle joins the title's line when it can, drops below the
## title when it cannot, and the title itself wraps only when it is too long for
## the column - so a row is one line unless its own copy demands more.
func _measure_row(font: Font, index: int) -> Dictionary:
	var step: Dictionary = _steps[index]
	var title := String(step.get("title", ""))
	var subtitle := String(step.get("subtitle", ""))
	var title_height := 0.0
	var subtitle_height := 0.0
	var title_line_width := 0.0
	var subtitle_line_width := 0.0
	var inline_subtitle := false
	if _text_visible:
		if not title.is_empty():
			title_height = _text_height(font, title, _text_width, TITLE_FONT_SIZE)
			title_line_width = _line_width(font, title, TITLE_FONT_SIZE)
		if not subtitle.is_empty():
			subtitle_height = _text_height(font, subtitle, _text_width, SUBTITLE_FONT_SIZE)
			subtitle_line_width = _line_width(font, subtitle, SUBTITLE_FONT_SIZE)
		inline_subtitle = (
			title_height > 0.0
			and subtitle_height > 0.0
			and title_line_width <= _text_width
			and title_line_width + INLINE_GAP + subtitle_line_width <= _text_width
		)
	var text_height := title_height
	if inline_subtitle:
		text_height = maxf(title_height, subtitle_height)
	elif subtitle_height > 0.0:
		text_height += (SUBTITLE_GAP if title_height > 0.0 else 0.0) + subtitle_height
	var height := maxf(ROW_PITCH, text_height)
	var text_top := roundf(maxf(height - text_height, 0.0) * 0.5)
	var first_line := _first_line_height(font, title, subtitle, title_height, subtitle_height)
	return {
		"height": height,
		"top": 0.0,
		"left": MARKER_LEFT,
		"width": MARKER_SIZE + MARKER_TEXT_GAP + minf(_text_width, title_line_width + 1.0),
		"text_left": TEXT_LEFT,
		"text_top": text_top,
		"title_height": title_height,
		"subtitle_height": subtitle_height,
		"title_width": minf(_text_width, title_line_width + 1.0),
		"subtitle_width": maxf(_text_width - title_line_width - INLINE_GAP, 0.0) if inline_subtitle else _text_width,
		"subtitle_inline": inline_subtitle,
		"first_line": first_line,
		"wrapped": text_height > first_line + EDGE_EPSILON,
	}

## The height of the text line the marker is aligned with: the first visual line
## of the title, or of the subtitle when there is no title.
func _first_line_height(font: Font, title: String, subtitle: String, title_height: float, subtitle_height: float) -> float:
	if font == null:
		return MARKER_SIZE
	var line := MARKER_SIZE
	if not title.is_empty() and title_height > 0.0:
		line = minf(title_height, ceilf(font.get_height(TITLE_FONT_SIZE)))
	elif not subtitle.is_empty() and subtitle_height > 0.0:
		line = minf(subtitle_height, ceilf(font.get_height(SUBTITLE_FONT_SIZE)))
	return maxf(line, MARKER_SIZE)

func _count_visible_rows() -> int:
	if _steps.is_empty():
		return 0
	# An unsized control (before the first layout pass) is unconstrained: report
	# every node and let the host's real height clip later.
	if size.y <= 0.0:
		return _rows.size()
	var visible := 0
	for index in _rows.size():
		var row: Dictionary = _rows[index]
		if float(row.get("top", 0.0)) + float(row.get("height", 0.0)) <= size.y + EDGE_EPSILON:
			visible = index + 1
		else:
			break
	return visible

func _place_labels() -> void:
	if _steps.is_empty():
		return
	for index in _rows.size():
		var row: Dictionary = _rows[index]
		var shown := index < _visible_rows and _text_visible
		var text_left := float(row.get("text_left", TEXT_LEFT))
		var text_top := float(row.get("top", 0.0)) + float(row.get("text_top", 0.0))
		var title_height := float(row.get("title_height", 0.0))
		var subtitle_height := float(row.get("subtitle_height", 0.0))
		var title_label: Label = _title_labels[index]
		title_label.visible = shown and title_height > 0.0
		_set_label_box(title_label, Vector2(text_left, text_top), Vector2(float(row.get("title_width", _text_width)), title_height + LABEL_HEIGHT_PADDING))
		var subtitle_label: Label = _subtitle_labels[index]
		if subtitle_label == null:
			continue
		subtitle_label.visible = shown and subtitle_height > 0.0
		if bool(row.get("subtitle_inline", false)):
			_set_label_box(subtitle_label, Vector2(text_left + float(row.get("title_width", 0.0)) + INLINE_GAP, text_top + _baseline_shift()), Vector2(float(row.get("subtitle_width", _text_width)), subtitle_height + LABEL_HEIGHT_PADDING))
		else:
			_set_label_box(subtitle_label, Vector2(text_left, text_top + title_height + (SUBTITLE_GAP if title_height > 0.0 else 0.0)), Vector2(float(row.get("subtitle_width", _text_width)), subtitle_height + LABEL_HEIGHT_PADDING))

## Places one label box. A Label's own minimum size follows the width it was last
## shaped at, so the width is handed over first: without that, a label still shaped
## at width zero clamps upward the height this view measured for it.
func _set_label_box(label: Label, position: Vector2, box: Vector2) -> void:
	label.position = position
	label.size = Vector2(box.x, label.size.y)
	# Reading the minimum first lets the label re-shape at the width it was just
	# given; only then does its own wrapped height allow the measured box to land.
	var needed := label.get_minimum_size()
	label.size = Vector2(box.x, maxf(box.y, needed.y))

## Keeps an inline 18px subtitle on the 20px title's baseline.
func _baseline_shift() -> float:
	var font := _ui_font()
	if font == null:
		return 0.0
	return roundf(font.get_ascent(TITLE_FONT_SIZE) - font.get_ascent(SUBTITLE_FONT_SIZE))

func _ui_font() -> Font:
	var packaged := ShellThemeScript.ui_font()
	if packaged != null:
		return packaged
	var themed := get_theme_default_font()
	return themed if themed != null else ThemeDB.fallback_font

## Only an exact String or StringName is drawn: a number or a missing field stays
## empty instead of being turned into copy the settlement never carried.
func _text(value: Variant) -> String:
	if value is String:
		return value
	if value is StringName:
		return String(value)
	return ""

func _normalize_state(value: Variant) -> String:
	var token := _text(value).strip_edges().to_lower()
	if STATE_KEYS.has(token):
		return token
	return STATE_UNKNOWN

func _state_at(index: int) -> String:
	if index < 0 or index >= _steps.size():
		return STATE_UNKNOWN
	return String(_steps[index].get("state", STATE_UNKNOWN))

## A connector is solid only when the run really stood on both of its ends.
func _segment_is_reached(index: int) -> bool:
	return REACHED_STATES.has(_state_at(index)) and REACHED_STATES.has(_state_at(index + 1))

func _marker_left(index: int) -> float:
	if index < 0 or index >= _rows.size():
		return MARKER_LEFT
	var row: Dictionary = _rows[index]
	return roundf(float(row.get("left", MARKER_LEFT)))

func _marker_top(index: int) -> float:
	if index < 0 or index >= _rows.size():
		return 0.0
	var row: Dictionary = _rows[index]
	var lead := maxf(float(row.get("first_line", MARKER_SIZE)), MARKER_SIZE)
	return roundf(float(row.get("top", 0.0)) + maxf(lead - MARKER_SIZE, 0.0) * 0.5)

func _text_height(font: Font, text: String, width: float, font_size: int) -> float:
	if font == null or text.is_empty() or width <= 0.0:
		return 0.0
	return maxf(ceilf(_measure(font, text, width, font_size).y), float(font_size))

func _line_width(font: Font, text: String, font_size: int) -> float:
	if font == null or text.is_empty():
		return 0.0
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x

## The wrapped block of one label, shaped with the same break flags a word-smart
## Label uses, so the box the view reserves is the box the Label fills.
func _measure(font: Font, text: String, width: float, font_size: int) -> Vector2:
	return font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, -1, WRAP_FLAGS)

func _rebuild_labels() -> void:
	for label in _title_labels:
		_drop_label(label)
	for label in _subtitle_labels:
		_drop_label(label)
	_title_labels = []
	_subtitle_labels = []
	if _empty_label != null:
		_drop_label(_empty_label)
		_empty_label = null
	if _steps.is_empty():
		_empty_label = _make_label("RouteEmpty", SUBTITLE_FONT_SIZE, ShellThemeScript.NEUTRAL)
		_empty_label.text = EMPTY_TEXT
		return
	for index in _steps.size():
		var title := _make_label("RouteTitle_%d" % index, TITLE_FONT_SIZE, ShellThemeScript.BONE)
		title.text = String(_steps[index].get("title", ""))
		_title_labels.append(title)
		# A step without a subtitle gets no subtitle label: the view never adds a
		# second node for copy that was not reported.
		var subtitle_text := String(_steps[index].get("subtitle", ""))
		if subtitle_text.is_empty():
			_subtitle_labels.append(null)
			continue
		var subtitle := _make_label("RouteSubtitle_%d" % index, SUBTITLE_FONT_SIZE, ShellThemeScript.NEUTRAL)
		subtitle.text = subtitle_text
		_subtitle_labels.append(subtitle)

func _make_label(label_name: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = label_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	var font := _ui_font()
	if font != null:
		label.add_theme_font_override("font", font)
	add_child(label)
	return label

func _drop_label(label: Label) -> void:
	if label == null:
		return
	if label.get_parent() == self:
		remove_child(label)
	label.free()

func _draw() -> void:
	_draw_passes += 1
	_red_markers_drawn = 0
	_ensure_layout()
	if _steps.is_empty() or not _markers_visible:
		return
	var font := _ui_font()
	for index in range(0, maxi(_visible_rows - 1, 0)):
		if _orientation == ORIENTATION_HORIZONTAL:
			# Start after this node's text, not at its marker: an arrow running from
			# the marker would strike through the title printed to its right.
			var from_x := float(_rows[index].get("left",0)) + float(_rows[index].get("width",MARKER_SIZE))
			var to_x := _marker_left(index + 1)
			if to_x - from_x > 1.0:
				_draw_connector_horizontal(from_x, to_x, _marker_top(index) + MARKER_SIZE * 0.5, _segment_is_reached(index))
			continue
		var from_y := _marker_top(index) + MARKER_SIZE
		var to_y := _marker_top(index + 1)
		if to_y - from_y > 1.0:
			_draw_connector_vertical(from_y, to_y, _segment_is_reached(index))
	for index in _visible_rows:
		_draw_marker(index, font)

## One straight arrow between two consecutive nodes; it carries reading order and
## nothing else. The view never draws a branch or a causal crossing.
func _draw_connector_horizontal(from_x: float, to_x: float, y: float, reached: bool) -> void:
	var color: Color = ShellThemeScript.COPPER_DULL if reached else ShellThemeScript.NEUTRAL
	if reached:
		draw_line(Vector2(from_x, y), Vector2(to_x, y), color, CONNECTOR_WIDTH)
	else:
		draw_dashed_line(Vector2(from_x, y), Vector2(to_x, y), color, CONNECTOR_WIDTH, DASH_LENGTH, true, false)
	var middle := roundf((from_x + to_x) * 0.5)
	var tip := Vector2(middle + ARROW_LENGTH, y)
	draw_line(tip, Vector2(middle, y - ARROW_HALF_WIDTH), color, CONNECTOR_WIDTH)
	draw_line(tip, Vector2(middle, y + ARROW_HALF_WIDTH), color, CONNECTOR_WIDTH)

func _draw_connector_vertical(from_y: float, to_y: float, reached: bool) -> void:
	var x := MARKER_CENTER_X
	var color: Color = ShellThemeScript.COPPER_DULL if reached else ShellThemeScript.NEUTRAL
	if reached:
		draw_line(Vector2(x, from_y), Vector2(x, to_y), color, CONNECTOR_WIDTH)
	else:
		draw_dashed_line(Vector2(x, from_y), Vector2(x, to_y), color, CONNECTOR_WIDTH, DASH_LENGTH, true, false)
	var middle := roundf((from_y + to_y) * 0.5)
	var tip := Vector2(x, middle + ARROW_LENGTH)
	draw_line(tip, Vector2(x - ARROW_HALF_WIDTH, middle), color, CONNECTOR_WIDTH)
	draw_line(tip, Vector2(x + ARROW_HALF_WIDTH, middle), color, CONNECTOR_WIDTH)

## The whole marker language is shape, not colour: a cleared room is a filled
## square, a room in progress is hollow with a core, an unreached room is hollow
## with a dashed edge, an unknown one is hollow with a question, and only a room
## main reported as failed carries the semantic danger colour.
func _draw_marker(index: int, font: Font) -> void:
	var left := _marker_left(index)
	var top := _marker_top(index)
	var rect := Rect2(left, top, MARKER_SIZE, MARKER_SIZE)
	match _state_at(index):
		STATE_COMPLETED:
			draw_rect(rect, ShellThemeScript.BONE, true)
			draw_rect(rect, ShellThemeScript.COPPER_DULL, false, BORDER_WIDTH)
		STATE_CURRENT:
			draw_rect(rect, ShellThemeScript.BONE, false, BORDER_WIDTH)
			var core := CURRENT_CORE_SIZE
			draw_rect(Rect2(left + MARKER_SIZE * 0.5 - core * 0.5, top + MARKER_SIZE * 0.5 - core * 0.5, core, core), ShellThemeScript.BONE, true)
		STATE_FAILED:
			_red_markers_drawn += 1
			draw_rect(rect, ShellThemeScript.WARNING, false, BORDER_WIDTH)
			draw_line(Vector2(left + FAILED_GLYPH_INSET, top + FAILED_GLYPH_INSET), Vector2(rect.end.x - FAILED_GLYPH_INSET, top + MARKER_SIZE - FAILED_GLYPH_INSET), ShellThemeScript.WARNING, BORDER_WIDTH)
			draw_line(Vector2(rect.end.x - FAILED_GLYPH_INSET, top + FAILED_GLYPH_INSET), Vector2(left + FAILED_GLYPH_INSET, top + MARKER_SIZE - FAILED_GLYPH_INSET), ShellThemeScript.WARNING, BORDER_WIDTH)
		STATE_UNREACHED:
			_draw_dashed_square(rect)
		_:
			draw_rect(rect, ShellThemeScript.NEUTRAL, false, BORDER_WIDTH)
			_draw_question(font, rect)

func _draw_dashed_square(rect: Rect2) -> void:
	var color: Color = ShellThemeScript.NEUTRAL
	var top_left := rect.position
	var top_right := Vector2(rect.end.x, rect.position.y)
	var bottom_right := rect.end
	var bottom_left := Vector2(rect.position.x, rect.end.y)
	draw_dashed_line(top_left, top_right, color, BORDER_WIDTH, DASH_LENGTH, true, false)
	draw_dashed_line(top_right, bottom_right, color, BORDER_WIDTH, DASH_LENGTH, true, false)
	draw_dashed_line(bottom_right, bottom_left, color, BORDER_WIDTH, DASH_LENGTH, true, false)
	draw_dashed_line(bottom_left, top_left, color, BORDER_WIDTH, DASH_LENGTH, true, false)

func _draw_question(font: Font, rect: Rect2) -> void:
	if font == null:
		return
	var ascent := font.get_ascent(GLYPH_FONT_SIZE)
	var descent := font.get_descent(GLYPH_FONT_SIZE)
	var baseline := roundf(rect.position.y + (MARKER_SIZE - (ascent + descent)) * 0.5 + ascent)
	draw_string(font, Vector2(rect.position.x, baseline), "?", HORIZONTAL_ALIGNMENT_CENTER, MARKER_SIZE, GLYPH_FONT_SIZE, ShellThemeScript.NEUTRAL)
