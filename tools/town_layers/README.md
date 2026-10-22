# Offline Town Layers and Native Spatial Derivation

Runtime inputs are `content/rooms/town/hearthside.tscn`, its neighboring
`hearthside.spatial.json`, and `layers/`. Runtime loads native nodes and baked
PNGs; `TownPresenter` consumes snapshots and shares `WorldPresenter.SortRoot`
with static nodes. This is the legacy sliced-art pipeline, not the new modular
environment-object authoring path.

## Inputs and Conversion

| Input | Dimensions / SHA256 |
| --- | --- |
| `art/production/p1/hamlet_town/town.png` | 1536 × 1024；`fa5d79265d233d9d013c097df44bc810419a31d41e8b756e1b3daf6c42186ee5` |
| Neighboring `layout.json` | world = 1536 × 960; `48995ebb2520227967b63bde71d8c620cb81361bae696417d8d49cee758c165f` |

`bake.py` uses Pillow's `Image.Resampling.NEAREST` to normalize the source once
to 1536 × 960 (X scale 1; Y scale 15/16). UV points map to world coordinates
as `(u × 1536, v × 960)`. Authored `foreground` polygons assign ownership,
ordered by `(feet_uv.y, id)`; later owners take overlaps. Each pixel has one owner.

`ground.png` retains only owner=0 source pixels. Each native PNG retains only
its own mask and crops to that mask's bounding box. Output is RGBA PNG with
`compress_level=9`. Feet retain authored floating-point world coordinates;
Sprite2D uses position=feet, offset=`crop.xy - feet`, centered=false. The
manifest records source/output hashes, dimensions, feet, crop, interaction,
and owned_pixels.

Pixels outside a part are RGBA `(0,0,0,0)`. The generator declares
`unknown_underplate="transparent"`, `supports_cutaway=false`,
`supports_fade=false`: this source has no proven clean plate beneath the
extracted pieces. Shared Y sorting establishes occlusion.

**Known pre-existing drift:** the shipped legacy manifest/runtime expects
`supports_cutaway=true` and `supports_fade=true`, while this generator still
emits false/false. English migration preserves shipped behavior and all image
bytes; it does not silently change either capability contract. A complete
`--check` is therefore not claimed as passed for the final preserved manifest.
Do not advertise complete underpainting or alter flags merely to silence this
check. New modular assets require their own opaque underplate and authored
full/revealed/mask resources.

## Native Gameplay Coordinates

`--author-scene` is a one-time conversion into static geometry, boundaries,
sockets, and routes. Thereafter the `.tscn` is the gameplay source of truth:
derive the spatial manifest directly from scene edits. Re-running
`--author-scene` overwrites the native scene and may lose later authored fixes;
do so only when explicitly requested.

`TownSceneRoot.derive_spatial_manifest()` uses `_pair()` with
`snappedf(component, 1.0 / 64.0)` for static polygon vertices, circle centers,
and authored sockets/routes. Radii use `snappedf(radius, 1.0 / 64.0)`.
Polygons are triangulated in native coordinates, then output vertices are
snapped; degenerate triangles are discarded. Loading never silently repairs
an inconsistent derived manifest.

The native `MovementBoundary` exports `Rect2(14,14,1508,932)` unchanged. The
1/64 rule applies to authored gameplay data, not per-tick actor feet: those
retain registry floating-point movement. `floor()` in
`TownPresenter.camera_world_offset()` affects presentation only.

The 2026-10-14 precision audit compared Godot-loaded native Vector2 (float32)
with manifest coordinates, and metadata float64 radii with manifest radii.
It covered 226 static points and 22 circles; that derivation had 162 shapes.

| Error | Recorded maximum (px) |
| --- | ---: |
| X component | 0.0018310546875 |
| Y component | 0.00048828125 |
| Either component | 0.0018310546875 |
| Point Euclidean distance | 0.0018673166632652283 |
| Circle radius | 0.0003599999999996939 |

The theoretical rounding bounds are `1/128 px` per component/radius and
`sqrt(2)/128 px` for point distance. These are geometry errors, not pixel
recomposition errors.

## Generation and Read-Only Checks

```bash
python3 tools/town_layers/bake.py --check
```

This checks hashes, ownership, pixel recomposition, and temporary-directory
cold generation. Earlier evidence recorded 35 natives / 1,474,560 pixels,
ownership=once, recomposition=exact, cold_bytes=identical. The final English
manifest retains the pre-existing flag discrepancy described above, so this
historical success must not be presented as a current complete `--check` pass.

For explicitly requested layer regeneration:

```bash
python3 tools/town_layers/bake.py
```

Use `bake.py --author-scene` only for an intentional author-source conversion;
then derive spatial data. Run Godot as an ordinary user:

```bash
source scripts/project_env.sh
mib_godot --headless --path . --script res://tools/town_layers/bake_spatial.gd
```

## Historical Negative-Input Evidence

The earlier negative load/source audit lives in ignored
`build/current/town-negative-audit/`. `run.log` records commands and scope;
`check_negative.gd` corrupts inputs only in memory; `check_sources.py` checks
hashes, dimensions, feet/crop, native bindings, transparent holes, and authority
boundaries without regeneration/recomposition. It rejected 25 invalid inputs,
and the corrected load log had no script errors.

That audit did not run visual walkthroughs, a full build, exports, publication,
or golden updates. Refer to later playtest reports for those checks. Record
llvmpipe correctness evidence separately from hardware-specific evidence.
