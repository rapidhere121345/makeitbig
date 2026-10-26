# generated_world_v02 — whole-object packer

Deterministic production packing of the fresh imagegen sources under
`docs/art-production/generated-world-v02/perspective-20261024/sources/` into runtime art at
`art/production/p1/generated_world_v02/`. This is technical sprite packing
only: no procedural redrawing, no cutting of old reference art, and no
roof/base splits — each object is one whole entity on one canvas.

Run from the repository root in the approved portable environment:

```bash
source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
source scripts/project_env.sh
python3 -I -m unittest discover -s tools/art_pipeline/generated_world_v02/tests
python3 -I tools/art_pipeline/generated_world_v02/pack.py --available
python3 -I tools/art_pipeline/generated_world_v02/pack.py --verify
python3 -I tools/art_pipeline/generated_world_v02/pack.py --list
```

`--available` (the default) packs every configured asset whose raw source
exists. `--asset NAME` (repeatable; `ground` aliases the ground plate) packs
only the named asset and carries over still-valid previous entries.
`--verify` recomputes every packed entry and asserts byte-identical outputs
and manifest fields. `packing_config.json` is the single source of truth for
canvas, anchor, per-asset `alpha_threshold`, optional pinned
`source_sha256`, and the ground `src_rect` crop.

## Output pair contract (per object `<id>`)

| File | Alpha | RGB |
| --- | --- | --- |
| `<id>_opaque.png` | 255 occupied, 0 outside | source RGB on occupied, black outside |
| `<id>_transparent.png` | 128 occupied, 0 outside | identical to the opaque canvas |

Both share the configured canvas, anchor, and occupied geometry exactly; the
packer asserts the pair contract at build time. No shadow is emitted.

## Occupancy and transform

Raw generated alpha has the object at 250..254 and a low-alpha background
wash below 240. Occupancy is `alpha >= alpha_threshold` (default 240,
per-asset override in the config). Only transparent padding is trimmed; all
occupied components of the object map together. Discarded fringe pixels
(`0 < alpha < threshold`) are counted per run with their bbox and alpha
histogram in `build/current/generated-world-v02/packing/packing_report.json`.

One uniform rational scale `s = min(max_w/src_w, max_h/src_h)` (destination
px per source px) is shared by both axes, where `max_w = canvas_w - 16` and
`max_h = anchor_y - 8`. Destination size is `ceil(src * s)` so the whole
occupied extent is covered; sampling is exact integer nearest-neighbour,
`src_i = (2*i + 1) * step_num // (2 * step_den)` clamped to the source
extent (`step = 1/s`), never a resampling library call. The window is
centred on `anchor_x` (half-pixel left bias on odd widths) and its bottom
bound (exclusive) sits at `anchor_y`. The full configured canvas is always
preserved; occupied content stays inside the 8 px side/top margins, and an
empty object fails closed rather than producing an empty canvas.

The ground plates are separate paths per `grounds.<id>`: mode `crop` uses a
fixed `src_rect` with no resize; mode `fit_width_crop_height` applies
one uniform rational scale `s = fit_width / raw_w` to both axes, then cuts a
centre band of `canvas[1]` rows out of the scaled plate. The active arena
ground uses this fit mode; exact scale and crop are recorded in the manifest.
Every ground output asserts full opacity.

## assets.json

Top level: `schema_version`, `package`, `generator`, `config_sha256`,
`semantics`, `ground`, `grounds`, `sections`, `assets`, `pending`, `stale`,
`complete`.

Each `assets.<id>` entry: `status` (`packed` / `pending` / `stale`),
`kind` (`object`), `section`, `canvas`, `anchor`, `occupied_rect`,
`occlusion_rect` (occupied AABB grown by the configured padding (default 8 px) on every side, never clipped;
`occlusion_overflow: true` flags the rect if it ever leaves the canvas),
`opaque_path`, `transparent_path`, `raw_sha256`, `opaque_sha256`,
`transparent_sha256`, `transform` (`src_rect`, `dst_rect`, `scale`, `step`,
`alpha_threshold`, `source`). Pending entries carry `pending_reason`
(`raw_missing` or `not_requested`) and null paths; an asset whose raw is
absent is never claimed complete. A previously packed entry that fails its
provenance check (changed raw or outputs) is reported `stale` with
`stale_reason` while its paths remain for inspection.

`grounds.<id>` entries use the same field shape with `kind: ground`,
`transparent_path: null`, and `occlusion_rect: null`. `ground` mirrors
`grounds[primary_ground]` (arena) so the original single-ground contract is
unchanged. `sections.<name>` groups asset/ground ids per configured
`section` (`town`, `arena`) with an independent `complete` flag plus its own
`pending`/`stale` lists, so a consumer is never blocked by an unfinished
other section.

Rects are `[x, y, width, height]` canvas pixels; paths are `res://`-relative.
The manifest contains no timestamps: identical raws and config reproduce a
byte-identical `assets.json`.

## Godot import identity

Retain the generated PNG `.import` sidecars. They pin lossless compression, no
mipmaps and `process/fix_alpha_border=false`. Alpha-border repair would change
invisible RGB pixels and therefore invalidate the strict native scene fingerprint
after import/export. For additional texture paths, set the same import options
before baking spatial manifests. The full gate runs
`tests/test_generated_texture_import.gd` immediately after import and requires
all 75 imported textures (this package plus the actor, polish, expansion and town-order packs) to equal raw RGBA8 bytes.
The image compilers preserve these sidecars when rebuilding PNGs.

The proxy and woodpile use 11 px detection padding so its full visual detection still
contains the preserved, slightly larger ground footprint. The shorter low pier uses 12 px so side proximity can reveal it before contact.
Other families retain 8 px. Per-asset detection padding may enlarge, never shrink, the default.
