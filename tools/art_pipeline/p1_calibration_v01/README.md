# P1 calibration art technical pipeline v01

This directory contains only the technical pipeline. It does not generate, repair, or substitute bitmap art. Source PNGs are read-only inputs; generated imagegen files and crop choices remain owned by the main art workflow.

## Files

- `build.py` — validates a recipe, cleans source-cell transparency, applies exact palette limiting, performs nearest-neighbor fit scaling, packs atlases, and writes generated artifacts.
- `verify.py` — independently checks artifact and source hashes, bounds, non-empty sprites, exact palettes, binary alpha, integer metadata, animation references, and source-cell clipping.
- `tests/test_pipeline.py` — geometric, in-memory/temp-directory unit tests. No game art and no bitmap-art fallback.

## Recipe

The recipe schema is:

```json
{
  "schema_version": 1,
  "resource_prefix": "res://art/production/p1/calibration_v01",
  "native_view": [640, 360],
  "palette": ["#rrggbb"],
  "sources": {
    "key": {
      "path": "/absolute/path.png",
      "grid": [4, 4],
      "background": {
        "mode": "alpha|edge_colors|color_key|opaque",
        "colors": ["#rrggbb"],
        "tolerance": 0.0
      }
    }
  },
  "atlases": {
    "key": {"cell_size": [64, 64], "columns": 16, "padding": 2}
  },
  "sprites": [
    {
      "id": "sprite_id",
      "source": "key",
      "cell": [0, 0],
      "atlas": "key",
      "anchor": [32, 60],
      "fit": [60, 56],
      "crop": null,
      "facing": null,
      "state": null,
      "palette": null,
      "scale_group": null,
      "keep_rows": null
    }
  ],
  "animations": {"id": {"frames": ["sprite_id"], "fps": 8, "loop": true}}
}
```

Semantic notes:

- `crop` is an absolute source-pixel rectangle `[x,y,w,h]` and overrides `cell`.
- `alpha` applies an alpha threshold of 128. Values below 128 become 0; values at or above become 255 while RGB remains untouched.
- `color_key` removes every pixel near any explicitly supplied flat key, including contained holes. Matching uses raw three-channel RGB Euclidean distance; for a `#00ff00` key, `tolerance: 100` absorbs slight key variation.
- `edge_colors` floods matching colors only from the cell border. It cannot remove matching enclosed foreground details.
- `opaque` performs no background removal.
- Transparent sprites are alpha-bbox trimmed, nearest-neighbor fitted, then palette-limited. RGB pixels are mapped only to the configured exact palette; no dithering or gradients are invented.
- A `scale_group` uses one stable factor for every member: the maximum width/height fit ratio in that group.
- `keep_rows` is a half-open `[first,last)` mask applied to the full native cell after anchor placement. It preserves the complete canvas, so complementary tower layers reconstruct without shifting or losing a row.
- Sprites are horizontally centered and bottom-aligned at the cell-local anchor. Padding defaults to 2 and is INSIDE each cell. Atlas stride is exactly the cell dimensions. Recipe order defines cell order; IDs are not alphabetically repacked.
- Output rects cover whole cells (not cropped content). Use `position - anchor` for drawing; no hidden trim offset.
- Source files are never written.

## Build

```bash
python3 tools/art_pipeline/p1_calibration_v01/build.py \
  --config /path/to/recipe.json \
  --output /path/to/generated-version-dir
```

An empty output directory is accepted. A non-empty output fails by default. `--replace-generated` permits replacement only of exact paths recorded by the previous manifest; any unmanaged entry aborts the build.

Manifest-owned paths must resolve to direct children of the requested output directory. Symlinked output entries are refused, including links to other manifest-owned files; replacement never follows a link into a source or unrelated file.

Outputs are one PNG per atlas plus `atlas.json`, `manifest.json`, and `contact_sheet.png`. The contract is:

```json
{
  "schema_version": 1,
  "native_view": [640, 360],
  "textures": {"key": {"path": "res://...", "width": 128, "height": 128}},
  "sprites": {"id": {"texture": "key", "rect": [0, 0, 64, 64], "anchor": [32, 60]}},
  "animations": {"id": {"frames": ["id"], "fps": 8, "loop": true}}
}
```

Optional `facing` and `state` are copied from the sprite recipe.
For split objects, the half-open `keep_rows` mask is also copied into metadata so consumers do not invent a different split boundary.

`manifest.json` records config/source provenance, hashes, byte sizes, the exact artifact list, and a technical verification field. Technical verification is explicitly not visual approval.

The contact sheet shows each generated atlas against gray, followed by a true grayscale copy, at native 100%. The separate QA tool provides 2x/4x nearest-neighbor sheets and a 25%-of-4x view (= native 100%). It is built only from generated artifacts and is not an input to production.

## Verify

```bash
python3 tools/art_pipeline/p1_calibration_v01/verify.py \
  --output /path/to/generated-version-dir \
  --config /path/to/recipe.json \
  --update-manifest
```

`--config` can be omitted to use the config path recorded in the manifest. Clipping is reported when foreground touches a transparent source cell edge or when a fitted sprite exceeds its configured fit; it is an error, not a warning.

Verification compares each sprite with its recipe-ordered texture/cell, not only an in-bounds grid rectangle. A different valid slot or texture cannot pass as the correct pose. Multi-layer slices of one source cell must have complementary half-open row intervals spanning the full native height; missing masks, gaps and overlaps fail.

Omit `--update-manifest` for read-only rechecks of archived deliveries. Rebuild into a fresh temporary directory when testing reproducibility instead of replacing an accepted artifact set.

## Tests

```bash
python3 -m unittest discover -s tools/art_pipeline/p1_calibration_v01/tests -v
```

## Offline QA (not Godot screenshots)

```bash
python3 tools/art_pipeline/p1_calibration_v01/qa_preview.py \
  --atlas-dir art/production/p1/calibration_v01 \
  --output docs/art-production/p1-calibration-v01/qa
```

Composes only real atlas pixels at their cell-local anchors. Outputs native/2x/25%-of-display/grayscale world views, 4x family sheets, a pose-inspection GIF, and a hash/count report. This does not certify actual GPU output, camera motion, gameplay or animation timing. Ordinary sprites are checked against an 8-color budget, hero/Boss against 12. QA files live outside the runtime output directory.

`tests/test_preview_qa.py` covers parity with Godot tower overlap: full hero cell versus retained upper-layer rows, half-open touching boundaries, and no fade in front. The combined suite currently contains 21 tests (18 pipeline + 3 offline overlap). Existing production PNGs and QA evidence are not rewritten by tests.
