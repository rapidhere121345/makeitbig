class_name TestConsole
extends CanvasLayer
## An opt-in diagnostic surface. Hosts may mount it beside any route, but it has
## no dependency on GameRoot, game state, or a particular presentation screen.

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")

const PANEL_MAX_SIZE := Vector2(920.0, 640.0)
const PANEL_MIN_SIZE := Vector2(520.0, 320.0)
const VIEWPORT_MARGIN := 24.0
const PANEL_BODY_FONT_SIZE := ShellThemeScript.BODY_FONT_SIZE

var _snapshot_provider: Callable
var _console_root: Control
var _panel: PanelContainer
var _body: TextEdit
var _is_open := false


func _ready() -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_build_interface()
	get_viewport().size_changed.connect(_fit_panel)


## Supplies the player-independent diagnostic snapshot used while the console is
## open. Reconfiguring an open console immediately replaces its displayed view.
func configure(snapshot_provider: Callable) -> void:
	_snapshot_provider = snapshot_provider
	if _is_open:
		refresh()


func open_console() -> void:
	if _is_open:
		refresh()
		return
	_is_open = true
	_console_root.visible = true
	_console_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_fit_panel()
	refresh()


func close_console() -> void:
	if not _is_open:
		return
	_is_open = false
	# Do not leave diagnostic data in an otherwise hidden control tree.
	_body.text = ""
	_console_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_console_root.visible = false


func toggle_console() -> void:
	if _is_open:
		close_console()
	else:
		open_console()


## A closed console deliberately never queries or caches raw diagnostic data.
func refresh() -> void:
	if not _is_open:
		return
	if not _snapshot_provider.is_valid():
		_body.text = "No diagnostic snapshot provider is configured."
		return
	var snapshot_value: Variant = _snapshot_provider.call()
	if not snapshot_value is Dictionary:
		_body.text = "Diagnostic snapshot unavailable."
		return
	_body.text = _render_snapshot(snapshot_value as Dictionary)
	_body.scroll_vertical = 0


func is_console_open() -> bool:
	return _is_open


## F10 is observed before GUI dispatch so focused controls cannot swallow the
## global toggle. Escape is intentionally reserved only while this layer is open.
func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_F10:
		toggle_console()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_ESCAPE and _is_open:
		close_console()
		get_viewport().set_input_as_handled()


func _build_interface() -> void:
	_console_root = Control.new()
	_console_root.name = "TestConsoleRoot"
	_console_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_console_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_console_root.theme = ShellThemeScript.create()
	_console_root.visible = false
	add_child(_console_root)

	_panel = PanelContainer.new()
	_panel.name = "TestConsolePanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_console_root.add_child(_panel)

	var content := VBoxContainer.new()
	content.name = "ConsoleLayout"
	content.add_theme_constant_override("separation", 12)
	_panel.add_child(content)

	var header := HBoxContainer.new()
	header.name = "ConsoleHeader"
	header.add_theme_constant_override("separation", 10)
	content.add_child(header)

	var title := Label.new()
	title.name = "ConsoleTitle"
	title.text = "Test Console"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", ShellThemeScript.BODY_FONT_SIZE + 2)
	title.add_theme_color_override("font_color", ShellThemeScript.BONE)
	header.add_child(title)

	var refresh_button := Button.new()
	refresh_button.name = "RefreshButton"
	refresh_button.text = "Refresh"
	refresh_button.custom_minimum_size = Vector2(88.0, 42.0)
	refresh_button.pressed.connect(refresh)
	header.add_child(refresh_button)

	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(88.0, 42.0)
	close_button.pressed.connect(close_console)
	header.add_child(close_button)

	_body = TextEdit.new()
	_body.name = "SnapshotText"
	_body.editable = false
	_body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(0.0, 220.0)
	_body.add_theme_font_size_override("font_size", PANEL_BODY_FONT_SIZE)
	_body.add_theme_color_override("font_readonly_color", ShellThemeScript.BONE)
	_body.add_theme_stylebox_override("read_only", _frame(ShellThemeScript.INK, ShellThemeScript.GROUND))
	content.add_child(_body)


func _fit_panel() -> void:
	if _panel == null:
		return
	var viewport := get_viewport()
	# A final window-size notification can arrive while the CanvasLayer is leaving
	# the tree. There is no panel to fit once its viewport lease is gone.
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	var available := (viewport_size - Vector2(VIEWPORT_MARGIN, VIEWPORT_MARGIN) * 2.0).max(Vector2(1.0, 1.0))
	var panel_size := Vector2(
		minf(PANEL_MAX_SIZE.x, available.x),
		minf(PANEL_MAX_SIZE.y, available.y)
	)
	panel_size.x = maxf(minf(PANEL_MIN_SIZE.x, available.x), panel_size.x)
	panel_size.y = maxf(minf(PANEL_MIN_SIZE.y, available.y), panel_size.y)
	_panel.size = panel_size
	_panel.position = (viewport_size - panel_size) * 0.5


func _render_snapshot(snapshot: Dictionary) -> String:
	var lines: Array[String] = []
	_append_first_field(lines, snapshot, "Route", ["route", "route_id", "scene_route"])
	_append_first_field(lines, snapshot, "Window Resolution", ["window_resolution", "window", "resolution"])
	_append_first_field(lines, snapshot, "Logical Resolution", ["logical_resolution", "logical_size", "design_resolution"])
	_append_first_field(lines, snapshot, "Build ID", ["build_id", "build_identifier", "build"])
	_append_first_field(lines, snapshot, "Profile ID", ["profile_id", "profile_identifier", "profile"])
	_append_first_field(lines, snapshot, "Training Report", ["training", "training_report"])
	_append_first_field(lines, snapshot, "Raw Report", ["raw_report", "report_raw"])
	_append_first_field(lines, snapshot, "Proxy Protocol", ["proxy_protocol", "protocol"])
	_append_first_field(lines, snapshot, "Proxy Fingerprint", ["proxy_fingerprint", "fingerprint"])
	_append_first_field(lines, snapshot, "Latest Settlement Raw Fields", ["last_settlement_raw", "last_settlement", "last_settlement_fields"])
	_append_first_field(lines, snapshot, "Test Flags", ["test_flags", "flags"])
	_append_first_field(lines, snapshot, "Log Path", ["log_path", "playtest_log_path"])
	_append_sections(lines, snapshot)
	if lines.is_empty():
		return "No diagnostic fields to display."
	return "\n".join(lines).strip_edges()


func _append_first_field(lines: Array[String], snapshot: Dictionary, title: String, keys: Array[String]) -> void:
	for key: String in keys:
		if snapshot.has(key):
			lines.append("[%s]" % title)
			lines.append(_format_value(snapshot[key]))
			lines.append("")
			return


func _append_sections(lines: Array[String], snapshot: Dictionary) -> void:
	if not snapshot.has("sections") or not snapshot["sections"] is Array:
		return
	for section_value: Variant in snapshot["sections"]:
		if section_value is Dictionary:
			var section := section_value as Dictionary
			var title := String(section.get("title", section.get("name", "Additional Information")))
			var content: Variant = section.get("content", section.get("data", section))
			lines.append("[%s]" % title)
			lines.append(_format_value(content))
		elif section_value != null:
			lines.append("[Additional Information]")
			lines.append(_format_value(section_value))
		else:
			continue
		lines.append("")


func _format_value(value: Variant) -> String:
	if value == null:
		return "(Empty)"
	if value is String:
		return value as String
	return JSON.stringify(value, "  ", false)


func _frame(fill: Color, border: Color) -> StyleBoxFlat:
	return UiKit.flat_style(fill, border, 1, 0, Vector4(12.0, 10.0, 12.0, 10.0))
