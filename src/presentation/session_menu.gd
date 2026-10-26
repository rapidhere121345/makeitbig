class_name SessionMenu
extends CanvasLayer
## Root-window menu. The host freezes only its current route; this layer never
## changes simulation speed, rewards, or the player's frozen contract mode.

signal opened
signal resumed
signal abandon_requested
signal display_requested(resolution: Vector2i, fullscreen: bool)
signal effects_volume_changed(value: float)
signal language_requested(locale_code: String)
signal menu_scale_requested(value: float)
signal render_quality_requested(value: String)

const Locale = preload("res://src/localization/game_locale.gd")
const RENDER_QUALITIES: Array[String] = ["balanced", "native", "fast"]
const MENU_SCALES: Array[float] = [1.0, 1.15, 1.25]

const Shell = preload("res://src/presentation/shell_theme.gd")
const DisplayPolicyScript = preload("res://src/presentation/display_policy.gd")
const PixelStageScript = preload("res://src/presentation/pixel_stage.gd")
var _quality: OptionButton
var _language: OptionButton
var _menu_scale: OptionButton
var _preferred_scale := 1.0
var _fixed_column: VBoxContainer
var _scroll: ScrollContainer
var _column: VBoxContainer
var _root: Control
var _shade: ColorRect
var _panel: PanelContainer
var _launcher: Button
var _heading: Label
var _note: Label
var _resume: Button
var _abandon: Button
var _resolution: OptionButton
var _fullscreen: CheckButton
var _display_hint: Label
var _options: Array[Vector2i] = DisplayPolicyScript.PRESETS.duplicate()
var _volume: HSlider
var _volume_label: Label
var _open := false
var _arena := false
var _confirm_abandon := false
var _return_focus: WeakRef


func _ready() -> void:
	layer = 90
	_root = Control.new()
	_root.name = "SessionMenuRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = Shell.create()
	add_child(_root)
	_launcher = Button.new()
	_launcher.name = "SessionMenuButton"
	_launcher.pressed.connect(open_menu)
	_root.add_child(_launcher)
	_shade = ColorRect.new()
	_shade.color = Color(0.025, 0.035, 0.045, 0.86)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.visible = false
	_root.add_child(_shade)
	_panel = PanelContainer.new()
	_panel.name = "SessionMenuPanel"
	_panel.visible = false
	_root.add_child(_panel)
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	_panel.add_child(margin)
	var outer := VBoxContainer.new()
	_fixed_column = outer
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.name = "SettingsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	outer.add_child(scroll)
	var column := VBoxContainer.new()
	_column = column
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	_heading = _label("", 28)
	outer.add_child(_heading)
	outer.move_child(_heading, 0)
	_note = _label("", 18)
	outer.add_child(_note)
	outer.move_child(_note, 1)
	_resume = _button("Resume", "ResumeButton", outer)
	outer.move_child(_resume, 2)
	_resume.pressed.connect(close_menu)
	var language_row := HBoxContainer.new()
	column.add_child(language_row)
	var language_label := _label("Language", 20)
	language_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	language_row.add_child(language_label)
	_language = OptionButton.new()
	_language.name = "LanguageChoice"
	_language.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for code: String in Locale.SUPPORTED:
		_language.add_item(Locale.language_name(code))
	_language.item_selected.connect(func(index: int): language_requested.emit(Locale.SUPPORTED[index]))
	language_row.add_child(_language)
	var scale_row := HBoxContainer.new()
	column.add_child(scale_row)
	var scale_label := _label("Menu Scale", 20)
	scale_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_child(scale_label)
	_menu_scale = OptionButton.new()
	_menu_scale.name = "MenuScale"
	for caption: String in ["Standard · 100%", "Comfortable · 115%", "Large · 125%"]:
		_menu_scale.add_item(caption)
	_menu_scale.item_selected.connect(func(index: int): menu_scale_requested.emit(MENU_SCALES[index]))
	scale_row.add_child(_menu_scale)
	var scale_hint := _label("Larger menus and reading panels on high-resolution displays.", 16)
	column.add_child(scale_hint)
	column.add_child(_label("Display", 22))
	var display := HBoxContainer.new()
	display.add_theme_constant_override("separation", 12)
	column.add_child(display)
	_resolution = OptionButton.new()
	_resolution.name = "WindowResolution"
	_resolution.tooltip_text = "Window resolution"
	_resolution.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resolution.item_selected.connect(func(_index: int): _refresh_hint())
	display.add_child(_resolution)
	_fullscreen = CheckButton.new()
	_fullscreen.name = "FullscreenToggle"
	_fullscreen.text = "Fullscreen"
	_fullscreen.toggled.connect(func(_on: bool): _refresh_hint())
	display.add_child(_fullscreen)
	_display_hint = _label("", 16)
	_display_hint.name = "DisplayHint"
	column.add_child(_display_hint)
	_rebuild_options(Vector2i.ZERO)
	var quality_row := HBoxContainer.new()
	column.add_child(quality_row)
	var quality_label := _label("Game Rendering", 20)
	quality_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quality_row.add_child(quality_label)
	_quality = OptionButton.new()
	_quality.name = "RenderQuality"
	for caption: String in ["Balanced", "Native Resolution", "Performance"]:
		_quality.add_item(caption)
	_quality.item_selected.connect(func(index: int): render_quality_requested.emit(RENDER_QUALITIES[index]))
	quality_row.add_child(_quality)
	column.add_child(_label("Balanced reduces 4K rendering cost. Native keeps the finest text detail. Reading panels always render at native resolution.", 16))
	var apply := _button("Apply Display Settings", "ApplyDisplay", column)
	apply.pressed.connect(func(): display_requested.emit(selected_resolution(), _fullscreen.button_pressed))
	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 16)
	column.add_child(_label("Audio", 22))
	column.add_child(volume_row)
	_volume_label = _label("Sound 45%", 22)
	_volume_label.custom_minimum_size.x = 146
	volume_row.add_child(_volume_label)
	_volume = HSlider.new()
	_volume.name = "EffectsVolume"
	_volume.min_value = 0
	_volume.max_value = 100
	_volume.step = 1
	_volume.value = 45
	_volume.custom_minimum_size = Vector2(200, 36)
	_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume.value_changed.connect(func(value: float):
		_volume_label.text = "Sound %d%%" % int(value)
		effects_volume_changed.emit(value / 100.0))
	volume_row.add_child(_volume)
	column.add_child(_label("Controls", 22))
	column.add_child(_label("WASD Move   Left-click Target and shoot\nSpace Aim assist   Q Mark   E Assault\nShift / Right-click Dodge   Tab Battle report\nEsc Pause / Resume   F1 Settings   F11 Fullscreen", 18))
	_abandon = _button("Abandon Contract", "AbandonButton", column)
	_abandon.pressed.connect(_request_abandon)
	get_viewport().size_changed.connect(_fit)
	set_route("title")
	_fit()
	_fit.call_deferred()


func _label(text: String, font_size: int) -> Label:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size", font_size)
	return node


func _button(text: String, node_name: String, parent: Node) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size.y = 42
	parent.add_child(button)
	return button


func set_route(route: String) -> void:
	_arena = route == "arena"
	_launcher.visible = route in ["title", "base", "arena"]
	_launcher.text = "Pause Esc" if _arena else "Settings F1"
	_heading.text = "Combat Paused" if _arena else "Game Settings"
	_note.text = "Resume to continue combat. Abandoning forfeits this contract's rewards." if _arena else "Language and menu size apply immediately and are saved."
	_abandon.visible = _arena
	_fit()


func sync_accessibility(locale_code: String, menu_scale: float, quality: String = "balanced") -> void:
	_quality.select(maxi(0, RENDER_QUALITIES.find(quality)))
	_language.select(Locale.SUPPORTED.find(Locale.normalize(locale_code)))
	_preferred_scale = menu_scale
	var index := MENU_SCALES.find(menu_scale)
	_menu_scale.select(index if index >= 0 else 0)
	_fit()
	_fit.call_deferred()


func sync_settings(resolution: Vector2i, fullscreen: bool, volume: float) -> void:
	if resolution not in _options:
		_options = DisplayPolicyScript.with_entry(_options, resolution)
	_rebuild_options(resolution)
	_fullscreen.set_pressed_no_signal(fullscreen)
	_volume.set_value_no_signal(clampf(volume, 0, 1) * 100)
	_volume_label.text = "Sound %d%%" % int(_volume.value)
	_refresh_hint()


## Replaces the offered window sizes; the current one is kept selected and listed.
func set_resolution_options(options: Array[Vector2i], current: Vector2i) -> void:
	_options = DisplayPolicyScript.with_entry(options, current)
	_rebuild_options(current)


func selected_resolution() -> Vector2i:
	return _options[clampi(_resolution.selected, 0, _options.size() - 1)]


func _rebuild_options(select: Vector2i) -> void:
	var keep := select if select != Vector2i.ZERO else (selected_resolution() if _resolution.item_count > 0 else DisplayPolicyScript.DEFAULT_WINDOW)
	_resolution.clear()
	for value in _options:
		_resolution.add_item("%d × %d" % [value.x, value.y])
	var index := _options.find(keep)
	_resolution.select(index if index >= 0 else 0)
	_refresh_hint()


func _refresh_hint() -> void:
	if _display_hint != null and _fullscreen != null and _resolution.item_count > 0:
		_display_hint.text = DisplayPolicyScript.hint(selected_resolution(), _fullscreen.button_pressed)
		_display_hint.visible = not _display_hint.text.is_empty()


func open_menu() -> void:
	if _open:
		return
	var focus := get_viewport().gui_get_focus_owner()
	_return_focus = weakref(focus) if focus != null else null
	_open = true
	_confirm_abandon = false
	_abandon.text = "Abandon Contract"
	_shade.show()
	_panel.show()
	_fit()
	opened.emit()
	_resume.grab_focus()
	_fit.call_deferred()


func close_menu() -> void:
	if not _open:
		return
	_open = false
	_shade.hide()
	_panel.hide()
	resumed.emit()
	var focus = _return_focus.get_ref() if _return_focus != null else null
	if is_instance_valid(focus) and focus is Control and focus.is_visible_in_tree():
		focus.grab_focus()
	_return_focus = null


func is_open() -> bool:
	return _open


func _request_abandon() -> void:
	if not _confirm_abandon:
		_confirm_abandon = true
		_abandon.text = "Confirm Abandon · Forfeit Rewards"
		return
	close_menu()
	abandon_requested.emit()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1 or (event.keycode == KEY_ESCAPE and (_open or _arena)):
			if _open: close_menu()
			else: open_menu()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F11:
			_fullscreen.set_pressed_no_signal(not _fullscreen.button_pressed)
			display_requested.emit(selected_resolution(), _fullscreen.button_pressed)
			get_viewport().set_input_as_handled()


func _fit() -> void:
	if _panel == null or not is_inside_tree() or get_viewport() == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var ui_scale := maxf(0.75, minf(viewport_size.x / 1600.0, viewport_size.y / 900.0)) * _preferred_scale
	# A scrollable panel keeps every setting reachable on compact screens and
	# when a high-DPI monitor is moved to a smaller display.
	var available := (viewport_size - Vector2(32, 32)) / ui_scale
	_panel.scale = Vector2.ONE * ui_scale
	_panel.size = Vector2(minf(680, available.x), minf(_column.get_combined_minimum_size().y + _fixed_column.get_combined_minimum_size().y + 40, available.y))
	_panel.position = ((viewport_size - _panel.size * ui_scale) * 0.5).floor()
	_launcher.size = Vector2(144, 42)
	if _arena:
		# This root-window control follows the same physical stage as the HUD.
		# Side/top borders must remain empty, and the pause cue scales with the HUD.
		var layout: Dictionary = PixelStageScript.layout_for_window(Vector2i(viewport_size))
		ui_scale = float(layout.ui_scale)
		_launcher.scale = Vector2.ONE * ui_scale
		_launcher.position = Vector2(layout.origin) + Vector2(12.0 * ui_scale,
			float(layout.stage_size.y) - (_launcher.size.y + 8.0) * ui_scale)
	else:
		_launcher.scale = Vector2.ONE * ui_scale
		_launcher.position = Vector2(viewport_size.x - (_launcher.size.x + 12) * ui_scale, 14 * ui_scale)
