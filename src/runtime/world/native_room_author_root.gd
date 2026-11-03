class_name NativeRoomAuthorRoot
extends Node2D

## Shared base for native room authoring nodes (RoomAssetRoot,
## NativeStaticRoomRoot, TownSceneRoot). RoomManifestValidator accepts a scene
## only when its root or its "RoomAsset" child extends this class.


## Validates the authored scene against the expected manifest facts.
## Subclasses override this; the base reports a missing contract.
func validate_contract(_expected: Dictionary = {}) -> Dictionary:
	return {"ok": false, "errors": ["native_scene_contract_missing"]}
