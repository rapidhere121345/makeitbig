# P1 scene rework technical verification v01

This directory is independent of the calibration pipeline. It does not build, repair, or replace bitmap art. verify.py checks generated artifacts and mechanically converts real generated pixels for review.

## Contract

The delivery must contain exactly seven atlases and nineteen sprites:

| Atlas | PNG size | Cells | Anchor |
| --- | --- | --- | --- |
| ground | 1024x640 | scene.ground | (0,0) |
| decals | 512x96 | four 128x96 decals | (64,90) |
| ruins | 512x128 | four 128x128 ruins | (64,120) |
| ranger | 128x48 | four 32x48 facings | (16,44) |
| boss_body | 256x128 | two 128x128 bodies | (64,120) |
| boss_hands | 96x64 | two 48x64 hands | (24,56) |
| boss_core | 64x64 | two 32x64 cores | (16,56) |

Exact IDs are scene.ground; the four ground.* decals; the four ruin.* structures; ranger.south/north/west/east.idle; boss.body_phase1/2; boss.hand_left/right; and boss.core_phase1/2.

Checks cover the existing atlas.json object format, exact texture/rect/anchor slots, bounds, binary alpha, non-empty cells, minimum 2px padding except ground, opaque-color budgets (8, or 12 for ranger/Boss), opaque ground, SHA-256 hashes and byte counts for every real artifact, recipe/source provenance hashes from the old manifest fields, exact ground repetition at 64px offsets, and optional layout bounds/IDs. Rect slots follow the build recipe order; scene.ground keeps the recipe-owned origin anchor. Verification is mechanical and is not visual approval.

## Run

    python3 tools/art_pipeline/p1_scene_rework_v01/verify.py \
      --output art/production/p1/scene_rework_v01

--layout is optional; output/layout.json is checked automatically when present. Modular placements may reuse the same sprite ID at different feet positions; only an identical (id, feet) pair is rejected as an overlapping duplicate.

Mechanical QA writes 100%, 2x nearest-neighbor, 25% nearest-neighbor, and grayscale copies of the seven real atlases plus the real contact sheet into a new empty directory outside the output:

    python3 tools/art_pipeline/p1_scene_rework_v01/verify.py \
      --output art/production/p1/scene_rework_v01 \
      --qa-output docs/art-production/p1-scene-rework-v01/qa-mechanical

QA adds no painting, labels, borders, or placeholders and is written only after verification passes.

## Tests

    python3 -m unittest discover -s tools/art_pipeline/p1_scene_rework_v01/tests -v

Tests use synthetic temporary bitmaps only and cover valid delivery, exact contracts, rect/anchor failures, alpha/padding/palette failures, obvious ground tiling, manifest hashes/artifact sets, layout bounds/IDs, and QA conversion output. Production art is never read or rewritten.
