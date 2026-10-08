# P1 ranger actions technical pipeline v01

Mechanical packing and checking tool for the ranger action atlas: raw RGBA
sources in, one 48x48-cell atlas with the feet pinned to anchor (24, 44) out.

This directory contains only technical pipeline code. It never generates,
repairs, or substitutes bitmap art, it never removes an undeclared background,
and it never writes to a source image. Source PNGs are read-only inputs; crop,
anchor and scale choices stay owned by the main art workflow. The same packer is
shared by later batches (for example an enemy action batch) through the optional
`texture_key` recipe field; a recipe without it is the accepted ranger contract
and reproduces `ranger.png` byte for byte.

## Files

- `build.py` — validates a recipe, cuts explicit crops, applies the declared
  background rule, one unified nearest scale per source, the exact palette, and
  fixed-anchor placement; writes `<texture_key>.png` (`ranger.png` by default),
  `atlas.json`, `manifest.json`.
- `verify.py` — read-only recheck of the artifacts, provenance hashes, geometry,
  alpha, palette, animation set and fake-animation duplicates.
- `review.py` — mechanical previews only (nearest 1x/2x/25%, grayscale, per
  animation GIF, plus a read-only palette/color listing).
- `recipe.example.json`, `recipe.schema.json` — schema reference. The example is
  not runnable until the raw imagegen sheet path is filled in.
- `tests/test_pipeline.py` — synthetic geometry fixtures in temporary
  directories. No game art is read and no bitmap art is produced.

## Recipe

```json
{
  "schema_version": 1,
  "resource_prefix": "res://art/production/p1/ranger_actions_v01",
  "native_view": [640, 360],
  "palette": ["#rrggbb"],
  "texture_key": "ranger",
  "sources": {"id": "/absolute/path.png"},
  "background": {"id": {"mode": "alpha|color_key", "colors": ["#00ff00"], "tolerance": 60, "scope": "all|border"}},
  "cell_size": [48, 48],
  "anchor": [24, 44],
  "columns": 4,
  "frames": [
    {
      "id": "ranger.east.attack.0",
      "source": "id",
      "crop": [0, 0, 48, 48],
      "source_anchor": [24, 44],
      "scale": 1,
      "action": "attack",
      "facing": "east"
    }
  ],
  "animations": {"ranger.<facing>.<action>": {"frames": ["frame_id"], "fps": 8, "loop": false}},
  "disclosure": {"source_id": "why a pre-existing file is reused"}
}
```

## Semantics

- `crop` is an absolute source-pixel rectangle `[x,y,w,h]`; `source_anchor` is the
  cut-off point `[x,y]` **inside that crop** that must land on the cell anchor
  `(24, 44)`. Paste origin is `anchor - round(source_anchor * scale)`, so the
  foot point is identical in every cell.
- Frames are never fitted per frame. A bow or an arm reaching out of the body
  changes the drawn silhouette only; it cannot move the feet or resize the pose.
  If the scaled crop cannot be placed inside the 48x48 cell, the build fails.
- `scale` is a float and must be identical for every frame cut from the same
  source, so one sheet cannot produce poses of different apparent size. Other
  sources may use other scales; the chosen values are listed in
  `manifest.json.scale_by_source` so a cross-source size mismatch is visible.
- `texture_key` is optional and defaults to `ranger`, which keeps every existing
  recipe and the accepted `ranger.png` contract unchanged. It must be a plain
  identifier (`[A-Za-z][A-Za-z0-9_-]{0,63}`): the texture file is
  `<texture_key>.png` inside the output directory, so path separators, dots and
  dot segments are rejected before anything is written. A recipe may therefore
  pack `"texture_key": "enemies"` and produce `enemies.png` with `atlas.json`
  and `manifest.json` naming that texture; verify and review follow the recipe
  and the atlas instead of assuming `ranger`. Cell size `48x48`, anchor
  `(24, 44)` and the `<character>.<facing>.<action>` animation naming apply to
  every texture key, so an enemy batch may use `melee.south.attack`,
  `charger.east.charge` or `ranged.north.shoot` without a pipeline change.
- Palette limiting is exact: visible pixels are snapped to the nearest color of
  `palette` (4-channel distance, palette order breaks ties). To reuse accepted
  art **verbatim**, the palette must contain its exact colors — otherwise
  `manifest.json.frames[].palette_remapped_pixels` is non-zero and the build
  warns. The included example palette is exactly the 12 colors of the accepted
  `scene_rework_v01/ranger.png`.
- Alpha is preserved by default (normalized to binary at 128). A source with no
  transparent pixel at all fails the build: an accidental checkerboard or a
  failed imagegen alpha is never removed or disguised. The permitted remedy is an
  explicit key: `"background": {"<id>": {"mode": "color_key", "colors": ["#00ff00"],
  "tolerance": 60}}`. `tolerance` is mandatory for `color_key` (RGB Euclidean
  distance to the key) so the choice is explicit.
- `scope` of a color key is `all` (every matching pixel, including enclosed
  holes) or `border` (only matching pixels 4-connected to the crop border, so
  enclosed interior art can never be deleted). Both record
  `background_removed_pixels` and `background_removed_enclosed_pixels` per frame,
  and the source report records `matched_pixels` / `matched_ratio`, so a wrong
  key or a too loose tolerance is visible instead of silent.
- Sources outside the recipe directory reuse pre-existing files and must be
  disclosed under `disclosure`; the manifest and `atlas.json` carry the text.
- Animations must be named `<character>.<facing>.<action>` and a frame may only
  join an animation with the same action and facing. Two frames of one animation
  with identical pixels are rejected as a fake animation.

## Commands

```bash
python3 tools/art_pipeline/p1_ranger_actions_v01/build.py \
  --config /path/to/recipe.json \
  --output /data/repo/makeitbig/art/production/p1/ranger_actions_v01

python3 tools/art_pipeline/p1_ranger_actions_v01/verify.py \
  --output /data/repo/makeitbig/art/production/p1/ranger_actions_v01 [--update-manifest]

python3 tools/art_pipeline/p1_ranger_actions_v01/review.py \
  --output /data/repo/makeitbig/art/production/p1/ranger_actions_v01 \
  [--out /path/to/preview-dir] [--scale 1|2|0.25] [--gray] [--gif] [--anim ranger.east.attack] [--colors]

python3 -m unittest discover -s tools/art_pipeline/p1_ranger_actions_v01/tests -v
```

An empty output directory is accepted. A non-empty output directory is refused;
`--replace-generated` replaces only the exact paths recorded by the previous
manifest, refuses unmanaged entries and refuses symlinks. Previews are written
to a separate directory (a temporary one by default) and never into the version
directory. `--colors` prints the distinct visible colors of each packed frame
(read-only) — useful for building a verbatim-reuse palette.

## Output contract

`atlas.json`:

```json
{
  "schema_version": 1,
  "native_view": [640, 360],
  "cell_size": [48, 48],
  "textures": {"ranger": {"path": "res://art/production/p1/ranger_actions_v01/ranger.png", "width": 192, "height": 96}},
  "sprites": {"ranger.east.attack.0": {"texture": "ranger", "rect": [0, 0, 48, 48], "anchor": [24, 44]}},
  "animations": {"ranger.east.attack": {"frames": ["ranger.east.attack.0"], "fps": 8, "loop": false}},
  "action_semantics": {"ranger.east.attack": {"action": "attack", "facing": "east", "fps": 8, "loop": false, "frame_count": 1, "distinct_pixel_frames": 1, "cell_size": [48, 48], "anchor": [24, 44]}}
}
```

Rects cover whole cells in recipe order (row-major, `columns` per row); draw at
`position - anchor`. Beside the atlas contract, `manifest.json` records the
recipe path and hash, every source path/sha/size/background rule, the unified
scale per source, per-frame pixel counts, bbox `[x,y,w,h]`, paste origin, border
touches, removed background pixels, palette remaps, per-animation real distinct
pixel frame counts, cross-animation duplicate pixel groups, orphan frames,
disclosure text and artifact hashes.

## Verify rejections

Zero visible pixels, crop outside the source, scaled crop that cannot fit its
cell, alpha that is not binary, colors outside the palette, pixels a frame does
not place in its own cell (neighbor-cell leakage or tampering), missing or
renamed animations, frames that pretend a repeated image is animation, a changed
source file, a changed recipe, and artifact hash mismatches. Border touches,
orphan frames and cross-animation duplicate pixels are reported as information,
not failures. Technical verification is not visual approval.

## Previews

`review.py` sheets are mechanical nearest-neighbor contact sheets over a
checkerboard with the anchor marked. They are previews for crop/anchor checking
only; they are not in-game renders and are never inputs to production.
