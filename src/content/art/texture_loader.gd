extends RefCounted

## Shared texture loading for art readers. The loaders differ on purpose in
## precedence (raw PNG first versus imported resource first) and in how they
## treat a size mismatch, so each variant is a separately named function and
## no caller is silently moved to another policy. Loaders never log or cache;
## callers own their caches and their pending-reason wording.

const ERROR_NONE := ""
const ERROR_MISSING := "missing"
const ERROR_UNREADABLE := "unreadable"
const ERROR_INVALID_PNG := "invalid_png"


## Raw bytes of a PNG decoded into an Image, or null when the file cannot be
## opened or is not a PNG. No size or emptiness check is applied.
static func decode_png_path(path: String) -> Image:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	return image


## Raw PNG first (read through the globalized path so a stale import cache
## cannot shadow approved art), imported resource second for exported builds.
## Returns null when neither yields a Texture2D.
static func load_png_first(path: String) -> Texture2D:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute):
		var file := FileAccess.open(absolute, FileAccess.READ)
		if file != null and file.get_length() > 0:
			var image := Image.new()
			if image.load_png_from_buffer(file.get_buffer(file.get_length())) == OK:
				return ImageTexture.create_from_image(image)
	if ResourceLoader.exists(path):
		var resource: Variant = load(path)
		if resource is Texture2D:
			return resource
	return null


## Imported resource first, raw PNG at the same path second, with no size
## check. Returns {"texture": Texture2D or null, "error": ERROR_*}; callers map
## the error code to their own wording.
static func load_imported_first(path: String) -> Dictionary:
	if ResourceLoader.exists(path):
		var resource: Variant = ResourceLoader.load(path)
		if resource is Texture2D:
			return {"texture": resource, "error": ERROR_NONE}
	if not FileAccess.file_exists(path):
		return {"texture": null, "error": ERROR_MISSING}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() == 0:
		return {"texture": null, "error": ERROR_UNREADABLE}
	var image := Image.new()
	if image.load_png_from_buffer(file.get_buffer(file.get_length())) != OK:
		return {"texture": null, "error": ERROR_INVALID_PNG}
	return {"texture": ImageTexture.create_from_image(image), "error": ERROR_NONE}


## Imported resource first, raw PNG second, accepting only declared_size.
## When fall_back_on_import_mismatch is true an imported texture of the wrong
## size is skipped and the raw PNG is tried; when false an imported texture
## decides the result alone (right size returns it, wrong size returns null).
static func load_sized(path: String, declared_size: Vector2i, fall_back_on_import_mismatch: bool) -> Texture2D:
	if path.is_empty() or declared_size.x <= 0 or declared_size.y <= 0:
		return null
	if ResourceLoader.exists(path):
		var imported := ResourceLoader.load(path) as Texture2D
		if imported != null:
			if Vector2i(imported.get_size()) == declared_size:
				return imported
			if not fall_back_on_import_mismatch:
				return null
	var decoded := decode_png_path(path)
	if decoded == null or Vector2i(decoded.get_width(), decoded.get_height()) != declared_size:
		return null
	return ImageTexture.create_from_image(decoded)


## Imported resource first, then any image Godot can read at the path (a fresh
## author preview may precede editor import). When fall_back_when_import_null
## is false a path the ResourceLoader knows is authoritative: a failed load
## returns null without trying the file.
static func load_imported_or_file(path: String, fall_back_when_import_null: bool = true) -> Texture2D:
	if ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		if texture != null or not fall_back_when_import_null:
			return texture
	if FileAccess.file_exists(path):
		var image := Image.new()
		if image.load(path) == OK:
			return ImageTexture.create_from_image(image)
	return null
