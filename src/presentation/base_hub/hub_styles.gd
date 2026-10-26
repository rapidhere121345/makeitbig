extends RefCounted
## Stylebox factories shared by the hub's header, badge, buttons and residents,
## extracted from BaseHubScreen. Pure constructors; no state.

const ShellThemeScript = preload("res://src/presentation/shell_theme.gd")
const UiKit := preload("res://src/presentation/ui_kit.gd")


static func hotspot_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	return UiKit.flat_style(fill, border, width, 0, Vector4(10.0, 6.0, 10.0, 6.0))


static func prompt_style() -> StyleBox:
	## The proximity badge keeps the amber edge of the old prompt but only the
	## width its own copy needs.
	var style := ShellThemeScript.panel_style()
	style.content_margin_left = 10.0
	style.content_margin_top = 2.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 2.0
	return style


static func toggle_style(kind: String) -> StyleBoxTexture:
	var style := ShellThemeScript.panel_style(kind)
	style.content_margin_left = 8.0
	style.content_margin_top = 1.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 1.0
	return style
