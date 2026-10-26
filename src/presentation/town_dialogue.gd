extends Control
## A voluntary conversation stays in the town and preserves the avatar/camera.
## Only finishing the last line emits a read receipt; closing early is not read.

signal finished(entry_id: String)
signal dismissed

const ShellTheme = preload("res://src/presentation/shell_theme.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")
const PORTRAIT_ROOT := "res://art/production/p1/story_portraits_r14/"
const NPC_ROLES := {"mira":"Winter Tower Keeper", "iven":"Chronicler", "taren":"Traveling Merchant", "leia":"Keeper's Apprentice", "oren":"Mender"}
const NPC_NAMES := {"mira":"Mira", "iven":"Iven", "taren":"Taren", "leia":"Leia", "oren":"Oren"}

var _entry: Dictionary = {}
var _page := 0
var _panel: PanelContainer
var _portrait: TextureRect
var _speaker: Label
var _role: Label
var _speech: Label
var _count: Label
var _next: Button
var _previous: Button
var _close: Button
var _return_focus: WeakRef


func _ready() -> void:
	name = "TownDialogue"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = ShellTheme.create()
	var shade := ColorRect.new()
	shade.name = "DialogueShade"
	shade.color = Color(0.02, 0.035, 0.055, 0.28)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_panel = PanelContainer.new()
	_panel.name = "DialoguePanel"
	_panel.anchor_left = 0.12
	_panel.anchor_right = 0.88
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_top = -414
	_panel.offset_bottom = -102
	_panel.add_theme_stylebox_override("panel", ShellTheme.panel_style("paper"))
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	_panel.add_child(row)
	_portrait = TextureRect.new()
	_portrait.name = "DialoguePortrait"
	_portrait.custom_minimum_size = Vector2(128, 180)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_portrait)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	row.add_child(column)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 16)
	column.add_child(heading)
	_speaker = UiKit.colored_label("", 28, ShellTheme.BONE)
	_speaker.name = "DialogueSpeaker"
	heading.add_child(_speaker)
	_role = UiKit.colored_label("", 18, ShellTheme.NEUTRAL)
	_role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(_role)
	_close = Button.new()
	_close.name = "CloseDialogue"
	_close.text = "Close Esc"
	_close.add_theme_font_size_override("font_size", 18)
	## The advertised Esc must work while a dialogue button holds focus: GUI
	## focus consumes the key before the hub's unhandled handler sees it, so
	## the close action rides a real shortcut.
	var close_shortcut := Shortcut.new()
	var close_key := InputEventKey.new()
	close_key.keycode = KEY_ESCAPE
	close_key.physical_keycode = KEY_ESCAPE
	close_shortcut.events = [close_key]
	_close.shortcut = close_shortcut
	_close.pressed.connect(close_dialogue)
	heading.add_child(_close)
	_speech = UiKit.colored_label("", 22, ShellTheme.BONE)
	_speech.name = "DialogueSpeech"
	_speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_speech.custom_minimum_size.y = 74
	column.add_child(_speech)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 12)
	column.add_child(controls)
	_count = UiKit.colored_label("", 18, ShellTheme.NEUTRAL)
	_count.name = "DialoguePageCount"
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(_count)
	_previous = Button.new()
	_previous.name = "DialoguePrevious"
	_previous.text = "Previous Line"
	_previous.disabled = true
	_previous.add_theme_font_size_override("font_size", 22)
	_previous.custom_minimum_size = Vector2(108, 42)
	_previous.pressed.connect(previous_line)
	controls.add_child(_previous)
	_next = Button.new()
	_next.name = "DialogueNext"
	_next.add_theme_font_size_override("font_size", 22)
	_next.custom_minimum_size = Vector2(168, 42)
	_next.pressed.connect(advance)
	controls.add_child(_next)
	for button: Button in [_close, _previous, _next]:
		button.focus_mode = Control.FOCUS_ALL
	_update_focus_order()
	hide()


func open_conversation(entry: Dictionary) -> bool:
	if _panel == null or not entry.get("pages") is Array or entry.pages.is_empty():
		return false
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and not is_ancestor_of(owner):
		_return_focus = weakref(owner)
	else:
		_return_focus = null
	_entry = entry.duplicate(true)
	_page = 0
	show()
	_render_line()
	_next.grab_focus()
	return true


func is_open() -> bool:
	return visible and not _entry.is_empty()


func advance() -> void:
	if not is_open(): return
	if _page < _entry.pages.size() - 1:
		_page += 1
		_render_line()
		return
	var id := String(_entry.id)
	close_dialogue()
	finished.emit(id)


func previous_line() -> void:
	if not is_open(): return
	_page = maxi(0, _page - 1)
	_render_line()


func close_dialogue() -> void:
	if not is_open(): return
	hide()
	_entry.clear()
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and is_ancestor_of(focus): focus.release_focus()
	var previous = _return_focus.get_ref() if _return_focus != null else null
	if is_instance_valid(previous) and previous.is_inside_tree() and previous.is_visible_in_tree():
		previous.grab_focus()
	_return_focus = null
	dismissed.emit()


func dialogue_report() -> Dictionary:
	return {"open":is_open(), "entry_id":String(_entry.get("id", "")), "page":_page,
		"pages":(_entry.get("pages",[]) as Array).size(), "speaker":_speaker.text if _speaker != null else "",
		"portrait":_portrait.texture.resource_path if _portrait != null and _portrait.texture != null else ""}


func _render_line() -> void:
	var previous_had_focus := get_viewport().gui_get_focus_owner() == _previous
	var line := String(_entry.pages[_page])
	var parts := speaker_line(_entry, line)
	var name_value := String(parts.speaker)
	_speaker.text = name_value
	_speech.text = String(parts.speech)
	var portrait_id := portrait_id_for_line(_entry, line)
	## The role rail always names the conversation partner: when the wanderer
	## holds the line, "Wanderer · Wanderer" reads like the dialogue switched target
	## (GPU acceptance R1 backlog). The speaker label still tracks the line.
	var partner_id := String(_entry.get("npc", ""))
	if portrait_id == partner_id:
		_role.text = String(NPC_ROLES.get(partner_id, "")) + " · " + String(_entry.get("title", ""))
	else:
		_role.text = "Talk to %s · %s" % [String(_entry.get("npc_name", "")), String(_entry.get("title", ""))]
	_portrait.texture = portrait_for_line(_entry, line)
	# An empty player portrait keeps the same reading origin between speakers.
	_portrait.visible = true
	_count.text = "Line %d / %d" % [_page + 1, _entry.pages.size()]
	_previous.disabled = _page == 0
	_next.text = "Finish E / Enter" if _page == _entry.pages.size() - 1 else "Continue E / Enter"
	_update_focus_order()
	if previous_had_focus and _previous.disabled:
		_next.grab_focus()


func _update_focus_order() -> void:
	var buttons: Array[Button] = [_close]
	if not _previous.disabled: buttons.append(_previous)
	buttons.append(_next)
	for index in range(buttons.size()):
		var button := buttons[index]
		var before := button.get_path_to(buttons[posmod(index - 1, buttons.size())])
		var after := button.get_path_to(buttons[(index + 1) % buttons.size()])
		button.focus_previous = before
		button.focus_next = after
		button.focus_neighbor_left = before
		button.focus_neighbor_right = after
		button.focus_neighbor_top = before
		button.focus_neighbor_bottom = after


func _input(event: InputEvent) -> void:
	if not is_open() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if key == KEY_E: advance()
	elif key in [KEY_ENTER, KEY_SPACE]:
		var owner := get_viewport().gui_get_focus_owner() as Button
		if owner != null and is_ancestor_of(owner) and not owner.disabled:
			owner.pressed.emit()
		else:
			advance()
	elif key == KEY_ESCAPE: close_dialogue()
	else: return
	get_viewport().set_input_as_handled()


static func portrait_id_for_line(entry: Dictionary, line: String) -> String:
	var speaker := String(speaker_line(entry, line).speaker)
	if speaker == "Wanderer": return ""
	for id: String in NPC_NAMES:
		if speaker == NPC_NAMES[id]: return id
	return String(entry.get("npc", ""))


static func speaker_line(entry: Dictionary, line: String) -> Dictionary:
	# Split only recognized speakers, not ordinary prose that happens to use a colon.
	for delimiter: String in [":", "\uff1a"]:
		var split := line.find(delimiter)
		if split < 0:
			continue
		var speaker := line.substr(0, split).strip_edges()
		if speaker == "Wanderer" or speaker in NPC_NAMES.values():
			return {"speaker": speaker, "speech": line.substr(split + 1).strip_edges()}
	return {"speaker": String(entry.get("npc_name", "")), "speech": line}


static func portrait_for_line(entry: Dictionary, line: String) -> Texture2D:
	var id := portrait_id_for_line(entry, line)
	if id.is_empty(): return null
	var path := PORTRAIT_ROOT.path_join(id + ".png")
	return load(path) as Texture2D if FileAccess.file_exists(path + ".import") and ResourceLoader.exists(path) else null

