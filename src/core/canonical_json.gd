extends RefCounted
## Canonical JSON text: sorted object keys, integral floats written as
## integers, exact-range integers only, and a fixed string escaping. Save
## envelopes and build fingerprints hash this text, so its output must never
## change for existing data.

const MAX_SAFE_JSON_INTEGER: int = 9007199254740991


## The canonical text of a value, or "" when the value cannot be encoded.
static func text(value: Variant) -> String:
	var encoded: Dictionary = encode(value)
	return str(encoded.text) if bool(encoded.ok) else ""


## {"ok": true, "text": ...} or {"ok": false, "error": ...}.
static func encode(value: Variant) -> Dictionary:
	match typeof(value):
		TYPE_NIL:
			return {"ok": true, "text": "null"}
		TYPE_BOOL:
			return {"ok": true, "text": "true" if bool(value) else "false"}
		TYPE_INT:
			if absi(int(value)) > MAX_SAFE_JSON_INTEGER:
				return {"ok": false, "error": "integer exceeds JSON's exact range"}
			return {"ok": true, "text": str(int(value))}
		TYPE_FLOAT:
			var number: float = float(value)
			if is_nan(number) or is_inf(number):
				return {"ok": false, "error": "non-finite numbers are not valid save data"}
			if number == 0.0:
				return {"ok": true, "text": "0"}
			if absf(number) <= float(MAX_SAFE_JSON_INTEGER) and floor(number) == number:
				return {"ok": true, "text": str(int(number))}
			return {"ok": true, "text": JSON.stringify(number)}
		TYPE_STRING, TYPE_STRING_NAME:
			return {"ok": true, "text": encode_string(str(value))}
		TYPE_ARRAY:
			var parts: Array[String] = []
			for item in value:
				var item_encoding: Dictionary = encode(item)
				if not bool(item_encoding.ok):
					return item_encoding
				parts.append(str(item_encoding.text))
			return {"ok": true, "text": "[" + ",".join(parts) + "]"}
		TYPE_DICTIONARY:
			var keys: Array[String] = []
			for key in value.keys():
				if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
					return {"ok": false, "error": "save dictionaries require string keys"}
				keys.append(str(key))
			keys.sort()
			var members: Array[String] = []
			for key in keys:
				var member_encoding: Dictionary = encode(value[key])
				if not bool(member_encoding.ok):
					return member_encoding
				members.append(encode_string(key) + ":" + str(member_encoding.text))
			return {"ok": true, "text": "{" + ",".join(members) + "}"}
		_:
			return {"ok": false, "error": "unsupported save-data type: %s" % type_string(typeof(value))}


static func encode_string(value: String) -> String:
	var result: String = "\""
	for index in value.length():
		var codepoint: int = value.unicode_at(index)
		match codepoint:
			0x08:
				result += "\\b"
			0x09:
				result += "\\t"
			0x0a:
				result += "\\n"
			0x0c:
				result += "\\f"
			0x0d:
				result += "\\r"
			0x22:
				result += "\\\""
			0x5c:
				result += "\\\\"
			_:
				result += "\\u%04x" % codepoint if codepoint < 0x20 else value.substr(index, 1)
	return result + "\""
