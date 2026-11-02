extends SceneTree
const Layout = preload("res://src/presentation/facility_layout.gd")

func _initialize() -> void:
	var errors: Array[String] = []
	for outer in [Vector2(1024,576),Vector2(1280,720),Vector2(1366,768),Vector2(1600,900),Vector2(1920,1080),Vector2(1600,1000)]:
		for route in ["loadout","forge"]:
			var frame := Layout.frame(outer,route)
			var weights: Array = Layout.LOADOUT_WEIGHTS if route == "loadout" else Layout.FORGE_WEIGHTS
			var rectangles := Layout.columns(frame,weights)
			for index in rectangles.size():
				var rect: Rect2 = rectangles[index]
				if not Rect2(Vector2.ZERO,frame).encloses(rect): errors.append("column outside frame")
				if rect.size.x < 270 or rect.position.x != floorf(rect.position.x): errors.append("narrow or fractional column")
				if index > 0 and rect.intersects(rectangles[index-1]): errors.append("overlapping columns")
			if frame.x != minf(outer.x - 64, Layout.MAX_CONTENT_WIDTH): errors.append("unstable or unbounded content width")
	if Layout.FORGE_WEIGHTS != [0.36,0.64]: errors.append("forge weights are not the approved 0.36 / 0.64 split")
	# The shipped logical canvas is 1280x720 and the loadout body it leaves is 1216x570:
	# the frame is not a preference, it is the rectangle the reported regions are
	# measured against, so a change to either number has to fail here.
	if Layout.frame(Vector2(1280,720),"loadout") != Vector2(1216,570): errors.append("loadout frame is not the shipped 1216x570")
	if Layout.frame(Vector2(1280,720),"forge") != Vector2(1216,540): errors.append("forge frame is not the shipped 1216x540")
	if Layout.frame(Vector2(1600,900),"forge") != Vector2(1536,720): errors.append("adaptive forge frame is not 1536x720 at 1600x900")
	if Layout.frame(Vector2(1366,768),"loadout") != Vector2(1302,618): errors.append("1366x768 loadout does not use the available readable frame")
	if Layout.frame(Vector2(1600,900),"loadout") != Vector2(1536,720): errors.append("1600x900 loadout does not use the available height")
	if Layout.frame(Vector2(1600,900),"training") != Vector2(1536,660): errors.append("1600x900 supporting page does not use the available height")
	if Layout.frame(Vector2(1600,1000),"forge") != Vector2(1536,820): errors.append("1600x1000 forge frame is not 1536x820")
	var hd_frame := Layout.frame(Vector2(1920,1080),"forge")
	var hd_columns := Layout.columns(hd_frame,Layout.FORGE_WEIGHTS)
	if hd_frame != Vector2(1536,900): errors.append("1920x1080 forge frame is not bounded at 1536x900")
	if hd_columns.size() != 2 or (hd_columns[0] as Rect2).intersects(hd_columns[1]) or (hd_columns[0] as Rect2).end.x > (hd_columns[1] as Rect2).position.x:
		errors.append("1920x1080 forge columns are missing or overlap")
	_check_loadout_regions(errors)
	# A geometry calculation cannot certify rendered or first-screen visual fit.
	print("FACILITY_LAYOUT ","pass" if errors.is_empty() else "fail"," ",errors)
	quit(0 if errors.is_empty() else 1)


## Concept 10/03: the four open slots and the hero share the top row, the eight locked
## slots and the current/candidate comparison share the lower row, and each pair spans
## the workspace exactly. These are the relations the page reads; a page that put the
## hero under the strip, or the comparison under the strip, has to fail here instead of
## only in a capture.
func _check_loadout_regions(errors: Array[String]) -> void:
	for outer in [Vector2(1024,576),Vector2(1280,720),Vector2(1366,768),Vector2(1600,900),Vector2(1920,1080),Vector2(1600,1000)]:
		var frame := Layout.frame(outer,"loadout")
		var workspace := Vector2(frame.x,maxf(570.0,frame.y))
		var label := "loadout %dx%d" % [int(outer.x),int(outer.y)]
		var regions := Layout.loadout_regions(workspace)
		var slots: Rect2 = regions.slots
		var hero: Rect2 = regions.hero
		var locked: Rect2 = regions.locked
		var compare: Rect2 = regions.compare
		if slots.position != Vector2.ZERO or slots.size.y != 192.0:
			errors.append("%s: the slots are not the 192px top-left lane" % label)
		if hero.position.y != slots.position.y or hero.size != Vector2(248.0,192.0):
			errors.append("%s: the hero is not a 248x192 cell on the slots' own top edge" % label)
		if hero.position.x < slots.end.x or hero.position.x - slots.end.x != Layout.ROW_GAP or hero.end.x != workspace.x:
			errors.append("%s: the hero is not right of the four slots with exactly one row gap" % label)
		if slots.size.x != workspace.x - 260.0:
			errors.append("%s: the four-slot strip is not the workspace minus the hero's lane" % label)
		if locked.position.y != slots.end.y + Layout.ROW_GAP or compare.position.y != locked.position.y:
			errors.append("%s: the locked grid and the comparison are not the shared lower row" % label)
		if locked.position.x != 0.0 or locked.size.x != floorf(workspace.x * 0.30):
			errors.append("%s: the locked grid is not the floor(.30w) lower-left block" % label)
		if compare.position.x - locked.end.x != Layout.ROW_GAP or compare.end.x != workspace.x:
			errors.append("%s: the comparison is not right of the locked grid with exactly one row gap" % label)
		if locked.size.y != maxf(210.0,workspace.y - locked.position.y) or compare.size.y != locked.size.y:
			errors.append("%s: the lower row is not the remaining body height floored at 210" % label)
		if locked.size.x / 4.0 < 64.0:
			errors.append("%s: the lower-left block cannot hold four 64px locked cells" % label)
		for rect: Rect2 in [slots,hero,locked,compare]:
			if not Rect2(Vector2.ZERO,workspace).encloses(rect): errors.append("%s: a loadout region leaves the workspace" % label)
		if slots.intersects(hero) or locked.intersects(compare): errors.append("%s: two loadout regions overlap" % label)
