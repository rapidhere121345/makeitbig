class_name ReportEvidenceMark
extends "res://src/presentation/pixel_grid_icon.gd"
## Code-native monochrome UI marks, not bitmap gameplay assets. Their headings
## carry the meaning too, so grey/colour perception is never the only cue.
const ThemeSource = preload("res://src/presentation/shell_theme.gd")
var kind := "observed"
var active_warning := false

func _init() -> void:
	custom_minimum_size = Vector2(32,32)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

func _draw() -> void:
	var color := ThemeSource.BONE
	if kind == "unverified": color = ThemeSource.NEUTRAL
	if kind == "next": color = ThemeSource.AMBER
	if kind == "bottleneck": color = ThemeSource.WARNING if active_warning else ThemeSource.NEUTRAL
	# Every run is an integer logical rectangle; no anti-aliased strokes.
	var rows: Array[String] = []
	match kind:
		"observed":
			rows = ["..####..........", ".##..##.........", "##....##........", "##....##........", "##....##........", ".##..##.........", "..#####.........", "......###.......", ".......###......", "........###.....", ".........##....."]
		"unverified":
			rows = ["....#####.......", "...##...##......", "........##......", ".......##.......", "......##........", ".....##.........", ".....##.........", "................", ".....##.........", ".....##........."]
		"bottleneck":
			rows = [".......##.......", "......####......", ".....##..##.....", "....##.##.##....", "...##..##..##...", "..##...##...##..", ".##..........##.", "##.....##.....##", "################"]
		"next":
			rows = [".....####.......", "...###..###.....", "..##......##....", "..##......##....", "..##..##..##....", "...##.##.##.....", "....######......", ".....####.......", ".....####.......", "................", ".....####......."]
	var y := int((16-rows.size())/2)
	for row in rows:
		for x in row.length():
			if row[x] == "#": draw_rect(Rect2(x*2,y*2,2,2),color)
		y += 1

func set_warning(value: bool) -> void:
	active_warning = value
	queue_redraw()
