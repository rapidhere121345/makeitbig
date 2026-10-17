class_name SimSpatialPort
extends RefCounted

## Narrow integration port for movement and spatial indexing.
##
## The kernel knows nothing about geometry: this port owns boundary resolution,
## dynamic indexes, and continuous overlap queries. Implementations commit
## movement through typed store records and report contact facts as SimHit
## entries only.


## MOVEMENT_BOUNDARY phase: resolve intents into committed record positions.
func apply_movement(_ctx: SimTickContext) -> void:
	pass


## DYNAMIC_INDEX_REFRESH phase: rebuild dynamic indexes from the read view.
func refresh_dynamic_index(_ctx: SimTickContext) -> void:
	pass


## CONTINUOUS_QUERIES phase: run overlap/sensor queries against the refreshed
## index. Results enter the tick as SimHit entries, never as direct mutations.
func run_continuous_queries(_ctx: SimTickContext) -> void:
	pass
