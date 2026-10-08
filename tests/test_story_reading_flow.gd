extends SceneTree

const StoryScreenScript = preload("res://src/presentation/story_screen.gd")
const TownDialogueScript = preload("res://src/presentation/town_dialogue.gd")
const OPENING := {"completed_node_ids": ["tutorial_ranger_basics"]}
const COMPLETE := {
	"completed_node_ids": ["tutorial_ranger_basics", "mainline_01_first_hunt", "mainline_02_priority_under_pressure", "mainline_03_first_elite", "mainline_04_hazard_and_forge", "mainline_05_growth_gate", "threshold_colossus", "auto_certification"],
	"equipment_discovered": true, "growth_observed": true, "first_growth_state": "convergent",
	"exponential_observed": true, "proxy_unlocked": true, "early_game_complete": true,
}

var failures: Array[String] = []
var reads: Array[String] = []
var host: Control
var return_button: Button
var screen: StoryScreen


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	host = Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	return_button = Button.new()
	return_button.text = "Return to town"
	host.add_child(return_button)
	return_button.grab_focus()
	screen = StoryScreenScript.new()
	host.add_child(screen)
	screen.entry_read.connect(func(id: String): reads.append(id))
	await _check_opening_completion_and_return()
	await _check_person_filter_and_restore()
	await _check_journal_completion()
	await _check_full_chapter_directory_and_layout()
	screen.hide()
	await _check_town_dialogue()
	host.queue_free()
	await _settle()
	for failure in failures: printerr("- " + failure)
	print("STORY_READING_FLOW ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func _check_opening_completion_and_return() -> void:
	screen.present(OPENING, {})
	await _settle()
	_expect(_button("StoryTab_对话").text == "对话\n未读 2" and _button("StoryTab_日志").text == "日志\n未读 1", "opening unread counts include unavailable entries")
	_button("OpenUnread_1").pressed.emit()
	await _settle()
	_expect(_selected_id("ConversationList") == "Conversation_talk_p00_leia_stool", "newest unread entry was not selected in its directory")
	_expect(_focus_name() == "NextPage", "conversation did not focus forward paging")
	await _key(KEY_ENTER)
	_expect(_speech().begins_with("米拉：") and reads.is_empty() and _focus_name() == "NextPage", "Enter did not advance exactly one page without marking read")
	await _key(KEY_ESCAPE)
	_expect(not screen.visible and reads.is_empty() and root.gui_get_focus_owner() == return_button, "early codex close marked read or trapped focus")
	screen.present(OPENING, {})
	await _settle()
	await _key(KEY_ENTER)
	await _key(KEY_ENTER)
	_expect(reads.is_empty() and _focus_name() == "ReadConversation", "final conversation page did not focus explicit completion")
	await _key(KEY_ENTER)
	_expect(reads == ["talk_p00_leia_stool"], "conversation completion did not emit exactly one stable ID")
	_expect(_selected_id("ConversationList") == "Conversation_talk_p00_mira_door" and _focus_name() == "NextPage", "completion did not select the next unread entry and reset its page/focus")
	_expect(_button("StoryTab_对话").text == "对话\n未读 1", "conversation count did not update after completion")
	for _page in range(3): await _key(KEY_E)
	_expect(reads.size() == 1 and _focus_name() == "ReadConversation", "E paging produced an early conversation receipt")
	await _key(KEY_E)
	_expect(reads == ["talk_p00_leia_stool", "talk_p00_mira_door"], "E completion changed the wrong entry")
	_expect(_button("StoryTab_对话").text == "对话\n未读 0" and screen.find_child("ConversationDetail", true, false) == null, "completed unread directory retained a stale detail")
	_expect(_has_text(screen, "可读对话已全部听过") and _focus_name() == "ConversationUnreadFilter", "empty unread directory did not offer a focused way to reread")
	await _key(KEY_ENTER)
	_expect(_selected_id("ConversationList") != "" and _has_text(screen, "已读 ·"), "keyboard unread toggle did not restore rereading")


func _check_person_filter_and_restore() -> void:
	screen.present(OPENING, {"read_entry_ids": ["talk_p00_mira_door"]})
	await _settle()
	_set_unread(true, true)
	await _settle()
	_expect(_button("StoryTab_对话").text == "对话\n未读 1", "restored read state did not control unread count")
	_select_person("米拉")
	await _settle()
	_expect(screen.find_child("ConversationPersonFilter", true, false) != null and _has_text(screen, "这位镇民暂无未读对话"), "empty person filter removed its controls or explanation")
	_expect((screen.find_child("ConversationUnreadFilter", true, false) as CheckButton).text == "只看未读 0 / 1", "person count did not reflect evaluated resident entries")
	_set_unread(true, false)
	await _settle()
	_expect(_selected_id("ConversationList") == "Conversation_talk_p00_mira_door", "all entries did not retain the person filter")
	var before := reads.duplicate()
	for _page in range(3): await _key(KEY_E)
	_expect(_button("ReadConversation").disabled, "rereading offered a duplicate read receipt")
	_button("ReadConversation").pressed.emit()
	_expect(reads == before, "disabled reread callback emitted another receipt")
	_button("StoryTab_日志").pressed.emit()
	await _settle()
	_button("StoryTab_对话").pressed.emit()
	await _settle()
	screen.present({"completed_node_ids": ["tutorial_ranger_basics", "mainline_01_first_hunt"]}, screen.saved_story())
	await _settle()
	var filter := screen.find_child("ConversationPersonFilter", true, false) as OptionButton
	_expect(filter.get_item_text(filter.selected) == "米拉" and _selected_id("ConversationList") == "Conversation_talk_p00_mira_door", "tabs or snapshot refresh lost the selected person")
	_select_person("全部人物")
	_set_unread(true, true)
	await _settle()
	_expect(screen.find_child("Conversation_talk_p00_mira_door", true, false) == null and _button("StoryTab_对话").text == "对话\n未读 2", "combined all-person/unread filter included a read or unavailable conversation")


func _check_journal_completion() -> void:
	screen.present(OPENING, {})
	_button("StoryTab_日志").pressed.emit()
	await _settle()
	_set_unread(false, true)
	await _settle()
	var before := reads.duplicate()
	_button("JournalEntry_journal_p00_place_by_the_door").pressed.emit()
	await _settle()
	_button("ReadJournal").pressed.emit()
	_expect(reads == before and _button("ReadJournal").disabled, "journal selection or premature callback marked read")
	await _key(KEY_ENTER)
	await _key(KEY_ENTER)
	_expect(reads == before and _focus_name() == "ReadJournal", "last journal page auto-marked read or lost completion focus")
	await _key(KEY_ESCAPE)
	_expect(reads == before and screen.saved_story().read_entry_ids.is_empty(), "closing on final journal page produced a receipt")
	screen.present(OPENING, {})
	await _settle()
	for _page in range(2): await _key(KEY_E)
	await _key(KEY_ENTER)
	_expect(reads.size() == before.size() + 1 and reads.back() == "journal_p00_place_by_the_door", "journal explicit completion did not emit one stable ID")
	_expect(_button("StoryTab_日志").text == "日志\n未读 0" and _has_text(screen, "可读日志已全部读完") and _focus_name() == "JournalUnreadFilter", "journal completion left stale selection/count/focus")
	_set_unread(false, false)
	await _settle()
	_expect(_selected_id("JournalList") == "JournalEntry_journal_p00_place_by_the_door", "journal could not be reread")
	for _page in range(2): await _key(KEY_E)
	_expect(_button("ReadJournal").disabled and reads.size() == before.size() + 1, "journal reread changed receipts")
	screen.present({}, {})
	await _settle()
	_expect(_has_text(screen, "还没有日志") and screen.find_child("JournalUnreadFilter", true, false) != null, "no-unlocked-journal state removed filter or explanation")
	_button("StoryTab_对话").pressed.emit()
	await _settle()
	_expect(_has_text(screen, "当前还没有可交谈的人") and screen.find_child("ConversationPersonFilter", true, false) != null, "no-unlocked-conversation state removed filter or explanation")


func _check_full_chapter_directory_and_layout() -> void:
	screen.present(COMPLETE, {})
	_set_unread(true, true)
	await _settle()
	var state := screen.current_state()
	_expect(state.available_conversations.size() == 28 and state.journal_entries.size() == 10, "complete evaluated chapter lost conversations/journals")
	var seen: Array[String] = []
	for _group in range(7):
		var list := screen.find_child("ConversationList", true, false)
		for child in list.get_children():
			if child is Button and String(child.name).begins_with("Conversation_"):
				seen.append(String(child.name))
		_expect(_selected_id("ConversationList") != "", "directory page hid its selected conversation")
		var previous := list.find_child("PreviousPage", true, false) as Button
		if not previous.disabled:
			previous.grab_focus()
			await _key(KEY_ENTER)
	_expect(seen.size() == 28, "directory paging did not expose all 28 conversations")
	for viewport_size in [Vector2(1280, 720), Vector2(1600, 900)]:
		host.size = viewport_size
		await _settle()
		for tab in ["目标", "对话", "日志", "生活"]:
			_button("StoryTab_" + tab).pressed.emit()
			await _settle()
			_check_bounds(screen, Rect2(Vector2.ZERO, viewport_size), tab)
	host.size = Vector2(1280, 720)
	_button("StoryTab_对话").pressed.emit()
	await _settle()
	var read_count_before := reads.size()
	for _entry in range(28):
		var selected_id := _selected_id("ConversationList")
		_expect(not selected_id.is_empty(), "unread completion lost the directory selection")
		var entry := _entry_for(selected_id.trim_prefix("Conversation_"), screen.current_state().available_conversations)
		for _page in range(entry.get("pages", []).size()): await _key(KEY_E)
		_expect(_button("StoryTab_对话").text == "对话\n未读 %d" % (27 - _entry), "unread count drifted during chapter completion")
	_expect(reads.size() == read_count_before + 28 and screen.saved_story().read_entry_ids.size() == 28, "chapter completion dropped or duplicated stable receipts")
	_expect(screen.current_state().current_objective == state.current_objective and screen.current_state().town_changes == state.town_changes, "reading changed objective or town progression")


func _check_town_dialogue() -> void:
	var dialogue = TownDialogueScript.new()
	host.add_child(dialogue)
	var close := dialogue.find_child("CloseDialogue", true, false) as Button
	var next := dialogue.find_child("DialogueNext", true, false) as Button
	_expect(close.get_node_or_null(close.focus_next) == next and next.get_node_or_null(next.focus_next) == close,
		"town startup did not construct a valid focus cycle in _ready")
	var town_reads: Array[String] = []
	dialogue.finished.connect(func(id: String): town_reads.append(id))
	var entry := _entry_for("talk_p00_mira_door", screen.progression.evaluate(OPENING, {}).available_conversations)
	return_button.grab_focus()
	_expect(dialogue.open_conversation(entry), "town conversation did not open")
	await _settle()
	_expect(_focus_name() == "DialogueNext", "town did not focus the next line on opening")
	await _key(KEY_ENTER)
	_expect(dialogue.dialogue_report().page == 1 and town_reads.is_empty(), "town Enter advanced twice or marked read early")
	(dialogue.find_child("DialoguePrevious", true, false) as Button).grab_focus()
	await _key(KEY_ENTER)
	_expect(dialogue.dialogue_report().page == 0 and _focus_name() == "DialogueNext", "previous at first line stranded town focus")
	await _key(KEY_TAB)
	_expect(_focus_name() == "CloseDialogue", "town focus navigation escaped to an underlying control")
	await _key(KEY_ENTER)
	_expect(not dialogue.is_open() and town_reads.is_empty() and root.gui_get_focus_owner() == return_button, "town keyboard early close marked read or failed to restore focus")
	for viewport_size in [Vector2(1280, 720), Vector2(1600, 900)]:
		host.size = viewport_size
		return_button.grab_focus()
		dialogue.open_conversation(entry)
		await _settle()
		var panel := dialogue.find_child("DialoguePanel", true, false) as Control
		_expect(absf(panel.get_global_rect().get_center().x - viewport_size.x / 2.0) < 1.0, "town panel did not remain horizontally centered after resize")
		_expect(absf(panel.get_global_rect().end.y - (viewport_size.y - 102.0)) < 1.0, "town panel lost its bottom inset")
		_check_bounds(dialogue, Rect2(Vector2.ZERO, viewport_size), "town")
		for _page in range(entry.pages.size() - 1): await _key(KEY_E)
		_expect(town_reads.size() == (0 if viewport_size.x == 1280 else 1), "town final line was marked before explicit completion")
		await _key(KEY_ENTER)
		_expect(not dialogue.is_open() and root.gui_get_focus_owner() == return_button, "town completion failed to return focus")
	_expect(town_reads == [entry.id, entry.id], "town completion/reread did not preserve stable ID")
	dialogue.open_conversation(entry)
	await _key(KEY_ESCAPE)
	_expect(town_reads.size() == 2 and not dialogue.is_open(), "town Escape created another receipt")
	dialogue.queue_free()


func _button(node_name: String) -> Button:
	return screen.find_child(node_name, true, false) as Button


func _set_unread(conversation: bool, enabled: bool) -> void:
	var toggle := screen.find_child("ConversationUnreadFilter" if conversation else "JournalUnreadFilter", true, false) as CheckButton
	toggle.button_pressed = enabled


func _select_person(text: String) -> void:
	var filter := screen.find_child("ConversationPersonFilter", true, false) as OptionButton
	for index in range(filter.item_count):
		if filter.get_item_text(index) == text:
			filter.item_selected.emit(index)
			return
	_expect(false, "person filter missing " + text)


func _selected_id(list_name: String) -> String:
	var list := screen.find_child(list_name, true, false)
	if list == null: return ""
	for child in list.get_children():
		if child is Button and child.toggle_mode and child.button_pressed and (String(child.name).begins_with("Conversation_") or String(child.name).begins_with("JournalEntry_")):
			return String(child.name)
	return ""


func _entry_for(id: String, entries: Array) -> Dictionary:
	for entry: Dictionary in entries:
		if entry.id == id: return entry
	return {}


func _speech() -> String:
	return (screen.find_child("ConversationSpeech", true, false) as Label).text


func _focus_name() -> String:
	var owner := root.gui_get_focus_owner()
	return String(owner.name) if owner != null else ""


func _has_text(node: Node, text: String) -> bool:
	if node is Label or node is Button:
		if text in node.text: return true
	for child in node.get_children():
		if _has_text(child, text): return true
	return false


func _check_bounds(node: Node, bounds: Rect2, context: String) -> void:
	if node is Control and node.is_visible_in_tree():
		var rect: Rect2 = node.get_global_rect()
		_expect(bounds.grow(1.0).encloses(rect), "%s %s escaped %s: %s" % [context, node.name, bounds.size, rect])
	for child in node.get_children(): _check_bounds(child, bounds, context)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await _settle()


func _settle() -> void:
	for _frame in range(3): await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
