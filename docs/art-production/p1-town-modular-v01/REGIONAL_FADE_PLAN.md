# Regional Fade Plan — Town Art Integration Preparation

Date: 2026-10-23. Status: **inspection + guides complete; no engine, runtime,
or scene edits. Two backing plates are installed as rendered-trial assets
(`tree_south_backing_v01.png`, `loadout_backing_v01.png` — no runtime
wiring).** Runtime fade policy, definition/baker/root
validators are ca's lane. This plan prepares bounded regional art changes:
ROOF/CANOPY layers become transparent-capable, bases and actors stay solid.
Parent preference recorded: bounded regions preserving the existing town
appearance; no whole-town remake; base-only props (fences, lamps) stay opaque.

## Measured ground truth

Source `art/production/p1/hamlet_town/town.png` (1536x1024) is sliced into
`content/rooms/town/layers/` = 35 native slices + one ground underplate
(1536x960, `unknown_underplate: transparent`, `supports_fade: true`).
Ownership tiles the world exactly: ground opaque 1,113,455 px + slice-owned
361,105 px = 1,474,560 px — every layer's alpha hole equals its slice's owned
pixels (verified: loadout hole 42,294 = manifest 42,294; tree_south 8,525 =
8,525). **Fading any roof/canopy without a backing patch exposes a
transparent hole**, so each region needs a ground fill before fade goes live.

All numbers below are in `build/current/p1-town-modular-v01/regional-fade-prep/measurements.json`
+ `roof_split_verify.json` (tools: `inspect_regions.py`,
`verify_roof_split.py` in the same directory, deterministic; contact sheet,
crops, and split overlays verified visually).

## Deliverables this round (ignored build/, originals untouched)

| Path | Content |
| --- | --- |
| `contact_sheet_baseline.png` | all 36 layers, binding id + feet + world rect + owned px, checker = alpha |
| `region_loadout/` | `ground_crop.png`, `ground_crop_2x.png`, `guide_overlay.png` (slice/hole/patch rects + neighbor swatches), `slice_reference.png`, `slice_grid_2x.png`, `new_v01_composite.png`, `new_loadout_mock_overlay.png` (alignment A pasted, A/B outlines), `roof_split_polygon_overlay.png`, `t11_readability_overlay.png` |
| `region_tree_south/` | `ground_crop.png`, `ground_crop_2x.png`, `guide_overlay.png`, `slice_reference.png`, `pine_footprint_overlay.png` (pine canvas + footprint/envelope/trunk circles) |
| `measurements.json` | every figure quoted here |

## Region 1 — loadout (polygon split proposal; straight cut REJECTED; readability verdict below)

**Backing patch for this region is INSTALLED as**
`art/production/p1/town_modular_v01/loadout_backing_v01.png` (approved outer
extent (478,18)-(805,271); deliberately REPLACES the obsolete interior props,
not just the hole — root authorized; see
[LOADOUT_BACKING.md](LOADOUT_BACKING.md)).

Slice rect world (490,30)-(793,259), feet (671,262.5), 42,294 px, hole = full
rect. The spatial manifest's `town/static/loadout_roof` rect (494,16.9)-
(792,125.6) is a collision bbox, NOT a credible art boundary: the roof is a
**gable with a sloped eave** (measured chromatically and confirmed on the
labeled grid, `region_loadout/slice_grid_2x.png` + `roof_split_verify.json`).

**Straight world y=126 cut — rejected** (follow-up review, 2026-10-23): it
would keep **2,678 roof px solid** (west slope below the line, including
2,287 snow-material px) and would fade **4,591 solid wall px** (east wall
above the line). Eave evidence: polygon vs first-warm-wall per column —
x520 165/165, x550 153/154, x610 127/126, x730 90/85, x760 82/77, x780 77/73.

**Proposed simple polygon split** (no pixel-perfect matting), roof region =
(490,178) → (650,110) → (793,74) → (793,30) → (490,30), ridge ≈ (650,110):
17,675 opaque px, tracks the measured eave within ~5 px per sample. Overlay:
`region_loadout/roof_split_polygon_overlay.png`. Roof part renders
transparent under ca's primitive fade conditions — **no revealed/mask
channels are involved**; the split is pure geometry (two parts).

**T11 readability verdict (the key risk, measured)**: for a legal rear/side
actor stand at T11 (666.5657, 257.2501), the assumed 14x22 sprite box is
**100% covered by solid base art and 0 px of it lies in the roof polygon**
(`t11_readability_overlay.png`, `roof_split_verify.json`) — the door/crates
wall art reaches world y≈258 at x 655..680. A roof-only fade, straight or
polygon, therefore CANNOT clear an actor at T11; any existing-art split
solves only the north/back band above the eave (y≈74..178). The v01 compact
swap does not make T11 readable either — T11 falls INSIDE its alignment-A
movement envelope (601,212.5)-(741,268.5), so the stand becomes **illegal
(blocked), not readable** — a layout consequence to decide, not to apply now.
Conclusion: whether the existing-art split "solves the relevant route"
depends on which stands the route actually needs readable; if T11-class
rear/side stands must stay legal AND readable, a **new compact Loadout
sample/layout is necessary** (base short enough, or envelope shaped, so the
stand is either clear of solid art or deliberately excluded). Both
alternatives stay open — root decides; no collision/layout changes made.

**If the new Loadout v01 is used instead** (canvas 256x224, base strip
occupied bbox [59,128]-[195,177] — a visibly more compact shop; the mock
overlay shows the mass change):
- Placement (alignment A, recommended — keeps the building on the legacy
  base): `position = feet - common_anchor = (543, 84.5)`; canvas spans
  (543,85)-(799,309); footprint poly world (607,218.5)-(735,262.5);
  movement envelope poly (601,212.5)-(741,268.5) — 140x56, local to the base,
  no giant invisible collider.
- Socket `door.service` lands at (671,280.5); facility
  (711,284.0625), spawn socket `town/interaction/loadout`, and route-loadout
  endpoint (711,284.0625) would each move -40.0/-3.56 (gameplay metadata,
  owning lane applies). Alignment B (position (583,88.06)) preserves the
  facility exactly but shifts the building +40 px — outline on the mock.
- Collision replacement: legacy static shapes `loadout_west_wall`x2,
  `loadout_back_wall`x4, `loadout_crates`x3, `loadout_roof`x2 (11 polys,
  y 16.9..251.2) collapse into the v01 footprint+envelope polys; the hero
  gains the walkable band behind the shop that the roof collider used to
  block, with occlusion handled by the fading roof — no hero-on-top hack,
  sort anchors (128,178)/(128,142) keep the hero correctly ordered.

## Region 2 — tree_south (recommend replacement with the compact pine)

Slice rect (747,655)-(859,783), feet (805,771.56), 8,525 px, hole = full rect.
Row-width profile: conifer widest 108 px at rows 88-94, tapering to 1 px at
the bottom row. **Canopy/base split is not credible: 97.7% of the art mass
(rows 0..118) is canopy; the only narrow band is a 9-row bottom tip
(max 43 px wide).** There is no solid trunk/base mass to keep opaque.

**Backing patch for this region is INSTALLED as**
`art/production/p1/town_modular_v01/tree_south_backing_v01.png` (exact patch
rect, fully opaque; root accepted the generated candidate for a rendered
region trial — see [TREE_SOUTH_BACKING.md](TREE_SOUTH_BACKING.md)).

**Recommend replacement by the compact pine** (art owner 2691, contract:
canvas 96x144, anchor (48,128), footprint r10, envelope r14; the canopy is a
separate fading part under ca's primitive fade — no revealed/mask channels):
placement `position = trunk_center - anchor =
(757, 643.56)` puts the pine anchor exactly on the legacy trunk circle
`town/static/tree_south_trunk` (805,771.56) r8.5 — footprint r10 is a +1.5 px
radius change, envelope r14 keeps blocking a small local disc; canvas
(757,644)-(853,788) vs legacy (747,655)-(859,783): slightly taller and
narrower, same spot. `pine_footprint_overlay.png` shows the fit. Pine art is
still being authored (`pine_common.png` present; upper pair pending) — swap
only after 2691 delivers and the definition passes ca's validator.

## Backing patches (required before ANY fade goes live)

Complete coverage of the potential fade area, from the measured holes:

| Region | Patch rect (world) | Size | Palette anchor (neighbor ring) |
| --- | --- | --- | --- |
| loadout | (478,18)-(805,271) | 327x253 | mean rgb (89,88,96); top tones (32,48,64),(32,32,48),(80,80,80) dark cold night snow |
| tree_south | (735,643)-(871,795) | 136x152 | mean rgb (110,109,118); adds lighter snow (176,176,192) |

Edit references for root imagegen (inputs): each region's `ground_crop.png`
(the hole is the transparent target, context is the opaque ring) with
`guide_overlay.png` as the keep-out map. Prompt pattern:

> Fill ONLY the transparent hole in this dark night-time snowy ground plate.
> Continue the surrounding ground exactly: same cold blue-grey snow tones,
> same noise grain and value range, edges fully opaque where they meet the
> existing pixels. Do not add, move, or infer any objects, structures,
> shadows, paths, water, or terrain features — the hidden area is unknown and
> must stay plain ground. Keep every already-opaque pixel unchanged.

Never infer the hidden landscape exactly, never copy objects or pixels from
`town.png`. Note: the bright 960x640 sample ground guide
(`ground-checkpoint-1/`) is a different palette (overcast daytime) — regional
patches must match the measured night palettes above, not the sample.

## Remaining roof/canopy objects for policy consistency

Roof/base splits or pine-style replacements still needed (world rects from
the layout foreground polygons; trunk circles already authored for all trees):

- Buildings: `contract` (162,134)-(379,307), `forge` (893,65)-(1176,320),
  `proxy` (1300,99)-(1536,499 — tallest occluder, no roof rect authored yet,
  needs a roof/base decision), `forge_chimney` (1140,37)-(1286,358 — tall
  roof-zone occluder sharing the forge interaction; decide fade-with-forge
  vs stay solid).
- Trees (all have r8.5 trunk circles; apply the tree_south method — measure
  canopy share, replace with pine unless a real base band exists):
  `tree_board` (62,54)-(219,223), `tree_wood` (506,267)-(572,365),
  `tree_east` (1189,362)-(1279,466), `tree_southwest` (198,644)-(302,770),
  `tree_arrival` (235,757)-(333,868).
- Stay opaque (base-only props — do NOT fade): lamps 0-10, both arrival
  gates, `arrival_storage_fence`, wood piles x4, `cart`, `commons_fire`,
  training props x4.

## Suggested region sequence

1. **loadout backing patch** (imagegen fill) — needed for BOTH the split and
   the v01-swap paths; unblocks the biggest occluder first.
   **INSTALLED** as `loadout_backing_v01.png` (rendered trial pending).
2. **loadout split decision** — polygon split (preserves appearance, north
   band only) vs new compact Loadout sample/layout (if T11-class rear/side
   stands must remain legal and readable); v01 swap only if root prefers the
   compact shop after viewing the mock overlay.
3. **tree_south** pine swap (after 2691's pine upper lands) + backing patch.
4. Remaining five trees: measure → pine-replace or split.
5. `contract`, `forge`, then `proxy`/`forge_chimney` decisions (each needs its
   own backing patch first; same method, regions addable to the tool).

## Constraints honored

No engine runs; no runtime/scene/asset/preview edits; all originals preserved
(the tool reads layers read-only and writes only into the ignored prep
directory); no art generated here — imagegen fills happen in the root session
against the crops and prompts above.
