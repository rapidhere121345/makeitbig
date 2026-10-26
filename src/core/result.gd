extends RefCounted

## The failure result shape shared by command and port layers: a fresh
## dictionary {"ok": false, "error": code}. Richer failure shapes (extra
## fields, read-only results, error lists) stay with the module that owns them.


static func failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
