# Generated world v02

This package replaces the live town and battlefield scenery with newly generated
art. The retained Hearthside concept supplied a palette, materials and camera
reference. Its buildings, trees and ground pixels were not extracted into this
package.

`SOURCES.json` records the original 24 image-generation outputs: two ground plates, 17 complete
scenery objects and five resident sheets containing four work poses each. Every
record links the exact prompt and pins the source and prompt SHA256 hashes, plus
the reference hash. Original generator output paths are provenance records.
Repeating a generation prompt is not claimed to reproduce identical pixels.

The front-facing set (two grounds and 17 scenery objects) was retired on 2026-10-26.
Its raw PNGs and the rejected `polish-20261024/` drafts were deleted. `SOURCES.json`
keeps those entries under `retired` with the pinned hashes and prompts under
`prompts/`; only the five `npc_*_raw.png` resident sheets remain in `sources/`.

The active scenery inputs are the 17 angled dark-fantasy objects and two grounds in
`perspective-20261024/sources/`, with exact prompts and hashes in
`perspective-20261024/PROVENANCE.json`. The original five resident sheets in
`sources/` remain active (resident animations are further described in
`../actor-redraw-20261024/`).

The active art uses an elevated three-quarter view with visible top and side
planes. This corrects asset perspective; the runtime camera transform is unchanged.
The Last Spell is a qualitative dark-fantasy/isometric reference, not a claim of
matching its camera pitch or extracting its art.

## Asset contract

Each scenery object has an opaque PNG and a transparent PNG on the same canvas
with the same anchor and RGB pixels. Occupied alpha is respectively 255 and 128;
outside alpha is zero. The transparent state is derived from the new generated
object, rather than generated independently, so transitioning cannot misalign
silhouettes. There are no roof, trunk, foundation or common-part slices.

The source alpha threshold is 240. The compiler retains all occupied components,
reports discarded faint fringe, and applies one rational nearest-neighbor scale
to both axes. The full occupied bounds determine reveal detection (grown by eight
native pixels by default; proxy and woodpile use 11 and the low pier uses 12), not movement collision. In this 2.5D view, roofs, crowns and tall
walls project above the ground; their image bounds must not become floor walls.

`ground_footprints.json` authors a ground-contact rectangle for every scenery
family in canvas-local pixels, with a five-pixel safety margin. Town uses native
pixels; combat converts through the existing 0.72 scale and snaps absolute edges
to the manifest's 1/16-pixel grid. The native scene polygons remain gameplay
authority. Actors already use their feet and physical body radii, independently
of animation height. Depth sorting and the complete opaque/transparent pair
remain presentation responsibilities; no image slicing is needed for traversal.

Town and arena grounds are uniformly scaled to widths 1536 and 1024, then
center-cropped to 1536×960 and 1024×640 respectively. Both outputs are fully
opaque. Ground crops operate only on new generated terrain, not the reference.

## Reproduction

From the repository root in the approved portable environment:

```bash
python3 tools/art_pipeline/generated_world_v02/pack.py --available
python3 tools/art_pipeline/generated_world_v02/pack.py --verify
python3 -m unittest discover -s tools/art_pipeline/generated_world_v02/tests
python3 tools/art_pipeline/generated_world_v02/npc_pack.py
python3 tools/world_manifest/author_ground_footprints.py --check
```

After deliberately editing the footprint recipe, run the last command with
`--write`, then bake the town and three combat spatial manifests with the existing
Godot manifest tools and refresh combat catalog digests. A render-only change
must not silently enlarge a collider. Behind-object traversal and solid base
contact are both acceptance requirements, along with the existing route tests.

Environment canvas/anchor/source pins live in
`tools/art_pipeline/generated_world_v02/packing_config.json`. The runtime manifest
is `art/production/p1/generated_world_v02/assets.json`. The packer verifies exact
output bytes and pair geometry. The resident compiler verifies source pins,
four distinct frames per resident, shared per-resident scale and aligned feet;
its output hashes and source-cell mappings are in `residents/IMPORT.json`.

Resident IDs, clip names, work cadence and cell layout are retained as metadata
from the previous animation package. All 20 resident frame images are new.
The Ranger, combat enemies and articulated boss animation artwork remains from
the existing package; this work does not claim to regenerate those animation
sets. Previous art and acceptance evidence are retained for provenance.

Rendered acceptance and the fresh regression/export gate are recorded separately
under `docs/playtest/`; successful packing alone is not visual acceptance.

## Godot import identity

Retain the generated PNG `.import` sidecars. They pin lossless compression, no
mipmaps and `process/fix_alpha_border=false`. Alpha-border repair would change
invisible RGB pixels and therefore invalidate the strict native scene fingerprint
after import/export. For additional texture paths, set the same import options
before baking spatial manifests. The full gate runs
`tests/test_generated_texture_import.gd` immediately after import and requires
all 37 imported textures (including the resident sheet) to equal raw RGBA8 bytes.
The image compilers preserve these sidecars when rebuilding PNGs.
