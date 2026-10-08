class_name RangerSkillRules
extends RefCounted

## Single mechanical source for the early ranger actions. Combat consumes these
## constants directly; player-facing content repeats the values only as a
## validated projection so prose and authority cannot drift silently.

const TICKS_PER_SECOND := 30

const PIERCING_ARROW_COOLDOWN_TICKS := 13
const PIERCING_ARROW_WINDUP_TICKS := 5
const PIERCING_ARROW_RECOVERY_TICKS := 5
const PIERCING_ARROW_ACTION_TICKS := PIERCING_ARROW_WINDUP_TICKS + PIERCING_ARROW_RECOVERY_TICKS
const ACTION_INPUT_BUFFER_TICKS := 4

const DODGE_SPEED := 650.0
const DODGE_DURATION_TICKS := 5
const DODGE_COOLDOWN_TICKS := 35

const HUNTER_MARK_RANGE_MULTIPLIER := 1.5
const HUNTER_MARK_DURATION_TICKS := 180
const HUNTER_MARK_COOLDOWN_TICKS := 240
const HUNTER_MARK_DAMAGE_MULTIPLIER := 1.25
const P_OVERFLOW_DAMAGE_BASE_EFFICIENCY := 1.0

const DASH_DURATION_TICKS := 6
const DASH_COOLDOWN_TICKS := 90
const DASH_TOTAL_DISTANCE := 180.0

const CONTENT_FACTS := {
	"piercing_arrow": {
		"cooldown_ticks": PIERCING_ARROW_COOLDOWN_TICKS,
		"duration_ticks": PIERCING_ARROW_ACTION_TICKS,
		"displacement_units": 0.0,
		"speed_units_per_second": 0.0,
		"invulnerable": false,
	},
	"hunter_mark": {
		"cooldown_ticks": HUNTER_MARK_COOLDOWN_TICKS,
		"duration_ticks": HUNTER_MARK_DURATION_TICKS,
		"displacement_units": 0.0,
		"speed_units_per_second": 0.0,
		"invulnerable": false,
	},
	"dash": {
		"cooldown_ticks": DASH_COOLDOWN_TICKS,
		"duration_ticks": DASH_DURATION_TICKS,
		"displacement_units": DASH_TOTAL_DISTANCE,
		"speed_units_per_second": 0.0,
		"invulnerable": false,
	},
	"basic_dodge": {
		"cooldown_ticks": DODGE_COOLDOWN_TICKS,
		"duration_ticks": DODGE_DURATION_TICKS,
		"displacement_units": 0.0,
		"speed_units_per_second": DODGE_SPEED,
		"invulnerable": true,
	},
}
