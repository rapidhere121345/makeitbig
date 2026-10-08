class_name FacilityLayout
extends RefCounted
## Composition only, in the shipping logical coordinate space. Geometry is
## measured from the host, never from a container's content-driven minimum.
const ROW_GAP := 12
const MODIFIER_MIN_WIDTH := 260
## A desktop shell may fill the window without stretching its reading lanes forever.
## 1536px is the complete workspace at 1600x900 after the page gutters; wider
## windows keep that useful density and centre the content in the extra room.
const MAX_CONTENT_WIDTH := 1536.0
const LOADOUT_MAX_HEIGHT := 720.0
const SUPPORTING_PAGE_MAX_HEIGHT := 660.0
const LOADOUT_WEIGHTS := [0.38, 0.62]
## Forge keeps setup on the left and one decision surface on the right. The old
## third column repeated the same future item twice and made the choice harder to
## follow, especially at the minimum supported size.
const FORGE_WEIGHTS := [0.36, 0.64]

static func frame(outer: Vector2, facility: String) -> Vector2:
	var loadout := facility == "loadout"
	var reserved := 150.0 if loadout else 180.0
	var available_height := maxf(320.0, outer.y - reserved)
	## Forge is one self-contained workbench, so a larger adaptive-shell viewport
	## can give its two lanes real vertical space. Other pages still place supporting
	## sections after their primary composition and therefore retain their body cap.
	var height := available_height if facility == "forge" else minf(
		available_height,
		LOADOUT_MAX_HEIGHT if loadout else SUPPORTING_PAGE_MAX_HEIGHT
	)
	return Vector2(minf(maxf(320.0, outer.x - 64.0), MAX_CONTENT_WIDTH), height)

static func columns(workspace: Vector2, weights: Array) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var width := workspace.x - ROW_GAP * (weights.size() - 1)
	var offset := 0.0
	for weight in weights:
		var extent := floorf(width * float(weight))
		result.append(Rect2(offset,0,extent,workspace.y))
		offset += extent + ROW_GAP
	return result

## Concept 10/03: four slots top-left, ranger top-right; locked grid below
## left, current/candidate comparison below right. The 192px hero is never shrunk.
static func loadout_regions(workspace: Vector2) -> Dictionary:
	# The first-screen top lane holds the four equipped slots and the ranger.
	# Skills begin the lower-left lane, above the locally scrollable locked slots,
	# so their four actions remain discoverable without displacing Equip.
	var top := 192.0
	var lower_y := top + ROW_GAP
	var lock_width := floorf(workspace.x * 0.30)
	return {
		"slots": Rect2(0,0,workspace.x-260,top),
		"hero": Rect2(workspace.x-248,0,248,top),
		"locked": Rect2(0,lower_y,lock_width,maxf(210,workspace.y-lower_y)),
		"compare": Rect2(lock_width+ROW_GAP,lower_y,workspace.x-lock_width-ROW_GAP,maxf(210,workspace.y-lower_y)),
	}
