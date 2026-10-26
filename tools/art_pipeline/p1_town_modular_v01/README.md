# P1 town modular v01 — Loadout sample pipeline (checkpoints 1 and 2)

Tools for the first Loadout building sample defined by
[docs/art-production/TOWN_LOADOUT_SAMPLE_SPEC.md](../../../docs/art-production/TOWN_LOADOUT_SAMPLE_SPEC.md).
The reviewed processing recipes, measurements, deviations, and output hashes
are recorded in
[docs/art-production/p1-town-modular-v01/PROCESSING.md](../../../docs/art-production/p1-town-modular-v01/PROCESSING.md);
raw sources and provenance live in that same docs directory and are never
edited by these tools.

Status: **checkpoint 2 parent-accepted for advancing to the rendered sample
stage ONLY** (assembled/isolated/outline sheets reviewed 2026-10-22 — exact
paths and verdict in PROCESSING.md); **in-engine validation and shipped-town
integration are pending** — `validate()` and the preview mount have not been
run, and no runtime integration has happened.

## Tools

| Script | Purpose |
| --- | --- |
| `inspect_geometry.py` | read-only alpha row/column profiles, components, block color map |
| `measure_families.py` | read-only color-family segmentation (lip/wall/footing structure) |
| `measure_features.py` | read-only wall band + feature cluster edges (thresholds named) |
| `build_common.py` | deterministic common-layer pack; asserts the sample-spec invariants; writes `art/production/p1/town_modular_v01/loadout_common.png` + `manifest.json` |
| `make_guides.py` | 4x review sheet over neutral/white/black and the FIXED 256x224 roof/stubs imagegen guides into `build/current/p1-town-modular-v01/checkpoint-1/` |
| `build_upper.py` | normalizes both guide-edit upper raws with ONE shared uniform nearest transform, cuts the seam at y<=130, authors the contact shadow, and writes the upper layers + reviews + `manifest_upper.json` |

The checkpoint-1 pack transform lives in `build_common.py` as the `RECIPE`
constants (uniform nearest-neighbour scale 155/24, source window origin
(227,715) -> destination origin (59,128), alpha threshold 128) and serves the
candidate-01 raw space only. The checkpoint-2 generation-stage normalization
lives in `build_upper.py` as its own `RECIPE` (uniform scale 419/80, window
origin (209,668) -> (41,129), seam cut at y<=130); it is a separate source
space (the guide-edit outputs) and is the ONE transform shared by both upper
raws — never refit per state, and never mixed with the 155/24 recipe.
The accepted `common` layer's hash is pinned in `build_upper.py` and
re-verified on every run; the edited facades inside the upper raws are
discarded at the seam cut.

## Run

From the repository root in the approved portable environment:

```bash
source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
source scripts/project_env.sh
python3 -I -m unittest discover -s tools/art_pipeline/p1_town_modular_v01/tests
python3 -I tools/art_pipeline/p1_town_modular_v01/build_common.py
python3 -I tools/art_pipeline/p1_town_modular_v01/make_guides.py
python3 -I tools/art_pipeline/p1_town_modular_v01/build_upper.py
```

Both builders refuse a source whose SHA-256 differs from the recipe, an
output directory holding unmanaged files, and any canvas that violates the
invariants (size, binary alpha, margin, lip/feet or ridge/seam rows; the
revealed layer must keep the central bay transparent). Verification is
mechanical only; visual acceptance is the parent's review.

## Tests

`tests/test_p1_town_modular_v01.py` uses synthetic bitmaps only (temp
directories outside the repo): transform index math, alpha binarization,
invariant failures, output guarding and rebuild determinism, silhouette
rasterization spans/banding, stub rects, guide compositing precedence,
review-sheet panels, seam gating, shadow authoring/tamper detection, outline
comparison colors, and the checkpoint-2 end-to-end build. Production art is
never read or rewritten (the common layer is only ever hash-checked).
