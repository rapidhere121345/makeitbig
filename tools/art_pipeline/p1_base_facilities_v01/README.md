# p1_base_facilities_v01 — bounded QA + archival helper

Read-only helper for the `base_facilities_v01` art batch.  It never paints
pixels, never edits the atlas/recipe/layout, and never reverts repository files.
Both modules only read repository content; the verifier adds mechanical QA
conversions under an explicitly supplied new empty directory, and the archive
helper writes one baseline document it was asked to create.

## verify.py

Mechanical verification of the delivery plus pure conversions of pixels that
already exist in the generated atlas.  Checks: five `128x128` facility cells in
one `640x128` atlas, `foot anchor [64,120]`, >=2px padding, binary alpha,
exact recipe palette (<=8 colors per sprite), no animations, manifest/source
provenance, and the main-authored `layout.json` (`schema_version 1`,
`world_size [1024,640]`, `hero_start [512,380]`, `tower_feet [270,348]`, five
facilities with integer feet/footprints/split_row 96, optional 11-entry decals
with integer feet inside the world, split layers reproducing the whole sprite).

```bash
python3 tools/art_pipeline/p1_base_facilities_v01/verify.py \
  --output art/production/p1/base_facilities_v01 \
  --config docs/art-production/p1-base-facilities-v01/recipe.json
```

Add mechanical QA (native, 2x nearest, 25% nearest, grayscale, alpha silhouette
for the atlas and contact sheet, plus `QA_REPORT.json` with atlas/layout/recipe
hashes). `--qa-output` must be a new empty directory outside the atlas output:

```bash
python3 tools/art_pipeline/p1_base_facilities_v01/verify.py \
  --output art/production/p1/base_facilities_v01 \
  --config docs/art-production/p1-base-facilities-v01/recipe.json \
  --qa-output docs/art-production/p1-base-facilities-v01/qa
```

`--config` defaults to the recipe recorded in the manifest.  `--decals-atlas
<atlas.json>` additionally asserts that every layout decal id exists in the
scene atlas that will actually be drawn (the decals reuse existing sprite ids).

Exit codes: `0` pass, `1` verification failure with `ERROR:` lines on stderr.
Scope note printed on success: mechanical output properties only, not visual
approval.

## Boundary snapshots

The one-off `archive.py` helper and its dedicated test were retired after the
batch boundary was verified. The production verifier above remains the source
of truth for this batch; no runtime or asset file depends on the retired helper.

## tests

Synthetic, temporary-directory only (`tempfile`), covering valid delivery,
invalid slot/anchor/palette/alpha/animation/layout/decals, QA path safety and
non-overwrite, layer-split reproduction, provenance drift, plus archive
idempotence, non-overwrite, and path safety.

```bash
python3 -m unittest discover \
  -s tools/art_pipeline/p1_base_facilities_v01/tests \
  -t tools/art_pipeline/p1_base_facilities_v01
```
