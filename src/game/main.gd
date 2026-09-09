extends Node2D

const ContentRegistryScript = preload("res://src/content/content_registry.gd")
const DestinyForgeScript = preload("res://src/systems/destiny_forge.gd")
const DeterministicRngScript = preload("res://src/core/deterministic_rng.gd")
const FixedTickClockScript = preload("res://src/core/fixed_tick_clock.gd")
const ProxyRuntimeScript = preload("res://src/systems/proxy_runtime.gd")
const SaveStoreScript = preload("res://src/persistence/save_store.gd")

class EnemyData:
	extends RefCounted
	var position: Vector2
	var health: float
	var maximum_health: float
	var is_boss: bool

	func _init(spawn_position: Vector2, hp: float, boss: bool = false) -> void:
		position = spawn_position
		health = hp
		maximum_health = hp
		is_boss = boss


class ArrowTrace:
	extends RefCounted
	var from: Vector2
	var to: Vector2
	var remaining: float = 0.18

	func _init(start: Vector2, finish: Vector2) -> void:
		from = start
		to = finish


const ARENA_MARGIN: float = 42.0
const SIM_TICKS_PER_SECOND: int = 30
const SIM_STEP_SECONDS: float = 1.0 / float(SIM_TICKS_PER_SECOND)
const PLAYER_SPEED: float = 245.0
const AUTO_RANGE: float = 225.0
const ATTACK_COOLDOWN_TICKS: int = 13
const DODGE_SPEED: float = 650.0
const DODGE_DURATION_TICKS: int = 5
const DODGE_COOLDOWN_TICKS: int = 35
const BASE_PAYLOAD: float = 160.0
const FATE_SEED: int = 52969
const SAVE_PROTOCOL_VERSION: int = 1
const MANUAL_BONUS_CHANCE: float = 0.35
const FORGE_FAMILY_LABELS: Dictionary = {
	"growth_probability": "Growth Probability / 生长概率",
	"shared_lifetime": "Shared Lifetime / 共享寿命",
	"branch_count": "Branch Count / 分支数",
	"payload": "Payload / 载荷",
	"flight_speed": "Flight Speed / 飞行速度",
	"turn_time": "Turn Time / 转向时间",
}
const FORGE_FAMILY_SHORT: Dictionary = {
	"growth_probability": "Growth P",
	"shared_lifetime": "Lifetime",
	"branch_count": "Branches",
	"payload": "Payload",
	"flight_speed": "Speed",
	"turn_time": "Turn Time",
}

var selected_preset: String = "convergent"
var selected_mode: String = "Manual"
var locked_p: float = PiercingArrowModel.BASE_P
var in_arena: bool = false
var player_position: Vector2 = Vector2.ZERO
var player_health: float = 100.0
var player_facing: Vector2 = Vector2.RIGHT
var enemies: Array[EnemyData] = []
var boss: EnemyData
var boss_maximum: BigValue = BigValue.from_power10(12.0)
var boss_damage: BigValue = BigValue.from_float(0.0)
var traces: Array[ArrowTrace] = []
var attack_cooldown_ticks: int = 0
var dodge_cooldown_ticks: int = 0
var dodge_remaining_ticks: int = 0
var dodge_direction: Vector2 = Vector2.RIGHT
var elapsed: float = 0.0
var sim_tick: int = 0
var shots: int = 0
var defeated: int = 0
var battle_over: bool = false
var battle_report: String = ""
var dodge_requested: bool = false
var command_sequence: int = 0

var fixed_clock
var content_registry
var proxy_runtime
var destiny_forge
var save_store
var startup_errors: Array[String] = []
var proxy_prediction: String = "unknown"
var last_proxy_failure: Dictionary = {}
var contract_wins: int = 0
var last_drop_id: String = ""
var last_drop: String = "None"
var last_loot_rng_state: Dictionary = {}
var last_save_message: String = "No save yet"
var command_line_arguments: PackedStringArray = []
var test_session: bool = false
var state_hash_output_path: String = ""

var base_panel: VBoxContainer
var hud_panel: VBoxContainer
var model_label: Label
var boss_label: Label
var report_label: Label
var return_button: Button
var systems_panel: VBoxContainer
var content_status_label: Label
var progress_label: Label
var proxy_status_label: Label
var forge_status_label: Label
var preset_buttons: Dictionary = {}
var mode_buttons: Dictionary = {}
var forge_buttons: Array[Button] = []
var automation_smoke: bool = false


func _ready() -> void:
	command_line_arguments = OS.get_cmdline_user_args()
	test_session = command_line_arguments.has("--smoke") or command_line_arguments.has("--auto-smoke")
	for argument: String in command_line_arguments:
		if argument.begins_with("--state-hash-out="):
			state_hash_output_path = argument.trim_prefix("--state-hash-out=")
	_initialize_runtime()
	_build_ui()
	_show_base()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	queue_redraw()
	_handle_command_line()


func _process(delta: float) -> void:
	if not in_arena:
		return
	_update_traces(delta)
	var ticks_to_run: int = fixed_clock.consume_frame(delta)
	for _index in ticks_to_run:
		if battle_over:
			break
		_simulate_tick()
	_update_hud()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not in_arena or battle_over:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SHIFT or event.keycode == KEY_CTRL:
			dodge_requested = true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		dodge_requested = true


func _initialize_runtime() -> void:
	fixed_clock = FixedTickClockScript.new(SIM_TICKS_PER_SECOND)
	content_registry = ContentRegistryScript.new()
	startup_errors = content_registry.load_all()
	proxy_runtime = ProxyRuntimeScript.new()
	proxy_runtime.install_white_proxy("nearest_enemy", "piercing_arrow")
	proxy_prediction = proxy_runtime.predict({
		"perception": {"target_count": 1},
		"movement": {"pathing": 1.0, "range_control": 1.0},
		"execution": {"skill_count": 1, "timing": 1.0},
		"memory": {"target_memory": 1, "rotation_steps": 1},
	})
	var forge_families: Array[Dictionary] = [
		{"name": "growth_probability", "weight": 1},
		{"name": "shared_lifetime", "weight": 2},
		{"name": "branch_count", "weight": 2},
		{"name": "payload", "weight": 3},
		{"name": "flight_speed", "weight": 3},
		{"name": "turn_time", "weight": 1},
	]
	destiny_forge = DestinyForgeScript.new(FATE_SEED, forge_families, 3)
	destiny_forge.set_dice(DestinyForgeScript.TRACK_ADD, 6)
	save_store = SaveStoreScript.new()
	if not test_session:
		_load_progress()


func _load_progress() -> void:
	var loaded: Dictionary = save_store.load_latest()
	if not bool(loaded.get("ok", false)):
		last_save_message = "Fresh profile — save begins after a reward or forge choice"
		return
	var payload: Variant = loaded.get("payload", {})
	if not (payload is Dictionary) or int((payload as Dictionary).get("sim_protocol_version", -1)) != SAVE_PROTOCOL_VERSION:
		last_save_message = "Save ignored: incompatible simulation protocol"
		return
	var saved: Dictionary = payload
	contract_wins = maxi(0, int(saved.get("contract_wins", 0)))
	last_drop_id = String(saved.get("last_drop_id", ""))
	last_drop = String(saved.get("last_drop", "None"))
	var saved_loot_state: Variant = saved.get("last_loot_rng_state", {})
	if saved_loot_state is Dictionary:
		last_loot_rng_state = saved_loot_state.duplicate(true)
	var saved_preset := _normalize_preset_id(String(saved.get("selected_preset", selected_preset)))
	var saved_mode := String(saved.get("selected_mode", selected_mode))
	if content_registry.presets.has(saved_preset):
		selected_preset = saved_preset
	if saved_mode in ["Manual", "Auto"]:
		selected_mode = saved_mode
	var forge_state: Variant = saved.get("forge", {})
	if forge_state is Dictionary and not (forge_state as Dictionary).is_empty():
		if not destiny_forge.restore_state(forge_state):
			startup_errors.append("save: invalid forge state")
	last_save_message = "Recovered generation %d from slot %s (no offline progress)" % [int(loaded.generation), String(loaded.slot).to_upper()]


func _save_progress(reason: String) -> void:
	if test_session:
		return
	var result: Dictionary = save_store.save({
		"content_hash": _content_hash(),
		"contract_wins": contract_wins,
		"forge": destiny_forge.state(),
		"last_drop": last_drop,
		"last_drop_id": last_drop_id,
		"last_loot_rng_state": last_loot_rng_state,
		"offline_progress": 0,
		"selected_mode": selected_mode,
		"selected_preset": selected_preset,
		"sim_protocol_version": SAVE_PROTOCOL_VERSION,
	})
	if bool(result.get("ok", false)):
		last_save_message = "%s — generation %d / slot %s" % [reason, int(result.generation), String(result.slot).to_upper()]
	else:
		last_save_message = "SAVE FAILED: %s" % String(result.get("error", "unknown error"))


func _content_hash() -> String:
	var source := FileAccess.get_file_as_string(ContentRegistryScript.PROXY_PATH)
	source += "\n" + FileAccess.get_file_as_string(ContentRegistryScript.PRESET_PATH)
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return "unavailable"
	if context.update(source.to_utf8_buffer()) != OK:
		return "unavailable"
	return context.finish().hex_encode()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	base_panel = VBoxContainer.new()
	base_panel.position = Vector2(64.0, 54.0)
	base_panel.custom_minimum_size = Vector2(510.0, 0.0)
	layer.add_child(base_panel)
	var title := Label.new()
	title.text = "RANGER // PIERCING ARROW LAB"
	title.add_theme_font_size_override("font_size", 28)
	base_panel.add_child(title)
	var intro := Label.new()
	var preset_values: Array[String] = []
	for preset_id in content_registry.preset_order:
		preset_values.append("%.2f" % float(content_registry.presets[preset_id].p))
	intro.text = "Base p=.25. Diagnostic IVs come from validated content:\n%s; equipped parameters yield g=80.\nChoose a growth preset and pilot; configuration locks on deployment." % " / ".join(preset_values)
	base_panel.add_child(intro)
	base_panel.add_child(_section_label("GROWTH PRESET"))
	var preset_row := HBoxContainer.new()
	base_panel.add_child(preset_row)
	for preset: String in content_registry.preset_order:
		var button := Button.new()
		var preset_data: Dictionary = content_registry.presets[preset]
		var p_value := float(preset_data.p)
		var iv_note: String = "R<1" if p_value < 0.5 else ("R=1" if is_equal_approx(p_value, 0.5) else "R>1")
		button.text = "%s / %s\np=%.2f • %s" % [preset.capitalize(), String(preset_data.name), p_value, iv_note]
		button.tooltip_text = "Loaded from ranger_presets.json"
		button.toggle_mode = true
		button.pressed.connect(_select_preset.bind(preset))
		preset_row.add_child(button)
		preset_buttons[preset] = button
	base_panel.add_child(_section_label("PILOT"))
	var mode_row := HBoxContainer.new()
	base_panel.add_child(mode_row)
	for mode: String in ["Manual", "Auto"]:
		var button := Button.new()
		button.text = mode
		button.toggle_mode = true
		button.pressed.connect(_select_mode.bind(mode))
		mode_row.add_child(button)
		mode_buttons[mode] = button
	var controls := Label.new()
	controls.text = "Manual: WASD move • Space / Left click Skill 1 • Shift / Ctrl / Right click dodge\nAuto: nearest target • approach range • Skill 1 only"
	base_panel.add_child(controls)
	var start_button := Button.new()
	start_button.text = "DEPLOY"
	start_button.custom_minimum_size = Vector2(0.0, 48.0)
	start_button.pressed.connect(_enter_arena)
	base_panel.add_child(start_button)

	systems_panel = VBoxContainer.new()
	systems_panel.position = Vector2(650.0, 54.0)
	systems_panel.custom_minimum_size = Vector2(580.0, 0.0)
	layer.add_child(systems_panel)
	var systems_title := Label.new()
	systems_title.text = "CONTRACT SYSTEMS // LIVE"
	systems_title.add_theme_font_size_override("font_size", 24)
	systems_panel.add_child(systems_title)
	content_status_label = Label.new()
	content_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_status_label.custom_minimum_size = Vector2(570.0, 0.0)
	systems_panel.add_child(content_status_label)
	systems_panel.add_child(_section_label("WHITE PROXY LOADOUT"))
	proxy_status_label = Label.new()
	proxy_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	proxy_status_label.custom_minimum_size = Vector2(570.0, 0.0)
	systems_panel.add_child(proxy_status_label)
	systems_panel.add_child(_section_label("DESTINY FORGE // ADD TRACK"))
	forge_status_label = Label.new()
	forge_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	forge_status_label.custom_minimum_size = Vector2(570.0, 0.0)
	systems_panel.add_child(forge_status_label)
	var forge_row := HBoxContainer.new()
	systems_panel.add_child(forge_row)
	for choice_number in range(1, 4):
		var forge_button := Button.new()
		forge_button.custom_minimum_size = Vector2(185.0, 58.0)
		forge_button.pressed.connect(_choose_forge_candidate.bind(choice_number))
		forge_row.add_child(forge_button)
		forge_buttons.append(forge_button)
	systems_panel.add_child(_section_label("PERSISTENT CONTRACT RECORD"))
	progress_label = Label.new()
	progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress_label.custom_minimum_size = Vector2(570.0, 0.0)
	systems_panel.add_child(progress_label)
	var reward_note := Label.new()
	reward_note.text = "Manual Hunter Cache: deterministic 35% chance for +1 extra Fate Die.\nAuto and Manual never run simultaneously. Closing the game grants nothing."
	reward_note.add_theme_color_override("font_color", Color("c7aee8"))
	systems_panel.add_child(reward_note)

	hud_panel = VBoxContainer.new()
	hud_panel.position = Vector2(22.0, 16.0)
	hud_panel.custom_minimum_size = Vector2(430.0, 0.0)
	layer.add_child(hud_panel)
	model_label = Label.new()
	model_label.add_theme_font_size_override("font_size", 18)
	hud_panel.add_child(model_label)
	boss_label = Label.new()
	hud_panel.add_child(boss_label)
	report_label = Label.new()
	report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_label.custom_minimum_size = Vector2(430.0, 0.0)
	hud_panel.add_child(report_label)
	return_button = Button.new()
	return_button.text = "ABANDON / RETURN TO BASE"
	return_button.pressed.connect(_show_base)
	hud_panel.add_child(return_button)


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = "\n%s" % text
	label.add_theme_color_override("font_color", Color("71d8c6"))
	return label


func _select_preset(preset: String) -> void:
	if not in_arena and content_registry.presets.has(preset):
		selected_preset = preset
		_refresh_base_buttons()


func _select_mode(mode: String) -> void:
	if not in_arena:
		selected_mode = mode
		_refresh_base_buttons()


func _refresh_base_buttons() -> void:
	for preset: String in preset_buttons:
		(preset_buttons[preset] as Button).button_pressed = preset == selected_preset
	for mode: String in mode_buttons:
		(mode_buttons[mode] as Button).button_pressed = mode == selected_mode
	_refresh_system_panel()


func _normalize_preset_id(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	if content_registry.presets.has(normalized):
		return normalized
	# One-way compatibility for saves created by the earliest prototype.
	for preset_id in content_registry.preset_order:
		if String(content_registry.presets[preset_id].name).to_lower() == normalized:
			return preset_id
	return selected_preset


func _preset_display_name(preset_id: String) -> String:
	if not content_registry.presets.has(preset_id):
		return preset_id
	return "%s / %s" % [preset_id.capitalize(), String(content_registry.presets[preset_id].name)]


func _refresh_system_panel() -> void:
	if systems_panel == null:
		return
	if startup_errors.is_empty():
		content_status_label.text = "CONTENT OK  •  16 cores  •  10 attachments  •  16 firmware  •  schema v1"
		content_status_label.add_theme_color_override("font_color", Color("71d8c6"))
	else:
		content_status_label.text = "CONTENT BLOCKED: %s" % "; ".join(startup_errors)
		content_status_label.add_theme_color_override("font_color", Color("ff6b78"))
	var white_names: Array[String] = []
	for id in ["near_enemy_horizon", "direct_gait", "single_key_execution", "short_trace_memory"]:
		if content_registry.cores.has(id):
			white_names.append(String(content_registry.cores[id].name))
	proxy_status_label.text = "%s\nPrediction: %s. Auto may target nearest enemy and press Skill 1 only." % [" + ".join(white_names), proxy_prediction.to_upper()]
	var active_slot: int = _next_empty_forge_slot()
	var dice: int = destiny_forge.get_dice(DestinyForgeScript.TRACK_ADD)
	var equipped: Array[String] = []
	for affix in destiny_forge.affixes:
		if affix.is_empty():
			equipped.append("—")
		else:
			equipped.append("%s T%d" % [_forge_family_name(String(affix.family)), int(affix.tier)])
	forge_status_label.text = "Seed %d is saved. Candidate #n costs n dice; choosing advances the track.\nFate Dice: %d  •  slots: %s" % [FATE_SEED, dice, " | ".join(equipped)]
	var candidates: Array[Dictionary] = [] if active_slot < 0 else destiny_forge.preview(DestinyForgeScript.TRACK_ADD, active_slot, 3)
	for index in forge_buttons.size():
		var button: Button = forge_buttons[index]
		if index < candidates.size():
			var candidate: Dictionary = candidates[index]
			button.text = "#%d / COST %d\n%s T%d" % [index + 1, int(candidate.cost), String(FORGE_FAMILY_SHORT.get(String(candidate.family), candidate.family)), int(candidate.tier)]
			button.disabled = in_arena or not startup_errors.is_empty()
		else:
			button.text = "#%d\nLOCKED" % (index + 1)
			button.disabled = true
	progress_label.text = "Victories: %d  •  Last drop: %s\n%s" % [contract_wins, last_drop, last_save_message]


func _forge_family_name(family: String) -> String:
	return String(FORGE_FAMILY_LABELS.get(family, family))


func _next_empty_forge_slot() -> int:
	for index in destiny_forge.affixes.size():
		if (destiny_forge.affixes[index] as Dictionary).is_empty():
			return index
	return -1


func _choose_forge_candidate(choice_number: int) -> void:
	if in_arena or not startup_errors.is_empty():
		return
	var active_slot := _next_empty_forge_slot()
	if active_slot < 0:
		last_save_message = "All three prototype affix slots are filled"
		_refresh_system_panel()
		return
	var chosen: Dictionary = destiny_forge.choose(DestinyForgeScript.TRACK_ADD, active_slot, choice_number)
	if bool(chosen.get("ok", false)):
		var result: Dictionary = chosen.result
		last_drop = "Forged %s T%d" % [_forge_family_name(String(result.family)), int(result.tier)]
		_save_progress("Forge choice #%d committed" % choice_number)
	else:
		last_save_message = "Forge refused: %s" % String(chosen.get("error", "unknown error"))
	_refresh_system_panel()


func _show_base() -> void:
	in_arena = false
	battle_over = false
	if proxy_runtime != null:
		proxy_runtime.end_contract()
	base_panel.visible = true
	systems_panel.visible = true
	hud_panel.visible = false
	_refresh_base_buttons()
	queue_redraw()


func _enter_arena() -> void:
	if not startup_errors.is_empty():
		last_save_message = "Deployment blocked by content validation"
		_refresh_system_panel()
		return
	proxy_runtime.end_contract()
	proxy_runtime.install_white_proxy("nearest_enemy", "piercing_arrow")
	var contract_start: Dictionary = proxy_runtime.begin_contract(selected_mode.to_lower())
	if not bool(contract_start.get("ok", false)):
		last_save_message = "Deployment blocked: %s" % String(contract_start.get("error", "unknown error"))
		_refresh_system_panel()
		return
	var requirements := {
		"perception": {"target_count": 1},
		"movement": {"pathing": 1.0, "range_control": 1.0},
		"execution": {"skill_count": 1, "timing": 1.0},
		"memory": {"target_memory": 1, "rotation_steps": 1},
	}
	proxy_prediction = proxy_runtime.predict(requirements) if selected_mode == "Auto" else "manual"
	locked_p = float(content_registry.presets[selected_preset].p)
	in_arena = true
	battle_over = false
	base_panel.visible = false
	systems_panel.visible = false
	hud_panel.visible = true
	return_button.visible = true
	player_position = _arena_rect().get_center() + Vector2(-220.0, 100.0)
	player_health = 100.0
	attack_cooldown_ticks = 0
	dodge_cooldown_ticks = 0
	dodge_remaining_ticks = 0
	dodge_requested = false
	command_sequence = 0
	last_proxy_failure = {}
	sim_tick = 0
	elapsed = 0.0
	fixed_clock.reset()
	shots = 0
	defeated = 0
	battle_report = "Deployed: %s / %s. Proxy mode and loadout are locked for this contract." % [_preset_display_name(selected_preset), selected_mode]
	boss_damage = BigValue.from_float(0.0)
	_spawn_wave()
	_update_hud()
	queue_redraw()


func _spawn_wave() -> void:
	enemies.clear()
	traces.clear()
	var center: Vector2 = _arena_rect().get_center()
	var offsets: Array[Vector2] = [Vector2(-70.0, -150.0), Vector2(115.0, -125.0), Vector2(210.0, 25.0), Vector2(125.0, 150.0), Vector2(-65.0, 165.0), Vector2(-210.0, -45.0)]
	for offset: Vector2 in offsets:
		enemies.append(EnemyData.new(center + offset, 72.0))
	boss = EnemyData.new(center + Vector2(250.0, -40.0), 1200.0, true)
	enemies.append(boss)


func _simulate_tick() -> void:
	sim_tick += 1
	elapsed = float(sim_tick) / float(SIM_TICKS_PER_SECOND)
	attack_cooldown_ticks = maxi(0, attack_cooldown_ticks - 1)
	dodge_cooldown_ticks = maxi(0, dodge_cooldown_ticks - 1)
	if dodge_remaining_ticks > 0:
		dodge_remaining_ticks -= 1
	var commands: Array[Dictionary] = _auto_commands() if selected_mode == "Auto" else _manual_commands()
	commands.sort_custom(_command_precedes)
	var movement := Vector2.ZERO
	var speed_scale := 1.0
	for command in commands:
		match String(command.get("type", "")):
			"move":
				movement = Vector2(float(command.get("x", 0)), float(command.get("y", 0))).normalized()
				speed_scale = float(command.get("speed_scale", 1.0))
			"dodge":
				_start_dodge_from_command(movement)
			"cast_skill_1":
				_cast_skill_one()
	_advance_player_tick(movement, speed_scale)
	_update_enemies_tick()
	_check_battle_end()
	if automation_smoke and not battle_over and sim_tick >= SIM_TICKS_PER_SECOND * 180:
		printerr("AUTO_SMOKE_FAIL timeout ticks=%d casts=%d" % [sim_tick, shots])
		Engine.time_scale = 1.0
		get_tree().quit(1)


func _manual_commands() -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	var direction := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	).normalized()
	if direction != Vector2.ZERO:
		commands.append(_command("move", {"x": direction.x, "y": direction.y}))
	if dodge_requested:
		commands.append(_command("dodge"))
	dodge_requested = false
	if Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		commands.append(_command("cast_skill_1"))
	return commands


func _auto_commands() -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	var target: EnemyData = _nearest_enemy()
	if target == null:
		return commands
	var toward: Vector2 = target.position - player_position
	var distance: float = toward.length()
	if distance > AUTO_RANGE * 0.82:
		var direction := toward.normalized()
		commands.append(_command("move", {"x": direction.x, "y": direction.y, "speed_scale": 0.72}))
	if distance <= AUTO_RANGE:
		var pipeline_result: Dictionary = proxy_runtime.run_pipeline({
			"candidate_actions": ["cast_skill_1"],
			"cooldowns": {"skill_1_ticks": attack_cooldown_ticks},
			"in_range": true,
			"path_blocked": false,
			"requested_skill": "piercing_arrow",
			"requested_target": "nearest_enemy",
			"resources": {"arrows": "unlimited"},
			"rotation_steps": 1,
			"skill_ready": attack_cooldown_ticks == 0,
			"tick": sim_tick,
			"visible_state": {"distance_millipixels": roundi(distance * 1000.0)},
			"visible_targets": ["nearest_enemy"],
		})
		if bool(pipeline_result.get("ok", false)):
			commands.append(_command("cast_skill_1"))
		else:
			last_proxy_failure = pipeline_result.get("failure", {}).duplicate(true)
	return commands


func _command(type: String, fields: Dictionary = {}) -> Dictionary:
	var result := {
		"actor_id": "ranger",
		"sequence": command_sequence,
		"tick": sim_tick,
		"type": type,
	}
	command_sequence += 1
	for key in fields:
		result[key] = fields[key]
	return result


func _command_precedes(left: Dictionary, right: Dictionary) -> bool:
	if int(left.tick) != int(right.tick):
		return int(left.tick) < int(right.tick)
	if String(left.actor_id) != String(right.actor_id):
		return String(left.actor_id) < String(right.actor_id)
	return int(left.sequence) < int(right.sequence)


func _start_dodge_from_command(input_direction: Vector2) -> void:
	if selected_mode != "Manual" or dodge_cooldown_ticks > 0:
		return
	dodge_direction = input_direction if input_direction != Vector2.ZERO else player_facing
	dodge_remaining_ticks = DODGE_DURATION_TICKS
	dodge_cooldown_ticks = DODGE_COOLDOWN_TICKS


func _advance_player_tick(direction: Vector2, speed_scale: float) -> void:
	if dodge_remaining_ticks > 0:
		player_position += dodge_direction * DODGE_SPEED * SIM_STEP_SECONDS
	elif direction != Vector2.ZERO:
		player_facing = direction
		player_position += direction * PLAYER_SPEED * speed_scale * SIM_STEP_SECONDS
	player_position = _quantize_position(_clamp_to_arena(player_position, 14.0))


func _cast_skill_one() -> void:
	if attack_cooldown_ticks > 0:
		return
	var target: EnemyData = _nearest_enemy()
	if target == null or player_position.distance_to(target.position) > AUTO_RANGE:
		return
	attack_cooldown_ticks = ATTACK_COOLDOWN_TICKS
	shots += 1
	player_facing = player_position.direction_to(target.position)
	var model: Dictionary = _current_model()
	var events: float = float(model["total_events_float"])
	var aggregate_damage: BigValue = (model["total_events"] as BigValue).multiply(BigValue.from_float(BASE_PAYLOAD))
	if target.is_boss:
		boss_damage = boss_damage.add(aggregate_damage)
		if boss_damage.compare(boss_maximum) >= 0:
			target.health = 0.0
	else:
		target.health -= BASE_PAYLOAD * events
	_add_representative_traces(target.position, int(model["g"]))
	battle_report = "Skill 1: %s events × %.0f payload → %s aggregate damage." % [(model["total_events"] as BigValue).to_short_string(4), BASE_PAYLOAD, aggregate_damage.to_short_string(4)]
	if target.health <= 0.0:
		defeated += 1
		enemies.erase(target)


func _add_representative_traces(target_position: Vector2, generations: int) -> void:
	traces.append(ArrowTrace.new(player_position, target_position))
	var representatives: int = mini(3, maxi(0, generations))
	for index: int in representatives:
		var angle: float = -0.18 + 0.18 * float(index)
		var branch_end: Vector2 = target_position + player_facing.rotated(angle + 1.1) * (28.0 + 8.0 * index)
		traces.append(ArrowTrace.new(target_position, branch_end))


func _update_enemies_tick() -> void:
	for enemy: EnemyData in enemies:
		var distance: float = enemy.position.distance_to(player_position)
		var contact: float = 27.0 if enemy.is_boss else 19.0
		if distance > contact:
			var speed: float = 42.0 if enemy.is_boss else 62.0
			enemy.position = _quantize_position(enemy.position + enemy.position.direction_to(player_position) * speed * SIM_STEP_SECONDS)
		elif dodge_remaining_ticks <= 0:
			player_health = snappedf(maxf(0.0, player_health - (0.6 if enemy.is_boss else 8.0) * SIM_STEP_SECONDS), 0.001)


func _quantize_position(value: Vector2) -> Vector2:
	# Authority stores a 1/1000-pixel grid. Rendering may interpolate later, but
	# identical whole-tick commands always land on identical coordinates.
	return Vector2(snappedf(value.x, 0.001), snappedf(value.y, 0.001))


func _update_traces(delta: float) -> void:
	for index: int in range(traces.size() - 1, -1, -1):
		traces[index].remaining -= delta
		if traces[index].remaining <= 0.0:
			traces.remove_at(index)


func _check_battle_end() -> void:
	if boss != null and boss.health <= 0.0:
		battle_over = true
		var reward_summary := _grant_victory_reward()
		battle_report = "VICTORY — Boss defeated in %.1fs, %d casts, %d targets. %s" % [elapsed, shots, defeated, reward_summary]
		return_button.visible = true
		if automation_smoke:
			if contract_wins != 1 or destiny_forge.get_dice(DestinyForgeScript.TRACK_ADD) != 7 or last_drop_id.is_empty() or proxy_prediction != "stable":
				printerr("AUTO_SMOKE_FAIL integrated reward/proxy state is invalid")
				Engine.time_scale = 1.0
				get_tree().quit(1)
				return
			var state_hash := _semantic_state_hash("victory")
			if not _write_state_hash(state_hash):
				Engine.time_scale = 1.0
				get_tree().quit(1)
				return
			print("AUTO_SMOKE_PASS elapsed=%.2f ticks=%d casts=%d damage=%s state_hash=%s" % [elapsed, sim_tick, shots, boss_damage.to_short_string(5), state_hash])
			Engine.time_scale = 1.0
			get_tree().quit(0)
	elif player_health <= 0.0:
		battle_over = true
		battle_report = "DEFEAT — The ranger fell after %.1fs. Refit at base." % elapsed
		return_button.visible = true
		if automation_smoke:
			printerr("AUTO_SMOKE_FAIL elapsed=%.2f casts=%d" % [elapsed, shots])
			Engine.time_scale = 1.0
			get_tree().quit(1)


func _grant_victory_reward() -> String:
	contract_wins += 1
	var core_ids: Array = content_registry.core_ids()
	core_ids.sort()
	var reward_rng = DeterministicRngScript.create(FATE_SEED, "contract_drop/%d" % contract_wins)
	last_drop_id = String(core_ids[reward_rng.next_int(core_ids.size())])
	var drop_data: Dictionary = content_registry.cores[last_drop_id]
	last_drop = "%s [%s]" % [String(drop_data.name), String(drop_data.slot)]
	var dice_awarded := 1
	var bonus_text := ""
	if selected_mode == "Manual" and reward_rng.next_float() < MANUAL_BONUS_CHANCE:
		dice_awarded += 1
		bonus_text = " Manual Hunter Cache triggered."
	last_loot_rng_state = reward_rng.export_state()
	destiny_forge.grant_dice(DestinyForgeScript.TRACK_ADD, dice_awarded)
	_save_progress("Contract reward saved")
	return "Drop: %s; +%d Fate Die.%s No timer; no regeneration." % [last_drop, dice_awarded, bonus_text]


func _semantic_state_hash(result: String) -> String:
	var enemy_state: Array[Dictionary] = []
	for index in enemies.size():
		var enemy: EnemyData = enemies[index]
		enemy_state.append({
			"boss": enemy.is_boss,
			"health_milli": roundi(enemy.health * 1000.0),
			"index": index,
			"x_millipixels": roundi(enemy.position.x * 1000.0),
			"y_millipixels": roundi(enemy.position.y * 1000.0),
		})
	var state := {
		"boss_damage": {
			"layer": boss_damage.layer,
			"magnitude": String.num(boss_damage.magnitude, 12),
		},
		"boss_health_milli": roundi(boss.health * 1000.0),
		"boss_x_millipixels": roundi(boss.position.x * 1000.0),
		"boss_y_millipixels": roundi(boss.position.y * 1000.0),
		"casts": shots,
		"command_sequence": command_sequence,
		"content_hash": _content_hash(),
		"contract_wins": contract_wins,
		"cooldowns": {
			"attack": attack_cooldown_ticks,
			"dodge": dodge_cooldown_ticks,
			"dodge_remaining": dodge_remaining_ticks,
		},
		"defeated": defeated,
		"enemies": enemy_state,
		"forge": destiny_forge.state(),
		"last_drop": last_drop,
		"last_drop_id": last_drop_id,
		"last_loot_rng_state": last_loot_rng_state,
		"last_proxy_failure": last_proxy_failure,
		"mode": selected_mode.to_lower(),
		"p_basis_points": roundi(locked_p * 100.0),
		"player_health_milli": roundi(player_health * 1000.0),
		"player_x_millipixels": roundi(player_position.x * 1000.0),
		"player_y_millipixels": roundi(player_position.y * 1000.0),
		"proxy_mode": proxy_runtime.mode,
		"proxy_mode_locked": proxy_runtime.mode_locked,
		"proxy_prediction": proxy_prediction,
		"result": result,
		"sim_protocol_version": SAVE_PROTOCOL_VERSION,
		"tick": sim_tick,
	}
	var canonical := SaveStoreScript.canonical_json(state)
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(canonical.to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


func _write_state_hash(state_hash: String) -> bool:
	if state_hash.is_empty():
		printerr("STATE_HASH_FAIL: could not calculate hash")
		return false
	if state_hash_output_path.is_empty():
		return true
	var output_path := state_hash_output_path
	if not output_path.is_absolute_path() and not output_path.begins_with("user://") and not output_path.begins_with("res://"):
		output_path = ProjectSettings.globalize_path("res://" + output_path)
	var output_directory := output_path.get_base_dir()
	if not output_directory.is_empty():
		var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
		if directory_error != OK:
			printerr("STATE_HASH_FAIL: %s" % error_string(directory_error))
			return false
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		printerr("STATE_HASH_FAIL: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(state_hash + "\n")
	file.close()
	return true


func _current_model() -> Dictionary:
	var equipped: Dictionary = content_registry.preset_equipped_parameters
	return PiercingArrowModel.evaluate(
		locked_p,
		float(equipped.shared_lifetime),
		float(equipped.distance),
		float(equipped.speed),
		float(equipped.minimum_turn_time),
		true,
		true
	)


func _update_hud() -> void:
	var model: Dictionary = _current_model()
	var total: BigValue = model["total_events"] as BigValue
	model_label.text = "PIERCING ARROW  p=%.2f  R=%.2f  g=%d  Δt=d/v+τ=%.3fs\n%s  |  ΣR^k = %s  |  %s (LOCKED)  |  AUTHORITY 30 TICK" % [float(model["p"]), float(model["R"]), int(model["g"]), float(model["generation_time"]), str(model["state"]).to_upper(), total.to_short_string(4), selected_mode.to_upper()]
	var remaining: BigValue = _boss_remaining_display()
	boss_label.text = "Ranger HP %3.0f / 100    Boss HP ≈ %s / %s    Dodge %.1fs\nDamage accumulated: %s  •  tick %d  •  no regeneration  •  no time limit" % [player_health, remaining.to_short_string(4), boss_maximum.to_short_string(4), float(dodge_cooldown_ticks) / SIM_TICKS_PER_SECOND, boss_damage.to_short_string(4), sim_tick]
	var proxy_line := "Manual command stream; no automation process is running."
	if selected_mode == "Auto":
		proxy_line = "Proxy %s; pipeline OK." % proxy_prediction.to_upper()
		if not last_proxy_failure.is_empty():
			proxy_line = "Proxy %s; last refusal at tick %d [%s]: %s" % [proxy_prediction.to_upper(), int(last_proxy_failure.get("tick", sim_tick)), String(last_proxy_failure.get("category", "unknown")), String(last_proxy_failure.get("reason", "unknown"))]
	report_label.text = "%s\n%s" % [battle_report, proxy_line]


func _boss_remaining_display() -> BigValue:
	# Actual defeat uses BigValue.compare(). This subtraction is display-only;
	# the current 10^12 target and accumulated damage remain ordinary layer 0.
	if boss_damage.compare(boss_maximum) >= 0:
		return BigValue.from_float(0.0)
	if boss_damage.layer == 0 and boss_maximum.layer == 0:
		return BigValue.from_float(maxf(0.0, boss_maximum.magnitude - boss_damage.magnitude))
	return boss_maximum.duplicate_value()


func _nearest_enemy() -> EnemyData:
	var nearest: EnemyData
	var best_distance: float = INF
	for enemy: EnemyData in enemies:
		if enemy.health <= 0.0:
			continue
		var distance: float = player_position.distance_squared_to(enemy.position)
		if distance < best_distance:
			best_distance = distance
			nearest = enemy
	return nearest


func _arena_rect() -> Rect2:
	var size: Vector2 = get_viewport_rect().size
	const HUD_CLEARANCE: float = 190.0
	return Rect2(Vector2(ARENA_MARGIN, HUD_CLEARANCE), Vector2(maxf(400.0, size.x - ARENA_MARGIN * 2.0), maxf(280.0, size.y - HUD_CLEARANCE - ARENA_MARGIN)))


func _clamp_to_arena(value: Vector2, padding: float) -> Vector2:
	var rect: Rect2 = _arena_rect().grow(-padding)
	return Vector2(clampf(value.x, rect.position.x, rect.end.x), clampf(value.y, rect.position.y, rect.end.y))


func _on_viewport_size_changed() -> void:
	if in_arena:
		player_position = _clamp_to_arena(player_position, 14.0)
	queue_redraw()


func _handle_command_line() -> void:
	if command_line_arguments.has("--smoke"):
		if not startup_errors.is_empty() or destiny_forge.preview(DestinyForgeScript.TRACK_ADD, 0, 3).size() != 3:
			printerr("SCENE_SMOKE_FAIL systems=%s" % str(startup_errors))
			get_tree().quit(1)
			return
		print("SCENE_SMOKE_PASS systems=content,forge,proxy,save fixed_tick=%d" % SIM_TICKS_PER_SECOND)
		get_tree().create_timer(0.25).timeout.connect(func() -> void: get_tree().quit(0))
	if command_line_arguments.has("--auto-smoke"):
		automation_smoke = true
		selected_preset = "exponential"
		selected_mode = "Auto"
		_enter_arena()
		if not in_arena:
			printerr("AUTO_SMOKE_FAIL deployment blocked")
			get_tree().quit(1)
			return
		Engine.time_scale = 20.0
	for argument: String in command_line_arguments:
		if argument.begins_with("--capture="):
			_capture_frame.call_deferred(argument.trim_prefix("--capture="))


func _capture_frame(path: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error: Error = get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		printerr("CAPTURE_FAIL %s: %s" % [path, error_string(error)])
		get_tree().quit(1)
		return
	print("CAPTURE_PASS %s" % path)
	get_tree().quit(0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color("0b1020"))
	if not in_arena:
		_draw_base_backdrop()
		return
	var rect: Rect2 = _arena_rect()
	draw_rect(rect, Color("151d31"))
	for x: int in range(int(rect.position.x), int(rect.end.x), 32):
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color("1d2942"), 1.0)
	for y: int in range(int(rect.position.y), int(rect.end.y), 32):
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color("1d2942"), 1.0)
	draw_rect(rect, Color("48708a"), false, 3.0)
	for enemy: EnemyData in enemies:
		_draw_enemy(enemy)
	_draw_player()
	for trace: ArrowTrace in traces:
		var alpha: float = clampf(trace.remaining / 0.18, 0.0, 1.0)
		draw_line(trace.from, trace.to, Color(1.0, 0.86, 0.35, alpha), 3.0)
		draw_circle(trace.to, 3.0, Color(1.0, 0.96, 0.65, alpha))


func _draw_base_backdrop() -> void:
	var size: Vector2 = get_viewport_rect().size
	for y: int in range(0, int(size.y), 24):
		var width: float = 120.0 + float((y / 24) % 5) * 42.0
		draw_rect(Rect2(Vector2(size.x - width, y), Vector2(width, 12.0)), Color("101b32"))
	draw_circle(Vector2(size.x * 0.85, size.y * 0.82), 92.0, Color("162842"))
	draw_circle(Vector2(size.x * 0.85, size.y * 0.82), 61.0, Color("0b1020"))
	draw_line(Vector2(size.x * 0.79, size.y * 0.89), Vector2(size.x * 0.91, size.y * 0.75), Color("71d8c6"), 7.0)


func _draw_player() -> void:
	var color: Color = Color("ffffff") if dodge_remaining_ticks > 0 else Color("58d6b5")
	draw_rect(Rect2(player_position - Vector2(9.0, 11.0), Vector2(18.0, 22.0)), color)
	draw_rect(Rect2(player_position + Vector2(-5.0, -17.0), Vector2(10.0, 7.0)), Color("ccefe6"))
	draw_line(player_position, player_position + player_facing * 19.0, Color("f2bf4b"), 3.0)


func _draw_enemy(enemy: EnemyData) -> void:
	if enemy.is_boss:
		draw_rect(Rect2(enemy.position - Vector2(22.0, 22.0), Vector2(44.0, 44.0)), Color("bd4160"))
		draw_rect(Rect2(enemy.position - Vector2(28.0, 31.0), Vector2(56.0, 6.0)), Color("35172a"))
		var ratio: float = clampf(enemy.health / enemy.maximum_health, 0.0, 1.0)
		draw_rect(Rect2(enemy.position - Vector2(28.0, 31.0), Vector2(56.0 * ratio, 6.0)), Color("ff6b78"))
		draw_rect(Rect2(enemy.position + Vector2(-13.0, -29.0), Vector2(8.0, 8.0)), Color("f7cf68"))
		draw_rect(Rect2(enemy.position + Vector2(5.0, -29.0), Vector2(8.0, 8.0)), Color("f7cf68"))
	else:
		draw_rect(Rect2(enemy.position - Vector2(10.0, 10.0), Vector2(20.0, 20.0)), Color("9164d8"))
		draw_rect(Rect2(enemy.position + Vector2(-4.0, -5.0), Vector2(3.0, 3.0)), Color("f4e5ff"))
		draw_rect(Rect2(enemy.position + Vector2(2.0, -5.0), Vector2(3.0, 3.0)), Color("f4e5ff"))
