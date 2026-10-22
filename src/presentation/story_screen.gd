class_name StoryScreen
extends Control
## A fixed-page travel codex: chapter spines on the left, dark folios on the
## right, and explicit pagination instead of an administrative scrolling list.

signal closed
signal entry_read(entry_id: String)

const StoryProgressionScript = preload("res://src/systems/story_progression.gd")
const ShellTheme = preload("res://src/presentation/shell_theme.gd")
const TownDialogueScript = preload("res://src/presentation/town_dialogue.gd")

const TABS: Array[String] = ["Target", "Dialogue", "Journal", "Daily Life"]
const LIST_PAGE_SIZE := 4
const TOWN_PAGE_SIZE := 4
const TITLE_FONT_SIZE := 28
const BODY_FONT_SIZE := 22
const NOTE_FONT_SIZE := 18

var progression: StoryProgression

var _state: Dictionary = {}
var _saved_story: Dictionary = {}
var _progress_snapshot: Dictionary = {}
var _root: Control
var _title_label: Label
var _objective_label: Label
var _tab_row: VBoxContainer
var _body: VBoxContainer
var _tab := 0
var _conversation_id := ""
var _conversation_page := 0
var _conversation_list_page := 0
var _conversation_filter := ""
var _conversation_unread_only := true
var _journal_unread_only := true
var _return_focus: WeakRef
var _journal_id := ""
var _journal_page := 0
var _journal_list_page := 0
var _town_page := 0


func _init(story_progression: StoryProgression = null) -> void:
	progression = story_progression if story_progression != null else StoryProgressionScript.new()


func _ready() -> void:
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and not is_ancestor_of(owner):
		_return_focus = weakref(owner)
	custom_minimum_size = Vector2(1280, 720)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ShellTheme.create()
	ShellTheme.add_backdrop(self, "sanctuary")
	_build()
	if not _state.is_empty():
		_select_latest_entries()
		_clamp_selections()
		_rebuild()


func present(progress_snapshot: Dictionary, saved_story: Dictionary) -> void:
	_progress_snapshot = progress_snapshot.duplicate(true)
	_saved_story = progression.normalize_saved_story(saved_story)
	_state = progression.evaluate(_progress_snapshot, _saved_story)
	if _body == null:
		return
	show()
	_select_latest_entries()
	_clamp_selections()
	_rebuild("reading")


func current_state() -> Dictionary:
	return _state.duplicate(true)


func saved_story() -> Dictionary:
	return _saved_story.duplicate(true)


func _build() -> void:
	_root = Control.new()
	_root.name = "StoryScreenRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var margin := MarginContainer.new()
	margin.name = "CodexMargins"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	_root.add_child(margin)
	var column := VBoxContainer.new()
	column.name = "CodexColumn"
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var heading := HBoxContainer.new()
	heading.name = "CodexHeading"
	heading.add_theme_constant_override("separation", 12)
	column.add_child(heading)
	var title_block := VBoxContainer.new()
	title_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_block.add_theme_constant_override("separation", 0)
	heading.add_child(title_block)
	_title_label = _label("Journey Journal · Act I: Lingering Warmth", TITLE_FONT_SIZE, ShellTheme.BONE)
	_title_label.name = "StoryTitle"
	title_block.add_child(_title_label)
	_objective_label = _label("", BODY_FONT_SIZE, ShellTheme.NEUTRAL)
	_objective_label.name = "CurrentObjective"
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_block.add_child(_objective_label)
	var close := _button("Close Esc", "CloseStory", BODY_FONT_SIZE)
	close.custom_minimum_size = Vector2(142, 48)
	close.pressed.connect(_emit_closed)
	heading.add_child(close)

	var workspace := HBoxContainer.new()
	workspace.name = "CodexWorkspace"
	workspace.add_theme_constant_override("separation", 10)
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(workspace)

	_tab_row = VBoxContainer.new()
	_tab_row.name = "StoryTabs"
	_tab_row.custom_minimum_size = Vector2(150, 0)
	_tab_row.add_theme_constant_override("separation", 7)
	workspace.add_child(_tab_row)
	var tab_caption := _label("Chapter", BODY_FONT_SIZE, ShellTheme.NEUTRAL)
	tab_caption.name = "ChapterCaption"
	_tab_row.add_child(tab_caption)
	for index in range(TABS.size()):
		var tab := _make_tab(TABS[index])
		tab.name = "StoryTab_%s" % TABS[index]
		tab.text = TABS[index]
		tab.custom_minimum_size = Vector2(140, 55)
		tab.pressed.connect(_select_tab.bind(index))
		_tab_row.add_child(tab)

	var book_panel := PanelContainer.new()
	book_panel.name = "StoryBook"
	book_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	book_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	book_panel.add_theme_stylebox_override("panel", ShellTheme.panel_style("paper"))
	workspace.add_child(book_panel)
	var book_margin := MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		book_margin.add_theme_constant_override("margin_" + edge, 16)
	book_panel.add_child(book_margin)
	_body = VBoxContainer.new()
	_body.name = "StoryBody"
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	book_margin.add_child(_body)


func _make_tab(text_value: String) -> Button:
	var button := _button(text_value, "StoryTab", BODY_FONT_SIZE)
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return button


func _select_tab(index: int) -> void:
	_tab = clampi(index, 0, TABS.size() - 1)
	_clamp_selections()
	_rebuild("reading")


func _emit_closed() -> void:
	hide()
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and is_ancestor_of(owner):
		owner.release_focus()
	var previous = _return_focus.get_ref() if _return_focus != null else null
	if is_instance_valid(previous) and previous.is_inside_tree() and previous.is_visible_in_tree():
		previous.grab_focus()
	closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if key == KEY_ESCAPE:
		_emit_closed()
	elif key == KEY_E and _tab in [1, 2]:
		var detail := find_child("ConversationDetail" if _tab == 1 else "JournalDetail", true, false)
		if detail != null:
			var next := detail.find_child("NextPage", true, false) as Button
			var read := detail.find_child("ReadConversation" if _tab == 1 else "ReadJournal", true, false) as Button
			if next != null and not next.disabled: next.pressed.emit()
			elif _can_focus(read) and (next == null or next.disabled): read.pressed.emit()
	else:
		return
	get_viewport().set_input_as_handled()


func _rebuild(focus_target: String = "") -> void:
	var owner := get_viewport().gui_get_focus_owner()
	var focus_path := get_path_to(owner) if owner != null and is_ancestor_of(owner) else NodePath("")
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var objective: Dictionary = _state.get("current_objective", {})
	_objective_label.text = "Current Target: %s" % String(objective.get("text", "Complete the Starting Exercises"))
	for index in range(TABS.size()):
		var button := _tab_row.get_node("StoryTab_%s" % TABS[index]) as Button
		button.set_pressed_no_signal(index == _tab)
		_style_tab(button, index == _tab)
		if index in [1, 2]:
			var entries: Array = _state.get("available_conversations" if index == 1 else "journal_entries", [])
			button.text = "%s\nUnread %d" % [TABS[index], _unread_count(entries)]
	match _tab:
		0: _render_objective()
		1: _render_conversations()
		2: _render_journal()
		3: _render_town()
	if focus_target != "reading" and not focus_path.is_empty():
		var replacement := get_node_or_null(focus_path) as Control
		if _can_focus(replacement):
			replacement.grab_focus()
			return
	_focus_reading()


func _can_focus(control: Control) -> bool:
	return control != null and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE \
		and (not control is BaseButton or not control.disabled)


func _focus_reading() -> void:
	var detail := find_child("ConversationDetail" if _tab == 1 else "JournalDetail", true, false)
	if _tab in [1, 2] and detail != null:
		for node_name: String in ["NextPage", "ReadConversation", "ReadJournal", "PreviousPage"]:
			var control := detail.find_child(node_name, true, false) as Control
			if _can_focus(control):
				control.grab_focus()
				return
	var fallback := find_child("ConversationUnreadFilter" if _tab == 1 else "JournalUnreadFilter", true, false) as Control
	if not _can_focus(fallback): fallback = find_child("CloseStory", true, false) as Control
	if _can_focus(fallback): fallback.grab_focus()


func _render_objective() -> void:
	var objective: Dictionary = _state.get("current_objective", {})
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_body.add_child(column)
	column.add_child(_chapter_heading("Chapter Objective"))
	column.add_child(_reading_label(String(objective.get("text", ""))))
	var unread_row := HBoxContainer.new()
	unread_row.add_theme_constant_override("separation", 12)
	column.add_child(unread_row)
	for index in [1, 2]:
		var entries: Array = _state.get("available_conversations" if index == 1 else "journal_entries", [])
		var unread := _button("Unread %s %d" % [TABS[index], _unread_count(entries)], "OpenUnread_%d" % index)
		unread.pressed.connect(func():
			if index == 1: _conversation_unread_only = true
			else: _journal_unread_only = true
			_select_latest_entries()
			_select_tab(index)
		)
		unread_row.add_child(unread)
	column.add_child(_note_label("Read observations at any time; close this to return to looting."))
	var campaign_node := String(objective.get("campaign_node", ""))
	if campaign_node != "":
		column.add_child(_reading_label("Visit the Contract Board in town and select the current main quest contract."))
	var journals: Array = _state.get("journal_entries", [])
	if not journals.is_empty():
		var latest: Dictionary = journals[journals.size() - 1]
		var pages: Array = latest.get("pages", [])
		if not pages.is_empty():
			column.add_child(_ink_rule())
			column.add_child(_reading_label(String(pages[0])))
			column.add_child(_note_label("Review the full entry later in the Journal. Reading is not required for rewards."))


func _render_conversations() -> void:
	var conversations := _filtered_conversations()
	var selected := _find_by_id(conversations, _conversation_id)
	var split := HSplitContainer.new()
	split.name = "ConversationSplit"
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(split)
	var list := VBoxContainer.new()
	list.name = "ConversationList"
	list.custom_minimum_size.x = 350
	list.add_theme_constant_override("separation", 7)
	split.add_child(list)
	list.add_child(_chapter_heading("Companions"))
	_add_person_filter(list)
	_add_unread_filter(list, true)
	if conversations.is_empty():
		var message := "No one is available to talk right now." if (_state.get("available_conversations", []) as Array).is_empty() else "This resident has no unread dialogue. Switch characters or disable Unread Only to review."
		if _conversation_filter.is_empty() and not (_state.get("available_conversations", []) as Array).is_empty():
			message = "All available dialogue has been heard. Disable Unread Only to review."
		list.add_child(_reading_label(message))
		return
	var page_count := _page_count(conversations.size(), LIST_PAGE_SIZE)
	_conversation_list_page = clampi(_conversation_list_page, 0, page_count - 1)
	var start := _conversation_list_page * LIST_PAGE_SIZE
	for index in range(start, mini(start + LIST_PAGE_SIZE, conversations.size())):
		var conversation: Dictionary = conversations[index]
		var button := _entry_button("Conversation_%s" % String(conversation.id))
		button.text = "%s · %s / %s" % ["Read" if bool(conversation.get("is_read", false)) else "Unread", String(conversation.get("npc_name", "")), String(conversation.get("title", ""))]
		button.tooltip_text = button.text
		button.set_pressed_no_signal(String(conversation.id) == _conversation_id)
		button.pressed.connect(func():
			_select_entry(conversation, true)
			_rebuild("reading")
		)
		list.add_child(button)
	_add_page_controls(list, _conversation_list_page, page_count, func(page: int):
		_select_entry(conversations[page * LIST_PAGE_SIZE], true)
		_rebuild()
	, "Dialogue Index")
	var detail := VBoxContainer.new()
	detail.name = "ConversationDetail"
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 10)
	split.add_child(detail)
	detail.add_child(_reading_label("%s: %s" % [String(selected.get("npc_name", "")), String(selected.get("title", ""))], ShellTheme.BONE))
	detail.add_child(_ink_rule())
	var pages: Array = selected.get("pages", [])
	_conversation_page = clampi(_conversation_page, 0, maxi(0, pages.size() - 1))
	var speech := _reading_label(String(pages[_conversation_page]), ShellTheme.BONE)
	speech.name = "ConversationSpeech"
	speech.custom_minimum_size.y = 72
	var reading_row := HBoxContainer.new()
	reading_row.name = "ConversationReadingRow"
	reading_row.add_theme_constant_override("separation", 16)
	detail.add_child(reading_row)
	var portrait := TextureRect.new()
	portrait.name = "ConversationPortrait"
	portrait.custom_minimum_size = Vector2(128, 160)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	portrait.texture = TownDialogueScript.portrait_for_line(selected, String(pages[_conversation_page]))
	reading_row.add_child(portrait)
	var reading := VBoxContainer.new()
	reading.name = "ConversationReading"
	reading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reading.add_theme_constant_override("separation", 10)
	reading_row.add_child(reading)
	reading.add_child(speech)
	_add_page_controls(reading, _conversation_page, pages.size(), func(page: int):
		_conversation_page = page
		_rebuild()
	)
	_add_read_completion(reading, selected, _conversation_page, true)


func _filtered_conversations() -> Array:
	var result: Array = []
	for conversation: Dictionary in _state.get("available_conversations", []):
		if not _conversation_filter.is_empty() and String(conversation.npc) != _conversation_filter:
			continue
		if not _conversation_unread_only or not bool(conversation.get("is_read", false)):
			result.append(conversation)
	return result


func _add_person_filter(parent: Node) -> void:
	var filter := OptionButton.new()
	filter.name = "ConversationPersonFilter"
	filter.custom_minimum_size.y = 42
	filter.add_theme_font_size_override("font_size", NOTE_FONT_SIZE)
	filter.add_item("All Characters")
	var ids: Array[String] = [""]
	var available := {}
	for conversation: Dictionary in _state.get("available_conversations", []):
		available[String(conversation.npc)] = true
	for npc: String in TownDialogueScript.NPC_NAMES:
		if not available.has(npc): continue
		ids.append(npc)
		filter.add_item(String(TownDialogueScript.NPC_NAMES[npc]))
	filter.select(maxi(0, ids.find(_conversation_filter)))
	filter.item_selected.connect(func(index: int):
		_conversation_filter = ids[index]
		_conversation_id = ""
		_clamp_selections()
		_rebuild()
	)
	parent.add_child(filter)


func _render_journal() -> void:
	var entries := _filtered_journals()
	var selected := _find_by_id(entries, _journal_id)
	var split := HSplitContainer.new()
	split.name = "JournalSplit"
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(split)
	var list := VBoxContainer.new()
	list.name = "JournalList"
	list.custom_minimum_size.x = 350
	list.add_theme_constant_override("separation", 7)
	split.add_child(list)
	list.add_child(_chapter_heading("Record Index"))
	_add_unread_filter(list, false)
	if entries.is_empty():
		var message := "No journal entries yet. Entries are recorded automatically after combat; reading is optional." if (_state.get("journal_entries", []) as Array).is_empty() else "All available journal entries have been read. Disable Unread Only to review."
		list.add_child(_reading_label(message))
		return
	var page_count := _page_count(entries.size(), LIST_PAGE_SIZE)
	_journal_list_page = clampi(_journal_list_page, 0, page_count - 1)
	var start := _journal_list_page * LIST_PAGE_SIZE
	for index in range(start, mini(start + LIST_PAGE_SIZE, entries.size())):
		var entry: Dictionary = entries[index]
		var button := _entry_button("JournalEntry_%s" % String(entry.id))
		var read := bool(entry.get("is_read", false))
		button.text = "%s · %s / %s" % ["Read" if read else "Unread", String(entry.get("entry_type", "Records")), String(entry.get("title", ""))]
		button.set_pressed_no_signal(String(entry.id) == _journal_id)
		button.tooltip_text = "Read" if read else "Unread; confirm after reading the last page to record it."
		button.pressed.connect(func():
			_select_entry(entry, false)
			_rebuild("reading")
		)
		list.add_child(button)
	_add_page_controls(list, _journal_list_page, page_count, func(page: int):
		_select_entry(entries[page * LIST_PAGE_SIZE], false)
		_rebuild()
	, "Record Index")
	var detail := VBoxContainer.new()
	detail.name = "JournalDetail"
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 10)
	split.add_child(detail)
	detail.add_child(_reading_label(String(selected.get("title", "")), ShellTheme.BONE))
	detail.add_child(_ink_rule())
	var pages: Array = selected.get("pages", [])
	_journal_page = clampi(_journal_page, 0, maxi(0, pages.size() - 1))
	var entry_text := _reading_label(String(pages[_journal_page]), ShellTheme.BONE)
	entry_text.custom_minimum_size.y = 150
	detail.add_child(entry_text)
	detail.add_child(_note_label("Read" if bool(selected.get("is_read", false)) else "Unread"))
	_add_page_controls(detail, _journal_page, pages.size(), func(page: int):
		_journal_page = page
		_rebuild()
	)
	_add_read_completion(detail, selected, _journal_page, false)


func _render_town() -> void:
	var changes: Array = _state.get("town_changes", [])
	if changes.is_empty():
		_body.add_child(_reading_label("No changes in the hamlet for now."))
		return
	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	_body.add_child(column)
	column.add_child(_chapter_heading("Hamlet Observations"))
	var page_count := _page_count(changes.size(), TOWN_PAGE_SIZE)
	_town_page = clampi(_town_page, 0, page_count - 1)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)
	var start := _town_page * TOWN_PAGE_SIZE
	for index in range(start, mini(start + TOWN_PAGE_SIZE, changes.size())):
		var change: Dictionary = changes[index]
		var card := PanelContainer.new()
		card.name = "TownChange_%s" % String(change.id)
		card.custom_minimum_size = Vector2(500, 106)
		card.add_theme_stylebox_override("panel", ShellTheme.panel_style("well"))
		var card_column := VBoxContainer.new()
		card_column.add_theme_constant_override("separation", 5)
		card.add_child(card_column)
		var title := _reading_label(String(change.get("title", "")), Color("e9ddc3"))
		card_column.add_child(title)
		card_column.add_child(_note_label(String(change.get("description", ""))))
		grid.add_child(card)
	_add_page_controls(column, _town_page, page_count, func(page: int):
		_town_page = page
		_rebuild()
	)


func _filtered_journals() -> Array:
	var entries: Array = _state.get("journal_entries", [])
	return entries.filter(func(entry: Dictionary): return not _journal_unread_only or not bool(entry.get("is_read", false)))


func _unread_count(entries: Array) -> int:
	return entries.filter(func(entry: Dictionary): return not bool(entry.get("is_read", false))).size()


func _add_unread_filter(parent: Node, conversation: bool) -> void:
	var entries: Array = _state.get("available_conversations" if conversation else "journal_entries", [])
	if conversation and not _conversation_filter.is_empty():
		entries = entries.filter(func(entry: Dictionary): return String(entry.npc) == _conversation_filter)
	var filter := CheckButton.new()
	filter.name = "ConversationUnreadFilter" if conversation else "JournalUnreadFilter"
	filter.text = "Unread Only %d / %d" % [_unread_count(entries), entries.size()]
	filter.add_theme_font_size_override("font_size", NOTE_FONT_SIZE)
	filter.set_pressed_no_signal(_conversation_unread_only if conversation else _journal_unread_only)
	filter.toggled.connect(func(enabled: bool):
		if conversation: _conversation_unread_only = enabled
		else: _journal_unread_only = enabled
		_clamp_selections()
		_rebuild()
	)
	parent.add_child(filter)


func _select_entry(entry: Dictionary, conversation: bool) -> void:
	var entries := _filtered_conversations() if conversation else _filtered_journals()
	var index := entries.find(entry)
	if conversation:
		_conversation_id = String(entry.id)
		_conversation_page = 0
		_conversation_list_page = maxi(0, index) / LIST_PAGE_SIZE
	else:
		_journal_id = String(entry.id)
		_journal_page = 0
		_journal_list_page = maxi(0, index) / LIST_PAGE_SIZE


func _add_read_completion(parent: Node, entry: Dictionary, page: int, conversation: bool) -> void:
	var read := _button("Read · Available to Review" if bool(entry.get("is_read", false)) else "Record This Conversation E" if conversation else "Record This Entry E", "ReadConversation" if conversation else "ReadJournal", NOTE_FONT_SIZE)
	read.disabled = bool(entry.get("is_read", false)) or page < (entry.get("pages", []) as Array).size() - 1
	read.tooltip_text = "Record after the last page; closing early will not mark it read."
	read.pressed.connect(_complete_reading.bind(String(entry.id), conversation))
	parent.add_child(read)


func _complete_reading(entry_id: String, conversation: bool) -> void:
	var entries := _filtered_conversations() if conversation else _filtered_journals()
	var entry := _find_by_id(entries, entry_id)
	var page := _conversation_page if conversation else _journal_page
	if entry.is_empty() or bool(entry.get("is_read", false)) or page < (entry.get("pages", []) as Array).size() - 1:
		return
	var index := entries.find(entry)
	_saved_story = progression.mark_entry_read(_progress_snapshot, _saved_story, entry_id)
	_state = progression.evaluate(_progress_snapshot, _saved_story)
	var remaining := _filtered_conversations() if conversation else _filtered_journals()
	if _find_by_id(remaining, entry_id).is_empty() and not remaining.is_empty():
		_select_entry(remaining[mini(index, remaining.size() - 1)], conversation)
	_clamp_selections()
	_rebuild("reading")
	entry_read.emit(entry_id)


func _add_page_controls(parent: Node, page: int, count: int, change: Callable, context: String = "Text") -> void:
	var row := HBoxContainer.new()
	row.name = "PageControls"
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var previous := _button("Previous", "PreviousPage", NOTE_FONT_SIZE)
	previous.custom_minimum_size = Vector2(90, 40)
	previous.disabled = page <= 0
	previous.pressed.connect(func(): change.call(page - 1))
	row.add_child(previous)
	var status := _note_label("%s %d / %d" % [context, page + 1, count])
	status.custom_minimum_size.x = 100
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(status)
	var next := _button("Next", "NextPage", NOTE_FONT_SIZE)
	next.custom_minimum_size = Vector2(90, 40)
	next.disabled = page >= count - 1
	next.pressed.connect(func(): change.call(page + 1))
	row.add_child(next)
	previous.visible = count > 1
	next.visible = count > 1


func _clamp_selections() -> void:
	for conversation: bool in [true, false]:
		var entries := _filtered_conversations() if conversation else _filtered_journals()
		var id := _conversation_id if conversation else _journal_id
		var selected := _find_by_id(entries, id)
		if entries.is_empty():
			if conversation:
				_conversation_id = ""
				_conversation_page = 0
				_conversation_list_page = 0
			else:
				_journal_id = ""
				_journal_page = 0
				_journal_list_page = 0
			continue
		if selected.is_empty():
			_select_entry(entries.back(), conversation)
			selected = entries.back()
		var last_page := maxi(0, (selected.get("pages", []) as Array).size() - 1)
		if conversation:
			_conversation_page = clampi(_conversation_page, 0, last_page)
			_conversation_list_page = entries.find(selected) / LIST_PAGE_SIZE
		else:
			_journal_page = clampi(_journal_page, 0, last_page)
			_journal_list_page = entries.find(selected) / LIST_PAGE_SIZE


func _select_latest_entries() -> void:
	for conversation: bool in [true, false]:
		var entries := _filtered_conversations() if conversation else _filtered_journals()
		var unread := entries.filter(func(entry: Dictionary): return not bool(entry.get("is_read", false)))
		if not unread.is_empty(): entries = unread
		if not entries.is_empty(): _select_entry(entries.back(), conversation)


func _find_by_id(values: Array, id: String) -> Dictionary:
	for value in values:
		if value is Dictionary and String((value as Dictionary).get("id", "")) == id:
			return value
	return {}


func _page_count(item_count: int, page_size: int) -> int:
	return maxi(1, int(ceil(float(item_count) / float(page_size))))


func _chapter_heading(text_value: String) -> Label:
	var label := _label(text_value, BODY_FONT_SIZE, ShellTheme.AMBER)
	label.name = "ChapterHeading"
	return label


func _reading_label(text_value: String, color: Color = ShellTheme.BONE) -> Label:
	return _page_label(text_value, BODY_FONT_SIZE, color)


func _note_label(text_value: String) -> Label:
	return _page_label(text_value, NOTE_FONT_SIZE, ShellTheme.NEUTRAL)


func _page_label(text_value: String, font_size: int, color: Color = ShellTheme.BONE) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _label(text_value: String, font_size: int, color: Color) -> Label:
	return _page_label(text_value, font_size, color)


func _button(text_value: String, node_name: String, font_size: int = BODY_FONT_SIZE) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.add_theme_font_size_override("font_size", font_size)
	button.focus_mode = Control.FOCUS_ALL
	return button


func _entry_button(node_name: String) -> Button:
	var button := _button("", node_name, BODY_FONT_SIZE)
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(330, 54)
	button.autowrap_mode = TextServer.AUTOWRAP_OFF
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_theme_color_override("font_color", Color("e9ddc3"))
	return button


func _ink_rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = Color("8a6a44")
	rule.custom_minimum_size = Vector2(160, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return rule


func _style_tab(button: Button, selected: bool) -> void:
	button.add_theme_stylebox_override("normal", ShellTheme.panel_style("button"))
	button.add_theme_stylebox_override("hover", ShellTheme.panel_style("hover"))
	button.add_theme_stylebox_override("pressed", ShellTheme.panel_style("selected"))
	button.add_theme_stylebox_override("disabled", ShellTheme.panel_style("disabled"))
	if selected:
		button.add_theme_stylebox_override("normal", ShellTheme.panel_style("selected"))
		button.add_theme_color_override("font_color", Color("fff1ce"))
