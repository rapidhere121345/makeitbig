# Title world refresh

Generated with the built-in `image_gen` tool on 2026-11-01. No external asset
extraction or reference image inputs. The original output is retained unchanged
in `sources/title_original.png`; `recipe.json` uses the existing calibration
packer for a 640x360 native atlas. The source is 1672x941; the recipe crops the
top-left 1664x936 rectangle before nearest-neighbor fitting and palette mapping.

## Executed prompt

Create a production GAME TITLE BACKGROUND for Make It Big, a dark-fantasy pixel-art ranger adventure. One opaque 16:9 image, preferably 1536x864. NO text, logo, UI, border or watermark. Elevated three-quarter parallel camera, diagonal ground axes, visible tops and sides like a detailed tactical pixel game. Restrained crisp intentional pixel clusters, dark ancient timber and charcoal stone, muted cold brown earth, sparse snow only in crevices, small amber lanterns and very restrained cyan rune accents. NO giant 8-bit blocks, no painterly blur or gradients, no bright cream castle, no floating masonry, no broad magical glows. Composition: LEFT 42 percent very quiet dark slate ground/shadow for engine-rendered title and menu; no objects or highlights there. RIGHT 58 percent a small grounded winter hamlet edge: an old broken dark stone watchtower behind a low timber forge and an iron brazier on a stone plinth, a weathered wooden palisade and pine at right edge. A winding cobbled road leads from lower center past the brazier toward the distant tower. The tower is background context, not an oversized toy dominating the screen. Warmth is scarce, shelter feels earned. Dense controlled pixel detailing on architecture, quiet broad ground shapes, readable silhouettes. Match the project's current angled dark stone-and-timber scenery; avoid the older pale cylindrical tower with canvas cooking shelter. Full continuous landscape, no painted interface. Must remain legible when packed to 640x360 with nearest-neighbor scaling.

## Reproduction and retirement

```bash
python3 tools/art_pipeline/p1_calibration_v01/build.py \
  --config docs/art-production/title-world-20261101/recipe.json \
  --output art/production/p1/title_world_v03 --replace-generated
```

The manifest records source, recipe, and output hashes. The previous title's
original, prompt, and recipe remain in `p1-title-concept-v02` for provenance;
its unused runtime package is retired. Shared `title_life_v01` frames remain
active for this title and other scenes. The new native fire anchor is (554,250)
on the foreground brazier; the smoke anchor is (554,165) at the forge chimney.
The historical tower/cooking-pot anchors must not be reused.
