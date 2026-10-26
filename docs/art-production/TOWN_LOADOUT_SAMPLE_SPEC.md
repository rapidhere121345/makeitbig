# Loadout Building Sample Specification

Date: 2026-10-22. Status: **geometry contract frozen; packed loadout sample
accepted at checkpoint 2, rendered-sample preview accepted 2026-10-23
([acceptance record](../playtest/TOWN_LOADOUT_SAMPLE_ACCEPTANCE_20261023.md))
— shipped-town integration is pending and nothing is integrated into the
shipped town.** The
packed layers live under `art/production/p1/town_modular_v01/` with the
definition at `content/environment_objects/town_loadout_v01.tres`; four raw
candidates are retained unaccepted under
[p1-town-modular-v01/](p1-town-modular-v01/) (exact requests in its
PROMPTS.md, provenance in its PROVENANCE.md). The processed
common/upper_full/upper_revealed/shadow layers and definition were accepted
from the isolated composites, triple-background sheets, and outline compare
for advancement to the rendered sample only — the packing recipe and the
outline/stub deviations accepted **as drawn, not spec-pixel-identical** are
recorded in [p1-town-modular-v01/PROCESSING.md](p1-town-modular-v01/PROCESSING.md).
The [delivery brief](TOWN_MODULAR_ASSET_BRIEF.md) remains the source contract;
the collision footprint, movement envelope, sort anchors, and socket in this
file are unchanged and exact in the definition. This sample is one building,
not a whole-town solution.

Arithmetic is code-grounded: greybox geometry from `tools/modular_town_preview.gd`,
canvas-to-world composition and binding ids from
`src/runtime/world/environment_object_baker.gd`, reveal semantics from
`src/presentation/occlusion/authored_reveal_controller.gd` and
`src/presentation/occlusion_query.gd`, facility contract from
`src/runtime/world/town_scene_root.gd` and
`content/rooms/town/hearthside.spatial.json`.

## Calibration

- Shared canvas **256×224**, one canvas pixel = one design pixel (640×360
  logical viewport).
  Greybox stays 192×160; production geometry is the greybox shifted by (+32,+32)
  with no scaling, giving room for roof overhang, snow silhouette, and a separate
  contact shadow the greybox never had.
- Camera: locked top-down three-quarter **parallel projection, due south** —
  facade at bottom, roof plane rising to a horizontal ridge. Light: subtle
  upper-left; shadows pool lower-right.
- `world_point = placement + canvas_point` (`environment_object_baker.gd` composes
  parts, shapes, and sockets this way), so padding must move the placement:
  **placement (148,148) = (180,180) − (32,32)** keeps every world value identical.

Parity table (greybox world = (180,180)+c; production world = (148,148)+c+(32,32)):

| Element | Greybox → world | Production → world | Parity |
| --- | --- | --- | --- |
| Footprint (32,102,128,44) → (64,134,128,44) | (212,282)-(340,326) | (212,282)-(340,326) | exact |
| Envelope (26,96,140,56) → (58,128,140,56) | (206,276)-(346,332) | (206,276)-(346,332) | exact |
| `common` anchor (96,146) → (128,178) | (276,326) | (276,326) | exact |
| `upper` anchor (96,110) → (128,142) | (276,290) | (276,290) | exact |

Envelope bottom 332 plus hero radius 6 gives the blocked center y 338 the preview
asserts (`blocked.y ∈ [337.9,350)`), unchanged by the swap.

## Coordinates (production canvas 256×224)

| Element | Greybox (192×160) | Production (256×224) |
| --- | --- | --- |
| Wall band | x 32..160, y 98..146 | x 64..192, y 130..178 |
| Door | (83,110,26,36) | (115,142,26,36), center x 128 |
| Windows | (40,108,28,20), (124,108,28,20) | (72,140,28,20), (156,140,28,20) |
| Wall-top/eaves seam | y 96..98 | y 128..130 |
| Roof base | x 8..184 | x 40..216 (24 px overhang per side; 40 px canvas margin) |
| Roof ridge | y 16 | y 48 |
| Roof-off stubs | x 30..40, 152..162, y 82..98 | x 62..72, 184..194, y 114..130 |
| Footprint polygon | rect (32,102,128,44) | (64,134)-(192,134)-(192,178)-(64,178) |
| Movement envelope | rect (26,96,140,56) | (58,128)-(198,128)-(198,184)-(58,184) |

## Layer Contract

Placement id `building` at **(148,148)**; part ids stay `common`/`upper` so the
preview reveal keys (`building/upper`) are unchanged. Every texture is exactly
canvas-size (`validate()` rejects `environment_canvas_mismatch`).

| part_id | Type | File (proposed `art/production/p1/town_modular_v01/`) | Content |
| --- | --- | --- | --- |
| `shadow.contact` | ground_part, layer `GroundEffects` | `loadout_shadow.png` | Flat translucent cold slab at the feet line, offset lower-right; one alpha level plus at most two dither steps |
| `common` | visual, rank 0, anchor (128,178) | `loadout_common.png` | Facade band only: walls, stone footing, door, windows; nothing above the wall-top lip |
| `upper` | visual, rank 1, anchor (128,142), reveal | `loadout_upper_full.png` | Roof x 40..216, ridge y 48, eaves y 128; static chimney cap only, no smoke |
| — revealed | on `upper` | `loadout_upper_revealed.png` | End stubs x 62..72/184..194, open mid-span, warm light from below |
| — mask | on `upper` | the `upper_full` file itself | Immutable full-state alpha |

## Socket (stable facility id preserved)

```json
{ "part_id": "door.service", "position": [128, 196], "kind": "interaction",
  "id": "loadout", "label": "Loadout", "radius": 48.0,
  "landmark_offset_y": -112.0, "order": 1.0, "locked": false }
```

`id`, label, radius, landmark offset, and order match the current
`hearthside.spatial.json` facilities entry. World position = (148,148)+(128,196)
= (276,344), on the door centerline. Reachable: the envelope bottom is world y
332 and the hero center stops at 332+6=338, so 344 sits 6 px beyond the closest
reachable approach; radius 48 covers the approach. The baker emits binding id
`building/door.service`.

## Reveal Mask

The mask is the immutable alpha of the **full** upper state;
`authored_reveal_controller.gd` intersects the subject readability box with mask
alpha ≥ 0.5 pixel-by-pixel (transparent gaps contribute nothing), applies
hysteresis (enter 0.12 / exit 0.04) and a 0.15 s weight tween. It is precise
coverage, not a broad-phase box, and never feeds collision — collision is only
the authored polygons above. `full`, `revealed`, and `mask` must all be 256×224
with single-canvas sprites (no regions/frames/flips). Reusing the `upper_full`
file as the mask keeps it in sync by construction; a separate mask file must be
regenerated whenever `upper_full` changes.

## Common/Upper Separation

Only parts with a reveal variant ever fade, so `common` must never cover the
hero. Verified geometry: a hero behind the building stops at center y =
envelope top 276 − 6 = 270; its head/torso box spans roughly y 244..264. The
common band (canvas 130..178) is world 278..326 — 14 px clear of that box even
at closest approach — while the upper band (canvas 48..128) covers it, so
`SortRelation.is_front` holds and the reveal opens, holds, and closes exactly as
the walkthrough asserts. Therefore: `common` keeps all opaque content at canvas
y ≥ 130 (a lip of at most 2 px at 128..130, as in the greybox seam); everything
above y 128 — roof, ridge, chimney, rear-wall hints, stubs — belongs to `upper`.
A horizontal beam, rafter, or other structure crossing the roof-off opening is
rejected outright: it would hide the hero standing at the door, the retained-beam
failure recorded in the earlier visual review.

## Alignment and Packing

All aligned states come from one locked composition, so one transform serves
every layer: record a single **uniform** nearest-neighbour scale applied to the
generated source — fractional uniform source scaling is allowed; the brief
prohibits only nonuniform stretching and independent per-state fitting — with
crop and paste offsets chosen so every destination pixel is whole (facade at
x 64..192, wall top y 130, feet y 178), and apply that same recorded transform
unchanged to the upper and revealed states. Integer guarantees apply where they
matter: runtime display magnification and whole-pixel destination placement,
not the offline source scale. The generator is not
assumed to produce pixel-exact geometry — exactness is measured after the
transform: wall-top line y 130 and facade edges x 64/192 identical (±0 px)
across states, door rect exactly (115,142,26,36), nothing inside the 8 px
canvas-edge margin. An output whose aspect or structure does not fit one
uniform transform is **rejected and regenerated — never stretched unevenly,
re-fitted per state, or composited from mismatched framings**.

As built (full recipe and accepted deviations in
[PROCESSING.md](p1-town-modular-v01/PROCESSING.md)): the `common` layer comes
from the candidate-01 raw space with the locked uniform transform 155/24
(origin (227,715) → (59,128)); both upper states share one guide-edit space
transform 419/80 (origin (209,668) → (41,129)). The two source spaces are
never mixed, the same guide-edit transform serves full and revealed, and there
is no per-state fitting.

## Visual Rejection (sample-specific)

- Perspective convergence or camera drift between states (doorpost, wall-top, or
  roof edge moves between base/upper/revealed outputs).
- Roof cropped at the canvas edge; any content inside the 8 px margin.
- Composite scenes: multiple buildings, ground, sky, characters, or furniture
  baked into the sprite.
- Baked shadows or ambient occlusion inside `common`/`upper` (the contact shadow
  is the separate `GroundEffects` part).
- Semi-transparent fringes or stray pixels; palette drift from the reference's
  temperature family (no sampled hex values are pinned here).
- Roof-off state that alters the facade, or any beam crossing the opening.
- Text, UI, watermarks, or non-pixel-art soft edges.

## Prompt Templates (future requests only)

The brief's section 5 templates stay the source. For this sample, run them as
one chained edit — base first, then upper variants as edits of the accepted
base — with these pinned values: ~8:7 aspect, single centered object on
transparent background with wide margins; base = "storehouse base without roof,
nothing above the wall-top plate"; upper = "roof only, facade unchanged";
revealed = "roof removed, opening completely clear, no crossing beam"; shadow =
"flat slab, lower-right offset, at most two dither steps". All executed
requests to date are recorded verbatim in
[p1-town-modular-v01/PROMPTS.md](p1-town-modular-v01/PROMPTS.md): two
base-layer candidates (candidate 01 packed into the accepted `common`;
candidate 02 retained unpacked) and two upper guide edits (packed as
`upper_full`/`upper_revealed`); the shadow is code-authored, not generated.
The template wording above is reference, not a record. At acceptance time
record sources, tool and parameters, raw outputs, reviewed processing, and
output SHAs per the brief. Palette and atmosphere reference:
`art/production/p1/hamlet_town/town.png` (reference only, never a cutout
source); style family context: `art/production/p1/hamlet_style_r13/`.

## Substitution (later, minimal)

The `.tres` definition is authored from the tables above at
`content/environment_objects/town_loadout_v01.tres` (footprint, envelope,
anchors, and socket unchanged). In-engine preview validation ran on
2026-10-23 via the preview `--definition=` mount at placement (148,148) with
the greybox default and all walkthrough assertions unchanged — 63/63 checks
passed and the parent reviewed every frame
([acceptance record](../playtest/TOWN_LOADOUT_SAMPLE_ACCEPTANCE_20261023.md));
shipped-town integration remains. Runtime, baker, and placement code needed no
edits.
