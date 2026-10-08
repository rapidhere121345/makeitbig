class_name HubNavigationBar
extends Control
## Persistent bottom navigation of the base hub: one compact card per P1
## facility, in the order the main-owned icon pack publishes.
##
## Scope contract: this file owns the five cards, the optional 32x32 icon atlas
## reader and the click/focus behaviour only. It never writes progression, never
## derives a gameplay number and never claims a facility is usable that the hub
## did not hand it as unlocked; every label is a copy of the state the hub read
## from the save.
##
## Immortality (恒生坛) is not a P1 surface and therefore has no card: five
## entries stay five buttons, so the bar can never open a system that is not in
## this prototype.
##
## Icon contract (main thread): res://art/production/p1/hub_navigation_v01/
##   icons.png  160x32, five 32x32 cells, left to right
##              contract / loadout / forge / training / proxy
##   atlas.json schema_version 1, sprites as an ARRAY, one entry per cell with
##              id "facility.<feature>" (bare "<feature>" also accepted),
##              rect [32*column, 0, 32, 32] and anchor [16, 16]
## The cards draw those cells at the published 2x (64x64) with nearest filtering.
## The pack is read strictly: the array shape, every id, rect, anchor and the
## 160x32 texture must all hold, and the five entries are committed only once the
## last one has validated. Nothing is guessed and nothing is substituted: while
## the pack is unpublished or does not conform, the cards show their text and
## their icon slot stays empty.

signal card_activated(feature_id: String)

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")

const ICON_DIRECTORY: String = "res://art/production/p1/hub_navigation_v01"
const ICON_ATLAS_PATH: String = ICON_DIRECTORY + "/atlas.json"

## The one authoritative card order, shared by the layout, the icon cells, the
## exposed state list and the tests.
const FEATURE_IDS: Array[String] = ["contract", "loadout", "forge", "training", "proxy"]

const NATIVE_ICON_SIZE := Vector2i(32, 32)
const ICON_ANCHOR := Vector2i(16, 16)
const DISPLAY_SCALE: int = 2
const DISPLAY_ICON_SIZE := Vector2i(64, 64)

## Design-space band of the bar inside the 1280x720 hub canvas: under the world
## viewport and clear of the authored entry foot point (640, 520).
const BAR_RECT := Rect2(0.0, 620.0, 1280.0, 84.0)
const CARD_INSET_X := 16.0
## Five 240px cards plus four 12px gaps fill the 1248px inside the 16px page
## margins exactly, so the row is centred on the canvas without a remainder.
const CARD_GAP := 12.0
const CARD_TOP := 8.0
const CARD_SIZE := Vector2(240.0, 68.0)
const ICON_ORIGIN := Vector2(4.0, 2.0)
const COPY_LEFT := 74.0
const COPY_INSET_RIGHT := 10.0
const TITLE_TOP := 4.0
const TITLE_HEIGHT := 28.0
const STATUS_TOP := 32.0
const STATUS_HEIGHT := 26.0
const TITLE_FONT_SIZE := 20
const STATUS_FONT_SIZE := 18

var _cards: Dictionary = {}
var _entries: Dictionary = {}
var _texture: Texture2D = null
var _layers: Control


func setup() -> void:
	## Idempotent: the hub may call this again after a hot reload. Cards keep
	## their copy and simply gain their icons once the pack is published.
	if _layers == null:
		_build_layout()
	load_icons()
	_apply_icons()


func cards() -> Dictionary:
	## feature_id -> Button. The stable BaseNav_<id> node names are derived from
	## this map, never from the widget order.
	return _cards.duplicate()


func card_node_name(feature_id: String) -> String:
	return "BaseNav_%s" % feature_id


func apply_states(states: Array) -> void:
	## One entry per card, in FEATURE_IDS order. Every field is rendered exactly
	## as the hub derived it: a locked card says why, an available card never
	## borrows that wording.
	for index in FEATURE_IDS.size():
		var feature_id := FEATURE_IDS[index]
		var card: Button = _cards.get(feature_id, null)
		if card == null:
			continue
		var state: Dictionary = states[index] if index < states.size() and states[index] is Dictionary else {}
		_apply_card(card, state, feature_id)


func set_current_feature(feature_id: String) -> void:
	## The stand the avatar is close enough to open gets the same single-side
	## cue the world markers use, so "current" never relies on colour alone.
	var current_id := feature_id
	for id: String in FEATURE_IDS:
		var card: Button = _cards.get(id, null)
		if card == null:
			continue
		card.button_pressed = not current_id.is_empty() and id == current_id


## ------------------------------------------------------------------ icon pack

func icons_ready() -> bool:
	return _texture != null and _entries.size() == FEATURE_IDS.size()


func pending_reason() -> String:
	if icons_ready():
		return ""
	if not FileAccess.file_exists(_pack_path(ICON_ATLAS_PATH)):
		return "ASSETS PENDING: %s" % ICON_ATLAS_PATH
	if not FileAccess.file_exists(_pack_path(ICON_DIRECTORY + "/icons.png")):
		return "ASSETS PENDING: %s/icons.png" % ICON_DIRECTORY
	return "ASSETS PENDING: the hub navigation pack is not published"


func icon_cell(feature_id: String) -> Rect2i:
	## The published source cell of a card, or an empty rect while the pack is
	## pending. Read from atlas.json only, never guessed from the order here.
	var rect: Variant = (_entries.get(feature_id, {}) as Dictionary).get("rect", [])
	if not rect is Array or (rect as Array).size() != 4:
		return Rect2i()
	var values := rect as Array
	return Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3]))


func icon_texture(feature_id: String) -> Texture2D:
	if _texture == null:
		return null
	var entry: Dictionary = _entries.get(feature_id, {})
	if entry.is_empty():
		return null
	var rect: Array = entry.get("rect", [])
	if rect.size() != 4:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = _texture
	atlas.region = Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
	return atlas


func load_icons() -> bool:
	## Same reader contract as the other P1 icon packages: the approved PNG bytes
	## are preferred and the imported resource is the exported-build fallback. A
	## missing or non-conforming pack leaves every icon slot empty and reported as
	## pending instead of substituting another image.
	_entries.clear()
	_texture = null
	var atlas_file := FileAccess.open(_pack_path(ICON_ATLAS_PATH), FileAccess.READ)
	if atlas_file == null:
		return false
	var parsed: Variant = JSON.parse_string(atlas_file.get_as_text())
	if not parsed is Dictionary or int((parsed as Dictionary).get("schema_version", 0)) != 1:
		return false
	var raw_sprites: Variant = (parsed as Dictionary).get("sprites", [])
	var by_id := {}
	if not raw_sprites is Array or raw_sprites.size() != FEATURE_IDS.size():
		return false
	for raw_entry: Variant in raw_sprites as Array:
		if not raw_entry is Dictionary:
			return false
		var id := String(raw_entry.get("id", ""))
		if id.is_empty() or by_id.has(id):
			return false
		by_id[id] = raw_entry.duplicate(true)
	var texture := _load_texture(_pack_path(ICON_DIRECTORY + "/icons.png"))
	if texture == null or texture.get_size() != Vector2(NATIVE_ICON_SIZE.x * FEATURE_IDS.size(), NATIVE_ICON_SIZE.y):
		return false
	var validated := {}
	for index in FEATURE_IDS.size():
		var feature_id := FEATURE_IDS[index]
		var entry: Dictionary = _lookup_entry(by_id, feature_id)
		if entry.is_empty() or not _validate_entry(entry, index, texture):
			return false
		validated[feature_id] = entry
	## Atomic commit: a half-read pack never leaves the bar with a partial set.
	_entries = validated
	_texture = texture
	return true


func _lookup_entry(by_id: Dictionary, feature_id: String) -> Dictionary:
	## The two published id spellings only. A renamed key is a contract mismatch
	## and stays unreported art rather than being matched by a guess.
	for candidate: String in ["facility.%s" % feature_id, feature_id]:
		if by_id.has(candidate):
			var entry: Variant = by_id[candidate]
			if entry is Dictionary:
				return entry as Dictionary
	return {}


func _validate_entry(entry: Dictionary, index: int, texture: Texture2D) -> bool:
	var rect: Variant = entry.get("rect", [])
	var anchor: Variant = entry.get("anchor", [])
	if not rect is Array or (rect as Array).size() != 4 or not anchor is Array or (anchor as Array).size() != 2:
		return false
	var values := rect as Array
	for number: Variant in values + (anchor as Array):
		# JSON integers arrive as floats; reject fractional, string and bool values
		# instead of silently truncating the frame/anchor contract.
		if not (number is int or number is float) or not is_finite(float(number)) or float(number) != floorf(float(number)):
			return false
	if entry.get("type", "") != "ui_icon" or entry.get("texture", "") != "icons":
		return false
	var cell := Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3]))
	if cell.size != NATIVE_ICON_SIZE or Vector2i(int((anchor as Array)[0]), int((anchor as Array)[1])) != ICON_ANCHOR:
		return false
	var published := Vector2i(NATIVE_ICON_SIZE.x * index, 0)
	if cell.position != published:
		return false
	return Rect2i(Vector2i.ZERO, texture.get_size()).encloses(cell)


func _load_texture(path: String) -> Texture2D:
	var absolute := _pack_path(path)
	if FileAccess.file_exists(absolute):
		var file := FileAccess.open(absolute, FileAccess.READ)
		if file != null and file.get_length() > 0:
			var image := Image.new()
			if image.load_png_from_buffer(file.get_buffer(file.get_length())) == OK:
				return ImageTexture.create_from_image(image)
	if ResourceLoader.exists(path):
		var resource: Variant = load(path)
		if resource is Texture2D:
			return resource
	return null


func _pack_path(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("res://") else path


## -------------------------------------------------------------------- layout

func _build_layout() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	## The bar is positioned by the design canvas grid it was written for, so it
	## keeps its explicit rectangle instead of taking an anchor preset.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = BAR_RECT.position
	size = BAR_RECT.size
	custom_minimum_size = BAR_RECT.size

	var strip := ColorRect.new()
	strip.name = "BaseNavStrip"
	strip.color = Color("111820f0")
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.position = Vector2.ZERO
	strip.size = BAR_RECT.size
	add_child(strip)

	_layers = Control.new()
	_layers.name = "BaseNavCards"
	_layers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layers.position = Vector2.ZERO
	_layers.size = BAR_RECT.size
	add_child(_layers)

	for index in FEATURE_IDS.size():
		var feature_id := FEATURE_IDS[index]
		var card := Button.new()
		card.name = card_node_name(feature_id)
		card.toggle_mode = true
		card.focus_mode = Control.FOCUS_ALL
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.position = Vector2(CARD_INSET_X + (CARD_SIZE.x + CARD_GAP) * float(index), CARD_TOP)
		card.size = CARD_SIZE
		card.custom_minimum_size = CARD_SIZE
		card.tooltip_text = ""
		card.set_meta("feature_id", feature_id)
		card.pressed.connect(_on_card_activated.bind(feature_id))
		card.gui_input.connect(_on_card_gui_input.bind(feature_id))
		_layers.add_child(card)
		_build_card_content(card, feature_id)
		_cards[feature_id] = card
	## Focus neighbours are wired once every card exists, so the ring is complete
	## in both directions from the first frame.
	_wire_focus_neighbours()


func _build_card_content(card: Button, feature_id: String) -> void:
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.position = ICON_ORIGIN
	icon.size = Vector2(DISPLAY_ICON_SIZE)
	icon.custom_minimum_size = Vector2(DISPLAY_ICON_SIZE)
	icon.set_meta("native_size", NATIVE_ICON_SIZE)
	card.add_child(icon)

	var copy := Control.new()
	copy.name = "Copy"
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.position = Vector2(COPY_LEFT, 0.0)
	copy.size = Vector2(CARD_SIZE.x - COPY_LEFT - COPY_INSET_RIGHT, CARD_SIZE.y)
	card.add_child(copy)

	var title := Label.new()
	title.name = "Title"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.position = Vector2(0.0, TITLE_TOP)
	title.size = Vector2(copy.size.x, TITLE_HEIGHT)
	copy.add_child(title)

	var status := Label.new()
	status.name = "Status"
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.clip_text = true
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.add_theme_font_size_override("font_size", STATUS_FONT_SIZE)
	status.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
	status.position = Vector2(0.0, STATUS_TOP)
	status.size = Vector2(copy.size.x, STATUS_HEIGHT)
	status.set_meta("feature_id", feature_id)
	copy.add_child(status)


func _wire_focus_neighbours() -> void:
	## Tab/Shift+Tab and left/right share the same five-card focus ring.
	for index in FEATURE_IDS.size():
		var card: Button = _cards.get(FEATURE_IDS[index], null)
		if card == null:
			continue
		var right: Button = _cards.get(FEATURE_IDS[(index + 1) % FEATURE_IDS.size()], null)
		var left: Button = _cards.get(FEATURE_IDS[(index - 1 + FEATURE_IDS.size()) % FEATURE_IDS.size()], null)
		if right != null and right != card:
			card.focus_neighbor_right = _sibling_path(card, right)
			card.focus_next = card.focus_neighbor_right
		if left != null and left != card:
			card.focus_neighbor_left = _sibling_path(card, left)
			card.focus_previous = card.focus_neighbor_left


func _sibling_path(from: Control, to: Control) -> NodePath:
	## The ring is written as an explicit sibling path from the card that owns it,
	## which is what a stock Tab step follows; the name fallback keeps the wiring
	## readable while the bar is only being inspected outside a scene tree.
	var path := from.get_path_to(to)
	if path.is_empty() and from.get_parent() != null and from.get_parent() == to.get_parent():
		return NodePath("../%s" % to.name)
	return path


func _apply_icons() -> void:
	for feature_id: String in FEATURE_IDS:
		var card: Button = _cards.get(feature_id, null)
		if card == null:
			continue
		var icon := card.get_node_or_null(NodePath("Icon")) as TextureRect
		if icon == null:
			continue
		var region := icon_texture(feature_id)
		icon.texture = region
		icon.visible = region != null


func _apply_card(card: Button, state: Dictionary, feature_id: String) -> void:
	var title := card.get_node_or_null(NodePath("Copy/Title")) as Label
	var status := card.get_node_or_null(NodePath("Copy/Status")) as Label
	var locked := bool(state.get("locked", false))
	card.tooltip_text = "%s\n%s" % [String(state.get("title", feature_id)), String(state.get("status", ""))]
	if title != null:
		title.text = String(state.get("title", feature_id))
		if locked:
			title.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL)
		else:
			title.add_theme_color_override("font_color", ShellThemeScript.BONE)
	if status != null:
		status.text = String(state.get("status", ""))
		status.visible = not status.text.is_empty()
		status.add_theme_color_override("font_color", ShellThemeScript.NEUTRAL if locked else ShellThemeScript.AMBER)


func _on_card_activated(feature_id: String) -> void:
	## One signal for every card, exactly like the world entry path: the hub turns
	## it into contract_requested or feature_requested. No state is written here.
	card_activated.emit(feature_id)


func _on_card_gui_input(event: InputEvent, feature_id: String) -> void:
	# Space is also world-interact/attack. Explicitly consume it while a card
	# owns focus; the engine's ui_accept binding is not guaranteed to include it.
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	var key := key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
	if key != KEY_SPACE:
		return
	var card: Button = _cards[feature_id]
	card.accept_event()
	if event.pressed and not event.echo:
		_on_card_activated(feature_id)
