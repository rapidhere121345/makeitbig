# tree_south Backing Plate v01

Date: 2026-10-23. Status: **asset installed for a RENDERED REGION TRIAL —
this is root's acceptance scope, not final town visual acceptance.** No
scene/runtime/engine integration has been made; consuming the plate is a
later lane after the trial.

## Asset

| Field | Value |
| --- | --- |
| Path | `art/production/p1/town_modular_v01/tree_south_backing_v01.png` |
| World rect | (735,643)-(871,795) — exact inner patch |
| Canvas | 136x152, fully opaque (asserted) |
| sha256 | `baba1e08e6f28d9523d4969aeb19aadeef0080e2cc3b350c60e4698e8b331d05` |
| Content | original opaque ground pixels byte-identical + tree_south ownership (8,525 px) filled from root's generated candidate |

## Provenance (exact request preserved)

- Request: `build/current/p1-town-modular-v01/regional-fade-prep/request-tree-backing-01.json`
- Generator: root imagegen session (parent dispatch 2026-10-23); original
  output `/home/dev/.codex/generated_images/01a165a0-131e-7690-be00-610833ac1143/exec-36fe2d82-95ac-48fc-85e8-45bf3e75aac8.png`
  (not read from this sandbox).
- Retained raw: `docs/art-production/p1-town-modular-v01/sources/tree_south_backing_candidate_01.png`,
  sha256 `89cce76f0f3120b238a1fa35f0ef5361546b5c02fa038af0d532f15ce4a39b3c`,
  1198x1313 RGB opaque.
- Root review: accepts candidate appearance for rendered region trial;
  peripheral small trees/props are reference content; no new center tree.

Executed prompt, verbatim:

> Use case: precise-object-edit.
> Edit target: this small 136x152 pixel-art snowy ground crop from a dark-fantasy town. The large transparent tree-shaped gap in its center is missing background. Fill ONLY that transparent gap with newly painted plain cold gray-blue snow and sparse gray stone flecks, continuing the adjacent ground's dark muted values and chunky pixel texture. The top edge is stony gray, lower edges are snowy blue-gray; blend those existing ground values naturally across the fill without a dark outline or a tree-shaped shadow. Keep every existing opaque border pixel and all existing surrounding scenery in exactly the same location and design. Do not reconstruct a tree or its shadow: the center must be empty walkable ground. No new objects, trunks, foliage, buildings, water, light sources, footprints, text, borders or vignette. Whole canvas and origin locked; if upscaled scale the entire canvas uniformly, do not zoom or crop. Output a completely opaque ground plate, including the filled center. This is new underpainting, not recovery of hidden source scenery.

**Prompt-size mismatch (disclosed):** the prompt calls the edit target a
"136x152 pixel-art snowy ground crop", but the image actually supplied via
`referenced_image_paths` was `region_tree_south/ground_crop.png` — the
168x184 CONTEXT crop (slice rect + 28 px margin). 136x152 is the INTENDED
INNER PATCH, and the accepted asset is exactly that inner rect cut from the
packed context. The generated plate covers the full 168x184 context, so the
intended patch is fully contained; the description mismatch affects no
geometry but is recorded here rather than silently normalized.

## Recipe (deterministic, hash-pinned)

Tool: `tools/art_pipeline/p1_town_modular_v01/build_tree_backing.py`
(evidence: `build/current/p1-town-modular-v01/tree-backing-v01/report.json`
+ `review_sheet_native.png` / `review_sheet_2x.png`).

1. Derive everything from live sources: tree_south slice rect and
   `owned_pixels` from `content/rooms/town/layers/manifest.json`; context
   crop = slice rect +/- 28 px (168x184); patch = slice rect +/- 12 px
   (136x152, the asset rect). Fail closed unless ground.png and the raw
   candidate match their pinned sha256 values.
2. **One uniform rational scale** `1313/184 = 7.13587` on BOTH axes via an
   integer nearest sampler `src = (dest * 1313) // 184`, origin locked
   (0,0) — this corrects the earlier prep-dir pack, which used PIL's resize
   with per-axis ratios 7.1310/7.1359 (anisotropic despite the 0.00069
   difference; that label was wrong and this tool reports real measurements).
   Canvas residue, documented: source columns 1192..1197 and rows
   1306..1312 are never sampled (the uniform map ends at dest x=167.89).
3. Registration: exhaustive +-4 px offset fit against the original opaque
   ring; best offset (0,0), ring mean RGB distance 38.38 over 22,296 px
   (whole-canvas lock confirmed).
4. Fill scope: ONLY ground-transparent pixels inside the tree_south slice
   rect — exactly 8,525 px, asserted equal to the manifest `owned_pixels`.
   The 91 px of the arrival_east_gate corner in the context crop are NOT
   filled (different slice's ownership) and lie outside the asset rect.
5. Invariants asserted every run: 0 original opaque context pixels changed;
   asset exactly 136x152; fully opaque; 0 original opaque ground pixels
   changed inside the asset; deterministic byte-identical reruns.

## Scope note

This file is the tree_south-backing lane's record, kept separate from the
pine owner's shared PROMPTS/PROVENANCE notes (concurrent-edit avoidance).
The loadout roof work (polygon split, T11 verdict) is recorded in
[REGIONAL_FADE_PLAN.md](REGIONAL_FADE_PLAN.md). Nothing here installs the
plate into the runtime ground; the rendered region trial and any runtime
wiring follow in later lanes (runtime policy owned by ca).
