# Sample Ground Guide Specification

Date: 2026-10-23. Status: **deterministic guide ready for root image
generation.** This is the ground plate for the 960x640 preview sample only —
it is NOT the whole-town ground, no final terrain or town layout is authored
here, and nothing is integrated into the shipped town. Generation happens in
the root session; this lane prepares guide, prompt, and packing QC.

## Layout contract (code-grounded)

Geometry is the preview's own ground authoring
(`tools/modular_town_preview.gd` `_author_scene`), minus every debug mark:

| Element | Contract |
| --- | --- |
| Canvas | 960x640, one canvas pixel = one design pixel, fully opaque |
| Base | complete cold snowy ground across the entire canvas, no gaps |
| Horizontal band | `Rect(12,352,936,88)` — x 12..948, y 352..440, worn grey stone |
| Vertical path | `Rect(568,12,64,616)` — x 568..632, y 12..628, same material |
| Junction | both bands solid stone through the crossing, merged smoothly |
| Edges | up to ~3 px dithered snow-into-stone skirt; rects stay the exact layout |
| Excluded | preview debug grid, envelope/footprint outlines, tree discs, fence boxes |
| Forbidden | buildings, trees, fences, logs, lamps, characters, baked object shadows, water, cliff holes, borders/vignette |

The ground must read complete with every building upper part removed
(all-uppers-off view never exposes a hole or missing underpainting).

## Artifacts (checkpoint 1, ignored `build/`)

Generator: `tools/art_pipeline/p1_town_modular_v01/make_ground_guides.py`
(deterministic — fixed integer coordinate hashes, no RNG; byte-identical
reruns verified). Run in the approved portable environment.

| Artifact | Size | SHA256 |
| --- | --- | --- |
| `build/current/p1-town-modular-v01/ground-checkpoint-1/ground_guide_960x640.png` | 960x640 | `b29c0ed3bb0d0505958058f6f34bcca91f9c4e8128cc7d73a1fe07ad2e1071fc` |
| `build/current/p1-town-modular-v01/ground-checkpoint-1/ground_guide_review_2x.png` | 1920x1280 | `edac11e76044aea085b94765dad3ba6356ccb0a725cb900dc2f7ca89727ae2a1` |

Visual review (this checkpoint): complete cold snowfield, both bands at the
exact rects, smoothly merged crossing, dithered edges, zero extraneous
marks, cold palette throughout. The guide is a layout/palette reference, not
final art.

## Style references — STYLE ONLY

Accepted Loadout layers (`art/production/p1/town_modular_v01/`) and the
legacy town illustration (see the
[asset brief](../TOWN_MODULAR_ASSET_BRIEF.md)) define the cold-snow,
dark-wood/stone, amber-light look. Reference their temperature, value range,
and pixel density only; never copy pixels, and never lift objects or shadows
from the old `town.png` — the ground plate is empty ground by contract.

## Proposed imagegen prompt (root session)

> Top-down pixel-art ground plate, 960x640, cold overcast winter palette:
> pale blue-white packed snowfield with subtle wind-speckle covering the
> entire canvas edge to edge, no gaps. A worn grey flagstone road crosses as
> a horizontal band (rows 352-440, spanning the width with a 12px snow
> margin left and right) and a narrower vertical footpath (columns 568-632,
> spanning the height with a 12px snow margin top and bottom); stones are
> cool grey-taupe with darker joints, snow drifting a dithered 2-3px into
> their edges; the two paths merge seamlessly where they cross. No
> buildings, trees, fences, props, lamps, characters, footprints, wheel
> tracks, water, cliffs, holes, vignette, or border; fully opaque; flat
> parallel top-down view, no perspective, no lighting hotspot.

Edit from the guide image where the tool supports image-conditioned edits;
otherwise generate fresh and verify against the guide.

## Uniform packing QC

```bash
python3 -I tools/art_pipeline/p1_town_modular_v01/make_ground_guides.py \
    --check <generated.png>
```

Mechanical checks only: exact 960x640, alpha 255 everywhere, not one flat
fill, and both path bands distinguishable from the
snow field (region-mean distance >= 12). Region means are reported for
review. QC cannot judge seams, style, or palette fit — the parent's visual
inspection against the guide remains required before any acceptance.

## Scaling to the production 1536x960 underplate

The production world is 1536x960 (8:5); this sample canvas is 960x640 (3:2).
**Nonuniform stretch is forbidden** (1.6x horizontal vs 1.5x vertical would
distort pixels) — the sample must never be scaled into the production plate.

| Approach | Pros | Cons |
| --- | --- | --- |
| (a) Reusable snow base + path decals | one snow base reused everywhere; layout changes re-author only small decals with feathered alpha; sample work carries directly into town; schema already supports multiple `ground_parts` with offsets | decal/base seams need authored soft edges; separately generated pieces risk style drift; crossing decals overlap |
| (b) Full-world ground from a future layout guide | single coherent 1536x960 plate, no seams, one provenance | full regeneration on every layout change; large single asset; generation-resolution limits |

**Bounded recommendation:** produce the sample and near-term rounds with (a);
carry (a) into the shipped town if decal seams pass rendered review, and
switch to (b) only at layout freeze if seams or style drift fail it. In (b)
the layout guide itself is authored at 1536x960 with production-world
coordinates — never derived by stretching this sample.

## Remaining production decision

Root/parent chooses (a) vs (b) for the shipped-town ground once the town
layout guide exists, and whether the snow base is one full-canvas texture or
a tiling tile. This sample makes no claim on that decision.
