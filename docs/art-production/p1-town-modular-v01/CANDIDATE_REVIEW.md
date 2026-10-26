# Candidate Review — p1-town-modular-v01 (read-only inspection)

Factual measurements only; no visual acceptance is claimed and no pixel was
edited. All quantities below come from
[measure_candidates.py](measure_candidates.py); its full output is retained in
[measure_candidates_output.txt](measure_candidates_output.txt). Reproduce from
the repository root in the approved portable environment:

```bash
source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
source scripts/project_env.sh
python3 -I docs/art-production/p1-town-modular-v01/measure_candidates.py
```

Conventions: pixel indices are inclusive; PIL `getbbox` reports exclusive
right/bottom, which is why the independent parent check prints bbox values one
larger. Logical coordinates map the whole 1340×1174 image onto the
[sample spec](../TOWN_LOADOUT_SAMPLE_SPEC.md) 256×224 logical canvas
(logical = pixel × 256/1340 horizontally, × 224/1174 vertically). Spec facade
target: x 64..192 (width 128), y 130..178 (height 48), feet y 178, center x 128.

## Measurements (thresholds named)

| Metric | Candidate 01 | Candidate 02 |
| --- | --- | --- |
| Canvas px | 1340×1174 (aspect 1.1414) | same |
| Share alpha = 0 | 80.8951% | 72.5433% |
| Share alpha 1..127 (faint halo) | 1.3562% | 0.8873% |
| Share alpha 128..249 | 0.6719% | 0.4809% |
| Share alpha 250..254 (near-opaque mass) | 17.0750% | 26.0710% |
| Share alpha = 255 (fully opaque) | 0.0018% (28 px) | 0.0176% (277 px) |
| Share alpha 1..254 (non-binary total) | 19.1031% | 27.4391% |
| Opaque content extent, alpha ≥ 128 | px (227,715)-(1113,1036) | px (122,710)-(1217,1098) |
| … in logical px | x 43.37..212.63, y 136.42..197.67 (169.46 × 61.44) | x 23.31..232.50, y 135.47..209.50 (209.39 × 74.22) |
| Nonzero-alpha extent, alpha > 0 | px (0,31)-(1293,1157) — near full canvas | px (0,51)-(1270,1169) — near full canvas |
| Unique RGBA colors (sampled /2) | 27227 | 25325 |
| Median horizontal run (image px) | 1.0 | 1.0 |

Correction note: an earlier revision of this table reported "semi-transparent"
as 2.03% / 1.37% using an undocumented 0 < alpha < 250 bucket (which excludes
the near-opaque 250..254 mass entirely) and extrapolated candidate 02's
transparency from candidate 01 as "~81%". Both rows were wrong without their
threshold definitions and are superseded by the ladder above, which reproduces
the independent parent check exactly.

The "opaque content extent" is the alpha ≥ 128 pixel bounds of the whole drawn
object — it includes the wall-top plate lip, footing, and snow irregularities.
It is **not** a measurement of the facade wall band, door, or window geometry;
those edges were not isolated by any threshold and no claim below treats the
extent as facade geometry.

## Findings

1. **Density (both; candidate 02 improved but not native).** The image is
   oversampled ×5.23 relative to the logical canvas. Candidate 01 renders
   detail far finer than native: median feature run 1 image px (0.19 logical
   px), 27k distinct colors. Candidate 02's edit shifted the run-length
   distribution toward longer runs (2 px runs ~7.5×, 3 px runs ~15× more
   frequent), consistent with the parent's visual judgment that blockiness
   improved — but the stored file still varies per image pixel (median run
   1 px, ~25k colors), so the requested ~24-color flat-block rendition was not
   achieved in the file. No dominant uniform block size was detected.
2. **Alpha is not binary in either file.** The visible mass sits at alpha
   250..254 — essentially nothing is fully opaque (28 / 277 pixels at 255) —
   and a faint 1..127 halo reaches to near the canvas corners (the alpha > 0
   extent nearly spans the image). Both facts fail the sample spec's
   near-binary-alpha QC as stored and would have to be addressed in any
   packing review; nothing was edited here.
3. **Candidate 02 composition drift (extent-level, parent-confirmed).** At the
   alpha ≥ 128 threshold the drawn content grew from 169.46 to 209.39 logical
   px wide (+39.9) and from 61.44 to 74.22 tall (+12.8); the vertical center
   held roughly and the horizontal extent grew outward on both sides. This
   matches the parent's visual judgment that facade bounds changed despite the
   preservation request, and it is the primary reason candidate 02 is not an
   aligned layer candidate as-is.
4. **Scale observations only — no fit claim.** Mapping the alpha ≥ 128 content
   extent onto the 128 × 48 target rectangle would need width/height ratios of
   0.7554 / 0.7813 for candidate 01 (3.4% relative spread) and 0.6113 / 0.6467
   for candidate 02 (5.8%). These are extent ratios, upper-bound observations
   over drawn pixels that include lip, footing, and snow — not facade
   geometry, and not a precise fitting, aspect, or impossibility claim. The
   actual wall band, door, and window edges are unverified by any measurement
   so far.

## Conclusion

Both files are retained as raw, unaccepted base-layer candidates; neither has
been packed, cropped, scaled, or imported, and no upper/revealed/shadow state
exists. Honest next-step QC, in order: visually verified alignment at named
thresholds (identify the true wall band, door, and window edges against the
spec rectangles), an alpha-binarization assessment, and a density decision —
before any packing transform is chosen or upper states are generated.
Candidate 01 is the closer starting point by extent; candidate 02's
composition drift stands on its own. Per the
[sample spec](../TOWN_LOADOUT_SAMPLE_SPEC.md), fractional **uniform**
nearest-neighbour source scaling is allowed at packing time; what is
prohibited is nonuniform stretching and per-state independent fitting.
