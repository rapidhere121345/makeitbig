extends Node2D

const ContentRegistryScript = preload("res://src/content/content_registry.gd")
const DestinyForgeScript = preload("res://src/systems/destiny_forge.gd")
const DeterministicRngScript = preload("res://src/core/deterministic_rng.gd")
const FixedTickClockScript = preload("res://src/core/fixed_tick_clock.gd")
const ProxyRuntimeScript = preload("res://src/systems/proxy_runtime.gd")
const ProxyDecisionScript = preload("res://src/systems/proxy_decision.gd")
const CombatCommandProtocolScript = preload("res://src/systems/combat_command_protocol.gd")
const ManualCombatInputScript = preload("res://src/systems/manual_combat_input.gd")
const ManualAimResolverScript = preload("res://src/systems/manual_aim_resolver.gd")
const PlayerActionTimelineScript = preload("res://src/systems/player_action_timeline.gd")
const EnemyTacticsScript = preload("res://src/systems/enemy_tactics.gd")
const WalkableGeometryScript = preload("res://src/systems/walkable_geometry.gd")
const CombatEventStreamScript = preload("res://src/systems/combat_event_stream.gd")
const SaveStoreScript = preload("res://src/persistence/save_store.gd")
const CombatStateCodecScript = preload("res://src/game/combat_state_codec.gd")
const ArenaHudScript = preload("res://src/presentation/arena_hud.gd")
const ArenaWorldViewScript = preload("res://src/presentation/arena_world_view.gd")
const RangerAnimationScript = preload("res://src/presentation/ranger_animation.gd")
const EnemyAnimationScript = preload("res://src/presentation/enemy_animation.gd")
const BossActionPoseScript = preload("res://src/presentation/boss_action_pose.gd")
const CombatMarksScript = preload("res://src/presentation/combat_marks.gd")
const DefeatPresentationScript = preload("res://src/presentation/defeat_presentation.gd")
const PaletteScript = preload("res://src/presentation/combat_palette.gd")
const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const CombatFeedbackAudioScript = preload("res://src/presentation/combat_feedback_audio.gd")
const RangerSkillRulesScript = preload("res://src/systems/ranger_skill_rules.gd")
const PiercingArrowModelScript = preload("res://src/systems/piercing_arrow_model.gd")

class EnemyData:
	extends RefCounted
	var entity_id: int = 0
	var kind_id: String = "melee_pursuer"
	var position: Vector2
	var health: float
	var maximum_health: float
	var is_boss: bool
	var facing: Vector2 = Vector2.RIGHT
	var motion_state: String = "idle"
	var action_state: String = "none"
	var state_started_tick: int = 0
	var state_ends_tick: int = 0
	var impact_tick: int = -1
	var impact_resolved: bool = false
	var hit_flash_until_tick: int = 0
	var death_started_tick: int = -1
	var charge_origin: Vector2 = Vector2.ZERO
	var charge_direction: Vector2 = Vector2.RIGHT
	var charge_length: float = 0.0
	var charge_width: float = 0.0
	var fan_origin: Vector2 = Vector2.ZERO
	var fan_direction: Vector2 = Vector2.RIGHT
	var fan_half_angle: float = 0.0
	var fan_radius: float = 0.0
	var phase_id: String = "sealed"
	var phase_state: String = "stable"
	var action_id: String = "none"
	var action_instance_id: int = 0
	var core_open: bool = false
	var core_vulnerable: bool = false
	var left_hand_position: Vector2 = Vector2.ZERO
	var right_hand_position: Vector2 = Vector2.ZERO
	var target_shape: Dictionary = {}
	var next_action_index: int = 0
	var tactic_state: String = "idle"
	var tactic_reason: String = "spawned"
	var next_action_ready_tick: int = 0

	func _init(spawn_position: Vector2, hp: float, boss: bool = false, stable_id: int = 0, enemy_kind: String = "melee_pursuer") -> void:
		entity_id = stable_id
		kind_id = enemy_kind
		position = spawn_position
		health = hp
		maximum_health = hp
		is_boss = boss
		left_hand_position = spawn_position + Vector2(-34.0, 0.0)
		right_hand_position = spawn_position + Vector2(34.0, 0.0)


class ArrowTrace:
	extends RefCounted
	var from: Vector2
	var to: Vector2
	var remaining: float = 0.18

	func _init(start: Vector2, finish: Vector2) -> void:
		from = start
		to = finish


## Authoritative Piercing Arrow entity. Every field that can affect travel or
## damage is frozen on release; presentation reads position/previous_position
## directly and never owns a second flight clock.
class ArrowProjectile:
	extends RefCounted
	var action_instance_id: int
	var target_entity_id: int
	var spawned_tick: int
	var origin: Vector2
	var direction: Vector2
	var position: Vector2
	var previous_position: Vector2
	var maximum_range: float
	var speed: float
	var distance_travelled: float = 0.0
	var aggregate_damage: BigValue
	var ordinary_damage: float
	var event_count: BigValue
	var payload: float

	func _init(
		action_id: int,
		target_id: int,
		release_tick: int,
		start: Vector2,
		aim: Vector2,
		range_limit: float,
		flight_speed: float,
		damage: BigValue,
		frozen_ordinary_damage: float,
		events: BigValue,
		frozen_payload: float
	) -> void:
		action_instance_id = action_id
		target_entity_id = target_id
		spawned_tick = release_tick
		origin = start
		direction = aim
		position = start
		previous_position = start
		maximum_range = range_limit
		speed = flight_speed
		aggregate_damage = damage
		ordinary_damage = frozen_ordinary_damage
		event_count = events
		payload = frozen_payload


const ARENA_MARGIN: float = 42.0
## Combat owns a fixed logical stage. Physical window resizing is presentation
## scaling and must never change pathing, hit geometry, or replay state.
const AUTHORITY_VIEWPORT_SIZE: Vector2 = Vector2(1280.0, 720.0)
const SIM_TICKS_PER_SECOND: int = RangerSkillRulesScript.TICKS_PER_SECOND
const SIM_STEP_SECONDS: float = 1.0 / float(SIM_TICKS_PER_SECOND)
## 1.8 s of on-screen guidance for an input that legitimately did nothing
## (blank-click hint, locked-skill notice): long enough to read the longest
## sentence at a glance, short enough to stay out of the way. Presentation-only.
const INPUT_FEEDBACK_DURATION_TICKS: int = SIM_TICKS_PER_SECOND * 18 / 10
const PLAYER_SPEED: float = 245.0
const AUTO_RANGE: float = 225.0
const ATTACK_COOLDOWN_TICKS: int = RangerSkillRulesScript.PIERCING_ARROW_COOLDOWN_TICKS
const DODGE_SPEED: float = RangerSkillRulesScript.DODGE_SPEED
const DODGE_DURATION_TICKS: int = RangerSkillRulesScript.DODGE_DURATION_TICKS
const DODGE_COOLDOWN_TICKS: int = RangerSkillRulesScript.DODGE_COOLDOWN_TICKS
const HUNTER_MARK_RANGE_MULTIPLIER: float = RangerSkillRulesScript.HUNTER_MARK_RANGE_MULTIPLIER
const HUNTER_MARK_DURATION_TICKS: int = RangerSkillRulesScript.HUNTER_MARK_DURATION_TICKS
const HUNTER_MARK_COOLDOWN_TICKS: int = RangerSkillRulesScript.HUNTER_MARK_COOLDOWN_TICKS
const HUNTER_MARK_DAMAGE_MULTIPLIER: float = RangerSkillRulesScript.HUNTER_MARK_DAMAGE_MULTIPLIER
const DASH_DURATION_TICKS: int = RangerSkillRulesScript.DASH_DURATION_TICKS
const DASH_COOLDOWN_TICKS: int = RangerSkillRulesScript.DASH_COOLDOWN_TICKS
const DASH_TOTAL_DISTANCE: float = RangerSkillRulesScript.DASH_TOTAL_DISTANCE
const MOBILITY_INPUT_BUFFER_TICKS: int = 3
const BASE_PAYLOAD: float = 160.0
const FATE_SEED: int = 52969
const SAVE_PROTOCOL_VERSION: int = 1
const MANUAL_BONUS_CHANCE: float = 0.35
const ACTOR_ATLAS_PATH: String = "res://art/early/actors_atlas_v0.2.png"
const ACTOR_CELL_SIZE: float = 32.0
## Latched ranger action events: one token per cast, damage source and death, so
## a redraw can never restart a clip and the same cast only ever fires once.
const RANGER_EVENT_SHOT := "ranger/shot"
const RANGER_EVENT_HIT := "ranger/hit"
const RANGER_EVENT_DEATH := "ranger/death"
## A damage event remains readable through dodge, dash and shooting without
## competing with their authored action clips. This is a presentation-only
## window measured on the same fixed tick as the event token.
const PLAYER_DAMAGE_OVERLAY_TICKS: int = 6
const ENEMY_HIT_FLASH_TICKS: int = 3
const MAX_ACTIVE_PIERCING_PROJECTILES: int = 16
## Latched enemy action event: the first tick of one observed hp drop. The kind is
## per entity, so the same drop only ever fires once and a redraw can never
## restart a reaction clip.
const ENEMY_HIT_EVENT_KIND: String = "enemy/%d/hit"
const COMBAT_FEEDBACK_LIFETIME_SECONDS: float = 0.72
const COMBAT_FEEDBACK_LIMIT: int = 24
const COMBAT_FEEDBACK_DEFAULT_VOLUME: float = 0.45
const COMBAT_SPARK_LIFETIME_SECONDS: float = 0.15
## Render-scale for world feedback text: 0.72 gameplay-to-world * 2 published
## display scale. A 14px font therefore lands at about 20 screen px in the
## full world view, while legacy fallback keeps the same readable 14px base.
const COMBAT_FEEDBACK_TEXT_FONT_SIZE: int = 14
## One live number per target keeps rapid piercing hits readable. Every damage
## event remains in CombatEventStream; this only replaces its visual projection.
const COMBAT_FEEDBACK_TEXT_LANES := {
	"enemy_damage": 0,
	"player_damage": 0,
	"blocked": 1,
	"miss": 1,
	"avoided": 1,
	"death": 2,
}
# Early campaign durability only; movement, action timing and Boss authority stay separate.
const EARLY_NORMAL_HEALTH_BY_KIND := {
	"melee_pursuer": 720.0,
	"charging_raider": 420.0,
	"fan_ranged": 240.0,
}
const EARLY_ELITE_HEALTH_BY_KIND := {
	"melee_pursuer": 1600.0,
	"charging_raider": 1300.0,
	"fan_ranged": 1000.0,
}
const MELEE_MOVE_SPEED: float = 72.0
const CHARGER_MOVE_SPEED: float = 62.0
const FAN_MOVE_SPEED: float = 58.0
const MELEE_WINDUP_TICKS: int = 5
const MELEE_ACTIVE_TICKS: int = 1
const MELEE_RECOVERY_TICKS: int = 11
const CHARGE_WINDUP_TICKS: int = 18
const CHARGE_ACTIVE_TICKS: int = 10
const CHARGE_RECOVERY_TICKS: int = 22
const FAN_WINDUP_TICKS: int = 21
const FAN_ACTIVE_TICKS: int = 1
const FAN_RECOVERY_TICKS: int = 28
const BOSS_TRANSITION_TICKS: int = 30
const BOSS_WINDUP_TICKS: int = 24
const BOSS_ACTIVE_TICKS: int = 1
const BOSS_RECOVERY_TICKS: int = 24
const HAZARD_WARNING_TICKS: int = 30
const HAZARD_ACTIVE_TICKS: int = 15
const HAZARD_CYCLE_TICKS: int = 90
const ELITE_BARRIER_PERIOD_TICKS: int = 60
const ELITE_BARRIER_ACTIVE_TICKS: int = 20
const TIMED_BREAK_BONUS_TICKS: int = 900
const VALID_LAYOUT_IDS: Array[String] = ["rectangle_arena", "corridor", "ring"]
const VALID_OBJECTIVE_IDS: Array[String] = ["clear", "hunt_elite", "timed_break"]
const VALID_ENEMY_IDS: Array[String] = ["melee_pursuer", "charging_raider", "fan_ranged"]
const VALID_HAZARD_IDS: Array[String] = ["exposed_ground_zone", "moving_fireline"]
const VALID_ELITE_RULE_IDS: Array[String] = ["periodic_barrier", "summon_reinforcements"]
## Approved 2026-09-14 skin: cold slate grey, bone information, old-copper
## accents, with a danger red kept for hostile telegraphs and a cold teal for
## proxy state. Colours are presentation only.
const COLOR_INK: Color = PaletteScript.INK
const COLOR_DEEP_BLUE: Color = PaletteScript.SLATE_0
const COLOR_GROUND: Color = PaletteScript.SLATE_1
const COLOR_NEUTRAL: Color = PaletteScript.SLATE_3
const COLOR_BONE: Color = PaletteScript.BONE
const COLOR_AMBER: Color = PaletteScript.COPPER
const COLOR_BLOOD: Color = PaletteScript.DANGER
const COLOR_WARNING: Color = PaletteScript.DANGER_BRIGHT
const COLOR_PROXY: Color = PaletteScript.COLD
const COLOR_ANOMALY: Color = PaletteScript.PURPLE
const ATTACK_SOURCE_ASSISTED: String = "assisted"
const ATTACK_SOURCE_POINTER: String = "pointer"
const ATTACK_SOURCE_PROXY: String = "proxy"
const POINTER_STATUS_NONE: String = "none"
const POINTER_STATUS_LOCKED: String = "locked"
const POINTER_STATUS_OUT_OF_RANGE: String = "out_of_range"
const POINTER_STATUS_LOST: String = "lost"
const POINTER_STATUS_NO_TARGET: String = "no_pointer_target"
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
var locked_payload: float = BASE_PAYLOAD
var locked_targeting_distance: float = AUTO_RANGE
var player_maximum_health: float = 100.0
var locked_build: Dictionary = {}
var in_arena: bool = false
var player_position: Vector2 = Vector2.ZERO
var player_health: float = 100.0
var player_facing: Vector2 = Vector2.RIGHT
var enemies: Array[EnemyData] = []
var boss: EnemyData
var boss_maximum: BigValue = BigValue.from_power10(12.0)
var boss_damage: BigValue = BigValue.from_float(0.0)
var projectiles: Array[ArrowProjectile] = []
## Local impact sparks only. The projectile itself is always drawn from the
## authoritative projectiles array above.
var traces: Array[ArrowTrace] = []
var attack_cooldown_ticks: int = 0
var dodge_cooldown_ticks: int = 0
var dodge_remaining_ticks: int = 0
var dodge_direction: Vector2 = Vector2.RIGHT
var marked_entity_id: int = 0
var hunter_mark_expires_tick: int = 0
var hunter_mark_cooldown_ticks: int = 0
var dash_cooldown_ticks: int = 0
var dash_remaining_ticks: int = 0
var dash_direction: Vector2 = Vector2.RIGHT
var dodge_started_tick: int = -1
var dash_started_tick: int = -1
var player_last_displacement: Vector2 = Vector2.ZERO
var elapsed: float = 0.0
var sim_tick: int = 0
var shots: int = 0
var arrow_hits: int = 0
var defeated: int = 0
var battle_over: bool = false
var battle_victory: bool = false
var last_damage_source_id: String = ""
var last_damage_tick: int = -1
var last_damage_amount: float = 0.0
var last_damage_direction: Vector2 = Vector2.ZERO
var battle_report: String = ""
var dodge_requested: bool = false
var attack_requested: bool = false
## Input edges are translated into one device-free cast command on the next
## fixed tick. Pointer edges retain the selected entity separately, so a quick
## press/release cannot lose the click before the simulation consumes it.
var attack_requested_source: String = ""
var attack_requested_target_entity_id: int = 0
var attack_requested_pointer_gameplay: Vector2 = Vector2.ZERO
## The held pointer lock is an entity lock, not a nearest-target hint. Its target
## may move and leave/re-enter range, but it never silently changes entity.
var manual_pointer_target_entity_id: int = 0
var manual_pointer_gameplay: Vector2 = Vector2.ZERO
var manual_pointer_target_anchor: Vector2 = Vector2.ZERO
var manual_pointer_target_radius: float = 0.0
var manual_pointer_status: String = POINTER_STATUS_NONE
var hunter_mark_requested: bool = false
var dash_requested: bool = false
var mobility_input_buffer: Dictionary = {}
var command_sequence: int = 0
var last_command_receipts: Array[Dictionary] = []
var last_attack_outcome: Dictionary = {}
## Bounded internal decision state owned by the currently equipped proxy cores.
## This collection does not represent or consume memory-slot capacity.
var proxy_decision_state: Dictionary = {}
var presentation_event_cursor: int = 0
var attack_origins: Dictionary = {}
## Presentation metadata is keyed outside CombatCommandProtocol. Mouse, keyboard
## and proxy ownership can therefore label the HUD without entering authoritative
## commands or changing replay validation.
var attack_command_sources: Dictionary = {}
var attack_request_sources: Dictionary = {}
var attack_action_request_ids: Dictionary = {}
var combat_feedback_marks: Array[Dictionary] = []
var combat_feedback_font: Font
var combat_feedback_audio: Node

## Presentation-only transient input feedback (blank-click hints, locked-skill
## notices). It reaches the player only through the HUD snapshot's existing
## "feedback" line; the command protocol, replay capture and semantic hashing
## never read it, and it expires on the combat clock without touching authority.
var _input_feedback_text: String = ""
var _input_feedback_expires_tick: int = -1

var fixed_clock
var content_registry
var proxy_runtime
var proxy_decision
var manual_combat_input
var manual_aim_resolver
var player_action_timeline
var enemy_tactics
var combat_event_stream
var destiny_forge
var save_store
var startup_errors: Array[String] = []
var proxy_prediction: String = "unknown"
var last_proxy_failure: Dictionary = {}
var last_proxy_trace: Array[String] = []
var contract_wins: int = 0
var last_drop_id: String = ""
var last_drop: String = "None"
var last_loot_rng_state: Dictionary = {}
var last_save_message: String = "No save yet"
var command_line_arguments: PackedStringArray = []
var test_session: bool = false
var embedded_session: bool = false
var presentation_enabled: bool = true
var state_hash_output_path: String = ""
var framework_active_build: Dictionary = {}
var framework_resolved_build: Dictionary = {}
var framework_resolved_proxy_build: Dictionary = {}
var framework_room: Dictionary = {}
var room_id: String = "legacy_smoke"
var layout_id: String = "rectangle_arena"
var objective_id: String = "clear"
var room_drop_tags: Array = []
var hazard_states: Array[Dictionary] = []
var elite_rule_ids: Array[String] = []
var elite_entity_id: int = 0
var elite_barrier_active: bool = false
var reinforcements_summoned: bool = false
var timed_bonus_available: bool = true
var next_entity_id: int = 1
var next_enemy_action_instance_id: int = 1
var room_reward_snapshot: Dictionary = {
	"add_dice_delta": 0,
	"rewrite_dice_delta": 0,
	"refine_dice_delta": 0,
	"bonus_earned": false,
	"bonus_lost": false,
}
var talent_capabilities: Dictionary = {}
var first_critical_bonus_used := false
var hunter_mark_candidate_entity_id := 0
var hunter_mark_candidate_expires_tick := 0
var three_skill_sequence_stage := 0
var three_skill_bonus_ready := false
var retained_arrow_damage: BigValue = BigValue.from_float(0.0)
var retained_arrow_ordinary_damage := 0.0

var base_panel: VBoxContainer
var hud_panel: Control
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
var automation_expected_contract_wins: int = 1
var automation_smoke_failure: String = ""
var actors_atlas: Texture2D
## Presentation-only world view. Null whenever the approved arena art is
## unavailable, in which case _draw() keeps the previous flat-field rendering.
var world_view
var world_pending_reason: String = ""
## Shared ranger action reader. Presentation only: it reads authoritative tick
## fields and latched events, writes nothing back into the simulation, and
## reports its pending fallback instead of substituting art for it.
var ranger_animation
var ranger_action_pending_reason: String = ""
## Age of the death clip in seconds, advanced on the presentation clock because
## the simulation stops ticking once the battle is over. Kept in float and
## converted at read time: a per-frame int() rounds a 60/144Hz step to zero and
## would freeze the clip. The arena still marks battle_over on the death tick
## itself -- the defeat is authoritative and immediate -- and the defeat window
## below holds only the visual route, so the published clip plays out on screen
## before the result page replaces it.
var ranger_death_seconds: float = 0.0
## Presentation-only defeat window, fed with the frame this arena hands to its
## renderer. The session router asks defeat_route_ready() before it leaves for
## the result screen; null whenever presentation is off, in which case nothing on
## screen is held back at all.
var defeat_presentation
## The action frame this frame will draw, resolved once per presentation commit
## instead of inside _draw(): the runtime diagnostic then answers in headless
## runs too, and a capture never reads the atlas mid-draw.
var ranger_frame: Dictionary = {}
## Shared enemy action reader. Presentation only: it reads authoritative tick
## fields plus the inferred movement and latched hp-drop events, writes nothing
## back into the simulation, and reports its pending fallback instead of
## substituting art for it. Null whenever presentation is off.
var enemy_animation
var enemy_animation_pending_reason: String = ""
## The action frame every live enemy draws this frame, keyed by entity id, plus
## the same resolution for every detached corpse. Resolved once per presentation
## commit so the occlusion pass and the draw calls read one frame, never two.
var enemy_frames: Dictionary = {}
## Presentation-only per-enemy watch record: the last observed position and hp
## (the movement and hp-drop inference) plus the walk loop clock. It duplicates
## authoritative fields for reading; nothing here is ever written back.
var enemy_watch: Dictionary = {}
## Detached corpses: the position, facing and role recorded at the authoritative
## kill, played on a presentation clock. A corpse never holds the despawn, the
## route or a reward, and a reset or a despawn creates none at all.
var enemy_corpses: Array[Dictionary] = []


func _ready() -> void:
	command_line_arguments = OS.get_cmdline_user_args()
	test_session = embedded_session or command_line_arguments.has("--smoke") or command_line_arguments.has("--auto-smoke")
	for argument: String in command_line_arguments:
		if argument.begins_with("--state-hash-out="):
			state_hash_output_path = argument.trim_prefix("--state-hash-out=")
	_initialize_runtime()
	_load_visual_assets()
	_build_ui()
	_show_base()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_presentation_redraw()
	if not embedded_session:
		_handle_command_line()


func _load_visual_assets() -> void:
	if not presentation_enabled:
		return
	combat_feedback_font = ShellThemeScript.ui_font()
	combat_feedback_audio = CombatFeedbackAudioScript.new()
	add_child(combat_feedback_audio)
	world_view = ArenaWorldViewScript.new()
	if not world_view.load_assets():
		world_pending_reason = String(world_view.pending_reason)
		world_view = null
	ranger_animation = RangerAnimationScript.new()
	if not ranger_animation.has_real_art():
		ranger_action_pending_reason = ranger_animation.pending_reason()
	## The enemy pack is produced separately; while it is absent the arena keeps
	## drawing the read-only calibration cells and this reason says so out loud.
	enemy_animation = EnemyAnimationScript.new()
	if not enemy_animation.has_real_art():
		enemy_animation_pending_reason = enemy_animation.pending_reason()
	## The window measures whatever the published atlas declares for the death
	## clip instead of a timing copied into this file.
	defeat_presentation = DefeatPresentationScript.new(_death_clip_timing())
	if not ResourceLoader.exists(ACTOR_ATLAS_PATH):
		return
	var atlas_resource := load(ACTOR_ATLAS_PATH)
	if atlas_resource is Texture2D:
		actors_atlas = atlas_resource


## Published death clip timing from the shared reader (the first facing that has
## one), or an empty dictionary while the atlas is pending so the window falls
## back to the agreed contract numbers, exactly like the reader itself does.
func _death_clip_timing() -> Dictionary:
	if ranger_animation == null:
		return {}
	for facing: String in RangerAnimationScript.FACINGS:
		var info: Dictionary = ranger_animation.clip_info(RangerAnimationScript.clip_id(facing, DefeatPresentationScript.ACTION_DEATH))
		var frames: Array = info.get("frames", [])
		if frames.is_empty():
			continue
		return {
			"frames": frames.size(),
			"fps": maxi(1, int(info.get("fps", DefeatPresentationScript.CLIP_FPS))),
		}
	return {}


func _process(delta: float) -> void:
	if not in_arena:
		return
	_presentation_update(delta)
	var ticks_to_run: int = fixed_clock.consume_frame(delta)
	for _index in ticks_to_run:
		if battle_over:
			break
		_simulate_tick()
	_presentation_commit(delta)


func _presentation_update(delta: float) -> void:
	if presentation_enabled:
		_update_traces(delta)
		_advance_combat_feedback(delta)
		_update_ranger_action_events(delta)


func _presentation_commit(delta: float = 0.0) -> void:
	if presentation_enabled:
		## Simulation ticks run after _presentation_update(). Consume the events they
		## just emitted before resolving this frame, so impact art is never one render
		## frame behind the authoritative hit.
		_consume_combat_presentation_events()
		_refresh_ranger_frame()
		_commit_enemy_animation(delta)
		_observe_defeat_presentation(delta)
		_update_hud()
		queue_redraw()


## Feeds the defeat window the frame this commit hands to the renderer, with the
## presentation time that frame is on screen for. Nothing else is ever written:
## the window reports, it never decides anything authoritative.
func _observe_defeat_presentation(delta: float) -> void:
	if defeat_presentation == null:
		return
	defeat_presentation.observe_frame(ranger_frame, delta)


## Resolved from authoritative state once per frame; an empty result means the
## reader is pending or broken and the approved static idle cell is drawn instead.
func _refresh_ranger_frame() -> void:
	if ranger_animation == null:
		ranger_frame = {}
		return
	var frame: Dictionary = ranger_animation.resolve(_ranger_animation_state())
	ranger_frame = {} if bool(frame.get("fallback", true)) else frame


func _presentation_redraw() -> void:
	if presentation_enabled:
		_refresh_ranger_frame()
		## A redraw re-reads the frames already resolved from the last authoritative
		## tick; it never observes, so it can never clear an inferred motion.
		_refresh_enemy_frames()
		queue_redraw()


## ------------------------------------------------------------------ enemies
## The enemy action pass: the arena observes what the simulation really did and
## the shared reader turns that into one frame per role. Nothing below writes an
## authoritative field, and the frames are resolved once per commit so the
## occlusion pass and the draw calls read the same cell.


## One presentation commit for the enemy reader: observe, then resolve frames.
func _commit_enemy_animation(delta: float) -> void:
	_observe_enemy_animation(delta)
	_refresh_enemy_frames()


## Read-only enemy observation. Walk/idle follows the displacement the simulation
## really committed. Hit reactions arrive through CombatEventStream and are never
## guessed from hp deltas, so a shielded arrow cannot flash as a hit. Nothing here
## is written back, so a redraw cannot change what the simulation will do.
##
## Motion and hp are sampled only when the authoritative tick really advanced: at
## 60/144Hz most render frames consume zero sim ticks, and sampling those would
## clear `moving` again, reset the walk loop and flicker a walking enemy back to
## idle. The walk clock is the number of authoritative ticks the enemy really
## moved, so one authority tick renders one frame at every render rate.
func _observe_enemy_animation(delta: float) -> void:
	_advance_enemy_corpses(delta)
	if enemy_animation == null or world_view == null:
		return
	var live := {}
	for enemy: EnemyData in enemies:
		if enemy.is_boss:
			continue
		live[enemy.entity_id] = true
		var record: Dictionary = enemy_watch.get(enemy.entity_id, {})
		if record.is_empty():
			enemy_watch[enemy.entity_id] = {"position": enemy.position, "health": enemy.health, "moving": false, "walk_ticks": 0, "tick": sim_tick}
			continue
		var advanced: int = sim_tick - int(record.get("tick", sim_tick))
		if advanced <= 0:
			## A render-only frame: no tick ran, so nothing could have moved or lost hp
			## and the last authoritative read stands unchanged.
			continue
		var moved: bool = enemy.position != (record["position"] as Vector2)
		record["health"] = enemy.health
		record["position"] = enemy.position
		record["moving"] = moved
		record["walk_ticks"] = int(record.get("walk_ticks", 0)) + advanced if moved else 0
		record["tick"] = sim_tick
	for entity_id: int in enemy_watch.keys():
		if not live.has(entity_id):
			## Unobserved and unkilled: a despawn or a route reset, never a death. The
			## record is dropped without a corpse, so no reset can play a death clip.
			enemy_watch.erase(entity_id)


func _enemy_hit_event_kind(entity_id: int) -> String:
	return ENEMY_HIT_EVENT_KIND % entity_id


## Detaches one presentation-only corpse at the authoritative kill: the death clip
## plays where the simulation killed the enemy and then expires on its own
## presentation clock. Only this hook ever creates a corpse, so a despawn or a
## route reset can never be mistaken for a death.
func _detach_enemy_corpse(enemy: EnemyData) -> void:
	if not presentation_enabled or not in_arena or enemy.is_boss or enemy_animation == null or world_view == null:
		return
	enemy_corpses.append({
		"entity_id": enemy.entity_id,
		"role": _enemy_role_id(enemy),
		"facing": enemy.facing,
		"position": enemy.position,
		"seconds": 0.0,
		"frame": {},
	})
	enemy_watch.erase(enemy.entity_id)


## The corpse clock runs on presentation time because the simulation stops ticking
## on victory: the death clip's own published length plus the agreed hold decides
## when the detached body is dropped. It blocks nothing on the way out.
func _advance_enemy_corpses(delta: float) -> void:
	if enemy_corpses.is_empty():
		return
	var kept: Array[Dictionary] = []
	for corpse: Dictionary in enemy_corpses:
		corpse["seconds"] = maxf(0.0, float(corpse.get("seconds", 0.0))) + delta
		if _corpse_ticks(corpse) <= _corpse_window_ticks(corpse):
			kept.append(corpse)
	enemy_corpses = kept


func _corpse_ticks(corpse: Dictionary) -> int:
	return roundi(maxf(0.0, float(corpse.get("seconds", 0.0))) * float(EnemyAnimationScript.SIM_TICKS_PER_SECOND))


## The published death length of this corpse's role plus the agreed hold.
func _corpse_window_ticks(corpse: Dictionary) -> int:
	var death_ticks := EnemyAnimationScript.agreed_duration_ticks("death")
	if enemy_animation != null:
		death_ticks = enemy_animation.clip_duration_ticks(String(corpse.get("role", "melee")), "death")
	return death_ticks + EnemyAnimationScript.CORPSE_HOLD_TICKS


## A new wave, a route reset or a return to base drops every inferred record and
## every detached corpse: nothing carries over between battles, and the reader
## latches are cleared so the first drop of the next fight is its own first drop.
func _reset_enemy_animation() -> void:
	enemy_watch.clear()
	enemy_corpses.clear()
	enemy_frames.clear()
	if enemy_animation != null:
		enemy_animation.clear_events()


## Resolves one frame per live enemy and per detached corpse from the state the
## last simulation tick left behind. A pending or broken delivery resolves to its
## explicit fallback, which the draw calls read as "keep the calibration cell".
func _refresh_enemy_frames() -> void:
	enemy_frames = {}
	if enemy_animation == null or world_view == null:
		return
	for enemy: EnemyData in enemies:
		if enemy.is_boss:
			continue
		enemy_frames[enemy.entity_id] = enemy_animation.resolve(_enemy_animation_state(enemy))
	for corpse: Dictionary in enemy_corpses:
		corpse["frame"] = enemy_animation.resolve(_corpse_animation_state(corpse))


## The reader's trigger contract for one live enemy, filled only from
## authoritative fields plus the inferred movement and the latched hp drop. A hit
## reaction expires on its own published length; a windup or an active state is
## authoritative and outranks it.
func _enemy_animation_state(enemy: EnemyData) -> Dictionary:
	var record: Dictionary = enemy_watch.get(enemy.entity_id, {})
	return {
		"role": _enemy_role_id(enemy),
		"facing": enemy.facing,
		"action_state": enemy.action_state,
		"state_started_tick": enemy.state_started_tick,
		"state_ends_tick": enemy.state_ends_tick,
		"moving": bool(record.get("moving", false)),
		"phase_ticks": _enemy_walk_phase_ticks(record),
		"hit_ticks": enemy_animation.latched_ticks(_enemy_hit_event_kind(enemy.entity_id), sim_tick),
		"dead": false,
		"death_ticks": 0,
		"tick": sim_tick,
	}


## The walk loop clock: the authoritative ticks the enemy really moved. It is not
## a render-delta clock, so the same authority tick reads the same walk frame at
## 30, 60 and 144Hz.
func _enemy_walk_phase_ticks(record: Dictionary) -> int:
	return maxi(0, int(record.get("walk_ticks", 0)))


## A detached corpse is dead for the reader and nothing else: the death clip holds
## its last published frame while the hold clock runs.
func _corpse_animation_state(corpse: Dictionary) -> Dictionary:
	return {
		"role": String(corpse.get("role", "melee")),
		"facing": corpse.get("facing", Vector2.RIGHT),
		"action_state": "none",
		"moving": false,
		"phase_ticks": 0,
		"hit_ticks": -1,
		"dead": true,
		"death_ticks": _corpse_ticks(corpse),
		"tick": sim_tick,
	}


func _enemy_action_frame(entity_id: int) -> Dictionary:
	var frame: Dictionary = enemy_frames.get(entity_id, {})
	return {} if bool(frame.get("fallback", true)) else frame


## The world rect a resolved action frame really draws into, built from the
## frame's own rect and anchor exactly like the world view builds its own cells,
## so the shared hero-occlusion budget is measured on the published cell geometry
## instead of an assumed slot.
func _enemy_frame_art_box(frame: Dictionary, feet_world: Vector2) -> Rect2:
	var rect: Rect2i = frame.get("rect", Rect2i())
	if rect.size.x <= 0 or rect.size.y <= 0:
		return Rect2()
	var anchor: Vector2i = frame.get("anchor", EnemyAnimationScript.DEFAULT_ANCHOR)
	return Rect2((feet_world - Vector2(anchor)).round(), Vector2(rect.size))


## The art box one live enemy contributes to the shared occlusion budget: the
## frame it is really drawn from when the new pack is live, the calibration cell
## it is really drawn from while the pack is pending.
func _enemy_art_box(enemy: EnemyData, feet_world: Vector2) -> Rect2:
	var frame: Dictionary = _enemy_action_frame(enemy.entity_id)
	if not frame.is_empty():
		return _enemy_frame_art_box(frame, feet_world)
	return world_view.sprite_art_box("enemy.%s.%s" % [_enemy_role_id(enemy), _enemy_pose_id(enemy)], feet_world)


## Draws one resolved action frame inside the world transform, exactly like the
## world view draws its own cells: the destination comes from the frame's own
## anchor and rect, a west frame is mirrored about its cell centre -- the
## published (24,44) anchor, so the feet stay where the calibration pack drew
## them -- and the cut window keeps this actor inside one share of the hero's
## opacity budget.
func _draw_enemy_action_frame(frame: Dictionary, feet_world: Vector2, modulate: Color, cut: Rect2, cut_alpha: float) -> void:
	var texture: Texture2D = frame.get("texture")
	var rect: Rect2i = frame.get("rect", Rect2i())
	if texture == null or rect.size.x <= 0 or rect.size.y <= 0:
		return
	var anchor := Vector2(frame.get("anchor", EnemyAnimationScript.DEFAULT_ANCHOR))
	var region := Rect2(rect)
	var destination := Rect2((feet_world - anchor).round(), region.size)
	var visible: Rect2 = destination.intersection(world_view.visible_world_region())
	if visible.size.x <= 0.0 or visible.size.y <= 0.0:
		return
	var core := _enemy_frame_cut_core(destination, cut, cut_alpha)
	if bool(frame.get("flip_x", false)):
		var center := destination.position + destination.size * 0.5
		var pieces: Array[Dictionary] = [{"dest": visible, "alpha": modulate.a}]
		if core.has_area():
			pieces = world_view.cut_pieces(destination, region, core, modulate.a, cut_alpha)
		## Compose with the active world transform: resetting to identity would put
		## every actor after a west-facing enemy in raw screen coordinates.
		draw_set_transform_matrix(world_view.world_transform() * Transform2D(0.0, Vector2(-1.0, 1.0), 0.0, center))
		for piece: Dictionary in pieces:
			var piece_dest: Rect2 = piece["dest"]
			var mirrored_local := Rect2(Vector2(center.x - piece_dest.end.x, piece_dest.position.y - center.y), piece_dest.size)
			var mirrored_source := Rect2(region.position + Vector2(destination.size.x - (piece_dest.end.x - destination.position.x), piece_dest.position.y - destination.position.y), piece_dest.size)
			draw_texture_rect_region(texture, mirrored_local, mirrored_source, Color(modulate.r, modulate.g, modulate.b, float(piece["alpha"])))
		draw_set_transform_matrix(world_view.world_transform())
		return
	if core.has_area():
		for piece: Dictionary in world_view.cut_pieces(destination, region, core, modulate.a, cut_alpha, false):
			var piece_dest: Rect2 = piece["dest"]
			var clipped: Rect2 = piece_dest.intersection(world_view.visible_world_region())
			if clipped.size.x <= 0.0 or clipped.size.y <= 0.0:
				continue
			var piece_source := Rect2(region.position + (clipped.position - destination.position), clipped.size)
			draw_texture_rect_region(texture, clipped, piece_source, Color(modulate.r, modulate.g, modulate.b, float(piece["alpha"])))
		return
	var source := Rect2(region.position + (visible.position - destination.position), visible.size)
	draw_texture_rect_region(texture, visible, source, modulate)


## The hero window in destination-local units, on the integer grid so every piece
## reads whole source pixels. Mirrors the world view's own split.
func _enemy_frame_cut_core(destination: Rect2, cut: Rect2, cut_alpha: float) -> Rect2:
	if cut.size.x <= 0.0 or cut.size.y <= 0.0 or cut_alpha >= 0.999:
		return Rect2()
	var local := Rect2((cut.position - destination.position).round(), cut.size.round())
	return local.intersection(Rect2(Vector2.ZERO, destination.size))


## Detached corpses draw from the position and facing recorded at the kill, never
## from a live entity: the simulation erased it already.
func _draw_enemy_corpse(corpse: Dictionary) -> void:
	var frame: Dictionary = corpse.get("frame", {})
	if frame.is_empty() or bool(frame.get("fallback", true)):
		return
	var feet: Vector2 = world_view.gameplay_to_world(corpse.get("position", Vector2.ZERO) as Vector2)
	var cut: Dictionary = world_view.cutaway_for(_enemy_frame_art_box(frame, feet), feet, world_view.gameplay_to_world(player_position))
	_draw_enemy_action_frame(frame, feet, Color.WHITE, cut["window"] if cut["in_front"] else Rect2(), float(cut["local_alpha"]))


## Runtime integration diagnostic for the enemy action pass: the reader state,
## the frame every live enemy is drawn from and the detached corpses with their
## clocks. Read it after a capture to compare the drawn frames against the state
## they came from.
func enemy_animation_report() -> Dictionary:
	var live: Array[Dictionary] = []
	for enemy: EnemyData in enemies:
		if enemy.is_boss:
			continue
		var frame: Dictionary = enemy_frames.get(enemy.entity_id, {})
		live.append({
			"entity_id": enemy.entity_id,
			"role": _enemy_role_id(enemy),
			"action_state": enemy.action_state,
			"action": String(frame.get("action", "")),
			"clip": String(frame.get("clip", "")),
			"frame": int(frame.get("frame", -1)),
			"rect": frame.get("rect", Rect2i()),
			"anchor": frame.get("anchor", Vector2i.ZERO),
			"flip_x": bool(frame.get("flip_x", false)),
			"fallback": bool(frame.get("fallback", true)),
			"reason": String(frame.get("reason", "")),
		})
	var corpses: Array[Dictionary] = []
	for corpse: Dictionary in enemy_corpses:
		corpses.append({
			"entity_id": int(corpse.get("entity_id", 0)),
			"role": String(corpse.get("role", "")),
			"ticks": _corpse_ticks(corpse),
			"window_ticks": _corpse_window_ticks(corpse),
			"frame": int((corpse.get("frame", {}) as Dictionary).get("frame", -1)),
		})
	var report := {
		"pending_reason": enemy_animation_pending_reason,
		"asset_state": enemy_animation.asset_state() if enemy_animation != null else "",
		"production": enemy_animation.production_report() if enemy_animation != null else {},
		"live": live,
		"corpses": corpses,
	}
	if enemy_animation != null:
		report["reader"] = enemy_animation.integration_report()
	return report


func _unhandled_input(event: InputEvent) -> void:
	if not in_arena or battle_over:
		return
	if selected_mode != "Manual" or (event is InputEventKey and event.echo):
		return
	## HUD ownership applies to the pointer event that began there. Keyboard and
	## controller dodge actions must not depend on wherever the mouse happens to
	## be when they are dispatched.
	if event.is_action_pressed("dodge") and (not (event is InputEventMouseButton) or not _pointer_is_over_hud()):
		dodge_requested = true
	elif event.is_action_pressed("skill_2"):
		if _is_skill_equipped(1, "hunter_mark"):
			hunter_mark_requested = true
			_clear_input_feedback()
		else:
			## Truthful whether the skill is campaign-locked or merely unequipped:
			## this authority only ever receives the equipped build, never an
			## unlock record, so the wording claims no unlock timing.
			_show_input_feedback("猎人印记未装配在本场构筑 · 暂无法施放")
	elif event.is_action_pressed("skill_3"):
		if _is_skill_equipped(2, "dash"):
			dash_requested = true
			_clear_input_feedback()
		else:
			_show_input_feedback("突袭未装配在本场构筑 · 暂无法施放")


## Attack is observed before GUI dispatch so releases cannot be swallowed by a
## Control. ManualCombatInput still gives pointer presses that begin on the HUD to
## the interface, while Space/controller input remains independent of cursor hover.
func _input(event: InputEvent) -> void:
	_capture_manual_attack_event(event, _pointer_is_over_hud())


func _capture_manual_attack_event(event: InputEvent, pointer_over_interface: bool) -> void:
	if manual_combat_input == null:
		return
	## Manual device state is outside the Auto contract. Reject it before the
	## physical-source tracker sees the event, so pointer activity cannot enter an
	## Auto decision, diagnostic snapshot or deterministic hash.
	if not in_arena or battle_over or selected_mode != "Manual":
		if selected_mode != "Manual":
			manual_combat_input.reset()
		return
	var newly_pressed: bool = manual_combat_input.observe_attack_event(event, pointer_over_interface)
	var pointer_event := event is InputEventMouseButton
	if pointer_event and event.is_action_released(&"attack"):
		_clear_manual_pointer_lock()
		return
	if not newly_pressed:
		return
	var source: String = manual_combat_input.attack_source(pointer_over_interface)
	if source == ATTACK_SOURCE_POINTER:
		if pointer_event:
			_capture_pointer_attack((event as InputEventMouseButton).position)
		else:
			_queue_pointer_attack_from_lock()
	else:
		_queue_assisted_attack()


func _capture_pointer_attack(screen_point: Vector2) -> void:
	_clear_pending_attack_edge()
	manual_pointer_gameplay = _screen_to_gameplay(screen_point)
	var resolved: Dictionary = manual_aim_resolver.resolve_pointer(
		manual_pointer_gameplay,
		player_position,
		locked_targeting_distance,
		_manual_aim_candidates()
	)
	if not bool(resolved.get("ok", false)):
		_clear_manual_pointer_lock(false)
		manual_pointer_gameplay = _screen_to_gameplay(screen_point)
		manual_pointer_status = POINTER_STATUS_NO_TARGET
		battle_report = "鼠标未锁定目标；空白点击不会改为自动寻敌。"
		## Immediate on press: the failed click is the moment the player needs
		## the alternative. A normal release happens long before the 0.9 s
		## duration ends, so the hint stays legible through it.
		_show_input_feedback("点击敌人射击 · 或按住空格辅助瞄准")
		return
	## A resolved lock (in range or not) is a successful new intent: it replaces
	## whatever stale input hint was on screen with the HUD's own lock states.
	_clear_input_feedback()
	manual_pointer_target_entity_id = int(resolved.get("target_entity_id", 0))
	manual_pointer_target_anchor = resolved.get("target_anchor", Vector2.ZERO)
	manual_pointer_target_radius = float(resolved.get("target_radius", 0.0))
	manual_pointer_status = POINTER_STATUS_LOCKED if bool(resolved.get("in_range", false)) else POINTER_STATUS_OUT_OF_RANGE
	if manual_pointer_status == POINTER_STATUS_LOCKED:
		_queue_pointer_attack_from_lock()
		battle_report = "指针已锁定目标。"
	else:
		battle_report = "指针已锁定目标，但目前在射程外。"
		## Same read-only truth as the 射程外 cell, one actionable next step for a
		## click that locked a real enemy it cannot reach yet. Cast, range and
		## buffer behavior are unchanged: the lock simply never queues a shot.
		_show_input_feedback("目标在射程外 · 靠近后再射")


func _screen_to_gameplay(screen_point: Vector2) -> Vector2:
	if world_view == null:
		return screen_point
	world_view.begin_frame(Rect2(Vector2.ZERO, get_viewport_rect().size), player_position, _arena_rect())
	return world_view.screen_to_gameplay(screen_point)


func _manual_aim_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for enemy: EnemyData in enemies:
		result.append({
			"entity_id": enemy.entity_id,
			"kind_id": enemy.kind_id,
			"position": enemy.position,
			"health": enemy.health,
			"is_boss": enemy.is_boss,
		})
	return result


func _queue_assisted_attack() -> void:
	attack_requested = true
	attack_requested_source = ATTACK_SOURCE_ASSISTED
	attack_requested_target_entity_id = 0
	attack_requested_pointer_gameplay = Vector2.ZERO


func _queue_pointer_attack_from_lock() -> void:
	_clear_pending_attack_edge()
	if not _refresh_manual_pointer_lock():
		return
	attack_requested = true
	attack_requested_source = ATTACK_SOURCE_POINTER
	attack_requested_target_entity_id = manual_pointer_target_entity_id
	attack_requested_pointer_gameplay = manual_pointer_gameplay


func _refresh_manual_pointer_lock() -> bool:
	if manual_pointer_target_entity_id <= 0:
		if manual_pointer_status != POINTER_STATUS_NO_TARGET:
			manual_pointer_status = POINTER_STATUS_LOST
		return false
	var target := _enemy_by_entity_id(manual_pointer_target_entity_id)
	if target == null or target.health <= 0.0:
		manual_pointer_status = POINTER_STATUS_LOST
		manual_pointer_target_anchor = Vector2.ZERO
		manual_pointer_target_radius = 0.0
		return false
	var candidate := {
		"entity_id": target.entity_id,
		"kind_id": target.kind_id,
		"position": target.position,
		"health": target.health,
		"is_boss": target.is_boss,
	}
	manual_pointer_target_anchor = manual_aim_resolver.target_anchor(candidate)
	manual_pointer_target_radius = manual_aim_resolver.target_radius(candidate)
	manual_pointer_status = POINTER_STATUS_LOCKED if player_position.distance_to(target.position) <= locked_targeting_distance else POINTER_STATUS_OUT_OF_RANGE
	return manual_pointer_status == POINTER_STATUS_LOCKED


func _clear_pending_attack_edge() -> void:
	attack_requested = false
	attack_requested_source = ""
	attack_requested_target_entity_id = 0
	attack_requested_pointer_gameplay = Vector2.ZERO


func _clear_manual_pointer_lock(clear_status: bool = true) -> void:
	manual_pointer_target_entity_id = 0
	manual_pointer_gameplay = Vector2.ZERO
	manual_pointer_target_anchor = Vector2.ZERO
	manual_pointer_target_radius = 0.0
	if clear_status:
		manual_pointer_status = POINTER_STATUS_NONE


func _reset_manual_attack_intent() -> void:
	_clear_pending_attack_edge()
	_clear_manual_pointer_lock()
	attack_command_sources.clear()
	attack_request_sources.clear()
	attack_action_request_ids.clear()
	_input_feedback_text = ""
	_input_feedback_expires_tick = -1
	if manual_combat_input != null:
		manual_combat_input.reset()


## Public pause boundary. A release swallowed while this node was inactive must
## not become a queued shot on resume; accepted timeline actions stay untouched.
func release_manual_controls() -> void:
	_reset_manual_attack_intent()
	dodge_requested = false
	hunter_mark_requested = false
	dash_requested = false
	mobility_input_buffer.clear()


func take_continuous_manual_input() -> RefCounted:
	if selected_mode != "Manual" or manual_combat_input == null:
		return null
	manual_combat_input.retain_pressed_assisted_sources()
	if not manual_combat_input.attack_held(false):
		return null
	var continued_input: RefCounted = manual_combat_input
	manual_combat_input = ManualCombatInputScript.new()
	_reset_manual_attack_intent()
	return continued_input


func resume_continuous_manual_input(continued_input: RefCounted) -> void:
	if selected_mode != "Manual" or not in_arena or battle_over or not continued_input is ManualCombatInputScript:
		return
	continued_input.retain_pressed_assisted_sources()
	manual_combat_input = continued_input


func set_effects_volume(value: float) -> void:
	if combat_feedback_audio != null:
		combat_feedback_audio.set_volume(value)


func _reset_combat_feedback_audio() -> void:
	if combat_feedback_audio != null:
		combat_feedback_audio.reset_audio()


func _initialize_runtime() -> void:
	fixed_clock = FixedTickClockScript.new(SIM_TICKS_PER_SECOND)
	content_registry = ContentRegistryScript.new()
	startup_errors = content_registry.load_all()
	proxy_runtime = ProxyRuntimeScript.new()
	proxy_decision = ProxyDecisionScript.new()
	manual_combat_input = ManualCombatInputScript.new()
	manual_aim_resolver = ManualAimResolverScript.new()
	player_action_timeline = PlayerActionTimelineScript.new()
	enemy_tactics = EnemyTacticsScript.new()
	combat_event_stream = CombatEventStreamScript.new()
	proxy_decision_state = {}
	proxy_prediction = "unknown"
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
	source += "\n" + FileAccess.get_file_as_string("res://content/early_campaign.json")
	source += "\n" + FileAccess.get_file_as_string("res://content/early_items.json")
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return "unavailable"
	if context.update(source.to_utf8_buffer()) != OK:
		return "unavailable"
	return context.finish().hex_encode()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var interface_theme := _build_interface_theme()
	base_panel = VBoxContainer.new()
	base_panel.theme = interface_theme
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
	controls.text = "Manual: WASD move • Space / LMB Skill 1 • Q Hunter Mark • E Dash • Shift / Ctrl / RMB dodge\nAuto: nearest target • approach range • Skill 1 only"
	base_panel.add_child(controls)
	var start_button := Button.new()
	start_button.text = "DEPLOY"
	start_button.custom_minimum_size = Vector2(0.0, 48.0)
	start_button.pressed.connect(_enter_arena)
	base_panel.add_child(start_button)

	systems_panel = VBoxContainer.new()
	systems_panel.theme = interface_theme
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
	systems_panel.add_child(_section_label("LAW FORGE // INSCRIPTION TRACK"))
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
	reward_note.text = "Manual Hunter Cache: deterministic 35% chance for +1 extra Inscription Tally.\nAuto and Manual never run simultaneously. Closing the game grants nothing."
	reward_note.add_theme_color_override("font_color", COLOR_ANOMALY)
	systems_panel.add_child(reward_note)

	hud_panel = ArenaHudScript.new()
	hud_panel.theme = interface_theme
	layer.add_child(hud_panel)
	hud_panel.skill_one_requested.connect(_on_hud_skill_one_requested)
	hud_panel.skill_two_requested.connect(_on_hud_skill_two_requested)
	hud_panel.skill_three_requested.connect(_on_hud_skill_three_requested)
	hud_panel.dodge_requested.connect(_on_hud_dodge_requested)
	hud_panel.return_requested.connect(_show_base)
	return_button = hud_panel.find_child("ReturnButton", true, false) as Button


func _build_interface_theme() -> Theme:
	var theme := Theme.new()
	# The packaged SC font is the only font the arena may draw Chinese with; no
	# SystemFont and no development-machine font is substituted.
	var ui_font: FontFile = ShellThemeScript.ui_font()
	if ui_font != null:
		theme.default_font = ui_font
	theme.set_color("font_color", "Label", COLOR_BONE)
	theme.set_color("font_shadow_color", "Label", COLOR_INK)
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)
	theme.set_color("font_color", "Button", COLOR_BONE)
	theme.set_color("font_hover_color", "Button", COLOR_BONE)
	theme.set_color("font_pressed_color", "Button", COLOR_INK)
	theme.set_color("font_disabled_color", "Button", COLOR_NEUTRAL)
	theme.set_color("font_focus_color", "Button", COLOR_BONE)
	theme.set_stylebox("normal", "Button", _button_style(COLOR_DEEP_BLUE, COLOR_NEUTRAL, 1))
	theme.set_stylebox("hover", "Button", _button_style(COLOR_GROUND, COLOR_BONE, 2))
	theme.set_stylebox("pressed", "Button", _button_style(COLOR_AMBER, COLOR_BONE, 2))
	theme.set_stylebox("disabled", "Button", _button_style(COLOR_GROUND, COLOR_NEUTRAL, 2))
	theme.set_stylebox("focus", "Button", _button_style(Color.TRANSPARENT, COLOR_AMBER, 2))
	return theme


func _button_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = "\n%s" % text
	label.add_theme_color_override("font_color", COLOR_PROXY)
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
		content_status_label.add_theme_color_override("font_color", COLOR_PROXY)
	else:
		content_status_label.text = "CONTENT BLOCKED: %s" % "; ".join(startup_errors)
		content_status_label.add_theme_color_override("font_color", COLOR_WARNING)
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
	forge_status_label.text = "Sacred-law seed %d is fixed. Future #n costs n Inscription Tallies when confirmed.\nInscription Tallies: %d  •  slots: %s" % [FATE_SEED, dice, " | ".join(equipped)]
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
	_reset_combat_feedback_audio()
	## Leaving the arena drops the detached corpses and every inferred record.
	_reset_enemy_animation()
	if defeat_presentation != null and not defeat_presentation.route_ready():
		## The player asked to leave the arena view while the published clip was still
		## playing (the HUD's return button reaches this line first). The window is cut
		## short on purpose and says so, instead of claiming it finished.
		defeat_presentation.skip("return_to_base")
	_reset_manual_attack_intent()
	dodge_requested = false
	hunter_mark_requested = false
	dash_requested = false
	mobility_input_buffer.clear()
	if player_action_timeline != null:
		player_action_timeline.reset()
	if proxy_runtime != null:
		proxy_runtime.end_contract()
	base_panel.visible = presentation_enabled
	systems_panel.visible = presentation_enabled
	hud_panel.visible = false
	_refresh_base_buttons()
	_presentation_redraw()


func _enter_arena() -> void:
	if not startup_errors.is_empty():
		last_save_message = "Deployment blocked by content validation"
		_refresh_system_panel()
		return
	if embedded_session and not _resolved_build_is_valid(framework_resolved_build):
		last_save_message = "Deployment blocked: invalid_resolved_build"
		_refresh_system_panel()
		return
	var room_error := _framework_room_error()
	if not room_error.is_empty():
		last_save_message = "Deployment blocked: %s" % room_error
		_refresh_system_panel()
		return
	locked_build = framework_resolved_build.duplicate(true) if _resolved_build_is_valid(framework_resolved_build) else {}
	if not locked_build.is_empty():
		var parameters: Dictionary = locked_build.final_parameters
		locked_p = float(parameters.p)
		locked_payload = float(parameters.damage)
		locked_targeting_distance = float(parameters.d)
		player_maximum_health = float(parameters.max_health)
	else:
		locked_p = float(content_registry.presets[selected_preset].p)
		locked_payload = BASE_PAYLOAD
		locked_targeting_distance = AUTO_RANGE
		player_maximum_health = 100.0
	_apply_framework_talents()
	proxy_runtime.end_contract()
	if selected_mode == "Auto":
		var proxy_install: Dictionary = proxy_runtime.install_resolved(
			framework_resolved_proxy_build,
			"nearest_enemy"
		)
		if not bool(proxy_install.get("ok", false)):
			last_save_message = "Deployment blocked: proxy_%s" % String(proxy_install.get("error", "invalid_build"))
			_refresh_system_panel()
			return
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
	in_arena = true
	battle_over = false
	battle_victory = false
	base_panel.visible = false
	systems_panel.visible = false
	hud_panel.visible = presentation_enabled
	return_button.visible = presentation_enabled
	player_position = _arena_rect().get_center() + Vector2(-220.0, 100.0)
	player_health = player_maximum_health
	attack_cooldown_ticks = 0
	dodge_cooldown_ticks = 0
	dodge_remaining_ticks = 0
	marked_entity_id = 0
	hunter_mark_expires_tick = 0
	hunter_mark_cooldown_ticks = 0
	dash_cooldown_ticks = 0
	dash_remaining_ticks = 0
	dash_direction = Vector2.RIGHT
	dodge_started_tick = -1
	dash_started_tick = -1
	_reset_talent_runtime_state()
	player_last_displacement = Vector2.ZERO
	dodge_requested = false
	_reset_manual_attack_intent()
	hunter_mark_requested = false
	dash_requested = false
	mobility_input_buffer.clear()
	command_sequence = 0
	last_command_receipts.clear()
	last_attack_outcome.clear()
	attack_origins.clear()
	projectiles.clear()
	combat_feedback_marks.clear()
	_reset_combat_feedback_audio()
	presentation_event_cursor = 0
	player_action_timeline.reset()
	combat_event_stream.reset()
	proxy_decision_state = proxy_decision.initial_state(framework_resolved_proxy_build) if selected_mode == "Auto" else {}
	if selected_mode == "Auto" and proxy_decision_state.is_empty():
		last_save_message = "Deployment blocked: proxy_invalid_initial_state"
		_refresh_system_panel()
		proxy_runtime.end_contract()
		return
	last_proxy_failure = {}
	last_proxy_trace.clear()
	automation_smoke_failure = ""
	sim_tick = 0
	elapsed = 0.0
	fixed_clock.reset()
	shots = 0
	arrow_hits = 0
	defeated = 0
	last_damage_source_id = ""
	last_damage_tick = -1
	last_damage_amount = 0.0
	last_damage_direction = Vector2.ZERO
	battle_report = "Deployed: %s / %s. Proxy mode and loadout are locked for this contract." % [_preset_display_name(selected_preset), selected_mode]
	boss_damage = BigValue.from_float(0.0)
	_spawn_wave()
	player_position = _quantize_position(_clamp_to_arena(player_position, 14.0))
	_presentation_commit()


func _spawn_wave() -> void:
	## A new wave is a route reset: the enemy action presentation starts over.
	_reset_enemy_animation()
	_reset_manual_attack_intent()
	if player_action_timeline != null:
		player_action_timeline.reset()
	if combat_event_stream != null:
		combat_event_stream.reset()
	presentation_event_cursor = 0
	attack_origins.clear()
	combat_feedback_marks.clear()
	_reset_combat_feedback_audio()
	last_attack_outcome.clear()
	player_last_displacement = Vector2.ZERO
	enemies.clear()
	projectiles.clear()
	traces.clear()
	boss = null
	hazard_states.clear()
	elite_rule_ids.clear()
	elite_entity_id = 0
	elite_barrier_active = false
	reinforcements_summoned = false
	timed_bonus_available = true
	next_entity_id = 1
	next_enemy_action_instance_id = 1
	room_reward_snapshot = _empty_room_reward_snapshot()
	last_damage_source_id = ""
	last_damage_tick = -1
	last_damage_amount = 0.0
	last_damage_direction = Vector2.ZERO
	var center: Vector2 = _arena_rect().get_center()
	if embedded_session and not framework_room.is_empty():
		room_id = String(framework_room.get("room_id", framework_room.get("id", "embedded_room")))
		layout_id = String(framework_room.get("layout_id", framework_room.get("layout", "rectangle_arena")))
		objective_id = String(framework_room.get("objective_id", framework_room.get("objective", "clear")))
		room_drop_tags = (framework_room.get("drop_tags", []) as Array).duplicate(true)
		var roster: Array = framework_room.get("enemy_ids", [])
		var room_offsets := _layout_spawn_offsets(layout_id, roster.size() + (1 if not String(framework_room.get("boss_id", "")).is_empty() else 0))
		for index in roster.size():
			var kind_id := String(roster[index])
			enemies.append(EnemyData.new(center + room_offsets[index], float(EARLY_NORMAL_HEALTH_BY_KIND[kind_id]), false, index + 1, kind_id))
		next_entity_id = roster.size() + 1
		var boss_id := String(framework_room.get("boss_id", ""))
		if boss_id == "threshold_colossus":
			boss = EnemyData.new(center + room_offsets[roster.size()], 1200.0, true, next_entity_id, boss_id)
			next_entity_id += 1
			boss.core_vulnerable = true
			enemies.append(boss)
		for value in framework_room.get("elite_rule_ids", []):
			elite_rule_ids.append(String(value))
		if objective_id == "hunt_elite" and not enemies.is_empty() and not enemies[0].is_boss:
			elite_entity_id = enemies[0].entity_id
			var elite_health := float(EARLY_ELITE_HEALTH_BY_KIND[enemies[0].kind_id])
			enemies[0].health = elite_health
			enemies[0].maximum_health = elite_health
		for value in framework_room.get("hazard_ids", []):
			hazard_states.append(_new_hazard_state(String(value), center))
		_update_room_rules_tick()
		return
	room_id = "legacy_smoke"
	layout_id = "rectangle_arena"
	objective_id = "hunt_elite"
	room_drop_tags = []
	var offsets: Array[Vector2] = [Vector2(-70.0, -150.0), Vector2(115.0, -125.0), Vector2(210.0, 25.0), Vector2(125.0, 150.0), Vector2(-65.0, 165.0), Vector2(-210.0, -45.0)]
	var kinds: Array[String] = ["melee_pursuer", "melee_pursuer", "charging_raider", "charging_raider", "fan_ranged", "fan_ranged"]
	for index in offsets.size():
		enemies.append(EnemyData.new(center + offsets[index], 72.0, false, index + 1, kinds[index]))
	boss = EnemyData.new(center + Vector2(250.0, -40.0), 1200.0, true, 7, "threshold_colossus")
	boss.core_vulnerable = true
	enemies.append(boss)
	next_entity_id = 8


func _simulate_tick() -> void:
	sim_tick += 1
	elapsed = float(sim_tick) / float(SIM_TICKS_PER_SECOND)
	attack_cooldown_ticks = maxi(0, attack_cooldown_ticks - 1)
	dodge_cooldown_ticks = maxi(0, dodge_cooldown_ticks - 1)
	hunter_mark_cooldown_ticks = maxi(0, hunter_mark_cooldown_ticks - 1)
	dash_cooldown_ticks = maxi(0, dash_cooldown_ticks - 1)
	_advance_mobility_counters()
	_process_player_action_events(player_action_timeline.advance(sim_tick))
	_update_hunter_mark_tick()
	_update_room_rules_tick()
	_update_talent_runtime_tick()
	_refresh_hazard_states_tick()
	var commands: Array[Dictionary]
	if embedded_session and automation_smoke and selected_mode == "Manual":
		commands = _automation_smoke_manual_commands()
	else:
		commands = _auto_commands() if selected_mode == "Auto" else _manual_commands()
	var buffered_mobility := _take_ready_mobility_command()
	if not buffered_mobility.is_empty():
		commands.append(buffered_mobility)
	var arbitration: Dictionary = CombatCommandProtocolScript.arbitrate(commands, sim_tick, _equipped_ability_ids(), true)
	last_command_receipts = (arbitration.get("receipts", []) as Array).duplicate(true)
	var movement := Vector2.ZERO
	var speed_scale := 1.0
	for receipt: Dictionary in last_command_receipts:
		if String(receipt.get("status", "")) == CombatCommandProtocolScript.STATUS_REJECTED:
			var rejected_command: Dictionary = receipt.get("command", {})
			attack_command_sources.erase(int(rejected_command.get("sequence", -1)))
			_emit_command_receipt(rejected_command, "rejected", String(receipt.get("reason", "invalid_command")))
	for command: Dictionary in arbitration.get("commands", []):
		match String(command.get("kind", "")):
			CombatCommandProtocolScript.KIND_MOVE:
				movement = _direction_from_command(command)
				speed_scale = float(command.get("speed_milli", 1000)) / 1000.0
				_emit_command_receipt(command, "accepted", "ok")
			CombatCommandProtocolScript.KIND_STOP_MOVE:
				movement = Vector2.ZERO
				speed_scale = 0.0
				_emit_command_receipt(command, "accepted", "ok")
			CombatCommandProtocolScript.KIND_DODGE:
				var dodge_ok := _start_dodge_from_command(_direction_from_command(command))
				var dodge_reason := "ok" if dodge_ok else _dodge_rejection_reason()
				if not dodge_ok and dodge_reason == "mobility_conflict" and _buffer_mobility_command(command):
					dodge_reason = "mobility_buffered"
				_emit_command_receipt(command, "accepted" if dodge_ok else ("buffered" if dodge_reason == "mobility_buffered" else "rejected"), dodge_reason)
			CombatCommandProtocolScript.KIND_CAST:
				_execute_cast_command(command)
	_process_player_action_events(player_action_timeline.advance(sim_tick))
	_advance_player_tick(movement, speed_scale)
	_update_enemies_tick()
	_advance_piercing_projectiles_tick()
	_resolve_hazard_hits_tick()
	_check_battle_end()
	if automation_smoke and not battle_over and sim_tick >= SIM_TICKS_PER_SECOND * 180:
		_fail_automation_smoke("timeout ticks=%d casts=%d" % [sim_tick, shots])


func _manual_commands() -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction != Vector2.ZERO:
		commands.append(_move_command(direction, 1.0))
	if dodge_requested:
		commands.append(_dodge_command(direction if direction != Vector2.ZERO else player_facing))
	dodge_requested = false
	if hunter_mark_requested:
		var mark_target := _nearest_enemy(HUNTER_MARK_RANGE_MULTIPLIER * locked_targeting_distance)
		commands.append(_cast_command("hunter_mark", mark_target.entity_id if mark_target != null else 0))
	hunter_mark_requested = false
	if dash_requested:
		commands.append(_cast_command("dash", 0, direction if direction != Vector2.ZERO else player_facing))
	dash_requested = false
	var held_source: String = manual_combat_input.attack_source(_pointer_is_over_hud()) if manual_combat_input != null else ""
	var attack_source: String = attack_requested_source if attack_requested else held_source
	## A live world pointer owns targeting while it is held. This also covers a
	## keyboard edge received during the same hold: assisted aim cannot silently
	## override the explicit entity lock.
	if held_source == ATTACK_SOURCE_POINTER:
		attack_source = ATTACK_SOURCE_POINTER
	elif attack_source.is_empty() and attack_requested:
		attack_source = ATTACK_SOURCE_ASSISTED
	var attack_target: EnemyData
	if attack_source == ATTACK_SOURCE_POINTER:
		var pointer_target_id := attack_requested_target_entity_id if attack_requested_source == ATTACK_SOURCE_POINTER else manual_pointer_target_entity_id
		attack_target = _enemy_by_entity_id(pointer_target_id)
		if pointer_target_id == manual_pointer_target_entity_id and manual_pointer_target_entity_id > 0:
			_refresh_manual_pointer_lock()
		if attack_target == null or attack_target.health <= 0.0:
			attack_target = null
			if manual_pointer_target_entity_id > 0:
				manual_pointer_status = POINTER_STATUS_LOST
		elif player_position.distance_to(attack_target.position) > locked_targeting_distance:
			if pointer_target_id == manual_pointer_target_entity_id:
				manual_pointer_status = POINTER_STATUS_OUT_OF_RANGE
			attack_target = null
	else:
		attack_target = _preferred_skill_one_target()
	var held_repeat_requested: bool = not held_source.is_empty() \
		and held_source == attack_source \
		and _held_attack_window_open(attack_target)
	if (attack_requested and attack_target != null) or held_repeat_requested:
		var attack_direction := player_position.direction_to(attack_target.position)
		var attack_command := _cast_command("piercing_arrow", attack_target.entity_id, attack_direction)
		attack_command_sources[int(attack_command.get("sequence", -1))] = attack_source
		commands.append(attack_command)
		_clear_input_feedback()
	elif attack_requested and attack_source == ATTACK_SOURCE_ASSISTED:
		## Assisted input retains the old explicit rejection receipt when no legal
		## target exists; pointer input intentionally has no nearest-target fallback.
		var rejected_command := _cast_command("piercing_arrow", 0, player_facing)
		attack_command_sources[int(rejected_command.get("sequence", -1))] = attack_source
		commands.append(rejected_command)
		_show_assisted_rejection_feedback()
	_clear_pending_attack_edge()
	return commands


## One actionable line when an assisted attempt cannot fire, using the same
## read-only nearest-target state the HUD cells already show. The rejected
## command receipt is unchanged: buffering, targeting and simulation are
## untouched, and the hint cannot fire anything by itself. This branch only
## runs when no living target exists; an out-of-range nearest target still
## queues its cast and is cued where the authority rejects it.
func _show_assisted_rejection_feedback() -> void:
	_show_input_feedback("暂无目标 · 靠近敌人后按空格")


## A held source submits once when the next action can enter the shared four-tick
## buffer. Existing buffered input owns that future slot, so holding cannot replace
## it every simulation tick or churn command receipts.
func _held_attack_window_open(target: EnemyData) -> bool:
	if target == null or player_position.distance_to(target.position) > locked_targeting_distance:
		return false
	var action_state := _player_attack_ui_state()
	return bool(action_state.get("request_open", false)) and not bool(action_state.get("buffered", false))


func _automation_smoke_manual_commands() -> Array[Dictionary]:
	# The Boss contract remains Manual. This deterministic harness supplies only
	# inputs a player can issue; combat, phase changes, hazards, and victory all
	# remain authoritative Main simulation outcomes.
	var commands: Array[Dictionary] = []
	var target: EnemyData = _nearest_enemy()
	if target == null:
		return commands
	var toward := target.position - player_position
	var distance := toward.length()
	var direction := toward.normalized() if distance > 0.001 else player_facing
	var dodge_required := _automation_smoke_dodge_required()
	if dodge_required:
		var vertical := Vector2.DOWN if player_position.y < target.position.y else Vector2.UP
		commands.append(_move_command(vertical, 1.0))
	elif distance > locked_targeting_distance * 0.82:
		commands.append(_move_command(direction, 0.72))
	if hunter_mark_cooldown_ticks == 0 and _is_skill_equipped(1, "hunter_mark"):
		commands.append(_cast_command("hunter_mark", target.entity_id))
	if dodge_cooldown_ticks == 0 and dodge_required:
		commands.append(_dodge_command(Vector2.DOWN if player_position.y < target.position.y else Vector2.UP))
	if distance <= locked_targeting_distance and attack_cooldown_ticks <= PlayerActionTimelineScript.INPUT_BUFFER_TICKS:
		commands.append(_cast_command("piercing_arrow", target.entity_id, direction))
	return commands


func _automation_smoke_dodge_required() -> bool:
	if dodge_cooldown_ticks > 0:
		return false
	for hazard: Dictionary in hazard_states:
		if String(hazard.get("id", "")) != "moving_fireline" or String(hazard.get("phase", "")) != "active":
			continue
		var line_x := float((hazard.get("origin", Vector2.ZERO) as Vector2).x)
		var dodge_step := DODGE_SPEED * SIM_STEP_SECONDS
		if absf(player_position.x - line_x) <= float(hazard.get("width", 0.0)) * 0.5 + dodge_step:
			return true
	if boss != null and boss.impact_tick == sim_tick + 1 and _boss_shape_contains(boss.target_shape, player_position):
		return true
	return false


func _on_hud_skill_one_requested() -> void:
	if selected_mode == "Manual" and in_arena and not battle_over:
		_queue_assisted_attack()


func _on_hud_skill_two_requested() -> void:
	if selected_mode == "Manual" and in_arena and not battle_over and _is_skill_equipped(1, "hunter_mark"):
		hunter_mark_requested = true


func _on_hud_skill_three_requested() -> void:
	if selected_mode == "Manual" and in_arena and not battle_over and _is_skill_equipped(2, "dash"):
		dash_requested = true


func _on_hud_dodge_requested() -> void:
	if selected_mode == "Manual" and in_arena and not battle_over:
		dodge_requested = true


func _pointer_is_over_hud() -> bool:
	return hud_panel != null and hud_panel.visible and bool(hud_panel.call("is_pointer_over_interface"))


func _auto_commands() -> Array[Dictionary]:
	var result: Dictionary = ProxyDecisionScript.decide(_public_proxy_snapshot(), framework_resolved_proxy_build, proxy_decision_state, command_sequence)
	last_proxy_trace.clear()
	for trace_entry: Variant in result.get("trace", []):
		last_proxy_trace.append(String(trace_entry))
	if not bool(result.get("ok", false)):
		last_proxy_failure = {
			"stage": "decision",
			"category": "protocol",
			"reason": String(result.get("error", "invalid_proxy_decision")),
			"tick": sim_tick,
		}
		return []
	proxy_decision_state = (result.get("next_state", {}) as Dictionary).duplicate(true)
	command_sequence = int(result.get("next_sequence", command_sequence))
	last_proxy_failure = {}
	return (result.get("commands", []) as Array).duplicate(true)


func _public_proxy_snapshot() -> Dictionary:
	var public_geometry := _walkable_geometry(14.0).duplicate(true)
	## Public geometry describes only the space the actor may occupy. Route and
	## room identifiers remain private even if a future helper revision carries
	## adapter metadata alongside the geometric primitives.
	public_geometry.erase("layout_id")
	var observations: Array = framework_resolved_proxy_build.get("observation_contract", [])
	var include_classification := "enemy.public_classification_tags" in observations
	var visible: Array[Dictionary] = []
	for enemy: EnemyData in enemies:
		var entry := {
			"entity_id": enemy.entity_id,
			"position": enemy.position,
			"health": enemy.health,
			## Action legality is part of enemy.basic. It reveals no barrier rule,
			## phase duration, or future opening tick.
			"targetable": enemy.health > 0.0 and not _piercing_arrow_target_is_currently_blocked(enemy),
		}
		if include_classification:
			var classification_tags: Array[String] = []
			if enemy.is_boss:
				classification_tags.append("boss")
			if enemy.entity_id == elite_entity_id:
				classification_tags.append("elite")
			if enemy.entity_id == marked_entity_id:
				classification_tags.append("marked")
			entry["classification_tags"] = classification_tags
		visible.append(entry)
	return {
		"snapshot_version": ProxyDecisionScript.SNAPSHOT_VERSION,
		"tick": sim_tick,
		"actor_id": "ranger",
		"player_position": player_position,
		"facing": player_facing,
		"action_state": _player_authority_action_state(),
		"attack_ready_tick": sim_tick + attack_cooldown_ticks,
		"targeting_distance": locked_targeting_distance,
		"visible_enemies": visible,
		"walkable_geometry": public_geometry,
	}


func _player_authority_action_state() -> String:
	if dodge_remaining_ticks > 0:
		return "dodge"
	if dash_remaining_ticks > 0:
		return "dash"
	return player_action_timeline.phase_at(sim_tick)


func _move_command(direction: Vector2, speed_scale: float) -> Dictionary:
	var milli := _direction_to_milli(direction)
	var result := CombatCommandProtocolScript.move(sim_tick, "ranger", command_sequence, milli.x, milli.y, clampi(roundi(speed_scale * 1000.0), 1, 1000))
	command_sequence += 1
	return result


func _dodge_command(direction: Vector2) -> Dictionary:
	var milli := _direction_to_milli(direction)
	var result := CombatCommandProtocolScript.dodge(sim_tick, "ranger", command_sequence, milli.x, milli.y)
	command_sequence += 1
	return result


func _cast_command(ability_id: String, target_entity_id: int, direction: Vector2 = Vector2.ZERO) -> Dictionary:
	var result: Dictionary
	if ability_id in ["dash", "piercing_arrow"]:
		var direction_milli := _direction_to_milli(direction)
		result = CombatCommandProtocolScript.cast(sim_tick, "ranger", command_sequence, ability_id, target_entity_id, direction_milli.x, direction_milli.y)
	else:
		result = CombatCommandProtocolScript.cast(sim_tick, "ranger", command_sequence, ability_id, target_entity_id)
	command_sequence += 1
	return result


func _direction_to_milli(direction: Vector2) -> Vector2i:
	var normalized := direction.normalized() if direction != Vector2.ZERO else player_facing.normalized()
	if normalized == Vector2.ZERO:
		normalized = Vector2.RIGHT
	return Vector2i(roundi(normalized.x * 1000.0), roundi(normalized.y * 1000.0))


func _direction_from_command(command: Dictionary) -> Vector2:
	var direction := Vector2(float(command.get("direction_x_milli", 0)), float(command.get("direction_y_milli", 0))) / 1000.0
	return direction.normalized() if direction != Vector2.ZERO else Vector2.ZERO


func _equipped_ability_ids() -> Array[String]:
	var result: Array[String] = ["piercing_arrow"]
	if _is_skill_equipped(1, "hunter_mark"):
		result.append("hunter_mark")
	if _is_skill_equipped(2, "dash"):
		result.append("dash")
	return result


func _emit_command_receipt(command: Variant, status: String, reason: String) -> void:
	combat_event_stream.emit(sim_tick, "command_receipt", {
		"status": status,
		"reason": reason,
		"command": command.duplicate(true) if command is Dictionary else {},
	})


func _execute_cast_command(command: Dictionary) -> void:
	var ability_id := String(command.get("ability_id", ""))
	var accepted := false
	var reason := "invalid_ability"
	match ability_id:
		"hunter_mark":
			accepted = _cast_hunter_mark(int(command.get("target_entity_id", 0)))
			reason = "ok" if accepted else _hunter_mark_rejection_reason(int(command.get("target_entity_id", 0)))
		"dash":
			accepted = _start_dash_from_command(_direction_from_command(command))
			reason = "ok" if accepted else _dash_rejection_reason()
			if not accepted and reason == "mobility_conflict" and _buffer_mobility_command(command):
				reason = "mobility_buffered"
		"piercing_arrow":
			var sequence := int(command.get("sequence", -1))
			var default_source := ATTACK_SOURCE_PROXY if selected_mode == "Auto" else ATTACK_SOURCE_ASSISTED
			var input_source := String(attack_command_sources.get(sequence, default_source))
			attack_command_sources.erase(sequence)
			var receipt := _request_piercing_arrow(int(command.get("target_entity_id", 0)), _direction_from_command(command), input_source)
			accepted = bool(receipt.get("accepted", false))
			reason = String(receipt.get("reason", "")) if not accepted else String(receipt.get("status", "accepted"))
			if not accepted and reason == "target_out_of_range" and selected_mode == "Manual" and input_source != ATTACK_SOURCE_PROXY:
				## The authority rejected this assist for range only here. Same
				## read-only truth as the 射程外 cell, one actionable next step.
				_show_input_feedback("目标在射程外 · 靠近后再射")
	_emit_command_receipt(command, "accepted" if accepted else ("buffered" if reason == "mobility_buffered" else "rejected"), reason)


func _buffer_mobility_command(command: Dictionary) -> bool:
	var remaining := maxi(dodge_remaining_ticks, dash_remaining_ticks)
	if remaining <= 0 or remaining > MOBILITY_INPUT_BUFFER_TICKS:
		return false
	var kind := String(command.get("kind", ""))
	var ability_id := String(command.get("ability_id", ""))
	if kind != CombatCommandProtocolScript.KIND_DODGE and not (kind == CombatCommandProtocolScript.KIND_CAST and ability_id == CombatCommandProtocolScript.ABILITY_DASH):
		return false
	mobility_input_buffer = {
		"kind": kind,
		"ability_id": ability_id,
		"direction_x_milli": int(command.get("direction_x_milli", 0)),
		"direction_y_milli": int(command.get("direction_y_milli", 0)),
		"request_tick": sim_tick,
		"expires_tick": sim_tick + MOBILITY_INPUT_BUFFER_TICKS,
	}
	return true


func _take_ready_mobility_command() -> Dictionary:
	if mobility_input_buffer.is_empty():
		return {}
	if sim_tick > int(mobility_input_buffer.get("expires_tick", -1)):
		mobility_input_buffer.clear()
		return {}
	if dodge_remaining_ticks > 0 or dash_remaining_ticks > 0:
		return {}
	var kind := String(mobility_input_buffer.get("kind", ""))
	var x := int(mobility_input_buffer.get("direction_x_milli", 0))
	var y := int(mobility_input_buffer.get("direction_y_milli", 0))
	var command: Dictionary = {}
	if kind == CombatCommandProtocolScript.KIND_DODGE and dodge_cooldown_ticks == 0:
		command = _dodge_command(Vector2(float(x), float(y)) / 1000.0)
	elif kind == CombatCommandProtocolScript.KIND_CAST and String(mobility_input_buffer.get("ability_id", "")) == CombatCommandProtocolScript.ABILITY_DASH and dash_cooldown_ticks == 0 and _is_skill_equipped(2, "dash"):
		command = _cast_command("dash", 0, Vector2(float(x), float(y)) / 1000.0)
	else:
		mobility_input_buffer.clear()
		return {}
	mobility_input_buffer.clear()
	return command


func _advance_mobility_counters() -> void:
	if dodge_remaining_ticks > 0:
		dodge_remaining_ticks -= 1
		if dodge_remaining_ticks == 0:
			combat_event_stream.emit(sim_tick, "displacement_ended", {"actor_id": "ranger", "kind": "dodge", "start_tick": dodge_started_tick, "actual_to": player_position})
	if dash_remaining_ticks > 0:
		dash_remaining_ticks -= 1
		if dash_remaining_ticks == 0:
			combat_event_stream.emit(sim_tick, "displacement_ended", {"actor_id": "ranger", "kind": "dash", "start_tick": dash_started_tick, "actual_to": player_position})


func _start_dodge_from_command(input_direction: Vector2) -> bool:
	if dodge_cooldown_ticks > 0 or dodge_remaining_ticks > 0 or dash_remaining_ticks > 0:
		return false
	if not bool(talent_capabilities.get("mobility_preserves_mark_and_lineage", false)):
		_process_timeline_interrupt(player_action_timeline.interrupt(sim_tick, "dodge"))
	dodge_direction = input_direction.normalized() if input_direction != Vector2.ZERO else player_facing.normalized()
	if dodge_direction == Vector2.ZERO:
		dodge_direction = Vector2.RIGHT
	## Facing is authoritative action state. Commit the accepted displacement
	## direction here so four-way dodge art and the facing marker cannot retain the
	## pre-dodge direction while movement travels elsewhere.
	player_facing = dodge_direction
	dodge_remaining_ticks = DODGE_DURATION_TICKS
	dodge_cooldown_ticks = _talent_scaled_cooldown(DODGE_COOLDOWN_TICKS)
	dodge_started_tick = sim_tick
	combat_event_stream.emit(sim_tick, "displacement_started", {
		"actor_id": "ranger", "kind": "dodge", "start_tick": sim_tick,
		"end_tick": sim_tick + DODGE_DURATION_TICKS, "from": player_position,
		"intended_to": player_position + dodge_direction * DODGE_SPEED * SIM_STEP_SECONDS * DODGE_DURATION_TICKS,
		"invulnerable": true,
	})
	return true


func _cast_hunter_mark(target_entity_id: int = 0) -> bool:
	if not _is_skill_equipped(1, "hunter_mark") or hunter_mark_cooldown_ticks > 0:
		return false
	var target := _enemy_by_entity_id(target_entity_id) if target_entity_id > 0 else _nearest_enemy(HUNTER_MARK_RANGE_MULTIPLIER * locked_targeting_distance)
	if target == null or target.health <= 0.0 or player_position.distance_to(target.position) > HUNTER_MARK_RANGE_MULTIPLIER * locked_targeting_distance:
		return false
	_advance_three_skill_sequence("hunter_mark")
	marked_entity_id = target.entity_id
	hunter_mark_expires_tick = sim_tick + _talent_scaled_ticks(HUNTER_MARK_DURATION_TICKS, "hunter_mark_duration_multiplier")
	hunter_mark_cooldown_ticks = HUNTER_MARK_COOLDOWN_TICKS
	battle_report = "猎人印记锁定：%s。" % _enemy_public_label(target)
	return true


func _start_dash_from_command(input_direction: Vector2) -> bool:
	if not _is_skill_equipped(2, "dash") or dash_cooldown_ticks > 0 or dash_remaining_ticks > 0 or dodge_remaining_ticks > 0:
		return false
	if not bool(talent_capabilities.get("mobility_preserves_mark_and_lineage", false)):
		_process_timeline_interrupt(player_action_timeline.interrupt(sim_tick, "dash"))
	dash_direction = input_direction.normalized() if input_direction != Vector2.ZERO else player_facing.normalized()
	if dash_direction == Vector2.ZERO:
		dash_direction = Vector2.RIGHT
	_advance_three_skill_sequence("dash")
	var dash_duration := _talent_scaled_ticks(DASH_DURATION_TICKS, "dash_duration_multiplier")
	dash_remaining_ticks = dash_duration
	dash_cooldown_ticks = DASH_COOLDOWN_TICKS
	dash_started_tick = sim_tick
	combat_event_stream.emit(sim_tick, "displacement_started", {
		"actor_id": "ranger", "kind": "dash", "start_tick": sim_tick,
		"end_tick": sim_tick + dash_duration, "from": player_position,
		"intended_to": player_position + dash_direction * DASH_TOTAL_DISTANCE,
		"invulnerable": false,
	})
	return true


func _dodge_rejection_reason() -> String:
	if dodge_cooldown_ticks > 0:
		return "cooldown_active"
	if dodge_remaining_ticks > 0 or dash_remaining_ticks > 0:
		return "mobility_conflict"
	return "action_locked"


func _dash_rejection_reason() -> String:
	if not _is_skill_equipped(2, "dash"):
		return "ability_not_equipped"
	if dash_cooldown_ticks > 0:
		return "cooldown_active"
	if dash_remaining_ticks > 0 or dodge_remaining_ticks > 0:
		return "mobility_conflict"
	return "action_locked"


func _hunter_mark_rejection_reason(target_entity_id: int) -> String:
	if not _is_skill_equipped(1, "hunter_mark"):
		return "ability_not_equipped"
	if hunter_mark_cooldown_ticks > 0:
		return "cooldown_active"
	var target := _enemy_by_entity_id(target_entity_id)
	if target == null or target.health <= 0.0:
		return "target_invalid"
	if player_position.distance_to(target.position) > HUNTER_MARK_RANGE_MULTIPLIER * locked_targeting_distance:
		return "target_out_of_range"
	return "action_locked"


func _update_hunter_mark_tick() -> void:
	if marked_entity_id == 0:
		return
	var target := _enemy_by_entity_id(marked_entity_id)
	if target != null and target.health > 0.0 and player_position.distance_to(target.position) > HUNTER_MARK_RANGE_MULTIPLIER * locked_targeting_distance:
		if bool(talent_capabilities.get("lost_mark_candidate_ticks", 0.0) > 0.0) and sim_tick < hunter_mark_expires_tick:
			hunter_mark_candidate_entity_id = target.entity_id
			hunter_mark_candidate_expires_tick = sim_tick + int(round(float(talent_capabilities.lost_mark_candidate_ticks)))
			marked_entity_id = 0
			hunter_mark_expires_tick = 0
		return
	if target != null and target.health > 0.0 and sim_tick < hunter_mark_expires_tick:
		return
	if target != null and target.health > 0.0 and bool(talent_capabilities.get("lost_mark_candidate_ticks", 0.0) > 0.0):
		hunter_mark_candidate_entity_id = target.entity_id
		hunter_mark_candidate_expires_tick = sim_tick + int(round(float(talent_capabilities.lost_mark_candidate_ticks)))
		marked_entity_id = 0
		hunter_mark_expires_tick = 0
		return
	marked_entity_id = 0
	hunter_mark_candidate_entity_id = 0
	hunter_mark_candidate_expires_tick = 0
	hunter_mark_expires_tick = 0


func _update_talent_runtime_tick() -> void:
	if hunter_mark_candidate_entity_id > 0 and sim_tick > hunter_mark_candidate_expires_tick:
		hunter_mark_candidate_entity_id = 0
		hunter_mark_candidate_expires_tick = 0


func _advance_three_skill_sequence(kind: String) -> void:
	if not talent_capabilities.has("three_skill_rhythm_windup_ticks"):
		return
	if three_skill_bonus_ready:
		return
	var expected := 1 + three_skill_sequence_stage
	var stage := {"piercing_arrow": 1, "hunter_mark": 2, "dash": 3}.get(kind, 0) as int
	if stage != expected:
		three_skill_sequence_stage = 0
		if kind == "piercing_arrow":
			_advance_three_skill_sequence("piercing_arrow")
		return
	three_skill_sequence_stage = stage
	if stage == 3:
		three_skill_bonus_ready = true


func _advance_player_tick(direction: Vector2, speed_scale: float) -> void:
	var before := player_position
	if dash_remaining_ticks > 0:
		player_facing = dash_direction
		player_position += dash_direction * (DASH_TOTAL_DISTANCE / float(_talent_scaled_ticks(DASH_DURATION_TICKS, "dash_duration_multiplier")))
	elif dodge_remaining_ticks > 0:
		player_position += dodge_direction * DODGE_SPEED * SIM_STEP_SECONDS
	elif direction != Vector2.ZERO:
		var action_phase: String = player_action_timeline.phase_at(sim_tick)
		var action_speed_scale := 0.38 if action_phase == PlayerActionTimelineScript.PHASE_WINDUP else (0.72 if action_phase == PlayerActionTimelineScript.PHASE_RECOVERY else 1.0)
		if action_phase == PlayerActionTimelineScript.PHASE_IDLE:
			player_facing = direction
		player_position += direction * PLAYER_SPEED * speed_scale * action_speed_scale * SIM_STEP_SECONDS
	player_position = _quantize_position(_clamp_to_arena(player_position, 14.0))
	player_last_displacement = _quantize_position(player_position - before)


func _cast_skill_one() -> bool:
	var target: EnemyData = _preferred_skill_one_target()
	if target == null:
		return false
	return bool(_request_piercing_arrow(target.entity_id, Vector2.ZERO, ATTACK_SOURCE_ASSISTED).get("accepted", false))


func _request_piercing_arrow(target_entity_id: int, requested_aim: Vector2 = Vector2.ZERO, input_source: String = ATTACK_SOURCE_ASSISTED) -> Dictionary:
	var target := _enemy_by_entity_id(target_entity_id)
	if target == null or target.health <= 0.0:
		return {"accepted": false, "status": "rejected", "reason": "target_invalid"}
	if player_position.distance_to(target.position) > locked_targeting_distance:
		return {"accepted": false, "status": "rejected", "reason": "target_out_of_range"}
	var aim := requested_aim.normalized() if requested_aim != Vector2.ZERO else player_position.direction_to(target.position)
	if aim == Vector2.ZERO:
		aim = player_facing if player_facing != Vector2.ZERO else Vector2.RIGHT
	var ready_tick := sim_tick + attack_cooldown_ticks
	var windup_ticks := PlayerActionTimelineScript.WINDUP_TICKS
	if three_skill_bonus_ready:
		windup_ticks = clampi(int(round(float(talent_capabilities.get("three_skill_rhythm_windup_ticks", windup_ticks)))), 1, PlayerActionTimelineScript.WINDUP_TICKS)
	var queued: Dictionary = player_action_timeline.snapshot().get("buffered", {})
	windup_ticks = mini(windup_ticks, int(queued.get("windup_ticks", PlayerActionTimelineScript.WINDUP_TICKS)))
	var receipt: Dictionary = player_action_timeline.request_attack(sim_tick, target_entity_id, aim, ready_tick, windup_ticks)
	if bool(receipt.get("accepted", false)):
		if three_skill_bonus_ready:
			three_skill_bonus_ready = false
			three_skill_sequence_stage = 0
		var request_id := int(receipt.get("request_id", 0))
		attack_request_sources[request_id] = _normalized_attack_source(input_source)
		var replaced_request_id := int(receipt.get("replaced_request_id", 0))
		if replaced_request_id > 0:
			attack_request_sources.erase(replaced_request_id)
		if String(receipt.get("status", "")) == "started":
			attack_cooldown_ticks = ATTACK_COOLDOWN_TICKS
			player_facing = aim
			var action_instance_id := int(receipt.get("action_instance_id", 0))
			if action_instance_id > 0:
				attack_action_request_ids[action_instance_id] = request_id
		battle_report = "穿刺箭已缓冲，等待动作窗口。" if String(receipt.get("status", "")) in ["buffered", "replaced"] else "穿刺箭拉弓中。"
	return receipt


func _normalized_attack_source(value: String) -> String:
	if value in [ATTACK_SOURCE_POINTER, ATTACK_SOURCE_PROXY]:
		return value
	return ATTACK_SOURCE_ASSISTED


func _process_player_action_events(events: Array) -> void:
	for value: Variant in events:
		if not value is Dictionary:
			continue
		var event: Dictionary = value
		var event_tick := int(event.get("tick", sim_tick))
		var action_instance_id := int(event.get("action_instance_id", 0))
		match String(event.get("type", "")):
			"buffered_started":
				attack_cooldown_ticks = ATTACK_COOLDOWN_TICKS
				var buffered_request_id := int(event.get("request_id", 0))
				if action_instance_id > 0 and buffered_request_id > 0:
					attack_action_request_ids[action_instance_id] = buffered_request_id
			"action_started":
				var aim_data: Dictionary = event.get("aim_direction_milli", {})
				var aim := Vector2(float(aim_data.get("x", 0)), float(aim_data.get("y", 0))) / 1000.0
				if aim != Vector2.ZERO:
					player_facing = aim.normalized()
				var action_windup_ticks := int(event.get("windup_ticks", PlayerActionTimelineScript.WINDUP_TICKS))
				var release_frame := RangerAnimationScript.shoot_frame_at_tick(PlayerActionTimelineScript.WINDUP_TICKS)
				var release_offset := RangerAnimationScript.arrow_attachment_offset(
					RangerAnimationScript.facing_key(player_facing),
					release_frame,
					ArenaWorldViewScript.GAMEPLAY_TO_WORLD
				)
				var projectile_origin := player_position + release_offset
				var target := _enemy_by_entity_id(int(event.get("target_entity_id", 0)))
				var locked_direction := player_facing
				if target != null and manual_aim_resolver != null:
					var locked_anchor: Vector2 = manual_aim_resolver.target_anchor(_manual_aim_candidate(target))
					if projectile_origin.distance_squared_to(locked_anchor) > 0.000001:
						locked_direction = projectile_origin.direction_to(locked_anchor)
				attack_origins[action_instance_id] = {
					"actor_origin": player_position,
					"projectile_origin": projectile_origin,
					"release_offset": release_offset,
					"direction": locked_direction,
				}
				combat_event_stream.emit(event_tick, "action_accepted", {
					"action_instance_id": action_instance_id,
					"actor_id": "ranger",
					"action_id": "piercing_arrow",
					"target_entity_id": int(event.get("target_entity_id", 0)),
					"locked_origin": projectile_origin,
					"locked_direction": locked_direction,
					"impact_tick": event_tick + action_windup_ticks,
				})
			"action_impact":
				## The timeline's generic impact boundary is this weapon's release
				## boundary. The combat stream reserves action_impact for actual world
				## contact, emitted by _resolve_piercing_arrow_contact().
				_resolve_piercing_arrow(event)
			"action_ended":
				combat_event_stream.emit(event_tick, "action_ended", {"action_instance_id": action_instance_id, "actor_id": "ranger", "action_id": "piercing_arrow"})
				attack_origins.erase(action_instance_id)
				_forget_attack_action_source(action_instance_id)
			"action_interrupted":
				three_skill_sequence_stage = 0
				three_skill_bonus_ready = false
				combat_event_stream.emit(event_tick, "action_interrupted", {
					"action_instance_id": action_instance_id,
					"actor_id": "ranger",
					"action_id": "piercing_arrow",
					"reason": String(event.get("reason", "interrupted")),
				})
				attack_origins.erase(action_instance_id)
				_forget_attack_action_source(action_instance_id)


func _process_timeline_interrupt(result: Dictionary) -> void:
	var cleared_request_id := int(result.get("cleared_request_id", 0))
	if cleared_request_id > 0:
		attack_request_sources.erase(cleared_request_id)
	_process_player_action_events(result.get("events", []))


func _forget_attack_action_source(action_instance_id: int) -> void:
	var request_id := int(attack_action_request_ids.get(action_instance_id, 0))
	attack_action_request_ids.erase(action_instance_id)
	if request_id > 0:
		attack_request_sources.erase(request_id)


func _resolve_piercing_arrow(action_event: Dictionary) -> void:
	var action_instance_id := int(action_event.get("action_instance_id", 0))
	var release_tick := int(action_event.get("tick", sim_tick))
	var target_entity_id := int(action_event.get("target_entity_id", 0))
	var aim_data: Dictionary = action_event.get("aim_direction_milli", {})
	var aim := Vector2(float(aim_data.get("x", 0)), float(aim_data.get("y", 0))) / 1000.0
	if aim == Vector2.ZERO:
		aim = player_facing if player_facing != Vector2.ZERO else Vector2.RIGHT
	aim = aim.normalized()
	var origin_state: Variant = attack_origins.get(action_instance_id, {})
	var origin := player_position
	if origin_state is Dictionary:
		## Windup allows reduced movement. Spawn from the hand's release-frame socket
		## at the Ranger's current feet so the first arrow frame cannot lag behind the
		## moving actor. Direction, range, speed and damage remain frozen separately.
		origin = player_position + ((origin_state as Dictionary).get("release_offset", Vector2.ZERO) as Vector2)
		aim = (origin_state as Dictionary).get("direction", aim)
	var target := _enemy_by_entity_id(target_entity_id)
	shots += 1
	if projectiles.size() >= MAX_ACTIVE_PIERCING_PROJECTILES:
		last_attack_outcome = combat_event_stream.emit(release_tick, "attack_resolved", {
			"action_instance_id": action_instance_id, "source_id": "ranger/piercing_arrow",
			"target_entity_id": target_entity_id, "outcome": "miss",
			"contact_point": origin, "reason": "projectile_limit",
		})
		battle_report = "穿刺箭未能离弦：场上箭矢已达上限。"
		return
	var model: Dictionary = _current_model()
	if String(model.state) == PiercingArrowModelScript.STATE_CRITICAL and not first_critical_bonus_used:
		var bonus := maxi(0, int(talent_capabilities.get("first_critical_bonus_generations", 0)))
		if bonus > 0:
			model.g = int(model.g) + bonus
			model.total_events = (model.total_events as BigValue).add(BigValue.from_float(float(bonus)))
			model.total_events_float = float(model.total_events_float) + float(bonus)
			first_critical_bonus_used = true
	var target_marked := target != null and target.entity_id == marked_entity_id
	var damage_multiplier := HUNTER_MARK_DAMAGE_MULTIPLIER if target_marked else 1.0
	var aggregate_damage: BigValue = (model["total_events"] as BigValue).multiply(BigValue.from_float(locked_payload * damage_multiplier))
	var ordinary_damage := float(model["total_events_float"]) * locked_payload * damage_multiplier
	var speed := _current_projectile_speed()
	var projectile := ArrowProjectile.new(
		action_instance_id,
		target_entity_id,
		release_tick,
		origin,
		aim,
		locked_targeting_distance,
		speed,
		aggregate_damage,
		ordinary_damage,
		model["total_events"] as BigValue,
		locked_payload
	)
	projectiles.append(projectile)
	combat_event_stream.emit(release_tick, "projectile_spawned", {
		"action_instance_id": action_instance_id,
		"source_id": "ranger/piercing_arrow",
		"target_entity_id": target_entity_id,
		"origin": origin,
		"direction": aim,
		"maximum_range_milli": roundi(projectile.maximum_range * 1000.0),
		"speed_milli": roundi(projectile.speed * 1000.0),
	})
	battle_report = "穿刺箭已离弦。"


func _current_projectile_speed() -> float:
	var speed := 0.0
	if not locked_build.is_empty():
		speed = float((locked_build.get("final_parameters", {}) as Dictionary).get("v", 0.0))
	elif content_registry != null:
		speed = float(content_registry.preset_equipped_parameters.get("speed", 0.0))
	if not is_finite(speed) or speed <= 0.0:
		## Content validation normally makes this unreachable. A deterministic
		## fallback keeps a malformed test fixture bounded instead of immortal.
		return 1.0
	return speed


func _advance_piercing_projectiles_tick() -> void:
	for index: int in range(projectiles.size() - 1, -1, -1):
		var projectile := projectiles[index]
		## The release tick must present the arrow on the authored bow-hand socket.
		## Travel begins on the following fixed tick, preventing the first rendered
		## frame from jumping one full 30 Hz step away from the Ranger.
		if projectile.spawned_tick >= sim_tick:
			projectile.previous_position = projectile.position
			continue
		var remaining := maxf(0.0, projectile.maximum_range - projectile.distance_travelled)
		var step := minf(projectile.speed * SIM_STEP_SECONDS, remaining)
		projectile.previous_position = projectile.position
		projectile.distance_travelled = minf(projectile.maximum_range, projectile.distance_travelled + step)
		var next_position := projectile.origin + projectile.direction * projectile.distance_travelled
		var target := _enemy_by_entity_id(projectile.target_entity_id)
		var contact: Variant = _piercing_arrow_swept_contact(projectile.previous_position, next_position, target)
		if contact != null:
			projectile.position = contact as Vector2
			_resolve_piercing_arrow_contact(projectile, target, contact as Vector2)
			projectiles.remove_at(index)
			continue
		projectile.position = next_position
		if projectile.distance_travelled >= projectile.maximum_range:
			_resolve_piercing_arrow_miss(projectile)
			projectiles.remove_at(index)


func _resolve_piercing_arrow_contact(projectile: ArrowProjectile, target: EnemyData, contact_point: Vector2) -> void:
	combat_event_stream.emit(sim_tick, "action_impact", {
		"action_instance_id": projectile.action_instance_id,
		"actor_id": "ranger",
		"action_id": "piercing_arrow",
		"target_entity_id": target.entity_id,
		"contact_point": contact_point,
	})
	if _piercing_arrow_target_is_currently_blocked(target):
		three_skill_sequence_stage = 0
		three_skill_bonus_ready = false
		_add_impact_traces(contact_point, projectile.direction, 1)
		last_attack_outcome = combat_event_stream.emit(sim_tick, "attack_resolved", {
			"action_instance_id": projectile.action_instance_id, "source_id": "ranger/piercing_arrow",
			"target_entity_id": target.entity_id, "outcome": "blocked",
			"contact_point": contact_point, "barrier_id": "periodic_barrier",
		})
		battle_report = "穿刺箭被周期屏障阻断。"
		return
	projectile.aggregate_damage = projectile.aggregate_damage.add(retained_arrow_damage)
	arrow_hits += 1
	projectile.ordinary_damage += retained_arrow_ordinary_damage
	retained_arrow_damage = BigValue.from_float(0.0)
	retained_arrow_ordinary_damage = 0.0
	var health_before := target.health
	_advance_three_skill_sequence("piercing_arrow")
	var boss_before := _boss_remaining_display().to_short_string(6) if target.is_boss else ""
	if target.is_boss:
		boss_damage = boss_damage.add(projectile.aggregate_damage)
		if boss_damage.compare(boss_maximum) >= 0:
			target.health = 0.0
	else:
		target.health = snappedf(maxf(0.0, target.health - projectile.ordinary_damage), 0.001)
		_maybe_summon_reinforcements(target)
	target.hit_flash_until_tick = sim_tick + ENEMY_HIT_FLASH_TICKS
	_add_impact_traces(contact_point, projectile.direction, int(_current_model()["g"]))
	var outcome := "killed" if target.health <= 0.0 else "damage"
	last_attack_outcome = combat_event_stream.emit(sim_tick, "attack_resolved", {
		"action_instance_id": projectile.action_instance_id, "source_id": "ranger/piercing_arrow",
		"target_entity_id": target.entity_id, "outcome": outcome,
		"contact_point": contact_point, "aggregate_damage": projectile.aggregate_damage.to_short_string(6),
	})
	combat_event_stream.emit(sim_tick, "damage_applied", {
		"action_instance_id": projectile.action_instance_id, "source_id": "ranger/piercing_arrow",
		"target_id": "enemy/%d" % target.entity_id, "target_entity_id": target.entity_id,
		"amount": projectile.aggregate_damage.to_short_string(6),
		"health_before_milli": roundi(health_before * 1000.0), "health_after_milli": roundi(target.health * 1000.0),
		"boss_remaining_before": boss_before,
		"boss_remaining_after": _boss_remaining_display().to_short_string(6) if target.is_boss else "",
		"contact_point": contact_point, "incoming_direction": projectile.direction,
	})
	battle_report = "穿刺箭命中：%s 次箭事件 × %.0f 载荷 → %s 总伤害。" % [projectile.event_count.to_short_string(4), projectile.payload, projectile.aggregate_damage.to_short_string(4)]
	if target.health <= 0.0:
		defeated += 1
		combat_event_stream.emit(sim_tick, "death_applied", {
			"source_id": "ranger/piercing_arrow", "target_id": "enemy/%d" % target.entity_id,
			"target_entity_id": target.entity_id, "position": target.position,
		})
		enemies.erase(target)
		var canceled_request_id: int = player_action_timeline.cancel_buffered_target(target.entity_id)
		if canceled_request_id > 0:
			attack_request_sources.erase(canceled_request_id)
		## Presentation only: the detached death clip plays where the simulation
		## killed the enemy and never delays the despawn itself.
		_detach_enemy_corpse(target)
		_update_hunter_mark_tick()


func _resolve_piercing_arrow_miss(projectile: ArrowProjectile) -> void:
	var target := _enemy_by_entity_id(projectile.target_entity_id)
	three_skill_sequence_stage = 0
	three_skill_bonus_ready = false
	var target_invalid := target == null or target.health <= 0.0
	var reason := "target_invalid" if target_invalid else "left_frozen_path"
	var retention := clampf(float(talent_capabilities.get("expiry_payload_retention", 0.0)), 0.0, 1.0)
	if retention > 0.0:
		# A miss banks only this arrow's own payload; no target is damaged here.
		retained_arrow_damage = retained_arrow_damage.add(projectile.aggregate_damage.multiply(BigValue.from_float(retention)))
		retained_arrow_ordinary_damage += projectile.ordinary_damage * retention
	last_attack_outcome = combat_event_stream.emit(sim_tick, "attack_resolved", {
		"action_instance_id": projectile.action_instance_id, "source_id": "ranger/piercing_arrow",
		"target_entity_id": projectile.target_entity_id, "outcome": "miss",
		"contact_point": projectile.position, "reason": reason,
		"retained_payload_ratio": clampf(float(talent_capabilities.get("expiry_payload_retention", 0.0)), 0.0, 1.0),
	})
	if retention > 0.0:
		battle_report = "穿刺箭落空：保留 %.0f%% 载荷，待下一支命中箭兑现。" % (retention * 100.0)
	else:
		battle_report = "穿刺箭落空：锁定目标已失效。" if reason == "target_invalid" else "穿刺箭落空：锁定目标已离开冻结弹道。"


func _piercing_arrow_target_is_currently_blocked(target: EnemyData) -> bool:
	return target != null and target.entity_id == elite_entity_id and elite_barrier_active


## Swept segment against the intended target's current public aim circle. Other
## enemies cannot steal the projectile, and target movement cannot bend its path.
func _piercing_arrow_swept_contact(start: Vector2, finish: Vector2, target: EnemyData) -> Variant:
	if target == null or manual_aim_resolver == null:
		return null
	var candidate := _manual_aim_candidate(target)
	var anchor: Vector2 = manual_aim_resolver.target_anchor(candidate)
	var radius: float = manual_aim_resolver.target_radius(candidate)
	if radius <= 0.0:
		return null
	var segment := finish - start
	var segment_length := segment.length()
	if segment_length <= 0.0:
		return start if start.distance_squared_to(anchor) <= radius * radius else null
	var aim := segment / segment_length
	var projection: float = (anchor - start).dot(aim)
	var perpendicular_squared: float = (anchor - start).length_squared() - projection * projection
	var radius_squared: float = radius * radius
	if perpendicular_squared > radius_squared:
		return null
	var reach := sqrt(maxf(0.0, radius_squared - perpendicular_squared))
	var contact_distance: float = projection - reach
	var exit_distance: float = projection + reach
	if exit_distance < 0.0 or contact_distance > segment_length:
		return null
	return start + aim * clampf(contact_distance, 0.0, segment_length)


func _add_impact_traces(target_position: Vector2, aim: Vector2, generations: int) -> void:
	if not presentation_enabled:
		return
	var representatives: int = mini(4, maxi(2, generations))
	for index: int in representatives:
		var angle: float = -1.15 + 0.76 * float(index)
		var branch_end: Vector2 = target_position + aim.rotated(angle) * (14.0 + 4.0 * index)
		traces.append(ArrowTrace.new(target_position, branch_end))


func _update_enemies_tick() -> void:
	_refresh_hazard_states_tick()
	var ordered: Array[EnemyData] = enemies.duplicate()
	ordered.sort_custom(func(left: EnemyData, right: EnemyData) -> bool: return left.entity_id < right.entity_id)
	for enemy: EnemyData in ordered:
		_finish_enemy_recovery_if_due(enemy)
	var planned: Dictionary = enemy_tactics.plan(_enemy_tactics_snapshot())
	var intents := {}
	if bool(planned.get("ok", false)):
		for intent: Dictionary in planned.get("intents", []):
			intents[int(intent.get("entity_id", 0))] = intent
	else:
		battle_report = "敌人战术快照被拒绝：%s" % String(planned.get("error", "unknown"))
	for enemy: EnemyData in ordered:
		_update_enemy_tick(enemy, intents.get(enemy.entity_id, {}))
	_maybe_summon_reinforcements(_enemy_by_entity_id(elite_entity_id))


func _enemy_tactics_snapshot() -> Dictionary:
	var geometry := _walkable_geometry(16.0)
	var actors: Array[Dictionary] = []
	for enemy: EnemyData in enemies:
		var planning_state := enemy.action_state
		if planning_state == "none":
			planning_state = "range_hold" if enemy.kind_id == "fan_ranged" and enemy.tactic_state == "range_hold" else "idle"
		var actor := {
			"entity_id": enemy.entity_id,
			"kind_id": enemy.kind_id,
			"position": enemy.position,
			"action_state": planning_state,
			"health": enemy.health,
			"facing": enemy.facing if enemy.facing != Vector2.ZERO else Vector2.RIGHT,
			"next_action_ready_tick": enemy.next_action_ready_tick,
		}
		if enemy.is_boss:
			actor["phase"] = enemy.phase_id
			actor["next_action_index"] = enemy.next_action_index
		actors.append(actor)
	return {
		"snapshot_version": EnemyTacticsScript.SNAPSHOT_VERSION,
		"tick": sim_tick,
		"player_position": player_position,
		"arena_rect": geometry.bounds,
		"walkable_geometry": geometry,
		"enemies": actors,
		"hazards": _enemy_tactics_hazards(),
	}


func _enemy_tactics_hazards() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hazard: Dictionary in hazard_states:
		var phase := String(hazard.get("phase", ""))
		if phase not in ["warning", "active"]:
			continue
		var shape: Dictionary
		if String(hazard.get("id", "")) == "moving_fireline":
			var origin: Vector2 = hazard.get("origin", Vector2.ZERO)
			shape = {"shape": "rect", "rect": Rect2(origin - Vector2(float(hazard.get("width", 0.0)) * 0.5, 0.0), Vector2(float(hazard.get("width", 0.0)), float(hazard.get("length", 0.0))))}
		else:
			shape = {"shape": "circle", "center": hazard.get("origin", Vector2.ZERO), "radius": float(hazard.get("radius", 0.0))}
		result.append({("active_geometry" if phase == "active" else "warning_geometry"): shape})
	return result


func _maybe_summon_reinforcements(elite: EnemyData) -> void:
	if elite == null or elite.entity_id != elite_entity_id:
		return
	if "summon_reinforcements" not in elite_rule_ids or reinforcements_summoned:
		return
	if elite.health > elite.maximum_health * 0.5:
		return
	reinforcements_summoned = true
	var reinforcement_id := _allocate_entity_id()
	var spawn := _layout_spawn_offsets(layout_id, reinforcement_id)[reinforcement_id - 1]
	enemies.append(EnemyData.new(_arena_rect().get_center() + spawn, float(EARLY_NORMAL_HEALTH_BY_KIND["melee_pursuer"]), false, reinforcement_id, "melee_pursuer"))


func _update_room_rules_tick() -> void:
	elite_barrier_active = "periodic_barrier" in elite_rule_ids and elite_entity_id > 0 and sim_tick % ELITE_BARRIER_PERIOD_TICKS < ELITE_BARRIER_ACTIVE_TICKS
	if objective_id == "timed_break" and sim_tick > TIMED_BREAK_BONUS_TICKS:
		timed_bonus_available = false


func _update_hazards_tick() -> void:
	_refresh_hazard_states_tick()
	_resolve_hazard_hits_tick()


func _refresh_hazard_states_tick() -> void:
	for state in hazard_states:
		var cycle := sim_tick / HAZARD_CYCLE_TICKS
		var cycle_tick := sim_tick % HAZARD_CYCLE_TICKS
		state["cycle"] = cycle
		state["cycle_tick"] = cycle_tick
		state["phase"] = "warning" if cycle_tick < HAZARD_WARNING_TICKS else ("active" if cycle_tick < HAZARD_WARNING_TICKS + HAZARD_ACTIVE_TICKS else "recovery")
		if String(state.id) == "moving_fireline":
			var rect := _arena_rect()
			var progress := float(cycle_tick) / float(HAZARD_CYCLE_TICKS - 1)
			state["origin"] = _quantize_position(Vector2(lerpf(rect.position.x, rect.end.x, progress), rect.position.y))


func _resolve_hazard_hits_tick() -> void:
	for state in hazard_states:
		var cycle := int(state.get("cycle", sim_tick / HAZARD_CYCLE_TICKS))
		if state.phase == "active" and int(state.last_hit_cycle) != cycle and _hazard_contains(state, player_position):
			state["last_hit_cycle"] = cycle
			var source_id := "hazard/%s" % String(state.id)
			var applied := _damage_player(9.0 if String(state.id) == "moving_fireline" else 7.0, source_id)
			combat_event_stream.emit(sim_tick, "attack_resolved", {
				"action_instance_id": 0,
				"source_id": source_id,
				"target_id": "ranger",
				"outcome": "damage" if applied else "avoided",
				"contact_point": player_position,
			})


func _new_hazard_state(id: String, center: Vector2) -> Dictionary:
	if id == "moving_fireline":
		return {"id": id, "phase": "warning", "cycle": 0, "cycle_tick": 0, "last_hit_cycle": -1, "origin": _arena_rect().position, "direction": Vector2.DOWN, "length": _arena_rect().size.y, "width": 34.0, "radius": 0.0}
	return {"id": id, "phase": "warning", "cycle": 0, "cycle_tick": 0, "last_hit_cycle": -1, "origin": center + Vector2(70.0, 0.0), "direction": Vector2.ZERO, "length": 0.0, "width": 0.0, "radius": 82.0}


func _hazard_contains(state: Dictionary, point: Vector2) -> bool:
	if String(state.id) == "moving_fireline":
		return _point_in_lane(point, state.origin, state.direction, float(state.length), float(state.width))
	return point.distance_to(state.origin) <= float(state.radius)


func _enemy_by_entity_id(id: int) -> EnemyData:
	for enemy: EnemyData in enemies:
		if enemy.entity_id == id:
			return enemy
	return null


func _allocate_entity_id() -> int:
	var result := next_entity_id
	next_entity_id += 1
	return result


func _update_enemy_tick(enemy: EnemyData, intent: Dictionary = {}) -> void:
	if enemy.health <= 0.0:
		return
	if enemy.is_boss:
		_update_boss_tick(enemy, intent)
		return
	match enemy.kind_id:
		"charging_raider":
			_update_charger_tick(enemy, intent)
		"fan_ranged":
			_update_fan_tick(enemy, intent)
		_:
			_update_melee_tick(enemy, intent)


func _advance_action_state(enemy: EnemyData, active_ticks: int, recovery_ticks: int) -> bool:
	if enemy.action_state == "windup" and sim_tick >= enemy.impact_tick:
		enemy.action_state = "active"
		enemy.state_started_tick = sim_tick
		enemy.state_ends_tick = sim_tick + active_ticks
		return true
	if enemy.action_state == "active" and sim_tick >= enemy.state_ends_tick:
		enemy.action_state = "recovery"
		enemy.state_started_tick = sim_tick
		enemy.state_ends_tick = sim_tick + recovery_ticks
		return true
	if _finish_enemy_recovery_if_due(enemy):
		return true
	return false


func _finish_enemy_recovery_if_due(enemy: EnemyData) -> bool:
	if enemy.action_state != "recovery" or sim_tick < enemy.state_ends_tick:
		return false
	var finished_action := enemy.action_id
	combat_event_stream.emit(sim_tick, "action_ended", {
		"action_instance_id": enemy.action_instance_id,
		"actor_id": "enemy/%d" % enemy.entity_id,
		"action_id": finished_action,
	})
	enemy.action_state = "none"
	enemy.action_id = "none"
	enemy.action_instance_id = 0
	enemy.state_started_tick = sim_tick
	enemy.state_ends_tick = sim_tick
	enemy.impact_tick = -1
	enemy.impact_resolved = false
	enemy.target_shape = {}
	enemy.next_action_ready_tick = sim_tick + _enemy_breath_ticks(enemy.kind_id)
	return true


func _begin_action(enemy: EnemyData, action_id: String, windup_ticks: int) -> void:
	enemy.action_id = action_id
	enemy.action_instance_id = next_enemy_action_instance_id
	next_enemy_action_instance_id += 1
	enemy.action_state = "windup"
	enemy.motion_state = "idle"
	enemy.state_started_tick = sim_tick
	enemy.impact_tick = sim_tick + windup_ticks
	enemy.state_ends_tick = enemy.impact_tick
	enemy.impact_resolved = false


func _emit_enemy_action_accepted(enemy: EnemyData) -> void:
	combat_event_stream.emit(sim_tick, "action_accepted", {
		"action_instance_id": enemy.action_instance_id,
		"actor_id": "enemy/%d" % enemy.entity_id,
		"action_id": enemy.action_id,
		"locked_origin": enemy.position,
		"locked_direction": enemy.facing,
		"impact_tick": enemy.impact_tick,
		"target_shape": enemy.target_shape.duplicate(true),
	})


func _enemy_breath_ticks(kind_id: String) -> int:
	match kind_id:
		"melee_pursuer": return 4
		"charging_raider": return 8
		"fan_ranged": return 10
	return 0


func _intent_for_enemy(enemy: EnemyData) -> Dictionary:
	var planned: Dictionary = enemy_tactics.plan(_enemy_tactics_snapshot())
	if not bool(planned.get("ok", false)):
		return {}
	for intent: Dictionary in planned.get("intents", []):
		if int(intent.get("entity_id", 0)) == enemy.entity_id:
			return intent
	return {}


func _update_melee_tick(enemy: EnemyData, intent: Dictionary = {}) -> void:
	var previous_state := enemy.action_state
	_advance_action_state(enemy, MELEE_ACTIVE_TICKS, MELEE_RECOVERY_TICKS)
	if enemy.action_state == "active" and not enemy.impact_resolved:
		enemy.impact_resolved = true
		_resolve_hostile_attack(enemy, 5.0, _boss_shape_contains(enemy.target_shape, player_position))
	if previous_state == "active" and enemy.action_state == "recovery" and not enemy.impact_resolved:
		enemy.impact_resolved = true
		_resolve_hostile_attack(enemy, 5.0, false)
	if enemy.action_state == "none":
		_commit_normal_enemy_intent(enemy, intent if not intent.is_empty() else _intent_for_enemy(enemy))
	else:
		enemy.motion_state = "idle"


func _start_melee_action(enemy: EnemyData, direction: Vector2 = Vector2.ZERO) -> void:
	_begin_action(enemy, "contact", MELEE_WINDUP_TICKS)
	enemy.facing = direction.normalized() if direction != Vector2.ZERO else enemy.position.direction_to(player_position)
	if enemy.facing == Vector2.ZERO:
		enemy.facing = Vector2.RIGHT
	enemy.target_shape = {"type": "circle", "origin": enemy.position, "radius": EnemyTacticsScript.MELEE_ATTACK_RANGE}
	_emit_enemy_action_accepted(enemy)


func _start_charger_action(enemy: EnemyData, direction: Vector2, action_distance: float) -> bool:
	if not is_finite(direction.x) or not is_finite(direction.y) or direction.is_zero_approx() or not is_finite(action_distance) or action_distance <= 0.0:
		return false
	_begin_action(enemy, "charge", CHARGE_WINDUP_TICKS)
	enemy.charge_origin = enemy.position
	enemy.charge_direction = direction.normalized()
	enemy.facing = enemy.charge_direction
	enemy.charge_length = action_distance
	enemy.charge_width = EnemyTacticsScript.CHARGER_CONTACT_RADIUS * 2.0
	enemy.target_shape = {"type": "lane", "origin": enemy.charge_origin, "direction": enemy.charge_direction, "length": enemy.charge_length, "width": enemy.charge_width}
	_emit_enemy_action_accepted(enemy)
	return true


func _update_charger_tick(enemy: EnemyData, intent: Dictionary = {}) -> void:
	var previous_state := enemy.action_state
	_advance_action_state(enemy, CHARGE_ACTIVE_TICKS, CHARGE_RECOVERY_TICKS)
	if enemy.action_state == "active":
		enemy.motion_state = "moving"
		var before := enemy.position
		var step := enemy.charge_length / float(CHARGE_ACTIVE_TICKS)
		enemy.position = _quantize_position(_clamp_to_arena(enemy.position + enemy.charge_direction * step, 16.0))
		if not enemy.impact_resolved:
			var contact := _distance_to_segment(player_position, before, enemy.position) <= EnemyTacticsScript.CHARGER_CONTACT_RADIUS
			if contact:
				enemy.impact_resolved = true
				_resolve_hostile_attack(enemy, 11.0, true)
	elif previous_state == "active" and enemy.action_state == "recovery" and not enemy.impact_resolved:
		enemy.impact_resolved = true
		_resolve_hostile_attack(enemy, 11.0, false)
	elif enemy.action_state == "none":
		_commit_normal_enemy_intent(enemy, intent if not intent.is_empty() else _intent_for_enemy(enemy))
	else:
		enemy.motion_state = "idle"


func _start_fan_action(enemy: EnemyData, direction: Vector2 = Vector2.ZERO) -> void:
	_begin_action(enemy, "fan", FAN_WINDUP_TICKS)
	var fan_direction := direction.normalized() if direction != Vector2.ZERO else enemy.position.direction_to(player_position)
	if fan_direction == Vector2.ZERO:
		fan_direction = enemy.facing
	enemy.target_shape = EnemyTacticsScript.fan_attack_shape(enemy.position, fan_direction)
	## Keep the compact action-state mirrors available to existing diagnostics and
	## semantic hashing. Presentation and hit resolution below read target_shape.
	enemy.fan_origin = enemy.target_shape["origin"]
	enemy.fan_direction = enemy.target_shape["direction"]
	enemy.fan_half_angle = enemy.target_shape["half_angle"]
	enemy.fan_radius = enemy.target_shape["radius"]
	enemy.facing = enemy.fan_direction
	_emit_enemy_action_accepted(enemy)


func _update_fan_tick(enemy: EnemyData, intent: Dictionary = {}) -> void:
	var previous_state := enemy.action_state
	_advance_action_state(enemy, FAN_ACTIVE_TICKS, FAN_RECOVERY_TICKS)
	if enemy.action_state == "active" and not enemy.impact_resolved:
		enemy.impact_resolved = true
		_resolve_hostile_attack(enemy, 8.0, EnemyTacticsScript.fan_attack_contains(enemy.target_shape, player_position))
	if previous_state == "active" and enemy.action_state == "recovery" and not enemy.impact_resolved:
		enemy.impact_resolved = true
		_resolve_hostile_attack(enemy, 8.0, false)
	if enemy.action_state == "none":
		_commit_normal_enemy_intent(enemy, intent if not intent.is_empty() else _intent_for_enemy(enemy))
	else:
		enemy.motion_state = "idle"


func _commit_normal_enemy_intent(enemy: EnemyData, intent: Dictionary) -> void:
	if intent.is_empty():
		enemy.motion_state = "idle"
		enemy.tactic_reason = "no_intent"
		return
	enemy.tactic_reason = String(intent.get("reason", "unknown"))
	var action := String(intent.get("request_action", ""))
	var action_direction_value: Variant = intent.get("action_direction", Vector2.ZERO)
	var action_direction := Vector2(action_direction_value) if action_direction_value is Vector2 else Vector2.ZERO
	match action:
		"melee_attack":
			_start_melee_action(enemy, action_direction)
			return
		"charge":
			var action_distance_value: Variant = intent.get("action_distance", null)
			var valid_direction := is_finite(action_direction.x) and is_finite(action_direction.y) and not action_direction.is_zero_approx()
			var valid_distance := (action_distance_value is int or action_distance_value is float) and not (action_distance_value is bool) and is_finite(float(action_distance_value)) and float(action_distance_value) > 0.0
			if not valid_direction or not valid_distance or not _start_charger_action(enemy, action_direction, float(action_distance_value)):
				enemy.motion_state = "idle"
				enemy.tactic_reason = "invalid_charge_execution"
			return
		"fan_attack":
			_start_fan_action(enemy, action_direction)
			return
	var direction: Vector2 = intent.get("move_direction", Vector2.ZERO)
	var speed_scale := clampf(float(intent.get("speed_scale", 0.0)), 0.0, 1.0)
	if direction == Vector2.ZERO or speed_scale <= 0.0:
		enemy.motion_state = "idle"
		return
	direction = direction.normalized()
	var base_speed := MELEE_MOVE_SPEED
	if enemy.kind_id == "charging_raider":
		base_speed = CHARGER_MOVE_SPEED
	elif enemy.kind_id == "fan_ranged":
		base_speed = FAN_MOVE_SPEED
	var before := enemy.position
	enemy.position = _quantize_position(_clamp_to_arena(enemy.position + direction * base_speed * speed_scale * SIM_STEP_SECONDS, 16.0))
	enemy.motion_state = "moving" if enemy.position != before else "idle"
	if enemy.kind_id == "fan_ranged":
		enemy.tactic_state = "range_hold" if enemy.tactic_reason in ["fan_strafe_hold", "fan_legal_band"] else "locomotion"
		enemy.facing = enemy.position.direction_to(player_position) if enemy.position != player_position else enemy.facing
	else:
		enemy.facing = direction


func _resolve_hostile_attack(enemy: EnemyData, amount: float, shape_hit: bool) -> void:
	var actor_id := "enemy/%d" % enemy.entity_id
	var source_id := "boss/%s" % enemy.action_id if enemy.is_boss else "enemy/%d/%s" % [enemy.entity_id, enemy.kind_id]
	combat_event_stream.emit(sim_tick, "action_impact", {
		"action_instance_id": enemy.action_instance_id,
		"actor_id": actor_id,
		"action_id": enemy.action_id,
		"contact_point": player_position,
	})
	var outcome := "miss"
	if shape_hit:
		outcome = "damage" if _damage_player(amount, source_id) else "avoided"
	combat_event_stream.emit(sim_tick, "attack_resolved", {
		"action_instance_id": enemy.action_instance_id,
		"source_id": source_id,
		"target_id": "ranger",
		"outcome": outcome,
		"contact_point": player_position,
	})


func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	if segment.length_squared() <= 0.000001:
		return point.distance_to(start)
	var fraction := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * fraction)


func _update_boss_tick(enemy: EnemyData, intent: Dictionary = {}) -> void:
	if enemy.phase_id == "sealed" and enemy.phase_state == "stable" and boss_damage.compare(boss_maximum.multiply(BigValue.from_float(0.5))) >= 0:
		if enemy.action_instance_id > 0:
			combat_event_stream.emit(sim_tick, "action_interrupted", {
				"action_instance_id": enemy.action_instance_id, "actor_id": "enemy/%d" % enemy.entity_id,
				"action_id": enemy.action_id, "reason": "phase_transition",
			})
		enemy.phase_state = "transition"
		enemy.action_id = "none"
		enemy.action_instance_id = 0
		enemy.action_state = "none"
		enemy.state_started_tick = sim_tick
		enemy.state_ends_tick = sim_tick + BOSS_TRANSITION_TICKS
		enemy.impact_tick = -1
		enemy.impact_resolved = false
		enemy.target_shape = {}
	if enemy.phase_state == "transition":
		if sim_tick >= enemy.state_ends_tick:
			enemy.phase_id = "awakened"
			enemy.phase_state = "stable"
			enemy.core_open = true
			enemy.core_vulnerable = true
			enemy.left_hand_position = enemy.position + Vector2(-43.0, -8.0)
			enemy.right_hand_position = enemy.position + Vector2(38.0, 12.0)
		return
	_advance_action_state(enemy, BOSS_ACTIVE_TICKS, BOSS_RECOVERY_TICKS)
	if enemy.action_state == "none":
		var chosen := intent if not intent.is_empty() else _intent_for_enemy(enemy)
		var requested := String(chosen.get("request_action", ""))
		if requested in ["slam", "sweep", "lane"]:
			_start_boss_action(enemy, requested, chosen.get("action_direction", Vector2.ZERO))
			if enemy.phase_id == "awakened":
				enemy.next_action_index += 1
	if enemy.action_state == "active" and not enemy.impact_resolved:
		enemy.impact_resolved = true
		_resolve_hostile_attack(enemy, 1.8 if enemy.phase_id == "awakened" else 1.2, _boss_shape_contains(enemy.target_shape, player_position))
	_update_boss_hands(enemy)


func _start_boss_action(enemy: EnemyData, action: String, planned_direction: Vector2 = Vector2.ZERO) -> void:
	_begin_action(enemy, action, BOSS_WINDUP_TICKS)
	var direction := planned_direction.normalized() if planned_direction != Vector2.ZERO else enemy.position.direction_to(player_position)
	if direction == Vector2.ZERO:
		direction = Vector2.LEFT
	enemy.facing = direction
	match action:
		"sweep":
			enemy.target_shape = {"type": "fan", "origin": enemy.position, "direction": direction, "half_angle": deg_to_rad(48.0), "radius": 190.0}
		"lane":
			enemy.target_shape = {"type": "lane", "origin": enemy.position, "direction": direction, "length": 230.0, "width": 52.0}
		_:
			var target := _clamp_to_arena(player_position, 28.0)
			enemy.target_shape = {"type": "rect", "rect": Rect2(target - Vector2(38.0, 30.0), Vector2(76.0, 60.0))}
	_emit_enemy_action_accepted(enemy)


func _update_boss_hands(enemy: EnemyData) -> void:
	var left_base := enemy.position + Vector2(-43.0 if enemy.phase_id == "awakened" else -34.0, -8.0 if enemy.phase_id == "awakened" else 0.0)
	var right_base := enemy.position + Vector2(38.0 if enemy.phase_id == "awakened" else 34.0, 12.0 if enemy.phase_id == "awakened" else 0.0)
	enemy.left_hand_position = left_base
	enemy.right_hand_position = right_base
	if enemy.action_state in ["windup", "active"]:
		match enemy.action_id:
			"slam":
				enemy.left_hand_position += Vector2(0.0, -20.0 if enemy.action_state == "windup" else 18.0)
			"sweep":
				enemy.right_hand_position += enemy.facing.rotated(-PI * 0.5) * (18.0 if enemy.action_state == "windup" else -18.0)
			"lane":
				enemy.left_hand_position += Vector2(-8.0, 10.0)
				enemy.right_hand_position += Vector2(8.0, -10.0)


func _damage_player(amount: float, source_id: String = "") -> bool:
	if dodge_remaining_ticks > 0:
		return false
	var health_before := player_health
	player_health = snappedf(maxf(0.0, player_health - amount), 0.001)
	if source_id.is_empty() or player_health >= health_before:
		return false
	last_damage_source_id = source_id
	last_damage_tick = sim_tick
	last_damage_amount = health_before - player_health
	var source_position := _damage_source_position(source_id)
	last_damage_direction = source_position.direction_to(player_position) if source_position != player_position else Vector2.ZERO
	combat_event_stream.emit(sim_tick, "damage_applied", {
		"source_id": source_id,
		"target_id": "ranger",
		"target_entity_id": 0,
		"amount": String.num(last_damage_amount, 3),
		"health_before_milli": roundi(health_before * 1000.0),
		"health_after_milli": roundi(player_health * 1000.0),
		"contact_point": player_position,
		"incoming_direction": last_damage_direction,
	})
	if player_health <= 0.0:
		combat_event_stream.emit(sim_tick, "death_applied", {
			"source_id": source_id, "target_id": "ranger", "target_entity_id": 0,
			"position": player_position,
		})
	return true


func _damage_source_position(source_id: String) -> Vector2:
	if source_id.begins_with("enemy/"):
		var source_parts := source_id.split("/")
		if source_parts.size() >= 3 and String(source_parts[1]).is_valid_int():
			var source_enemy := _enemy_by_entity_id(int(source_parts[1]))
			if source_enemy != null:
				return source_enemy.position
		for enemy: EnemyData in enemies:
			if "enemy/%s" % enemy.kind_id == source_id:
				return enemy.position
	if source_id.begins_with("boss/") and boss != null:
		return boss.position
	if source_id.begins_with("hazard/"):
		var hazard_id := source_id.trim_prefix("hazard/")
		for hazard: Dictionary in hazard_states:
			if String(hazard.get("id", "")) == hazard_id:
				return hazard.get("origin", player_position)
	return player_position


func _point_in_lane(point: Vector2, origin: Vector2, direction: Vector2, length: float, width: float) -> bool:
	var local := point - origin
	var forward := local.dot(direction)
	return forward >= 0.0 and forward <= length and absf(local.dot(direction.rotated(PI * 0.5))) <= width * 0.5


func _point_in_fan(point: Vector2, origin: Vector2, direction: Vector2, half_angle: float, radius: float) -> bool:
	var offset := point - origin
	return offset.length() <= radius and (offset == Vector2.ZERO or absf(direction.angle_to(offset.normalized())) <= half_angle)


func _boss_shape_contains(shape: Dictionary, point: Vector2) -> bool:
	match String(shape.get("type", "")):
		"circle":
			return point.distance_to(shape.get("origin", Vector2.ZERO)) <= float(shape.get("radius", 0.0))
		"rect":
			return (shape.get("rect", Rect2()) as Rect2).has_point(point)
		"fan":
			return _point_in_fan(point, shape.get("origin", Vector2.ZERO), shape.get("direction", Vector2.RIGHT), float(shape.get("half_angle", 0.0)), float(shape.get("radius", 0.0)))
		"lane":
			return _point_in_lane(point, shape.get("origin", Vector2.ZERO), shape.get("direction", Vector2.RIGHT), float(shape.get("length", 0.0)), float(shape.get("width", 0.0)))
	return false


func _quantize_position(value: Vector2) -> Vector2:
	# Authority stores a 1/1000-pixel grid. Rendering may interpolate later, but
	# identical whole-tick commands always land on identical coordinates.
	return Vector2(snappedf(value.x, 0.001), snappedf(value.y, 0.001))


func _framework_room_error() -> String:
	if not embedded_session or framework_room.is_empty():
		return ""
	var layout := String(framework_room.get("layout_id", framework_room.get("layout", "")))
	var objective := String(framework_room.get("objective_id", framework_room.get("objective", "")))
	if layout not in VALID_LAYOUT_IDS:
		return "unknown_layout_id"
	if objective not in VALID_OBJECTIVE_IDS:
		return "unknown_objective_id"
	var enemy_values: Variant = framework_room.get("enemy_ids", [])
	var hazard_values: Variant = framework_room.get("hazard_ids", [])
	var elite_values: Variant = framework_room.get("elite_rule_ids", [])
	var drop_values: Variant = framework_room.get("drop_tags", [])
	if not enemy_values is Array or not hazard_values is Array or not elite_values is Array or not drop_values is Array:
		return "invalid_room_fields"
	for value in (enemy_values as Array):
		if String(value) not in VALID_ENEMY_IDS:
			return "unknown_enemy_id"
	var boss_id := String(framework_room.get("boss_id", ""))
	if not boss_id.is_empty() and boss_id != "threshold_colossus":
		return "unknown_boss_id"
	for value in (hazard_values as Array):
		if String(value) not in VALID_HAZARD_IDS:
			return "unknown_hazard_id"
	for value in (elite_values as Array):
		if String(value) not in VALID_ELITE_RULE_IDS:
			return "unknown_elite_rule_id"
	return ""


func _layout_spawn_offsets(id: String, count: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if id == "rectangle_arena" and count == 3 and room_id in ["first_hunt_clear", "first_hunt_followup"]:
		# Equal approach distance gives the opening group a shared arrival window.
		# Keep the rear/left escape route open; the second room changes the fan's angles.
		var start_offset := Vector2(-220.0, 100.0)
		var angles := [-70.0, -35.0, 0.0] if room_id == "first_hunt_clear" else [-60.0, -25.0, 10.0]
		for angle: float in angles:
			result.append(start_offset + Vector2.from_angle(deg_to_rad(angle)) * 350.0)
		return result
	for index in count:
		match id:
			"corridor":
				result.append(Vector2(-180.0 + float(index % 4) * 120.0, -42.0 if index % 2 == 0 else 42.0))
			"ring":
				var angle := -PI * 0.5 + TAU * float(index) / float(maxi(1, count))
				result.append(Vector2.from_angle(angle) * 175.0)
			_:
				var columns := 3
				result.append(Vector2(float(index % columns - 1) * 145.0, float(index / columns) * 110.0 - 80.0))
	return result


func _update_traces(delta: float) -> void:
	for index: int in range(traces.size() - 1, -1, -1):
		traces[index].remaining -= delta
		if traces[index].remaining <= 0.0:
			traces.remove_at(index)


func _check_battle_end() -> void:
	var victory := boss != null and boss.health <= 0.0
	if boss == null and objective_id == "hunt_elite" and elite_entity_id > 0 and _enemy_by_entity_id(elite_entity_id) == null:
		victory = enemies.is_empty() if "summon_reinforcements" in elite_rule_ids else true
	if boss == null and enemies.is_empty():
		victory = true
	if victory:
		battle_over = true
		battle_victory = true
		var legacy_reward_before := _legacy_reward_state()
		var reward_summary := ""
		if embedded_session:
			room_reward_snapshot = _build_embedded_room_reward()
			reward_summary = _embedded_reward_summary(room_reward_snapshot)
		else:
			reward_summary = _grant_victory_reward()
		battle_report = "VICTORY — Room cleared in %.1fs, %d casts, %d targets. %s" % [elapsed, shots, defeated, reward_summary]
		if presentation_enabled:
			return_button.visible = true
		if automation_smoke:
			var smoke_valid := false
			if embedded_session:
				smoke_valid = (
					not framework_room.is_empty()
					and battle_victory
					and (selected_mode != "Auto" or proxy_prediction == "stable")
					and _legacy_reward_state() == legacy_reward_before
				)
			else:
				smoke_valid = contract_wins == automation_expected_contract_wins and destiny_forge.get_dice(DestinyForgeScript.TRACK_ADD) == 7 and not last_drop_id.is_empty() and proxy_prediction == "stable"
			if not smoke_valid:
				_fail_automation_smoke("integrated room/proxy/reward state is invalid")
				return
			if embedded_session:
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
		battle_victory = false
		battle_report = "DEFEAT — The ranger fell after %.1fs. Refit at base." % elapsed
		if presentation_enabled:
			return_button.visible = true
		if automation_smoke:
			if embedded_session:
				automation_smoke_failure = "defeat elapsed=%.2f casts=%d" % [elapsed, shots]
				return
			printerr("AUTO_SMOKE_FAIL elapsed=%.2f casts=%d" % [elapsed, shots])
			Engine.time_scale = 1.0
			get_tree().quit(1)


func _fail_automation_smoke(reason: String) -> void:
	automation_smoke_failure = reason
	battle_over = true
	battle_victory = false
	battle_report = "AUTOMATION FAILURE — %s" % reason
	if return_button != null and presentation_enabled:
		return_button.visible = true
	if embedded_session:
		return
	printerr("AUTO_SMOKE_FAIL %s" % reason)
	Engine.time_scale = 1.0
	get_tree().quit(1)


func _grant_victory_reward() -> String:
	if embedded_session:
		room_reward_snapshot = _build_embedded_room_reward()
		return _embedded_reward_summary(room_reward_snapshot)
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
	return "Drop: %s; +%d Inscription Tally.%s No timer; no regeneration." % [last_drop, dice_awarded, bonus_text]


func _empty_room_reward_snapshot() -> Dictionary:
	return {
		"add_dice_delta": 0,
		"rewrite_dice_delta": 0,
		"refine_dice_delta": 0,
		"bonus_earned": false,
		"bonus_lost": false,
	}


func _build_embedded_room_reward() -> Dictionary:
	var reward := _empty_room_reward_snapshot()
	reward["add_dice_delta"] = 1 if "add_dice" in room_drop_tags else 0
	reward["rewrite_dice_delta"] = 1 if "rewrite_dice" in room_drop_tags else 0
	reward["refine_dice_delta"] = 1 if "refine_dice" in room_drop_tags else 0
	if objective_id == "timed_break":
		reward["bonus_earned"] = timed_bonus_available
		reward["bonus_lost"] = not timed_bonus_available
	return reward


func _embedded_reward_summary(reward: Dictionary) -> String:
	var bonus := " Timed bonus lost; base room rewards preserved." if bool(reward.get("bonus_lost", false)) else ""
	return "Room reward: Inscription Tallies %d · Rewrite Tallies %d · Refinement Tallies %d.%s" % [int(reward.get("add_dice_delta", 0)), int(reward.get("rewrite_dice_delta", 0)), int(reward.get("refine_dice_delta", 0)), bonus]


func _legacy_reward_state() -> Dictionary:
	return {
		"contract_wins": contract_wins,
		"forge": destiny_forge.state().duplicate(true),
		"last_drop": last_drop,
		"last_drop_id": last_drop_id,
		"last_loot_rng_state": last_loot_rng_state.duplicate(true),
	}


func _semantic_state_hash(result: String) -> String:
	var enemy_state: Array[Dictionary] = []
	var ordered_enemies: Array[EnemyData] = enemies.duplicate()
	ordered_enemies.sort_custom(func(left: EnemyData, right: EnemyData) -> bool: return left.entity_id < right.entity_id)
	for enemy: EnemyData in ordered_enemies:
		enemy_state.append({
			"action_instance_id": enemy.action_instance_id,
			"action_id": enemy.action_id,
			"action_state": enemy.action_state,
			"boss": enemy.is_boss,
			"charge": CombatStateCodecScript.geometry_state(enemy.charge_origin, enemy.charge_direction, enemy.charge_length, enemy.charge_width),
			"core_open": enemy.core_open,
			"core_vulnerable": enemy.core_vulnerable,
			"entity_id": enemy.entity_id,
			"facing_x_milli": roundi(enemy.facing.x * 1000.0),
			"facing_y_milli": roundi(enemy.facing.y * 1000.0),
			"fan": CombatStateCodecScript.geometry_state(enemy.fan_origin, enemy.fan_direction, enemy.fan_radius, enemy.fan_half_angle),
			"health_milli": roundi(enemy.health * 1000.0),
			"hit_flash_until_tick": enemy.hit_flash_until_tick,
			"impact_resolved": enemy.impact_resolved,
			"impact_tick": enemy.impact_tick,
			"kind_id": enemy.kind_id,
			"maximum_health_milli": roundi(enemy.maximum_health * 1000.0),
			"left_hand_x_milli": roundi(enemy.left_hand_position.x * 1000.0),
			"left_hand_y_milli": roundi(enemy.left_hand_position.y * 1000.0),
			"motion_state": enemy.motion_state,
			"next_action_index": enemy.next_action_index,
			"next_action_ready_tick": enemy.next_action_ready_tick,
			"phase_id": enemy.phase_id,
			"phase_state": enemy.phase_state,
			"right_hand_x_milli": roundi(enemy.right_hand_position.x * 1000.0),
			"right_hand_y_milli": roundi(enemy.right_hand_position.y * 1000.0),
			"state_ends_tick": enemy.state_ends_tick,
			"state_started_tick": enemy.state_started_tick,
			"tactic_reason": enemy.tactic_reason,
			"tactic_state": enemy.tactic_state,
			"target_shape": CombatStateCodecScript.target_shape_state(enemy.target_shape),
			"x_millipixels": roundi(enemy.position.x * 1000.0),
			"y_millipixels": roundi(enemy.position.y * 1000.0),
		})
	var hazard_state: Array[Dictionary] = []
	for hazard in hazard_states:
		hazard_state.append({
			"cycle": int(hazard.get("cycle", 0)),
			"cycle_tick": int(hazard.get("cycle_tick", 0)),
			"direction_x_milli": roundi((hazard.get("direction", Vector2.ZERO) as Vector2).x * 1000.0),
			"direction_y_milli": roundi((hazard.get("direction", Vector2.ZERO) as Vector2).y * 1000.0),
			"id": String(hazard.get("id", "")),
			"last_hit_cycle": int(hazard.get("last_hit_cycle", -1)),
			"length_milli": roundi(float(hazard.get("length", 0.0)) * 1000.0),
			"origin_x_milli": roundi((hazard.get("origin", Vector2.ZERO) as Vector2).x * 1000.0),
			"origin_y_milli": roundi((hazard.get("origin", Vector2.ZERO) as Vector2).y * 1000.0),
			"phase": String(hazard.get("phase", "")),
			"radius_milli": roundi(float(hazard.get("radius", 0.0)) * 1000.0),
			"width_milli": roundi(float(hazard.get("width", 0.0)) * 1000.0),
		})
	var manual_input_state: Dictionary = {}
	if selected_mode == "Manual" and in_arena and not battle_over and manual_combat_input != null:
		var input_state: Dictionary = manual_combat_input.snapshot()
		var pointer_world_count := 0
		var pointer_hud_count := 0
		for world_owned: Variant in (input_state.get("pointer_sources", {}) as Dictionary).values():
			if bool(world_owned):
				pointer_world_count += 1
			else:
				pointer_hud_count += 1
		manual_input_state = {
			"assisted_held_count": (input_state.get("non_pointer_sources", {}) as Dictionary).size(),
			"pointer_world_held_count": pointer_world_count,
			"pointer_hud_owned_count": pointer_hud_count,
		}
	var projectile_state: Array[Dictionary] = []
	var ordered_projectiles: Array[ArrowProjectile] = projectiles.duplicate()
	ordered_projectiles.sort_custom(func(left: ArrowProjectile, right: ArrowProjectile) -> bool: return left.action_instance_id < right.action_instance_id)
	for projectile: ArrowProjectile in ordered_projectiles:
		projectile_state.append({
			"action_instance_id": projectile.action_instance_id,
			"target_entity_id": projectile.target_entity_id,
			"spawned_tick": projectile.spawned_tick,
			"origin_x_milli": roundi(projectile.origin.x * 1000.0),
			"origin_y_milli": roundi(projectile.origin.y * 1000.0),
			"direction_x_milli": roundi(projectile.direction.x * 1000.0),
			"direction_y_milli": roundi(projectile.direction.y * 1000.0),
			"position_x_milli": roundi(projectile.position.x * 1000.0),
			"position_y_milli": roundi(projectile.position.y * 1000.0),
			"previous_x_milli": roundi(projectile.previous_position.x * 1000.0),
			"previous_y_milli": roundi(projectile.previous_position.y * 1000.0),
			"distance_milli": roundi(projectile.distance_travelled * 1000.0),
			"maximum_range_milli": roundi(projectile.maximum_range * 1000.0),
			"speed_milli": roundi(projectile.speed * 1000.0),
			"ordinary_damage_milli": roundi(projectile.ordinary_damage * 1000.0),
			"aggregate_damage": {"layer": projectile.aggregate_damage.layer, "magnitude": String.num(projectile.aggregate_damage.magnitude, 12)},
			"event_count": {"layer": projectile.event_count.layer, "magnitude": String.num(projectile.event_count.magnitude, 12)},
			"payload_milli": roundi(projectile.payload * 1000.0),
		})
	var state := {
		"arena_geometry": CombatStateCodecScript.hash_safe({
			"player": _walkable_geometry(14.0),
			"enemy": _walkable_geometry(16.0),
		}),
		"boss_damage": {
			"layer": boss_damage.layer,
			"magnitude": String.num(boss_damage.magnitude, 12),
		},
		"boss_health_milli": roundi(boss.health * 1000.0) if boss != null else -1,
		"boss_x_millipixels": roundi(boss.position.x * 1000.0) if boss != null else 0,
		"boss_y_millipixels": roundi(boss.position.y * 1000.0) if boss != null else 0,
		"battle_victory": battle_victory,
		"action_timeline": CombatStateCodecScript.hash_safe(player_action_timeline.snapshot() if player_action_timeline != null else {}),
		"attack_origins": CombatStateCodecScript.hash_safe(attack_origins),
		"casts": shots,
		"arrow_hits": arrow_hits,
		"command_sequence": command_sequence,
		"command_receipts": CombatStateCodecScript.hash_safe(last_command_receipts),
		"combat_events": CombatStateCodecScript.hash_safe(combat_event_stream.snapshot() if combat_event_stream != null else {}),
		"content_hash": _content_hash(),
		"contract_wins": contract_wins,
		"cooldowns": {
			"attack": attack_cooldown_ticks,
			"dash": dash_cooldown_ticks,
			"dash_remaining": dash_remaining_ticks,
			"dodge": dodge_cooldown_ticks,
			"dodge_remaining": dodge_remaining_ticks,
			"hunter_mark": hunter_mark_cooldown_ticks,
		},
		"dash_direction_x_milli": roundi(dash_direction.x * 1000.0),
		"dash_direction_y_milli": roundi(dash_direction.y * 1000.0),
		"dash_started_tick": dash_started_tick,
		"dodge_direction_x_milli": roundi(dodge_direction.x * 1000.0),
		"dodge_direction_y_milli": roundi(dodge_direction.y * 1000.0),
		"dodge_started_tick": dodge_started_tick,
		"mobility_input_buffer": CombatStateCodecScript.hash_safe(mobility_input_buffer),
		"defeated": defeated,
		"enemies": enemy_state,
		"elite_barrier_active": elite_barrier_active,
		"elite_entity_id": elite_entity_id,
		"elite_rule_ids": elite_rule_ids,
		"forge": destiny_forge.state(),
		"last_drop": last_drop,
		"last_drop_id": last_drop_id,
		"last_loot_rng_state": last_loot_rng_state,
		"last_attack_outcome": CombatStateCodecScript.hash_safe(last_attack_outcome),
		"last_proxy_failure": last_proxy_failure,
		"hazards": hazard_state,
		"layout_id": layout_id,
		"objective_id": objective_id,
		"reinforcements_summoned": reinforcements_summoned,
		"room_drop_tags": room_drop_tags,
		"room_reward_snapshot": room_reward_snapshot,
		"room_id": room_id,
		"timed_bonus_available": timed_bonus_available,
		"build_fingerprint": String(locked_build.get("build_fingerprint", "legacy_diagnostic")),
		"mode": selected_mode.to_lower(),
		"manual_input": manual_input_state,
		"manual_attack_intent": {
			"edge_requested": attack_requested,
			"edge_source": attack_requested_source,
			"edge_target_entity_id": attack_requested_target_entity_id,
			"pointer_target_entity_id": manual_pointer_target_entity_id,
		},
		"marked_entity_id": marked_entity_id,
		"hunter_mark_candidate_entity_id": hunter_mark_candidate_entity_id,
		"hunter_mark_candidate_expires_tick": hunter_mark_candidate_expires_tick,
		"hunter_mark_expires_tick": hunter_mark_expires_tick,
		"next_entity_id": next_entity_id,
		"next_enemy_action_instance_id": next_enemy_action_instance_id,
		"payload_milli": roundi(locked_payload * 1000.0),
		"p_basis_points": roundi(locked_p * 100.0),
		"player_health_milli": roundi(player_health * 1000.0),
		"player_maximum_health_milli": roundi(player_maximum_health * 1000.0),
		"player_facing_x_milli": roundi(player_facing.x * 1000.0),
		"player_facing_y_milli": roundi(player_facing.y * 1000.0),
		"player_last_displacement_x_milli": roundi(player_last_displacement.x * 1000.0),
		"player_last_displacement_y_milli": roundi(player_last_displacement.y * 1000.0),
		"player_x_millipixels": roundi(player_position.x * 1000.0),
		"player_y_millipixels": roundi(player_position.y * 1000.0),
		"proxy_mode": proxy_runtime.mode,
		"proxy_mode_locked": proxy_runtime.mode_locked,
		"proxy_build_fingerprint": String(framework_resolved_proxy_build.get("semantic_fingerprint", "")),
		"proxy_decision_state": CombatStateCodecScript.hash_safe(proxy_decision_state),
		"proxy_prediction": proxy_prediction,
		"projectiles": projectile_state,
		"result": result,
		"sim_protocol_version": SAVE_PROTOCOL_VERSION,
		"targeting_distance_milli": roundi(locked_targeting_distance * 1000.0),
		"tick": sim_tick,
	}
	if not talent_capabilities.is_empty():
		state["talent_runtime"] = {
			"first_critical_bonus_used": first_critical_bonus_used,
			"three_skill_sequence_stage": three_skill_sequence_stage,
			"three_skill_bonus_ready": three_skill_bonus_ready,
			"retained_arrow_damage": {"layer": retained_arrow_damage.layer, "magnitude": String.num(retained_arrow_damage.magnitude, 12)},
			"retained_arrow_ordinary_damage": String.num(retained_arrow_ordinary_damage, 12),
		}
	return CombatStateCodecScript.sha256_canonical(state)


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
	if not locked_build.is_empty():
		var event_value: Dictionary = locked_build.get("total_events", {})
		var total_events := BigValue.from_components(
			int(event_value.get("layer", 0)),
			float(event_value.get("magnitude", 0.0))
		)
		if total_events != null:
			var generations := int(locked_build.generation_count)
			return {
				"p": float(locked_build.final_parameters.p),
				"R": float(locked_build.R),
				"g": generations,
				"generation_time": float(locked_build.generation_time),
				"state": String(locked_build.growth_classification),
				"total_events": total_events,
				"total_events_float": float(locked_build.total_events_float),
				"growth_snapshot_details": bool(talent_capabilities.get("growth_snapshot_details", false)),
			}
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
	var attack_ui := _player_attack_ui_state()
	var attack_held_source: String = manual_combat_input.attack_source(_pointer_is_over_hud()) if selected_mode == "Manual" and manual_combat_input != null else ""
	var attack_held: bool = not attack_held_source.is_empty()
	var attack_target_ui := _attack_target_ui_state(attack_ui)
	var remaining: BigValue = _boss_remaining_display()
	var nearest := _nearest_enemy()
	var ratio_known := remaining.layer == boss_maximum.layer and remaining.layer == 0
	var ratio := clampf(remaining.magnitude / boss_maximum.magnitude, 0.0, 1.0) if ratio_known and boss_maximum.magnitude > 0.0 else 0.0
	var equipped: Dictionary = content_registry.preset_equipped_parameters
	var lifetime := float(locked_build.final_parameters.T) if not locked_build.is_empty() else float(equipped.shared_lifetime)
	var targeting_distance := float(locked_build.final_parameters.d) if not locked_build.is_empty() else float(equipped.distance)
	var mark_target := _enemy_by_entity_id(marked_entity_id)
	var mark_range := locked_targeting_distance * HUNTER_MARK_RANGE_MULTIPLIER
	var action_edge_occluded := _combat_focus_near_action_edge(nearest)
	hud_panel.present({
		"room_id": room_id,
		"room_index": int(framework_room.get("room_index", 0)),
		"room_count": int(framework_room.get("room_count", 1)),
		"room_elapsed_seconds": elapsed,
		"player_health": player_health,
		"player_health_max": player_maximum_health,
		"key_status": "闪避中" if dodge_remaining_ticks > 0 else ("受创警戒" if player_health < 35.0 else "稳定"),
		"boss_remaining": remaining.to_short_string(4),
		"boss_maximum": boss_maximum.to_short_string(4),
		"boss_ratio_known": ratio_known,
		"boss_ratio": ratio,
		"has_boss": boss != null,
		"living_targets": enemies.size(),
		"layout_id": layout_id,
		"objective_id": objective_id,
		"objective_label": _objective_label(),
		"hazard_status": _hazard_status_text(),
		"elite_status": _elite_status_text(),
		"selected_mode": selected_mode,
		"battle_over": battle_over,
		"battle_victory": battle_victory,
		"attack_cooldown_seconds": float(attack_cooldown_ticks) / SIM_TICKS_PER_SECOND,
		"attack_phase": String(attack_ui.get("phase", "idle")),
		"attack_phase_label": String(attack_ui.get("label", "")),
		"attack_phase_tick": int(attack_ui.get("phase_tick", 0)),
		"attack_phase_remaining_ticks": int(attack_ui.get("phase_remaining_ticks", 0)),
		"attack_buffered": bool(attack_ui.get("buffered", false)),
		"attack_held": attack_held,
		"attack_held_source": attack_held_source,
		"attack_request_open": bool(attack_ui.get("request_open", false)),
		"attack_target_source": String(attack_target_ui.get("source", ATTACK_SOURCE_ASSISTED)),
		"attack_target_status": String(attack_target_ui.get("status", POINTER_STATUS_NONE)),
		"attack_target_entity_id": int(attack_target_ui.get("target_entity_id", 0)),
		"attack_has_target": bool(attack_target_ui.get("has_target", false)),
		"attack_target_in_range": bool(attack_target_ui.get("in_range", false)),
		"hunter_mark_equipped": _is_skill_equipped(1, "hunter_mark"),
		"hunter_mark_cooldown_seconds": float(hunter_mark_cooldown_ticks) / SIM_TICKS_PER_SECOND,
		"hunter_mark_remaining_seconds": float(maxi(0, hunter_mark_expires_tick - sim_tick)) / SIM_TICKS_PER_SECOND if mark_target != null else 0.0,
		"marked_entity_id": marked_entity_id,
		"marked_target_label": _enemy_public_label(mark_target),
		"dash_equipped": _is_skill_equipped(2, "dash"),
		"dash_cooldown_seconds": float(dash_cooldown_ticks) / SIM_TICKS_PER_SECOND,
		"dash_active": dash_remaining_ticks > 0,
		"dodge_cooldown_seconds": float(dodge_cooldown_ticks) / SIM_TICKS_PER_SECOND,
		"talent_skill_overrides": {
			"hunter_mark": {"duration_ticks": _talent_scaled_ticks(HUNTER_MARK_DURATION_TICKS, "hunter_mark_duration_multiplier")},
			"dash": {"duration_ticks": _talent_scaled_ticks(DASH_DURATION_TICKS, "dash_duration_multiplier")},
			"basic_dodge": {"cooldown_ticks": _talent_scaled_cooldown(DODGE_COOLDOWN_TICKS)},
		},
		"has_target": nearest != null,
		"target_in_range": nearest != null and player_position.distance_to(nearest.position) <= locked_targeting_distance,
		"mark_target_in_range": nearest != null and player_position.distance_to(nearest.position) <= mark_range,
		"damage": boss_damage.to_short_string(4),
		"feedback": _hud_feedback(),
		"input_feedback": _active_input_feedback(),
		"p": float(model["p"]),
		"lifetime": lifetime,
		"distance": targeting_distance,
		"g": int(model["g"]),
			"growth_verified": shots > 0,
			"growth_type": String(model["state"]),
			"growth_snapshot_details": bool(model.get("growth_snapshot_details", false)),
		"growth_generation_time": float(model.get("generation_time", 0.0)),
		"proxy_prediction": proxy_prediction,
		"last_proxy_failure": last_proxy_failure,
		"action_edge_occluded": action_edge_occluded,
	})


## The skill cells live against the lower-right edge.  When a living actor reaches
## that readout, the dock backing dims; keys, cooldowns, every authoritative HUD
## value and the input-notice strip remain available.  This is a presentation-only
## camera query and never feeds combat, paths or replay state.
func _combat_focus_near_action_edge(nearest: EnemyData) -> bool:
	if world_view == null:
		return false
	var frame := Rect2(Vector2.ZERO, get_viewport_rect().size)
	if frame.size.x <= 0.0 or frame.size.y <= 0.0:
		return false
	world_view.begin_frame(frame, player_position, _arena_rect())
	var edge := Rect2(frame.end - Vector2(332.0, 190.0), Vector2(324.0, 182.0)).grow(24.0)
	if edge.has_point(world_view.gameplay_to_screen(player_position)):
		return true
	if nearest != null and edge.has_point(world_view.gameplay_to_screen(nearest.position)):
		return true
	return boss != null and edge.has_point(world_view.gameplay_to_screen(boss.position))


func _enemy_public_label(enemy: EnemyData) -> String:
	if enemy == null:
		return ""
	if enemy.is_boss:
		return "阈门巨像"
	match enemy.kind_id:
		"melee_pursuer": return "近战追猎者"
		"charging_raider": return "冲锋掠袭者"
		"fan_ranged": return "扇射游猎者"
	return "敌人"


func _show_input_feedback(text_value: String) -> void:
	_input_feedback_text = text_value
	_input_feedback_expires_tick = sim_tick + INPUT_FEEDBACK_DURATION_TICKS


func _active_input_feedback() -> String:
	if _input_feedback_expires_tick >= 0 and sim_tick >= _input_feedback_expires_tick:
		_input_feedback_text = ""
		_input_feedback_expires_tick = -1
	return _input_feedback_text


## A successful intent (resolved lock, fired shot, equipped skill) replaces or
## clears the stale invalid-action hint so it can never mask real feedback.
func _clear_input_feedback() -> void:
	_input_feedback_text = ""
	_input_feedback_expires_tick = -1


func _hud_feedback() -> String:
	if battle_over:
		if battle_victory:
			return "目标已击破 · %d 次施放 · %d 个目标" % [shots, defeated]
		return "游侠倒下 · 返回基地调整构筑"
	if selected_mode == "Auto" and not last_proxy_failure.is_empty():
		var reason := String(last_proxy_failure.get("reason", ""))
		if reason in ["skill is not ready", "skill not ready"]:
			return "代理执行中 · 穿刺箭冷却"
		return "代理受阻 · %s" % reason
	var action_ui := _player_attack_ui_state()
	var action_label := String(action_ui.get("label", ""))
	var buffered := bool(action_ui.get("buffered", false))
	var attack_target_ui := _attack_target_ui_state(action_ui)
	if selected_mode == "Manual" and String(attack_target_ui.get("source", "")) == ATTACK_SOURCE_POINTER and action_label.is_empty() and not buffered:
		match String(attack_target_ui.get("status", POINTER_STATUS_NONE)):
			POINTER_STATUS_NO_TARGET:
				return "鼠标未锁定目标 · 空白点击不会自动改选"
			POINTER_STATUS_LOST:
				return "指针锁定已失效 · 松开后重新选择"
			POINTER_STATUS_OUT_OF_RANGE:
				return "指针目标在射程外 · 锁定保持"
	if action_label == "拉弓":
		return "穿刺箭拉弓 · 目标锁定%s" % (" · 下一发已缓冲" if buffered else "")
	var outcome_text := ""
	match String(last_attack_outcome.get("outcome", "")):
		"blocked": outcome_text = "圣律屏障阻断"
		"miss": outcome_text = "穿刺箭落空"
		"killed": outcome_text = "穿刺箭击破目标"
		"damage": outcome_text = "穿刺箭命中"
	if action_label == "放箭":
		return "放箭 · %s%s" % [outcome_text if not outcome_text.is_empty() else "判定结算", " · 下一发已缓冲" if buffered else ""]
	if action_label == "收势":
		return "收势%s%s" % [" · %s" % outcome_text if not outcome_text.is_empty() else "", " · 下一发已缓冲" if buffered else ""]
	if buffered:
		return "穿刺箭已缓冲 · 等待可用动作帧"
	if shots == 0:
		return "代理正在接近首个目标" if selected_mode == "Auto" else "靠近目标后施放穿刺箭"
	if outcome_text == "圣律屏障阻断" or outcome_text == "穿刺箭落空":
		return outcome_text
	return "%s · 对 Boss 伤害 %s · 已击败 %d" % [outcome_text, boss_damage.to_short_string(4), defeated] if boss != null else "%s · 已击败 %d · 剩余 %d" % [outcome_text, defeated, enemies.size()]


func _player_attack_ui_state() -> Dictionary:
	if player_action_timeline == null:
		return {"phase": "idle", "label": "", "phase_tick": 0, "phase_remaining_ticks": 0, "buffered": false, "request_open": attack_cooldown_ticks <= PlayerActionTimelineScript.INPUT_BUFFER_TICKS, "target_entity_id": 0, "input_source": ""}
	var snapshot: Dictionary = player_action_timeline.snapshot()
	var active: Dictionary = snapshot.get("active", {})
	var buffered: Dictionary = snapshot.get("buffered", {})
	var phase: String = player_action_timeline.phase_at(sim_tick)
	var label := ""
	var phase_tick := 0
	var phase_remaining_ticks := 0
	var lock_clear_tick := sim_tick
	if not active.is_empty():
		var start_tick := int(active.get("start_tick", sim_tick))
		var impact_tick := start_tick + int(active.get("windup_ticks", PlayerActionTimelineScript.WINDUP_TICKS))
		lock_clear_tick = impact_tick + PlayerActionTimelineScript.RECOVERY_TICKS
		if phase == PlayerActionTimelineScript.PHASE_WINDUP:
			label = "拉弓"
			phase_tick = maxi(0, sim_tick - start_tick)
			phase_remaining_ticks = maxi(0, impact_tick - sim_tick)
		elif phase == PlayerActionTimelineScript.PHASE_RECOVERY:
			label = "放箭" if sim_tick == impact_tick else "收势"
			phase_tick = maxi(0, sim_tick - impact_tick)
			phase_remaining_ticks = maxi(0, lock_clear_tick - sim_tick)
	var ready_tick := sim_tick + attack_cooldown_ticks
	var eligible_tick := maxi(sim_tick, maxi(ready_tick, lock_clear_tick))
	var visible_request: Dictionary = active if not active.is_empty() else buffered
	var visible_request_id := int(visible_request.get("request_id", 0))
	return {
		"phase": phase,
		"label": label,
		"phase_tick": phase_tick,
		"phase_remaining_ticks": phase_remaining_ticks,
		"buffered": not buffered.is_empty(),
		"request_open": eligible_tick - sim_tick <= PlayerActionTimelineScript.INPUT_BUFFER_TICKS,
		"target_entity_id": int(visible_request.get("target_entity_id", 0)),
		"request_id": visible_request_id,
		"input_source": String(attack_request_sources.get(visible_request_id, "")),
	}


## Presentation projection for the attack cell and pointer bracket. It never
## chooses a replacement for an explicit pointer entity. Assisted targeting keeps
## the documented mark/nearest policy and proxy uses its own public snapshot.
func _attack_target_ui_state(attack_ui: Dictionary = {}) -> Dictionary:
	if attack_ui.is_empty():
		attack_ui = _player_attack_ui_state()
	var held_source: String = manual_combat_input.attack_source(_pointer_is_over_hud()) if selected_mode == "Manual" and manual_combat_input != null else ""
	var input_snapshot: Dictionary = manual_combat_input.snapshot() if selected_mode == "Manual" and manual_combat_input != null else {}
	var pointer_lock_owned := bool(input_snapshot.get("pointer_world_held", false))
	var source := ATTACK_SOURCE_PROXY if selected_mode == "Auto" else ATTACK_SOURCE_ASSISTED
	var pointer_target_id := 0
	var pointer_status := POINTER_STATUS_NONE
	if pointer_lock_owned:
		source = ATTACK_SOURCE_POINTER
		pointer_target_id = manual_pointer_target_entity_id
		pointer_status = manual_pointer_status
	elif attack_requested and attack_requested_source == ATTACK_SOURCE_POINTER:
		source = ATTACK_SOURCE_POINTER
		pointer_target_id = attack_requested_target_entity_id
		pointer_status = POINTER_STATUS_LOCKED
	elif String(attack_ui.get("input_source", "")) == ATTACK_SOURCE_POINTER:
		source = ATTACK_SOURCE_POINTER
		pointer_target_id = int(attack_ui.get("target_entity_id", 0))
		pointer_status = POINTER_STATUS_LOCKED
	if source == ATTACK_SOURCE_POINTER:
		return _pointer_target_ui_state(pointer_target_id, pointer_status)
	var target := _preferred_skill_one_target()
	return {
		"source": source,
		"status": POINTER_STATUS_NONE if target != null else POINTER_STATUS_NO_TARGET,
		"target_entity_id": target.entity_id if target != null else 0,
		"has_target": target != null,
		"in_range": target != null and player_position.distance_to(target.position) <= locked_targeting_distance,
		"target_anchor": manual_aim_resolver.target_anchor(_manual_aim_candidate(target)) if target != null else Vector2.ZERO,
		"target_radius": manual_aim_resolver.target_radius(_manual_aim_candidate(target)) if target != null else 0.0,
	}.duplicate(true)


func _pointer_target_ui_state(target_entity_id: int, fallback_status: String) -> Dictionary:
	var target := _enemy_by_entity_id(target_entity_id)
	if target == null or target.health <= 0.0:
		return {
			"source": ATTACK_SOURCE_POINTER,
			"status": fallback_status if target_entity_id <= 0 else POINTER_STATUS_LOST,
			"target_entity_id": target_entity_id,
			"has_target": false,
			"in_range": false,
			"target_anchor": Vector2.ZERO,
			"target_radius": 0.0,
		}.duplicate(true)
	var candidate := _manual_aim_candidate(target)
	var in_range := player_position.distance_to(target.position) <= locked_targeting_distance
	return {
		"source": ATTACK_SOURCE_POINTER,
		"status": POINTER_STATUS_LOCKED if in_range else POINTER_STATUS_OUT_OF_RANGE,
		"target_entity_id": target.entity_id,
		"has_target": true,
		"in_range": in_range,
		"target_anchor": manual_aim_resolver.target_anchor(candidate),
		"target_radius": manual_aim_resolver.target_radius(candidate),
	}.duplicate(true)


func _manual_aim_candidate(enemy: EnemyData) -> Dictionary:
	return {
		"entity_id": enemy.entity_id,
		"kind_id": enemy.kind_id,
		"position": enemy.position,
		"health": enemy.health,
		"is_boss": enemy.is_boss,
	}


func _boss_remaining_display() -> BigValue:
	if boss == null:
		return BigValue.from_float(0.0)
	# Actual defeat uses BigValue.compare(). This subtraction is display-only;
	# the current 10^12 target and accumulated damage remain ordinary layer 0.
	if boss_damage.compare(boss_maximum) >= 0:
		return BigValue.from_float(0.0)
	if boss_damage.layer == 0 and boss_maximum.layer == 0:
		return BigValue.from_float(maxf(0.0, boss_maximum.magnitude - boss_damage.magnitude))
	return boss_maximum.duplicate_value()


func _objective_label() -> String:
	match objective_id:
		"hunt_elite": return "猎杀精英"
		"timed_break": return "限时击破（奖励%s）" % ("有效" if timed_bonus_available else "已失去")
		_: return "清除全部目标"


func _hazard_status_text() -> String:
	if hazard_states.is_empty():
		return "无"
	var parts: Array[String] = []
	for state in hazard_states:
		parts.append("%s:%s" % [String(state.id), String(state.phase)])
	return ", ".join(parts)


func _elite_status_text() -> String:
	var elite := _enemy_by_entity_id(elite_entity_id)
	if battle_over or elite_rule_ids.is_empty() or elite == null or elite.health <= 0.0:
		return "无"
	var parts: Array[String] = []
	for rule in elite_rule_ids:
		if rule == "periodic_barrier":
			parts.append("periodic_barrier:%s" % ("active" if elite_barrier_active else "open"))
		elif rule == "summon_reinforcements":
			parts.append("summon_reinforcements:%s" % ("used" if reinforcements_summoned else "ready"))
	return ", ".join(parts)


func _preferred_skill_one_target() -> EnemyData:
	var marked := _enemy_by_entity_id(marked_entity_id)
	if marked != null and marked.health > 0.0 and sim_tick < hunter_mark_expires_tick and player_position.distance_to(marked.position) <= locked_targeting_distance:
		return marked
	if hunter_mark_candidate_entity_id > 0 and sim_tick <= hunter_mark_candidate_expires_tick:
		var candidate := _enemy_by_entity_id(hunter_mark_candidate_entity_id)
		if candidate != null and candidate.health > 0.0 and player_position.distance_to(candidate.position) <= locked_targeting_distance:
			return candidate
	return _nearest_enemy()


func _nearest_enemy(maximum_distance: float = INF) -> EnemyData:
	var nearest: EnemyData
	var best_distance: float = maximum_distance * maximum_distance
	for enemy: EnemyData in enemies:
		if enemy.health <= 0.0:
			continue
		var distance: float = player_position.distance_squared_to(enemy.position)
		if distance < best_distance or (is_equal_approx(distance, best_distance) and (nearest == null or enemy.entity_id < nearest.entity_id)):
			best_distance = distance
			nearest = enemy
	return nearest


func _is_skill_equipped(slot_index: int, expected_id: String) -> bool:
	if not embedded_session:
		return false
	var skills: Variant = framework_active_build.get("skills", [])
	return skills is Array and slot_index >= 0 and slot_index < (skills as Array).size() and String((skills as Array)[slot_index]) == expected_id


func _arena_rect() -> Rect2:
	const HUD_CLEARANCE: float = 190.0
	return Rect2(Vector2(ARENA_MARGIN, HUD_CLEARANCE), Vector2(
		AUTHORITY_VIEWPORT_SIZE.x - ARENA_MARGIN * 2.0,
		AUTHORITY_VIEWPORT_SIZE.y - HUD_CLEARANCE - ARENA_MARGIN
	))


func _walkable_geometry(padding: float) -> Dictionary:
	var geometry_value: Variant = WalkableGeometryScript.from_layout(layout_id, _arena_rect(), padding)
	var normalized: Dictionary = WalkableGeometryScript.normalize(geometry_value)
	if not bool(normalized.get("ok", false)):
		var generation_error := "walkable_geometry_generation_failed: %s" % String(normalized.get("error", "unknown"))
		push_error(generation_error)
		assert(false, generation_error)
		return {}
	return (normalized.get("value", {}) as Dictionary).duplicate(true)


func _clamp_to_arena(value: Vector2, padding: float) -> Vector2:
	var projected: Dictionary = WalkableGeometryScript.project(value, _walkable_geometry(padding))
	if not bool(projected.get("ok", false)) or not projected.get("position", null) is Vector2:
		var projection_error := "walkable_geometry_projection_failed: %s" % String(projected.get("error", "invalid_position"))
		push_error(projection_error)
		assert(false, projection_error)
		return value
	return projected.position


func _on_viewport_size_changed() -> void:
	if in_arena:
		player_position = _clamp_to_arena(player_position, 14.0)
	_presentation_redraw()


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
	if not presentation_enabled:
		return
	var viewport_rect := Rect2(Vector2.ZERO, get_viewport_rect().size)
	draw_rect(viewport_rect, COLOR_INK)
	if not in_arena:
		_draw_base_backdrop()
		return
	var arena: Rect2 = _arena_rect()
	if world_view == null:
		_draw_legacy_arena(arena)
		return
	# The approved world fills the window at an integer 2x and follows the hero.
	world_view.begin_frame(viewport_rect, player_position, arena)
	draw_set_transform_matrix(world_view.world_transform())
	world_view.draw_ground(self)
	world_view.draw_room_concept(self, layout_id, sim_tick)
	world_view.draw_decals(self)
	world_view.draw_structure_shadows(self)
	_draw_actor_shadows()
	# Ground-level gameplay telegraphs stay under the actors.
	draw_set_transform_matrix(world_view.gameplay_transform())
	_draw_gameplay_ground_effects(arena)
	draw_set_transform_matrix(world_view.world_transform())
	_draw_actors_ysorted()
	draw_set_transform_matrix(world_view.gameplay_transform())
	_draw_gameplay_status_overlays()
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Flat-field fallback used only when the approved art is unavailable.
func _draw_legacy_arena(rect: Rect2) -> void:
	draw_rect(rect, COLOR_GROUND)
	_draw_arena_floor_legacy(rect)
	_draw_layout_markers(rect)
	for hazard in hazard_states:
		_draw_hazard(hazard)
	_draw_actors_ysorted_legacy()
	_draw_piercing_projectiles()
	for trace: ArrowTrace in traces:
		var alpha: float = clampf(trace.remaining / 0.18, 0.0, 1.0)
		var direction := (trace.to - trace.from).normalized()
		var start := trace.to - direction * minf(10.0, trace.from.distance_to(trace.to))
		draw_line(start, trace.to, Color(COLOR_AMBER, alpha * 0.55), 1.2, false)
	_draw_player_status_overlay()
	_draw_combat_feedback_marks()


func _draw_layout_markers(rect: Rect2) -> void:
	if layout_id == "corridor":
		var corridor := Rect2(Vector2(rect.position.x, rect.get_center().y - 86.0), Vector2(rect.size.x, 172.0))
		draw_rect(corridor, COLOR_AMBER, false, 2.0)
	elif layout_id == "ring":
		var radius := minf(rect.size.x, rect.size.y)
		draw_circle(rect.get_center(), radius * 0.20, Color(COLOR_INK, 0.55))
		draw_arc(rect.get_center(), radius * 0.43, 0.0, TAU, 48, COLOR_AMBER, 2.0)


## Hazard telegraphs stay in authoritative gameplay coordinates: the canvas is
## already transformed, so their geometry is untouched.
func _draw_gameplay_ground_effects(arena: Rect2) -> void:
	_draw_walkable_layout_boundaries(arena)
	## Art carries the floor; the remaining movement limits use quiet broken edges.
	## Keep the old amber debug-style layout marks only in the flat-field fallback.
	for enemy: EnemyData in enemies:
		if enemy.is_boss:
			_draw_boss_transition_rings(enemy)
			_draw_boss_target_shape(enemy)
		else:
			_draw_normal_target_shape(enemy)
	for hazard in hazard_states:
		_draw_hazard(hazard)


## Unlike a decoration, ring/corridor limits constrain real movement. Keep them
## readable as quiet ash-coloured broken edges, not the old amber targeting rings.
## The 14px player inset is the same argument used by _move_player/_clamp_to_arena.
func _draw_walkable_layout_boundaries(arena: Rect2) -> void:
	var bounds := arena.grow(-14.0)
	var edge := Color(COLOR_NEUTRAL, 0.60)
	if layout_id == "ring":
		var extent := minf(bounds.size.x, bounds.size.y)
		for factor in [0.20, 0.43]:
			var radius: float = extent * factor
			for segment in range(32):
				var start := TAU * float(segment) / 32.0
				var finish := start + TAU * 0.55 / 32.0
				draw_arc(bounds.get_center(), radius, start, finish, 3, edge, 1.5, false)
	elif layout_id == "corridor":
		var half_height := minf(72.0, bounds.size.y * 0.25)
		for sign_value in [-1.0, 1.0]:
			var y: float = bounds.get_center().y + half_height * sign_value
			var x := bounds.position.x
			while x < bounds.end.x:
				draw_line(Vector2(x, y), Vector2(minf(x + 18.0, bounds.end.x), y), edge, 1.5, false)
				x += 32.0


func _draw_gameplay_status_overlays() -> void:
	_draw_player_status_overlay()
	_draw_piercing_projectiles()
	for trace: ArrowTrace in traces:
		var alpha: float = clampf(trace.remaining / 0.18, 0.0, 1.0)
		var direction := (trace.to - trace.from).normalized()
		var start := trace.to - direction * minf(10.0, trace.from.distance_to(trace.to))
		draw_line(start, trace.to, Color(COLOR_AMBER, alpha * 0.55), 1.2, false)
	_draw_combat_feedback_marks()


func _draw_piercing_projectiles() -> void:
	for projectile: ArrowProjectile in projectiles:
		ArenaWorldViewScript.draw_piercing_arrow(
			self,
			projectile.previous_position,
			projectile.position,
			projectile.direction,
			projectile.origin
		)


## Transient marks are a read-only projection of CombatEventStream. Sparks and
## death bursts are bounded by the same mark array, and every meaning has its
## own shape. None of these presentation-only draws can affect combat authority.
func _draw_combat_feedback_marks() -> void:
	for mark: Dictionary in combat_feedback_marks:
		var duration := maxf(0.001, float(mark.get("duration", COMBAT_FEEDBACK_LIFETIME_SECONDS)))
		var remaining := clampf(float(mark.get("remaining", 0.0)), 0.0, duration)
		var progress := 1.0 - remaining / duration
		var alpha := clampf(remaining / minf(0.24, duration), 0.0, 1.0)
		var kind := String(mark.get("kind", ""))
		var position: Vector2 = mark.get("position", Vector2.ZERO)
		var color := COLOR_BONE
		if kind == "player_damage":
			color = COLOR_WARNING
		elif kind == "blocked":
			color = COLOR_PROXY
		elif kind == "miss":
			color = COLOR_NEUTRAL
		elif kind == "death":
			color = COLOR_AMBER
		var live_color := Color(color, alpha)
		match kind:
			"enemy_damage":
				var incoming := mark.get("incoming_direction", Vector2.RIGHT) as Vector2
				_draw_contact_sparks(position, incoming, live_color, remaining)
			"player_damage":
				var damage_direction := mark.get("incoming_direction", Vector2.RIGHT) as Vector2
				_draw_contact_sparks(position, damage_direction, live_color, remaining)
				var bar_top := position + Vector2(-11.0, -7.0)
				draw_line(bar_top, bar_top + Vector2(22.0, 0.0), live_color, 2.5)
				draw_line(bar_top + Vector2(9.0, 0.0), bar_top + Vector2(9.0, -6.0), live_color, 2.5)
			"blocked":
				for segment: Array in CombatMarksScript.corner_bracket_segments(Rect2(position - Vector2.ONE * 11.0, Vector2.ONE * 22.0), 5.0):
					draw_line(segment[0], segment[1], live_color, 1.5)
			"miss", "avoided":
				if kind == "avoided":
					for index in 2:
						draw_arc(position + Vector2(-4.0 + 8.0 * float(index), -3.0), 8.0, -PI * 0.18, PI * 0.62, 9, live_color, 2.0, true)
				else:
					draw_line(position + Vector2(-7.0, 0.0), position + Vector2(7.0, 0.0), live_color, 2.0)
			"death":
				_draw_death_burst(position, progress, live_color, Color(COLOR_WARNING, alpha * 0.65))
		if combat_feedback_font != null:
			var raw_text := String(mark.get("text", ""))
			var text := _compact_feedback_number(raw_text)
			var lane := int(mark.get("text_lane", 0))
			# Damage copy sits above the actor silhouette, not over the bow/face.
			var height := 64.0 if kind == "player_damage" else 38.0
			var baseline := position + Vector2(-49.0, -height - float(lane) * 15.0 - progress * 14.0)
			var outline_color := Color(COLOR_INK, 0.92 * alpha)
			for offset: Vector2 in [Vector2(-1.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, -1.0), Vector2(0.0, 1.0)]:
				draw_string(combat_feedback_font, baseline + offset, text, HORIZONTAL_ALIGNMENT_CENTER, 98.0, COMBAT_FEEDBACK_TEXT_FONT_SIZE, outline_color)
			draw_string(combat_feedback_font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, 98.0, COMBAT_FEEDBACK_TEXT_FONT_SIZE, live_color)


func _draw_contact_sparks(position: Vector2, direction: Vector2, color: Color, mark_remaining: float) -> void:
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	var age := COMBAT_FEEDBACK_LIFETIME_SECONDS - mark_remaining
	var spark_alpha := clampf(1.0 - age / COMBAT_SPARK_LIFETIME_SECONDS, 0.0, 1.0)
	if spark_alpha <= 0.0:
		return
	for index in 2:
		var spread := (-0.58 + 1.16 * float(index)) * (1.0 - 0.38 * float(index))
		var spark_direction := direction.rotated(spread)
		draw_line(position, position + spark_direction * (7.0 + 3.0 * float(index)), Color(color, color.a * spark_alpha), 1.0)


func _draw_death_burst(position: Vector2, progress: float, edge: Color, core: Color) -> void:
	for index in 8:
		var angle := TAU * (float(index) + progress * 0.35) / 8.0
		var direction := Vector2.from_angle(angle)
		var start := 6.0 + progress * 11.0
		var finish := 16.0 + progress * 22.0
		draw_line(position + direction * start, position + direction * finish, edge, 2.0)
	draw_circle(position, 6.0 + progress * 6.0, core)


## Keeps the authoritative mark text intact while avoiding a long mantissa over
## overlapping actors. Ordinary small integers and short decimals stay natural.
func _compact_feedback_number(value: String) -> String:
	if not value.contains("e") and not value.contains("E"):
		var sign_prefix := value.left(1) if value.begins_with("−") or value.begins_with("-") or value.begins_with("+") else ""
		var number_text := value.substr(sign_prefix.length())
		if number_text.is_valid_float() and is_finite(number_text.to_float()):
			return sign_prefix + String.num(roundf(number_text.to_float()), 0)
		return value
	var parsed := value.to_float()
	if not is_finite(parsed) or absf(parsed) < 10000.0:
		return value
	var exponent := 0
	var coefficient := absf(parsed)
	while coefficient >= 10.0:
		coefficient *= 0.1
		exponent += 1
	while coefficient < 1.0 and coefficient > 0.0:
		coefficient *= 10.0
		exponent -= 1
	var compact := String.num(coefficient, 2)
	while compact.contains(".") and (compact.ends_with("0") or compact.ends_with(".")):
		compact = compact.substr(0, compact.length() - 1)
	return "%s%se%d" % ["-" if parsed < 0.0 else "", compact, exponent]


func _draw_actor_shadows() -> void:
	world_view.draw_shadow(self, world_view.gameplay_to_world(player_position), 30.0, 12.0, 0.24)
	for enemy: EnemyData in enemies:
		if enemy.is_boss:
			world_view.draw_shadow(self, world_view.gameplay_to_world(enemy.position), 92.0, 28.0, 0.34)
		else:
			world_view.draw_shadow(self, world_view.gameplay_to_world(enemy.position), 38.0, 14.0, 0.24)


func _draw_arena_floor_legacy(rect: Rect2) -> void:
	for x: int in range(int(rect.position.x), int(rect.end.x), 32):
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), COLOR_DEEP_BLUE, 1.0)
	for y: int in range(int(rect.position.y), int(rect.end.y), 32):
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), COLOR_DEEP_BLUE, 1.0)
	draw_rect(rect, COLOR_NEUTRAL, false, 3.0)


## Manual y-sort on ground contact points so the published artwork layers read in
## the same order as the approved sample without moving any entity. The world
## version draws every actor from the one world transform; the legacy version
## keeps raw screen coordinates for the flat-field fallback.
func _draw_actors_ysorted() -> void:
	var hero_world: Vector2 = world_view.gameplay_to_world(player_position)
	var drawables: Array[Dictionary] = []
	for entry in world_view.structure_draw_list():
		var structure_feet: Vector2 = entry["feet_world"]
		drawables.append({"y": structure_feet.y, "rank": 0, "kind": "structure", "sprite": String(entry["sprite_id"]), "world": structure_feet})
	drawables.append({"y": world_view.tower_feet_world().y, "rank": 0, "kind": "tower", "sprite": "", "world": world_view.tower_feet_world()})
	for enemy: EnemyData in enemies:
		var enemy_world: Vector2 = world_view.gameplay_to_world(enemy.position)
		drawables.append({"y": enemy_world.y, "rank": 3 if enemy.is_boss else 1, "kind": "boss" if enemy.is_boss else "enemy", "sprite": "", "world": enemy_world, "enemy": enemy})
	for corpse: Dictionary in enemy_corpses:
		var corpse_world: Vector2 = world_view.gameplay_to_world(corpse.get("position", Vector2.ZERO) as Vector2)
		drawables.append({"y": corpse_world.y, "rank": 1, "kind": "corpse", "sprite": "", "world": corpse_world, "corpse": corpse})
	drawables.append({"y": hero_world.y, "rank": 2, "kind": "player", "sprite": "", "world": hero_world})
	drawables.sort_custom(_drawable_precedes)
	var front_cells: Array[Dictionary] = []
	var hero_drawn := false
	for drawable: Dictionary in drawables:
		if drawable["kind"] == "player":
			hero_drawn = true
		elif hero_drawn and drawable["kind"] in ["enemy", "boss", "corpse"]:
			var feet: Vector2 = drawable["world"]
			if drawable["kind"] == "corpse":
				## A corpse can stand in front of the hero too, so it takes part in the
				## same one-shot budget instead of being added after the plan was split.
				var corpse: Dictionary = drawable["corpse"]
				var corpse_frame: Dictionary = corpse.get("frame", {})
				if not corpse_frame.is_empty() and not bool(corpse_frame.get("fallback", true)):
					front_cells.append({"id": "corpse.%d" % int(corpse.get("entity_id", 0)), "feet_world": feet, "art_box": _enemy_frame_art_box(corpse_frame, feet), "base_alpha": 1.0})
			elif drawable["kind"] == "boss":
				## The prepass consumes the same shared part geometry the draw uses, so the
				## hero-occlusion budget is measured on the cells that really land: pose
				## offsets, hand deltas and phase all come from one function.
				var boss_enemy: EnemyData = drawable["enemy"]
				var awakened := boss_enemy.phase_id == "awakened"
				var left_base := boss_enemy.position + Vector2(-43.0 if awakened else -34.0, -8.0 if awakened else 0.0)
				var right_base := boss_enemy.position + Vector2(38.0 if awakened else 34.0, 12.0 if awakened else 0.0)
				var parts: Array[Dictionary] = world_view.boss_draw_parts(feet, 2 if awakened else 1, boss_enemy.left_hand_position - left_base, boss_enemy.right_hand_position - right_base, _boss_visual_pose(boss_enemy))
				for part: Dictionary in parts:
					var part_id := String(part.get("sprite_id", ""))
					## boss_draw_parts() is the one source of the part anchor: both the GPU pass
					## and this budget pass consume the same sprite id and the same feet, so a
					## posed fist can never escape the hero's opacity split.
					var part_feet: Vector2 = part.get("feet", part.get("feet_world", feet))
					var part_alpha := float(part.get("base_alpha", world_view.boss_fade_alpha(feet, hero_world)))
					front_cells.append({"id": part_id, "feet_world": part_feet, "art_box": world_view.sprite_art_box(part_id, part_feet), "base_alpha": part_alpha})
			else:
				## The budget is measured on the cell this enemy really draws: the published
				## action frame when the new pack is live, the calibration slot while pending.
				var enemy: EnemyData = drawable["enemy"]
				front_cells.append({"id": "enemy.%d" % enemy.entity_id, "feet_world": feet, "art_box": _enemy_art_box(enemy, feet), "base_alpha": 1.0})
	world_view.prepare_actor_occlusion(front_cells, hero_world)
	for drawable in drawables:
		match String(drawable["kind"]):
			"structure":
				world_view.draw_structure(self, String(drawable["sprite"]), drawable["world"], hero_world)
			"tower":
				world_view.draw_tower(self, hero_world)
			"enemy", "boss":
				_draw_enemy(drawable["enemy"] as EnemyData)
			"corpse":
				_draw_enemy_corpse(drawable["corpse"] as Dictionary)
			_:
				_draw_player()
	_draw_mark_indicator()
	_draw_pointer_target_indicator()


func _draw_actors_ysorted_legacy() -> void:
	var drawables: Array[Dictionary] = []
	for enemy: EnemyData in enemies:
		drawables.append({"y": enemy.position.y, "rank": 3 if enemy.is_boss else 1, "kind": "boss" if enemy.is_boss else "enemy", "sprite": "", "world": enemy.position, "enemy": enemy})
	drawables.append({"y": player_position.y, "rank": 2, "kind": "player", "sprite": "", "world": player_position})
	drawables.sort_custom(_drawable_precedes)
	for drawable in drawables:
		match String(drawable["kind"]):
			"enemy", "boss":
				_draw_enemy(drawable["enemy"] as EnemyData)
			_:
				_draw_player()
	_draw_pointer_target_indicator()


func _drawable_precedes(left: Dictionary, right: Dictionary) -> bool:
	if not is_equal_approx(float(left["y"]), float(right["y"])):
		return float(left["y"]) < float(right["y"])
	if int(left["rank"]) != int(right["rank"]):
		return int(left["rank"]) < int(right["rank"])
	return String(left["kind"]) < String(right["kind"])


func _draw_hazard(state: Dictionary) -> void:
	var phase := String(state.get("phase", "warning"))
	var color := Color(COLOR_WARNING, 0.20 if phase == "warning" else (0.58 if phase == "active" else 0.10))
	if String(state.get("id", "")) == "moving_fireline":
		## Warning stays an open boundary; recovery loses the danger-red read.
		## All three stages use the simulation's exact origin/length/width.
		var line_color := Color(COLOR_NEUTRAL, 0.18) if phase == "recovery" else color
		_draw_lane_shape(state.origin, state.direction, float(state.length), float(state.width), line_color, phase == "active", phase == "warning")
	else:
		draw_circle(state.origin, float(state.radius), color)
		draw_arc(state.origin, float(state.radius), 0.0, TAU, 32, COLOR_WARNING if phase != "recovery" else COLOR_NEUTRAL, 2.0)


func _draw_base_backdrop() -> void:
	var size: Vector2 = get_viewport_rect().size
	for y: int in range(0, int(size.y), 24):
		var width: float = 120.0 + float((y / 24) % 5) * 42.0
		draw_rect(Rect2(Vector2(size.x - width, y), Vector2(width, 12.0)), COLOR_DEEP_BLUE)
	draw_circle(Vector2(size.x * 0.85, size.y * 0.82), 92.0, COLOR_GROUND)
	draw_circle(Vector2(size.x * 0.85, size.y * 0.82), 61.0, COLOR_INK)
	draw_line(Vector2(size.x * 0.79, size.y * 0.89), Vector2(size.x * 0.91, size.y * 0.75), COLOR_PROXY, 7.0)


func _draw_player() -> void:
	if world_view != null:
		# The shared action frame while the published action atlas is in hand; the
		# approved four-way static idle cell otherwise. The reader flags that pending
		# fallback explicitly (ranger_action_pending_reason), so it is never a silent
		# substitution, and the legacy step bob stays unimplemented on top of it.
		var frame: Dictionary = _ranger_frame()
		if not frame.is_empty():
			_draw_ranger_frame(frame)
			return
		world_view.draw_sprite(self, "ranger.%s.idle" % _player_facing_name(), world_view.gameplay_to_world(player_position))
	elif actors_atlas != null:
		var facing_column := _player_facing_column()
		var step_offset := 4 if _player_is_visually_moving() and int(sim_tick / 8) % 2 == 1 else 0
		var source := Rect2(Vector2(float(facing_column + step_offset) * ACTOR_CELL_SIZE, 0.0), Vector2.ONE * ACTOR_CELL_SIZE)
		draw_texture_rect_region(actors_atlas, Rect2(player_position - Vector2.ONE * 16.0, Vector2.ONE * ACTOR_CELL_SIZE), source)
	else:
		draw_rect(Rect2(player_position - Vector2(9.0, 11.0), Vector2(18.0, 22.0)), COLOR_BONE)
		draw_colored_polygon(PackedVector2Array([player_position + Vector2(-10.0, 11.0), player_position + Vector2(10.0, 11.0), player_position + Vector2(0.0, 18.0)]), COLOR_BONE)


## Consumes each authority event exactly once. Animation readers and transient
## marks receive the same event id that describes the resolved action; neither
## presentation path has to reconstruct a hit from counters or health deltas.
func _consume_combat_presentation_events() -> void:
	if combat_event_stream == null:
		return
	for event: Dictionary in combat_event_stream.events_after(presentation_event_cursor):
		presentation_event_cursor = maxi(presentation_event_cursor, int(event.get("event_id", 0)))
		if combat_feedback_audio != null:
			combat_feedback_audio.handle_event(event)
		var event_type := String(event.get("type", ""))
		var event_tick := int(event.get("tick", sim_tick))
		var event_token := "combat:%d" % int(event.get("event_id", 0))
		match event_type:
			"action_accepted":
				if ranger_animation != null and String(event.get("actor_id", "")) == "ranger" and String(event.get("action_id", "")) == "piercing_arrow":
					ranger_animation.latch_event(RANGER_EVENT_SHOT, event_token, event_tick)
			"damage_applied":
				var target_id := String(event.get("target_id", ""))
				var target_entity_id := int(event.get("target_entity_id", 0))
				if target_id == "ranger":
					if ranger_animation != null:
						ranger_animation.latch_event(RANGER_EVENT_HIT, event_token, event_tick)
					_append_combat_feedback(event, "player_damage", "−%s" % String(event.get("amount", "0")))
				elif target_entity_id > 0:
					if enemy_animation != null:
						enemy_animation.latch_event(_enemy_hit_event_kind(target_entity_id), event_token, event_tick)
					_append_combat_feedback(event, "enemy_damage", String(event.get("amount", "0")))
			"attack_resolved":
				var outcome := String(event.get("outcome", ""))
				if outcome == "blocked":
					_append_combat_feedback(event, "blocked", "圣律屏障")
				elif outcome == "miss" and String(event.get("source_id", "")).begins_with("ranger/"):
					_append_combat_feedback(event, "miss", "落空")
				elif outcome == "avoided" and String(event.get("target_id", "")) == "ranger":
					_append_combat_feedback(event, "avoided", "闪避")
			"death_applied":
				if String(event.get("target_id", "")) == "ranger":
					if ranger_animation != null:
						ranger_animation.latch_event(RANGER_EVENT_DEATH, event_token, event_tick)
				else:
					_append_combat_feedback(event, "death", "击破")


func combat_feedback_report() -> Dictionary:
	return {
		"mark_count": combat_feedback_marks.size(),
		"mark_limit": COMBAT_FEEDBACK_LIMIT,
		"presentation_event_cursor": presentation_event_cursor,
		"audio": combat_feedback_audio.report() if combat_feedback_audio != null else {},
	}


func _append_combat_feedback(event: Dictionary, kind: String, text: String) -> void:
	var position_value: Variant = event.get("contact_point", event.get("position", Vector2.ZERO))
	if not position_value is Vector2:
		return
	var feedback_key := _combat_feedback_key(event, kind)
	if kind == "enemy_damage" or kind == "player_damage":
		for index: int in range(combat_feedback_marks.size() - 1, -1, -1):
			var current: Dictionary = combat_feedback_marks[index]
			if String(current.get("feedback_key", "")) != feedback_key:
				continue
			## Keep the latest resolved value at the latest contact point. This is a
			## presentation replacement, so the authority event id still advances.
			current["event_id"] = int(event.get("event_id", 0))
			current["position"] = position_value
			current["text"] = text
			if event.has("incoming_direction"):
				current["incoming_direction"] = event.get("incoming_direction")
			current["remaining"] = COMBAT_FEEDBACK_LIFETIME_SECONDS
			current["duration"] = COMBAT_FEEDBACK_LIFETIME_SECONDS
			combat_feedback_marks[index] = current
			return
	combat_feedback_marks.append({
		"event_id": int(event.get("event_id", 0)),
		"kind": kind,
		"feedback_key": feedback_key,
		"position": position_value,
		"incoming_direction": event.get("incoming_direction", Vector2.RIGHT),
		"text": text,
		"text_lane": int(COMBAT_FEEDBACK_TEXT_LANES.get(kind, 0)),
		"remaining": COMBAT_FEEDBACK_LIFETIME_SECONDS,
		"duration": COMBAT_FEEDBACK_LIFETIME_SECONDS,
	})
	while combat_feedback_marks.size() > COMBAT_FEEDBACK_LIMIT:
		combat_feedback_marks.pop_front()


func _combat_feedback_key(event: Dictionary, kind: String) -> String:
	var target_entity_id := int(event.get("target_entity_id", 0))
	if target_entity_id > 0:
		return "%s:enemy/%d" % [kind, target_entity_id]
	var target_id := String(event.get("target_id", ""))
	if not target_id.is_empty():
		return "%s:%s" % [kind, target_id]
	return "%s:event/%d" % [kind, int(event.get("event_id", 0))]


func _advance_combat_feedback(delta: float) -> void:
	for index: int in range(combat_feedback_marks.size() - 1, -1, -1):
		combat_feedback_marks[index]["remaining"] = maxf(0.0, float(combat_feedback_marks[index].get("remaining", 0.0)) - maxf(0.0, delta))
		if float(combat_feedback_marks[index]["remaining"]) <= 0.0:
			combat_feedback_marks.remove_at(index)


## Advances the defeat clip's presentation clock and consumes any events left by
## direct test drivers. It only reads authoritative fields.
func _update_ranger_action_events(delta: float) -> void:
	_consume_combat_presentation_events()
	if player_health <= 0.0:
		if in_arena:
			ranger_death_seconds += maxf(0.0, delta)
		if ranger_animation != null and ranger_animation.latched_event_id(RANGER_EVENT_DEATH).is_empty():
			ranger_animation.latch_event(RANGER_EVENT_DEATH, "ranger:death:fallback", sim_tick)
	else:
		ranger_death_seconds = 0.0
		if defeat_presentation != null:
			defeat_presentation.reset()


## The shared reader's trigger contract, filled only from authoritative fields
## and the latched events above. Dodge and dash report the tick counters the
## simulation already owns; a one-shot clip drops out on its own published length.
func _ranger_animation_state() -> Dictionary:
	var timeline_snapshot: Dictionary = player_action_timeline.snapshot() if player_action_timeline != null else {}
	var active_action: Dictionary = timeline_snapshot.get("active", {})
	var shoot_ticks := -1
	if not active_action.is_empty():
		var elapsed := maxi(0, sim_tick - int(active_action.get("start_tick", sim_tick)))
		var windup := maxi(1, int(active_action.get("windup_ticks", PlayerActionTimelineScript.WINDUP_TICKS)))
		shoot_ticks = floori(float(elapsed * PlayerActionTimelineScript.WINDUP_TICKS) / float(windup)) if elapsed < windup else PlayerActionTimelineScript.WINDUP_TICKS + elapsed - windup
	var state := {
		"facing": player_facing,
		"dead": player_health <= 0.0,
		## Rounded, not truncated: 144 steps of 1/144s sum to 0.9999999 in float, and
		## truncating that would leave the clip one tick short after a second.
		"death_ticks": roundi(ranger_death_seconds * float(RangerAnimationScript.SIM_TICKS_PER_SECOND)),
		"hit_ticks": -1,
		"dodge_ticks": maxi(0, sim_tick - dodge_started_tick) if dodge_remaining_ticks > 0 and dodge_started_tick >= 0 else -1,
		"dodge_window_ticks": DODGE_DURATION_TICKS,
		"dash_ticks": maxi(0, sim_tick - dash_started_tick) if dash_remaining_ticks > 0 and dash_started_tick >= 0 else -1,
		"dash_window_ticks": _talent_scaled_ticks(DASH_DURATION_TICKS, "dash_duration_multiplier"),
		"shoot_ticks": shoot_ticks,
		"shoot_window_ticks": PlayerActionTimelineScript.WINDUP_TICKS + PlayerActionTimelineScript.RECOVERY_TICKS,
		"moving": _player_is_visually_moving(),
		"phase_ticks": sim_tick,
		"tick": sim_tick,
	}
	if ranger_animation != null:
		state["hit_ticks"] = ranger_animation.latched_ticks(RANGER_EVENT_HIT, sim_tick)
	return state


## The shared action frame, or an empty dictionary while the action atlas is
## pending or broken, in which case the approved static four-way idle cell is
## drawn and the reader reports the reason.
func _ranger_frame() -> Dictionary:
	return ranger_frame


## Drawn inside the world transform, exactly like the world view draws its own
## cells: the destination is built from the frame's own anchor and rect, so no
## cell slot is ever assumed.
func _draw_ranger_frame(frame: Dictionary) -> void:
	var texture: Texture2D = frame.get("texture")
	var rect: Rect2i = frame.get("rect", Rect2i())
	if texture == null or rect.size.x <= 0 or rect.size.y <= 0:
		return
	var anchor: Vector2i = frame.get("anchor", RangerAnimationScript.DEFAULT_ANCHOR)
	var draw_offset: Vector2i = frame.get("draw_offset", Vector2i.ZERO)
	var feet_world: Vector2 = world_view.gameplay_to_world(player_position)
	draw_texture_rect_region(texture, Rect2((feet_world - Vector2(anchor) + Vector2(draw_offset)).round(), Vector2(rect.size)), Rect2(rect))


## Runtime integration diagnostic for the art pass: the frame the hero is drawn
## from (action, facing, clip, frame, rect, anchor) and the last latched action
## token with its time. Read it after a capture to compare against the state.
func ranger_animation_report() -> Dictionary:
	var report := {
		"pending_reason": ranger_action_pending_reason,
		"state": _ranger_animation_state(),
		"frame": ranger_frame,
		## True while the published death clip is the frame this arena draws: the
		## defeat window's screen evidence, which the router waits for before the
		## result page replaces the corpse.
		"death_clip_visible": in_arena and player_health <= 0.0 and _defeat_clip_drawable(),
	}
	if ranger_animation != null:
		report["reader"] = ranger_animation.integration_report()
	return report


## The router's read-only visual gate for a defeat. An empty reason means the
## route may move now; a non-empty one names the live hold. The hold never
## touches authoritative state: battle_over, the settlement and the rewards
## already latched on the death tick, so this only decides when the result screen
## may replace the fallen ranger.
func defeat_hold_reason() -> String:
	if not presentation_enabled:
		return ""
	if not in_arena:
		return ""
	if battle_victory:
		return ""
	if player_health > 0.0:
		return ""
	if defeat_presentation == null:
		return ""
	if not _defeat_clip_drawable():
		return ""
	if defeat_presentation.route_ready():
		return ""
	return DefeatPresentationScript.HOLD_REASON


## True when the session router may move on. A false answer is always named by
## defeat_hold_reason(), is bounded by the router's own fallback clock, and is
## released by defeat_skip_presentation().
func defeat_route_ready() -> bool:
	return defeat_hold_reason().is_empty()


## The shared death clip is the thing this arena is drawing: the action atlas is
## in hand and the world view draws the shared hero frame. A pending atlas or the
## flat-field fallback has no death frames to show, so it never holds a route and
## never claims the clip played.
func _defeat_clip_drawable() -> bool:
	return world_view != null and ranger_animation != null and ranger_animation.has_real_art()


## Public skip entry: a player pressing return, an abandon request, or a capture
## script that has already recorded the fall. The result was latched on the death
## tick, so skipping only moves the route -- it never re-settles, and a repeat is
## a no-op because the router finalizes once.
func defeat_skip_presentation(reason: String = "skipped") -> void:
	if defeat_presentation == null:
		return
	defeat_presentation.skip(reason)


## Read-only runtime diagnostic for the defeat window: whether the route is held,
## why, and what the window has actually seen on screen. Read it after a real
## death to compare the drawn frames against the published clip.
func defeat_presentation_report() -> Dictionary:
	var window_report: Dictionary = defeat_presentation.report() if defeat_presentation != null else {}
	return {
		"route_ready": defeat_route_ready(),
		"hold_reason": defeat_hold_reason(),
		"clip_drawable": _defeat_clip_drawable(),
		"presentation_enabled": presentation_enabled,
		"battle_over": battle_over,
		"battle_victory": battle_victory,
		"dead": player_health <= 0.0,
		"death_seconds": ranger_death_seconds,
		"death_ticks": roundi(ranger_death_seconds * float(RangerAnimationScript.SIM_TICKS_PER_SECOND)),
		"sim_tick": sim_tick,
		"window": window_report,
	}


## Hero state overlays stay in authoritative gameplay coordinates and are drawn
## through the gameplay transform, after every actor.
func _draw_player_status_overlay() -> void:
	var damage_overlay := _player_damage_overlay_state()
	if not damage_overlay.is_empty():
		## Keep impact marks outside the silhouette so a hit never hides a dodge
		## or bow pose. This reads only the latched authority event.
		var offset: Vector2 = damage_overlay.get("offset", Vector2.ZERO)
		var alpha := float(damage_overlay.get("alpha", 0.0))
		var body := Rect2(player_position + offset - Vector2(11.0, 37.0), Vector2(22.0, 31.0)) if world_view != null else Rect2(player_position + offset - Vector2(9.0, 11.0), Vector2(18.0, 22.0))
		for segment in CombatMarksScript.corner_bracket_segments(body.grow(7.0), 4.0):
			draw_line(segment[0], segment[1], Color(COLOR_WARNING, alpha), 1.2, false)
	if dash_remaining_ticks > 0:
		var dash_step := DASH_TOTAL_DISTANCE / float(_talent_scaled_ticks(DASH_DURATION_TICKS, "dash_duration_multiplier"))
		for trail_index in range(1, 4):
			draw_circle(player_position - dash_direction * dash_step * float(trail_index), 8.0 - float(trail_index), Color(COLOR_PROXY, 0.28 / float(trail_index)))
	if dodge_remaining_ticks > 0:
		var dodge_frame := Rect2(player_position - Vector2(22.0, 54.0), Vector2(44.0, 64.0)) if world_view != null else Rect2(player_position - Vector2(13.0, 16.0), Vector2(26.0, 32.0))
		## Same authored frame and the same active window, drawn as four short bone
		## corners: a closed box around the hero read as a hitbox he was standing in.
		for segment in CombatMarksScript.corner_bracket_segments(dodge_frame, 10.0):
			draw_line(segment[0], segment[1], COLOR_BONE, 2.0)
	var aim_origin := player_position + Vector2(0.0, -26.0) if world_view != null else player_position
	var aim_length := 19.0
	draw_line(aim_origin, aim_origin + player_facing * aim_length, COLOR_AMBER, 3.0)


## A deterministic, independent player-damage channel. It exposes the source
## event token for diagnostics/tests, while draw code receives only derived
## visual values. A repeated presentation commit sees the same token and age,
## so it cannot restart or duplicate the impact.
func _player_damage_overlay_state() -> Dictionary:
	if ranger_animation == null or player_health <= 0.0:
		return {}
	var age_ticks: int = ranger_animation.latched_ticks(RANGER_EVENT_HIT, sim_tick)
	if age_ticks < 0 or age_ticks >= PLAYER_DAMAGE_OVERLAY_TICKS:
		return {}
	var alpha := clampf(0.92 - 0.10 * float(age_ticks), 0.32, 0.92)
	return {
		"event_id": ranger_animation.latched_event_id(RANGER_EVENT_HIT),
		"age_ticks": age_ticks,
		"duration_ticks": PLAYER_DAMAGE_OVERLAY_TICKS,
		"alpha": alpha,
		"offset": Vector2(1.0 if age_ticks % 2 == 0 else -1.0, 0.0),
	}


func _player_facing_name() -> String:
	if absf(player_facing.x) > absf(player_facing.y):
		return "east" if player_facing.x >= 0.0 else "west"
	return "south" if player_facing.y >= 0.0 else "north"


func _player_facing_column() -> int:
	if absf(player_facing.x) > absf(player_facing.y):
		return 1 if player_facing.x >= 0.0 else 3
	return 2 if player_facing.y >= 0.0 else 0


func _player_is_visually_moving() -> bool:
	return player_last_displacement.length_squared() > 0.000001


func _resolved_build_is_valid(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var build: Dictionary = value
	if not bool(build.get("ok", false)) or String(build.get("build_fingerprint", "")).length() != 64:
		return false
	var parameters: Variant = build.get("final_parameters", {})
	if not parameters is Dictionary:
		return false
	for key in ["p", "T", "v", "d", "turn", "damage", "max_health"]:
		var parameter: Variant = (parameters as Dictionary).get(key, null)
		if typeof(parameter) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(parameter)):
			return false
	if not build.get("total_events", {}) is Dictionary:
		return false
	return true


func _apply_framework_talents() -> void:
	# The contract compiler is the only authority. Never recompile mutable profile
	# data or accept a second talent injection channel in the arena.
	talent_capabilities = (locked_build.get("talent_capabilities", {}) as Dictionary).duplicate(true)


func _reset_talent_runtime_state() -> void:
	retained_arrow_damage = BigValue.from_float(0.0)
	retained_arrow_ordinary_damage = 0.0
	first_critical_bonus_used = false
	hunter_mark_candidate_entity_id = 0
	hunter_mark_candidate_expires_tick = 0
	three_skill_sequence_stage = 0
	three_skill_bonus_ready = false


func _talent_scaled_ticks(base_ticks: int, capability_id: String) -> int:
	return maxi(1, int(round(float(base_ticks) * (1.0 + clampf(float(talent_capabilities.get(capability_id, 0.0)), -1.0, 10.0)))))


func _talent_scaled_cooldown(base_ticks: int) -> int:
	var reduction := clampf(float(talent_capabilities.get("dodge_cooldown_reduction", 0.0)), 0.0, 0.95)
	return maxi(1, int(round(float(base_ticks) * (1.0 - reduction))))


func _draw_enemy(enemy: EnemyData) -> void:
	if enemy.is_boss:
		if world_view != null:
			_draw_world_boss(enemy)
			_draw_boss_world_bar(enemy)
		else:
			_draw_legacy_boss_art(enemy)
			_draw_boss_health_bar(enemy, 64.0, enemy.position - Vector2(32.0, 39.0))
	else:
		if world_view != null:
			var feet: Vector2 = world_view.gameplay_to_world(enemy.position)
			## Small RGB-only lift separates the dark authored cells from stone.
			## Keep alpha, hit flash, action geometry and the cutaway share intact.
			var role_tint := Color(1.20, 1.18, 1.14, 1.0)
			match enemy.kind_id:
				"charging_raider": role_tint = Color(1.22, 1.16, 1.10, 1.0)
				"fan_ranged": role_tint = Color(1.14, 1.20, 1.24, 1.0)
			var modulate := Color(1.6, 1.6, 1.6, 1.0) if sim_tick < enemy.hit_flash_until_tick else role_tint
			var frame: Dictionary = _enemy_action_frame(enemy.entity_id)
			if not frame.is_empty():
				## The published three-role action cell. A west frame mirrors about the
				## same (24,44) anchor the calibration read flipped on, so the facing
				## transform and the clip are unchanged.
				var cut: Dictionary = world_view.cutaway_for(_enemy_frame_art_box(frame, feet), feet, world_view.gameplay_to_world(player_position))
				_draw_enemy_action_frame(frame, feet, modulate, cut["window"] if cut["in_front"] else Rect2(), float(cut["local_alpha"]))
			else:
				## Pending or broken delivery: the calibration cell stays on screen and
				## enemy_animation_pending_reason() names the cause, so the fallback is
				## never a silent substitution.
				var sprite_id := "enemy.%s.%s" % [_enemy_role_id(enemy), _enemy_pose_id(enemy)]
				var cut: Dictionary = world_view.cutaway_for(world_view.sprite_art_box(sprite_id, feet), feet, world_view.gameplay_to_world(player_position))
				world_view.draw_sprite(self, sprite_id, feet, enemy.facing.x < -0.001, modulate, cut["window"] if cut["in_front"] else Rect2(), float(cut["local_alpha"]))
		else:
			_draw_legacy_normal_art(enemy)


## Phase change rings are authoritative-tick driven vectors, drawn in gameplay
## space under the actor layer.
func _draw_boss_transition_rings(enemy: EnemyData) -> void:
	if enemy.phase_state != "transition":
		return
	var transition_progress := clampf(float(sim_tick - enemy.state_started_tick) / float(maxi(1, enemy.state_ends_tick - enemy.state_started_tick)), 0.0, 1.0)
	for layer in range(3):
		var half_size := 40.0 - float(layer) * 8.0 - transition_progress * (8.0 + float(layer) * 3.0)
		draw_rect(Rect2(enemy.position - Vector2.ONE * half_size, Vector2.ONE * half_size * 2.0), COLOR_ANOMALY, false, 2.0)


## Read-only colossus assembly. The published parts are placed at the approved
## sample spacing and the simulation's own hand offsets are added on top, so the
## windup/active poses read the same without writing any hand position back.
func _draw_world_boss(enemy: EnemyData) -> void:
	var awakened := enemy.phase_id == "awakened"
	var left_base := enemy.position + Vector2(-43.0 if awakened else -34.0, -8.0 if awakened else 0.0)
	var right_base := enemy.position + Vector2(38.0 if awakened else 34.0, 12.0 if awakened else 0.0)
	world_view.draw_boss(
		self,
		world_view.gameplay_to_world(enemy.position),
		2 if awakened else 1,
		enemy.left_hand_position - left_base,
		enemy.right_hand_position - right_base,
		enemy.core_open,
		world_view.gameplay_to_world(player_position),
		_boss_visual_pose(enemy)
	)


## The colossus pose layer is a pure function of authoritative fields: the action
## id, the action state and its two tick stamps, the phase and the facing. It adds
## whole-pixel offsets on top of the approved baseline and never replaces the
## authoritative hand deltas, so a redraw cannot restart a clip and the same tick
## renders the same pose at 30, 60 and 144Hz.
## Recovery additionally carries the pose layer's read-only bridge: the share of
## the active strike the sim has already put back at the base, which keeps the
## fists where the active tick drew them and retracts them along that vector.
func _boss_visual_pose(enemy: EnemyData) -> Dictionary:
	var frame: Dictionary = BossActionPoseScript.pose(
		String(enemy.action_id),
		String(enemy.action_state),
		sim_tick,
		enemy.state_started_tick,
		enemy.state_ends_tick,
		2 if enemy.phase_id == "awakened" else 1,
		enemy.facing,
		String(enemy.phase_state)
	)
	## The sim zeroes its hand deltas the moment the state flips to recovery, so the
	## draw call adds back the share of the strike the pose layer does not carry,
	## scaled into world pixels by the world view's own factor. The frame keeps its
	## six fields, and nothing is written back to the enemy record.
	var bridge: Dictionary = BossActionPoseScript.authority_recovery_hand_offsets(
		String(enemy.action_id),
		String(enemy.action_state),
		sim_tick,
		enemy.state_started_tick,
		enemy.state_ends_tick,
		enemy.facing,
		ArenaWorldViewScript.GAMEPLAY_TO_WORLD
	)
	var pose_left: Vector2 = Vector2(frame["left_hand_offset_px"] as Vector2i)
	var pose_right: Vector2 = Vector2(frame["right_hand_offset_px"] as Vector2i)
	var left_total: Vector2 = pose_left + (bridge["left"] as Vector2)
	var right_total: Vector2 = pose_right + (bridge["right"] as Vector2)
	if left_total != pose_left or right_total != pose_right:
		## One snap for the whole offset, so the pose layer's own rounding cannot
		## fight the bridge's over the last pixel.
		frame["left_hand_offset_px"] = Vector2i(roundi(left_total.x), roundi(left_total.y))
		frame["right_hand_offset_px"] = Vector2i(roundi(right_total.x), roundi(right_total.y))
	return frame


## World-space colossus bar: 64 world units wide is 128 displayed pixels, so it
## still spans the reworked body.
func _draw_boss_world_bar(enemy: EnemyData) -> void:
	var feet: Vector2 = world_view.gameplay_to_world(enemy.position)
	_draw_boss_health_bar(enemy, 64.0, feet + Vector2(-32.0, -134.0), 3.0)


func _draw_boss_health_bar(enemy: EnemyData, width: float, top_left: Vector2, height: float = 6.0) -> void:
	var ratio: float = clampf(1.0 - boss_damage.magnitude / boss_maximum.magnitude, 0.0, 1.0) if boss_damage.layer == 0 and boss_maximum.layer == 0 else 1.0
	draw_rect(Rect2(top_left, Vector2(width, height)), COLOR_DEEP_BLUE)
	draw_rect(Rect2(top_left, Vector2(width * ratio, height)), COLOR_WARNING)
	draw_rect(Rect2(top_left, Vector2(width, height)), COLOR_BONE, false, maxf(1.0, height / 6.0))


## Hunter mark indicator, drawn in world units so it hugs the reworked sprites.
## The bible reads the mark as an open bracket above the target
## ("标记=目标上方开口括号"), so the full circle over the walking space is gone:
## the published dot keeps its offset and a small open bracket hugs it, well
## above the red ground telegraphs it used to compete with.
func _draw_mark_indicator() -> void:
	if world_view == null or marked_entity_id == 0 or sim_tick >= hunter_mark_expires_tick:
		return
	var target := _enemy_by_entity_id(marked_entity_id)
	if target == null or target.health <= 0.0:
		return
	var feet: Vector2 = world_view.gameplay_to_world(target.position)
	var dot := feet + Vector2(0.0, -126.0 if target.is_boss else -56.0)
	var half_extent := 12.0 if target.is_boss else 10.0
	# The dot sits just below the Boss world bar (-134..-131); a tall square
	# overlaps that bar. Keep the mark shallow and wholly below it (-130..-122).
	var bracket := Rect2(dot - Vector2(half_extent, 4.0), Vector2(half_extent * 2.0, 8.0))
	for segment in CombatMarksScript.corner_bracket_segments(bracket, 3.0):
		draw_line(segment[0], segment[1], COLOR_AMBER, 2.0)
	draw_circle(dot, 2.0, COLOR_AMBER)


## Explicit pointer target, distinct from the amber Hunter Mark. This is a
## read-only projection of the held/active entity lock; the bracket follows the
## target body while the original pointer press remains unchanged.
func _draw_pointer_target_indicator() -> void:
	if selected_mode != "Manual" or manual_aim_resolver == null:
		return
	var state := _attack_target_ui_state()
	var source := String(state.get("source", ""))
	if source != ATTACK_SOURCE_POINTER and source != ATTACK_SOURCE_ASSISTED:
		return
	if not bool(state.get("has_target", false)):
		return
	var center_gameplay: Vector2 = state.get("target_anchor", Vector2.ZERO)
	var radius_gameplay := float(state.get("target_radius", 0.0))
	if radius_gameplay <= 0.0:
		return
	var center := center_gameplay
	var radius := radius_gameplay
	if world_view != null:
		center = world_view.gameplay_to_world(center_gameplay)
		radius = center.distance_to(world_view.gameplay_to_world(center_gameplay + Vector2(radius_gameplay, 0.0)))
	if source == ATTACK_SOURCE_ASSISTED:
		_draw_assisted_target_circle(state, center, radius)
		return
	var bracket := Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
	var color := Color(COLOR_NEUTRAL, 0.82) if String(state.get("status", "")) == POINTER_STATUS_OUT_OF_RANGE else Color(COLOR_PROXY, 0.96)
	for segment in CombatMarksScript.corner_bracket_segments(bracket, clampf(radius * 0.34, 6.0, 18.0)):
		draw_line(segment[0], segment[1], color, 1.5)
	var diamond := PackedVector2Array([
		center + Vector2(0.0, -4.0),
		center + Vector2(4.0, 0.0),
		center + Vector2(0.0, 4.0),
		center + Vector2(-4.0, 0.0),
		center + Vector2(0.0, -4.0),
	])
	draw_polyline(diamond, color, 1.5)


## Subtle assisted-aim ring over the same authoritative anchor the next shot
## uses: a dashed circle with neither corners nor a diamond, so assist can
## never be mistaken for the stronger explicit pointer lock. Read-only
## presentation over the existing target UI snapshot.
func _draw_assisted_target_circle(state: Dictionary, center: Vector2, radius: float) -> void:
	var tint := Color(COLOR_PROXY, 0.55) if bool(state.get("in_range", false)) else Color(COLOR_NEUTRAL, 0.45)
	var segments := 16
	var sweep := TAU / float(segments) * 0.55
	for index in range(segments):
		var start := TAU * float(index) / float(segments)
		draw_arc(center, radius, start, start + sweep, 4, tint, 1.5, false)


func _enemy_role_id(enemy: EnemyData) -> String:
	match enemy.kind_id:
		"charging_raider": return "charger"
		"fan_ranged": return "ranged"
		_: return "melee"


func _enemy_pose_id(enemy: EnemyData) -> String:
	match enemy.action_state:
		"windup": return "windup"
		"active": return "active"
		"recovery": return "recover"
		_: return "idle"


func _draw_legacy_boss_art(enemy: EnemyData) -> void:
	if actors_atlas != null:
		draw_texture_rect_region(actors_atlas, Rect2(enemy.position - Vector2.ONE * 32.0, Vector2.ONE * 64.0), Rect2(0.0, 64.0, 64.0, 64.0))
		draw_texture_rect_region(actors_atlas, Rect2(enemy.left_hand_position - Vector2.ONE * 16.0, Vector2.ONE * 32.0), Rect2(64.0, 64.0, 32.0, 32.0))
		draw_texture_rect_region(actors_atlas, Rect2(enemy.right_hand_position - Vector2.ONE * 16.0, Vector2.ONE * 32.0), Rect2(96.0, 64.0, 32.0, 32.0))
		var core_source := Rect2(160.0 if enemy.core_open else 128.0, 64.0, 32.0, 32.0)
		draw_texture_rect_region(actors_atlas, Rect2(enemy.position - Vector2.ONE * 16.0, Vector2.ONE * 32.0), core_source)
	else:
		draw_rect(Rect2(enemy.position - Vector2(22.0, 22.0), Vector2(44.0, 44.0)), COLOR_WARNING)
		draw_rect(Rect2(enemy.left_hand_position - Vector2(5.0, 12.0), Vector2(10.0, 24.0)), COLOR_BLOOD)
		draw_rect(Rect2(enemy.right_hand_position - Vector2(5.0, 12.0), Vector2(10.0, 24.0)), COLOR_BLOOD)
		draw_rect(Rect2(enemy.position - Vector2.ONE * 6.0, Vector2.ONE * 12.0), COLOR_ANOMALY if enemy.core_open else COLOR_INK)


func _draw_legacy_normal_art(enemy: EnemyData) -> void:
	if actors_atlas != null:
		var base_column := 0
		match enemy.kind_id:
			"charging_raider": base_column = 2
			"fan_ranged": base_column = 4
		var action_frame := enemy.action_state in ["windup", "active"] if enemy.kind_id != "melee_pursuer" else enemy.motion_state == "moving" and int(sim_tick / 8) % 2 == 1
		var source := Rect2(float(base_column + (1 if action_frame else 0)) * ACTOR_CELL_SIZE, 32.0, ACTOR_CELL_SIZE, ACTOR_CELL_SIZE)
		var modulate := Color(1.6, 1.6, 1.6, 1.0) if sim_tick < enemy.hit_flash_until_tick else Color.WHITE
		draw_set_transform(enemy.position, 0.0, Vector2(-1.0 if enemy.facing.x < 0.0 else 1.0, 1.0))
		draw_texture_rect_region(actors_atlas, Rect2(Vector2.ONE * -16.0, Vector2.ONE * ACTOR_CELL_SIZE), source, modulate)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_rect(Rect2(enemy.position - Vector2(10.0, 10.0), Vector2(20.0, 20.0)), COLOR_BLOOD)
		draw_colored_polygon(PackedVector2Array([enemy.position + Vector2(-10.0, -10.0), enemy.position + Vector2(0.0, -14.0), enemy.position + Vector2(10.0, -10.0)]), COLOR_INK)


func _draw_normal_target_shape(enemy: EnemyData) -> void:
	if enemy.action_state not in ["windup", "active"]:
		return
	var color := Color(COLOR_WARNING, 0.30) if enemy.action_state == "windup" else Color(COLOR_BLOOD, 0.62)
	if enemy.kind_id == "melee_pursuer":
		var origin: Vector2 = enemy.target_shape.get("origin", enemy.position)
		var radius := float(enemy.target_shape.get("radius", EnemyTacticsScript.MELEE_ATTACK_RANGE))
		if enemy.action_state == "active":
			draw_circle(origin, radius, color)
		draw_arc(origin, radius, 0.0, TAU, 24, COLOR_BONE if enemy.action_state == "active" else COLOR_WARNING, 2.0, false)
	elif enemy.kind_id == "charging_raider":
		if enemy.action_state == "windup":
			_draw_lane_shape(enemy.charge_origin, enemy.charge_direction, enemy.charge_length, enemy.charge_width, color, false)
		else:
			## During the active charge only the body's next fixed-tick segment is
			## dangerous. Keeping the full warning lane filled here would advertise a
			## hitbox the simulation no longer owns.
			var step := enemy.charge_length / float(CHARGE_ACTIVE_TICKS)
			_draw_lane_shape(enemy.position, enemy.charge_direction, step, enemy.charge_width, color, true)
	elif enemy.kind_id == "fan_ranged":
		var fan_shape: Dictionary = enemy.target_shape
		_draw_fan_shape(
			fan_shape.get("origin", enemy.position),
			fan_shape.get("direction", enemy.facing),
			float(fan_shape.get("half_angle", 0.0)),
			float(fan_shape.get("radius", 0.0)),
			color,
			enemy.action_state == "active"
		)


func _draw_boss_target_shape(enemy: EnemyData) -> void:
	if enemy.action_state not in ["windup", "active", "recovery"] or enemy.target_shape.is_empty():
		return
	var active := enemy.action_state == "active"
	var recovery := enemy.action_state == "recovery"
	var color := Color(COLOR_NEUTRAL, 0.55) if recovery else (Color(COLOR_BLOOD, 0.68) if active else Color(COLOR_WARNING, 0.34))
	match enemy.action_id:
		"slam":
			var rect: Rect2 = enemy.target_shape.get("rect", Rect2())
			if active:
				draw_rect(rect, color)
				draw_line(rect.position, rect.end, COLOR_BONE, 3.0)
				draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), COLOR_BONE, 3.0)
			elif recovery:
				draw_rect(rect, color, false, 2.0)
			else:
				_draw_bracket_rect(rect)
				## Concept: the true range as a hard edge outline plus sparse hatching.
				## The hatch is clipped to the authoritative rect, so the ground can no
				## longer advertise a slam the simulation will not resolve.
				for segment in CombatMarksScript.diagonal_hatch_segments(rect, CombatMarksScript.HATCH_SPACING):
					draw_line(segment[0], segment[1], Color(COLOR_WARNING, 0.55), 1.0)
		"sweep":
			var origin: Vector2 = enemy.target_shape.get("origin", Vector2.ZERO)
			var direction: Vector2 = enemy.target_shape.get("direction", Vector2.RIGHT)
			var radius := float(enemy.target_shape.get("radius", 0.0))
			if recovery:
				draw_line(origin + direction * radius * 0.58, origin + direction * radius * 0.82, color, 4.0)
			else:
				_draw_fan_shape(origin, direction, float(enemy.target_shape.get("half_angle", 0.0)), radius, color, active)
		"lane":
			var recovery_scale := 0.55 if recovery else 1.0
			_draw_lane_shape(enemy.target_shape.get("origin", Vector2.ZERO), enemy.target_shape.get("direction", Vector2.RIGHT), float(enemy.target_shape.get("length", 0.0)) * recovery_scale, float(enemy.target_shape.get("width", 0.0)), color, active, not recovery)


func _draw_bracket_rect(rect: Rect2) -> void:
	var corner := 13.0
	for point in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var sx := 1.0 if point.x == rect.position.x else -1.0
		var sy := 1.0 if point.y == rect.position.y else -1.0
		draw_line(point, point + Vector2(sx * corner, 0.0), COLOR_WARNING, 3.0)
		draw_line(point, point + Vector2(0.0, sy * corner), COLOR_WARNING, 3.0)


func _draw_lane_shape(origin: Vector2, direction: Vector2, length: float, width: float, color: Color, active: bool, emphasize_boundary: bool = true) -> void:
	var side := direction.rotated(PI * 0.5) * width * 0.5
	var finish := origin + direction * length
	var polygon := PackedVector2Array([origin + side, finish + side, finish - side, origin - side])
	if active:
		draw_colored_polygon(polygon, color)
		draw_line(finish + side, finish - side, COLOR_BONE, 3.0)
	else:
		## Stroke centres stay on the exact lane edges. A narrow dark
		## backing separates the red foreground from both snow and dark rubble.
		var edge_color := Color(color, maxf(color.a, 0.80)) if emphasize_boundary else color
		for edge in [PackedVector2Array([origin + side, finish + side]), PackedVector2Array([origin - side, finish - side])]:
			if emphasize_boundary:
				draw_polyline(edge, Color(COLOR_INK, 0.88), 5.0)
			draw_polyline(edge, edge_color, 2.5 if emphasize_boundary else 3.0)
		for step in range(1, 5):
			var center := origin + direction * length * float(step) / 5.0
			draw_line(center + side, center + side * 0.55, edge_color, 2.0)
			draw_line(center - side, center - side * 0.55, edge_color, 2.0)


func _draw_fan_shape(origin: Vector2, direction: Vector2, half_angle: float, radius: float, color: Color, active: bool) -> void:
	var points := PackedVector2Array([origin])
	const SEGMENTS := 12
	for index in range(SEGMENTS + 1):
		var angle := lerpf(-half_angle, half_angle, float(index) / float(SEGMENTS))
		points.append(origin + direction.rotated(angle) * radius)
	if active:
		draw_colored_polygon(points, color)
		draw_polyline(PackedVector2Array(points.slice(1)), COLOR_BONE, 3.0)
	else:
		for index in range(0, SEGMENTS + 1, 3):
			draw_line(origin, points[index + 1], color, 2.0)
		draw_polyline(PackedVector2Array(points.slice(1)), color, 3.0)
