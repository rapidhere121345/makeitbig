# World expansion sources

Original terrain and object images were generated with the built-in image_gen
tool. [GENERATION.json](GENERATION.json) records every retained source hash,
its exact prompt, and whether it is selected or a superseded draft. The accepted
world calibration is a style reference, not a source of extracted pixels.

The selected set contains the winding Hearthside ground, three distinct combat
floors, two bridge orientations, an open gateway, two residential house
orientations, and a wall section. The straight river and misaligned combat-floor
drafts are retained for provenance and are not runtime inputs.

Run from the project environment:

```bash
python3 tools/art_pipeline/world_expansion_v01/pack.py
python3 tools/art_pipeline/world_expansion_v01/pack.py --verify
python3 -B -m unittest discover -s tools/art_pipeline/world_expansion_v01/tests
```

The compiler uses pinned source hashes, one rational nearest-neighbor scale per
object, and deterministic PNG output. Town ground is cropped from the top to
1536×960 without resizing; combat floors are uniformly scaled to width 1024 and
center-cropped to height 640. Exact transforms are in the runtime `assets.json`.
Sortable scenery has aligned opaque and alpha-128 variants; bridge decks are
opaque ground art. Import sidecars preserve their Godot UID and disable alpha
border RGB rewriting.

Artwork does not define collision implicitly. The town layout recipe records
ground-contact footprints, shoreline geometry and bridge corridors. Combat
boundaries remain the authored gameplay geometry; the ritual well and boundary
trim are drawn from that geometry. Runtime validation and screenshots are
recorded separately in `docs/playtest/` after execution.

## Authoring the town

`town_layout.json` records the two measured bridge decks, ground-contact
footprints, perimeter placements, disclosed moves, routes and expedition socket.
`tools/world_manifest/author_town_expansion.py` traces the pinned ground's river
and mountain edges, cuts the measured bridge decks out of the water polygons,
and writes only expansion-owned nodes and the explicitly listed old routes or
placements. It verifies that facilities and residents remain reachable and that
closing both decks separates the two banks. These are offline geometry checks;
the mounted runtime tests separately exercise continuous movement and contact.

```bash
python3 tools/world_manifest/author_town_expansion.py --check
python3 tools/world_manifest/author_town_expansion.py --write --report
"$GODOT_BIN" --headless --path . --script res://tools/world_manifest/bake_spatial.gd
```

After changing a placement or shoreline, rebake the scene derivative and rerun
the town layout, runtime, gateway, reveal and geometry-rebuild tests. Bridge decks
stay in `Ground` with no reveal; houses, gate towers, walls and plants sort from
their feet and retain the aligned whole-object reveal pair. The expedition gate
uses a scene-authored exit socket to open the existing Contract screen.

Five old low decorations were moved onto dry ground in
`content/presentation/world_dressing.json`: fern 5 to `(835,741)`, fern 8 to
`(507,650)`, mushrooms 5 to `(1365,809)`, mushrooms 6 to `(537,650)`, and relic 4
to `(161,679)`. Their original positions intersected the winding water. Their
drawn pixels now clear the traced water; these ground details add no collision.
