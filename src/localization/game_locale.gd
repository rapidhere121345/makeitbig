class_name GameLocale
extends RefCounted
## Installs the catalog once; game/profile authority and authored content stay locale
## independent. The application host persists the player's preference in display.cfg.

const TranslationScript = preload("res://src/localization/game_translation.gd")
const SUPPORTED: Array[String] = ["en", "zh_CN"]
static var _owners := 0
static var _translation: Translation = null


static func install() -> void:
	if _translation != null:
		return
	_translation = TranslationScript.new()
	TranslationServer.add_translation(_translation)


static func normalize(value: Variant) -> String:
	if not value is String:
		return "en"
	return "zh_CN" if String(value).replace("-", "_") in ["zh", "zh_CN", "zh_Hans", "zh_Hans_CN"] else "en"


static func select(value: Variant) -> String:
	install()
	var selected := normalize(value)
	TranslationServer.set_locale(selected)
	return selected


static func current() -> String:
	return normalize(TranslationServer.get_locale())


static func text(source: String) -> String:
	install()
	return String(TranslationServer.translate(source))


static func language_name(code: String) -> String:
	install()
	# Autonyms stay recognizable when the rest of the menu changes language.
	return String((_translation as TranslationScript).source_messages.get("Simplified Chinese", "Chinese")) if code == "zh_CN" else "English"


static func acquire() -> void:
	_owners += 1
	install()


static func release() -> void:
	_owners = maxi(0, _owners - 1)
	if _owners == 0:
		shutdown()


static func shutdown() -> void:
	if _translation != null:
		TranslationServer.remove_translation(_translation)
		_translation = null
