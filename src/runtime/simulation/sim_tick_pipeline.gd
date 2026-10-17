class_name SimTickPipeline
extends RefCounted

## The fixed, code-defined tick pipeline.
##
## Phase order is a compile-time constant of the simulation: exactly these
## phases, exactly this order, every tick. There is no scheduler, no dynamic
## registration, and no data-driven ordering. Integration happens through the
## four typed ports at fixed slots; empty ports run as no-ops but the phases
## still execute so the tick trace is stable regardless of wiring.

enum Phase {
	BEGIN_TICK_READ_VIEW = 0,
	INTENT = 1,
	ACTION_COMMIT = 2,
	MOVEMENT_BOUNDARY = 3,
	DYNAMIC_INDEX_REFRESH = 4,
	CONTINUOUS_QUERIES = 5,
	DAMAGE_STATUS = 6,
	DEATH_SETTLEMENT = 7,
	STRUCTURAL_COMMIT = 8,
	AUTHORITATIVE_SNAPSHOT = 9,
}

const PHASE_COUNT: int = 10

const PHASE_NAMES: Array[StringName] = [
	&"begin_tick_read_view",
	&"intent",
	&"action_commit",
	&"movement_boundary",
	&"dynamic_index_refresh",
	&"continuous_queries",
	&"damage_status",
	&"death_settlement",
	&"structural_commit",
	&"authoritative_snapshot",
]


static func phase_name(phase_id: int) -> StringName:
	if phase_id < 0 or phase_id >= PHASE_COUNT:
		return &"unknown_phase"
	return PHASE_NAMES[phase_id]


## Runs one full tick against an executor exposing execute_tick_phase(phase_id,
## ctx). Returns the executed phase names in order (the tick trace).
func run(executor: Object, ctx: SimTickContext) -> Array[StringName]:
	# The order is fixed and every phase always executes, so the trace is the
	# contract itself: pre-fill it before execution so the authoritative
	# snapshot built during the final phase already carries the complete trace.
	ctx.phase_trace.clear()
	ctx.phase_trace.append_array(PHASE_NAMES)
	for phase_id in PHASE_COUNT:
		executor.execute_tick_phase(phase_id, ctx)
	return ctx.phase_trace.duplicate()
