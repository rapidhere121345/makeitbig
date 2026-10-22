extends SceneTree

const StoryScreenScript = preload("res://src/presentation/story_screen.gd")
const ShellTheme = preload("res://src/presentation/shell_theme.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var screen = StoryScreenScript.new()
	host.add_child(screen)
	var close_counts: Array[int] = [0]
	var read_events: Array[String] = []
	screen.closed.connect(func(): close_counts[0] += 1)
	screen.entry_read.connect(func(entry_id: String): read_events.append(entry_id))
	var detached = StoryScreenScript.new()
	detached.present(_snapshot(["tutorial_ranger_basics"], false, false), {})
	var pre_ready_presented := detached.current_state().size() == 4
	detached.free()
	screen.present(_snapshot(["tutorial_ranger_basics"], false, false), {})
	await _settle()
	_expect(pre_ready_presented, "present before _ready did not preserve public state")
	_expect(screen.theme != null and screen.theme.default_font == ShellTheme.ui_font()
		and screen.theme.default_font_size == ShellTheme.BODY_FONT_SIZE,
		"story screen did not use ShellTheme font and body-size contract")
	_check_layout(screen)
	(screen.find_child("StoryTab_Journal", true, false) as Button).pressed.emit()
	await _settle()
	var first_entry := screen.find_child("JournalEntry_journal_p00_place_by_the_door", true, false) as Button
	_expect(first_entry != null, "P00 journal entry is missing")
	if first_entry != null:
		first_entry.pressed.emit()
		await _settle()
		_expect(read_events.is_empty(), "selecting a journal created an early read receipt")
		var completion := screen.find_child("ReadJournal", true, false) as Button
		_expect(completion != null and completion.disabled, "journal completion was enabled before its last page")
		for _page in range(2):
			var detail := screen.find_child("JournalDetail", true, false)
			(detail.find_child("NextPage", true, false) as Button).pressed.emit()
			await _settle()
		_expect(read_events.is_empty(), "arriving at a journal's final page marked it read")
		completion = screen.find_child("ReadJournal", true, false) as Button
		_expect(completion != null and not completion.disabled, "journal completion missing on the final page")
		if completion != null: completion.pressed.emit()
		await _settle()
		_expect(read_events == ["journal_p00_place_by_the_door"], "entry_read did not emit exactly the stable id")
		_expect(screen.saved_story() == {"schema_version": 1, "read_entry_ids": ["journal_p00_place_by_the_door"]},
			"screen did not expose normalized saved story after reading")
	(screen.find_child("StoryTab_Dialogue", true, false) as Button).pressed.emit()
	await _settle()
	_check_conversation_paging(screen)
	await _check_portrait_and_person_filter(screen)
	screen.present(_snapshot(["tutorial_ranger_basics", "mainline_01_first_hunt"], false, false), screen.saved_story())
	await _settle()
	_check_layout(screen)
	_check_latest_conversation_selected(screen)
	_expect(screen.find_child("ScrollContainer", true, false) == null, "story page used scrolling instead of fixed pagination")
	var close_button := screen.find_child("CloseStory", true, false) as Button
	if close_button != null:
		close_button.pressed.emit()
	await _settle()
	_expect(close_counts[0] == 1, "close emitted more than once or not at all")
	host.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("PASS story screen")
		quit(0)
	else:
		for failure in failures:
			printerr("- %s" % failure)
		quit(1)


func _check_layout(screen: StoryScreen) -> void:
	var root_node := screen.find_child("StoryScreenRoot", true, false) as Control
	_expect(root_node != null and root_node.get_global_rect().size == Vector2(1280, 720),
		"story UI did not occupy exactly 1280x720")
	var body := screen.find_child("StoryBody", true, false) as Control
	var book := screen.find_child("StoryBook", true, false) as Control
	var tabs := screen.find_child("StoryTabs", true, false) as VBoxContainer
	_expect(body != null and body.get_global_rect().end.y <= 720.5 and body.get_global_rect().position.y >= 0,
		"story body escaped 720px height")
	_expect(book != null and tabs != null and tabs.get_child_count() == 5,
		"travel codex did not keep the warm reading page and four chapter spines")
	var labels := _labels(screen)
	var font_sizes: Array[int] = []
	for label in labels:
		font_sizes.append(int(label.get_theme_font_size("font_size")))
		if book != null and book.is_ancestor_of(label):
			var foreground := label.get_theme_color("font_color").srgb_to_linear()
			var paper := Color("292b27").srgb_to_linear()
			var contrast := (foreground.get_luminance() + 0.05) / (paper.get_luminance() + 0.05)
			_expect(contrast >= 4.5, "codex reading text lost contrast against its dark folio")
	for size in font_sizes:
		_expect(size == 22 or size == 18 or size == 28, "story UI used font size %d outside 28/22/18" % size)
	_expect(screen.current_state().has_all(["journal_entries", "available_conversations", "current_objective", "town_changes"]),
		"screen state does not expose the four public result fields")


func _check_conversation_paging(screen: StoryScreen) -> void:
	var all_next := []
	_collect(screen, "Button", all_next)
	var next_buttons := []
	for value in all_next:
		var button := value as Button
		if button.text == "Next" and _has_ancestor_name(button, "ConversationDetail"):
			next_buttons.append(button)
	_expect(next_buttons.size() == 1 and not next_buttons[0].disabled,
		"conversation detail did not expose an enabled page control for three short speech pages")


func _check_portrait_and_person_filter(screen: StoryScreen) -> void:
	var saved_before := screen.saved_story()
	var filter := screen.find_child("ConversationPersonFilter", true, false) as OptionButton
	_expect(filter != null and filter.item_count == 3, "opening person filter must contain All, Mira and Leia only")
	if filter == null: return
	var mira_index := -1
	for index in filter.item_count:
		if filter.get_item_text(index) == "Mira": mira_index = index
	_expect(mira_index >= 0, "Mira is missing from the conversation filter")
	if mira_index < 0: return
	filter.item_selected.emit(mira_index)
	await _settle()
	_expect(screen.find_child("Conversation_talk_p00_mira_door", true, false) != null
		and screen.find_child("Conversation_talk_p00_leia_stool", true, false) == null,
		"person filtering did not show only the selected resident's entries")
	var portrait := screen.find_child("ConversationPortrait", true, false) as TextureRect
	_expect(portrait != null and portrait.texture != null
		and portrait.texture.resource_path.ends_with("story_portraits_r14/mira.png"), "Mira's first line did not load her formal portrait")
	var detail := screen.find_child("ConversationDetail", true, false)
	var next := detail.find_child("NextPage", true, false) as Button
	next.pressed.emit()
	await _settle()
	portrait = screen.find_child("ConversationPortrait", true, false) as TextureRect
	_expect(portrait != null and portrait.texture == null, "the player line reused an NPC portrait")
	filter = screen.find_child("ConversationPersonFilter", true, false) as OptionButton
	filter.item_selected.emit(0)
	await _settle()
	_expect(screen.find_child("Conversation_talk_p00_leia_stool", true, false) != null, "All people did not restore the opening directory")
	portrait = screen.find_child("ConversationPortrait", true, false) as TextureRect
	_expect(portrait != null and portrait.texture != null
		and portrait.texture.resource_path.ends_with("story_portraits_r14/leia.png"), "Leia's first line did not load her formal portrait")
	detail = screen.find_child("ConversationDetail", true, false)
	(detail.find_child("NextPage", true, false) as Button).pressed.emit()
	await _settle()
	portrait = screen.find_child("ConversationPortrait", true, false) as TextureRect
	_expect(portrait != null and portrait.texture != null
		and portrait.texture.resource_path.ends_with("story_portraits_r14/mira.png"), "cross-speaker line did not follow Mira within Leia's conversation")
	_expect(screen.saved_story() == saved_before, "filtering and paging changed the read journal or marked a conversation read")


func _labels(screen: StoryScreen) -> Array[Label]:
	var values := []
	_collect(screen, "Label", values)
	var result: Array[Label] = []
	for value in values:
		result.append(value)
	return result


func _buttons(screen: StoryScreen, name_fragment: String) -> Array[Button]:
	var values := []
	_collect(screen, "Button", values)
	var result: Array[Button] = []
	for value in values:
		if name_fragment in (value as Button).name:
			result.append(value)
	return result


func _collect(node: Node, type: String, output: Array) -> void:
	for child in node.get_children():
		if child.get_class() == type:
			output.append(child)
		_collect(child, type, output)


func _check_latest_conversation_selected(screen: StoryScreen) -> void:
	var detail := screen.find_child("ConversationDetail", true, false)
	_expect(detail != null, "latest conversation detail is missing")
	if detail == null:
		return
	_expect(detail.get_child(0) is Label and String((detail.get_child(0) as Label).text).contains("Taren"),
		"returning to town did not select the newest-stage conversation first")


func _page_status(parent: Node) -> Label:
	if parent == null:
		return null
	for row in parent.get_children():
		if row is HBoxContainer:
			for value in row.get_children():
				if value is Label:
					return value
	return null


func _has_ancestor_name(node: Node, ancestor_name: String) -> bool:
	var current := node.get_parent()
	while current != null:
		if current.name == ancestor_name:
			return true
		current = current.get_parent()
	return false


func _snapshot(completed: Array[String], proxy_unlocked: bool, early_complete: bool) -> Dictionary:
	return {"completed_node_ids": completed, "proxy_unlocked": proxy_unlocked, "early_game_complete": early_complete}


func _settle() -> void:
	for _index in range(3):
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
