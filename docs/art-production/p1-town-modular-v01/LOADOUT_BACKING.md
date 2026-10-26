# loadout Backing Plate v01

Date: 2026-10-23. Status: **asset installed for a RENDERED REGION TRIAL —
pending, this is root's packing-trial acceptance scope, not final town visual
acceptance.** No scene/runtime/engine integration has been made; consuming the
plate is a later lane (runtime policy owned by ca).

## Asset

| Field | Value |
| --- | --- |
| Path | `art/production/p1/town_modular_v01/loadout_backing_v01.png` |
| World rect | (478,18)-(805,271) — parent-approved outer extent (= slice rect +/- 12 px) |
| Canvas | 327x253; opaque 82,693 px + 38 preserved tree_wood-owned transparent px (rows 267..270) |
| sha256 | `6f5b7ec156e418681388681683b5153b83242ca146e3e83f46636780c736ad37` |
| Content | everything outside the replacement mask byte-identical to ground (incl. transparency); ownership hole + obsolete interior props replaced from root's generated candidate |

## Provenance (exact request preserved)

- Request: `build/current/p1-town-modular-v01/regional-fade-prep/request-loadout-backing-01.json`
- Generator: root imagegen session (parent dispatch 2026-10-23).
- Retained raw: `docs/art-production/p1-town-modular-v01/sources/loadout_backing_candidate_01.png`,
  sha256 `816adb239478fc2aaf60efda091671817e763c31729b791876a2b2c6ea916a56`,
  1408x1117 RGB fully opaque.
- Root review: viewed the generated ground, accepts it for the packing trial.
- Input image: `region_loadout/ground_crop.png` (359x285 context crop, slice
  rect + 28 px margin) — request and image sizes are consistent here (no
  size mismatch to disclose, unlike the tree_south request).

Executed prompt, verbatim:

> Use case: precise-object-edit.
> Edit target: the supplied pixel-art winter town ground crop, with a large transparent building-shaped gap. Fill ONLY that transparent gap with newly authored complete plain ground: cold muted blue-gray packed snow, darker gray earth and small scattered flat stones continuing the adjacent ground texture. Match the dark overcast fantasy-town palette and chunky pixel-art density. Existing opaque scenery around and within the gap, including the visible workbench/crates, stone floor, snow, fence and distant trees, must stay at the same locations and design. Connect the ground naturally across the gap; no black building-shaped outline, no roof-shaped shadow, no new buildings, walls, doors, trees, props, people, text, lighting hotspots or vignette. This is newly painted backing, not a reconstruction of the missing building. Keep the complete canvas, framing, origin and all margins; do not zoom, crop or recenter. If upscaled, scale the entire canvas uniformly. Output fully opaque filled ground, with no transparency in the former gap.

**Disclosure — the prompt's keep-props clause is deliberately overridden by the
replacement mask:** the prompt ordered the visible workbench/crates kept, and
the candidate largely did keep floor tones (52.9% of the interior rect's
opaque px differ from the guide by <=120 RGB), while repainting the prop mass
(repainted blob 6,043 px, bbox (627,137)-(753,255)). Root's backing
requirement is that the old interior props be REMOVED, not just the hole
filled, so the mask replaces the whole interior rect from the candidate; root
authorized repainting those interior opaque pixels (old building removed).
This pack therefore does NOT claim preserve-all-opaque.

## Recipe (deterministic, hash-pinned)

Tool: `tools/art_pipeline/p1_town_modular_v01/build_loadout_backing.py`
(evidence: `build/current/p1-town-modular-v01/loadout-backing-v01/report.json`
+ `review_sheet_native.png` / `review_sheet_2x.png` / `mask_overlay_2x.png` /
`composite_v01_native.png` / `composite_v01_2x.png` /
`candidate_verification_3x.png`; deterministic byte-identical reruns verified).

1. Derive everything from live sources: loadout slice rect (490,30)-(793,259)
   and `owned_pixels` from `content/rooms/town/layers/manifest.json`; context
   crop = slice rect +/- 28 px (359x285); asset rect = slice rect +/- 12 px,
   asserted equal to the parent-approved outer extent (478,18)-(805,271). Fail
   closed unless ground.png and the raw candidate match their pinned sha256
   values.
2. **One uniform rational scale** `1117/285 = 3.919298` on BOTH axes via an
   integer nearest sampler `src = (dest * 1117) // 285`, origin locked (0,0).
   Canvas residue, documented: source columns 1404..1407 and rows 1114..1116
   are never sampled.
3. Registration: exhaustive +-4 px offset fit of the transformed candidate
   against the original opaque ring **EXCLUDING the replacement mask** (the
   interior is legitimately repainted and must not skew the fit); best offset
   (1,0), ring mean RGB distance 26.56 over 46,902 px ((0,0) alternative:
   33.12 — the 1 px x-shift is a real fit improvement, not a rounding choice).
4. Replacement mask (55,029 px): the loadout ownership hole — ground
   alpha<255 inside the slice rect, asserted == manifest 42,294 — UNION the
   obsolete interior rect (620,125)-(793,259) opaque px, pinned 12,735. Mask
   verified against the image before packing: the candidate's repaint blob
   lies fully inside the rect; the west band (490..620) is exterior
   forest/fence/barrels and is NOT in the mask; the only straddle is 38 px of
   floor continuity at x 618..619, y 255..258, kept as original so the floor
   reads continuous across the mask edge.
5. Invariants asserted every run: 0 px outside the mask changed (including
   the 38 tree_wood-owned transparent px, preserved byte-exact inside the
   asset); every replaced px opaque; asset exactly 327x253; preserved px
   byte-identical to ground.

## Seam quality (reported, not forced)

Rim RGB distances between replaced and adjacent preserved opaque px: hole rim
571 px mean 41.9 (max 486); interior rim 320 px mean 61.1 (max 365). Visual
review (review sheets + seam inspection): props gone, plain ground continues,
west band identical; a minor grain/tonal step along part of the old hole rim
and a few boundary-clipped stone tiles remain — the same marginal class as the
accepted tree_south trial (whose rim mean was 95.6), numerically better here.
Rendered trial pending; a regenerated candidate can be packed unchanged.

## Parent scope recorded (d19 acceptance)

Compact building placement `position = (583, 56.0625)` (canvas spans
(583,56)-(839,280)); ONE existing gameplay socket preserved —
facility/spawn `town/interaction/loadout` at (711, 284.0625), route endpoint
unchanged; tree trunk collision stays native r8.5. The review composite
pastes the v01 art (`loadout_common.png` + `loadout_upper_full.png`, 256x224)
at that position — paste rounded to integer (583,56), a 0.0625 px review-only
approximation — and marks T11 (666.5657,257.2501) below the v01 envelope
(legal + readable once the old slice art is gone), Taren (719.4,255.0), and
the facility. Review-only: no placement, collision, or layout was changed.

## Scope note

This file is the loadout-backing lane's record, kept separate from the pine
owner's shared PROMPTS/PROVENANCE notes (concurrent-edit avoidance). The
roof-split analysis and region sequence live in
[REGIONAL_FADE_PLAN.md](REGIONAL_FADE_PLAN.md); the tree_south plate is
[TREE_SOUTH_BACKING.md](TREE_SOUTH_BACKING.md). Nothing here installs the
plate into the runtime ground; the rendered region trial, preview adaptation,
and any runtime wiring follow in later lanes (runtime policy owned by ca).
