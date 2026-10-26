extends SceneTree
## Palette consolidation gate (src/presentation/palette.gd). Every module that
## aliases a shared colour must still resolve to its previously shipped value.
##   godot --headless --path . --script res://tests/unit/test_palette.gd

const SharedPalette := preload("res://src/presentation/palette.gd")
const CombatPalette := preload("res://src/presentation/combat_palette.gd")
const MotionOverlay := preload("res://src/presentation/ranger_motion_overlay.gd")
const TalentBoard := preload("res://src/presentation/ranger_talent_board.gd")

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	# Shell skin.
	_expect_hex(ShellTheme.INK, "111820", "ShellTheme.INK")
	_expect_hex(ShellTheme.DEEP_BLUE, "1d2731", "ShellTheme.DEEP_BLUE")
	_expect_hex(ShellTheme.GROUND, "2d3943", "ShellTheme.GROUND")
	_expect_hex(ShellTheme.BONE, "e9ddc3", "ShellTheme.BONE")
	_expect_hex(ShellTheme.COPPER_DULL, "ad7950", "ShellTheme.COPPER_DULL")
	# Combat skin keeps its own values where it disagrees with the shell.
	_expect_hex(CombatPalette.INK, "090c10", "CombatPalette.INK")
	_expect_hex(CombatPalette.SLATE_0, "111820", "CombatPalette.SLATE_0")
	_expect_hex(CombatPalette.SLATE_1, "1d2730", "CombatPalette.SLATE_1")
	_expect_hex(CombatPalette.SLATE_2, "2d3943", "CombatPalette.SLATE_2")
	_expect_hex(CombatPalette.BONE, "e9ddc3", "CombatPalette.BONE")
	_expect_hex(CombatPalette.COPPER_DULL, "896043", "CombatPalette.COPPER_DULL")
	_expect_hex(CombatPalette.COLD, "61a6a5", "CombatPalette.COLD")
	# Widgets.
	_expect_hex(TalentBoard.COPPER, "ad7950", "RangerTalentBoard.COPPER")
	_expect_hex(TalentBoard.BONE, "e9ddc3", "RangerTalentBoard.BONE")
	_expect_hex(TalentBoard.INK, "111820", "RangerTalentBoard.INK")
	_expect_hex(MotionOverlay.INK, "111820", "RangerMotionOverlay.INK")
	_expect_hex(MotionOverlay.BONE, "e9ddc3", "RangerMotionOverlay.BONE")
	_expect_hex(MotionOverlay.COLD, "61a6a5", "RangerMotionOverlay.COLD")
	_expect_hex(SharedPalette.BONE_HOVER, "fff1ce", "SharedPalette.BONE_HOVER")
	# Disagreeing values stay distinct instead of being merged.
	_expect(SharedPalette.COMBAT_INK != SharedPalette.SLATE_INK, "combat and shell ink remain distinct")
	_expect(SharedPalette.COMBAT_COPPER_DULL != SharedPalette.COPPER_EDGE, "combat and shell dull copper remain distinct")
	for message in failures:
		printerr(message)
	print("PALETTE ", "pass" if failures.is_empty() else "fail", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func _expect_hex(actual: Color, hex: String, label: String) -> void:
	_expect(actual == Color(hex), "%s must stay #%s (got #%s)" % [label, hex, actual.to_html(false)])


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append("FAIL: " + message)
