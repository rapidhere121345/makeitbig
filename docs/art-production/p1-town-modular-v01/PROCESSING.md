# Processing — p1-town-modular-v01

Checkpoint 1 (common layer pack) and checkpoint 2 (upper layers, shadow,
definition). Date: 2026-10-22. Status: **checkpoint 2 parent-accepted for
advancing to the rendered sample stage; the rendered-sample preview was
validated and accepted on 2026-10-23
([acceptance record](../../playtest/TOWN_LOADOUT_SAMPLE_ACCEPTANCE_20261023.md))
— shipped-town integration is pending, and nothing is integrated into the
shipped town.**
The independent pine package has its own parent-accepted common pack
(2026-10-22, pine section below) and its parent-accepted compact-base v02
assembly install (2026-10-22, pine v02 section below); they touch no Loadout
layer.
Each section documents the reviewed processing of retained raw sources; no
raw file was modified and its hash still matches
[PROVENANCE.md](PROVENANCE.md).

## Two source spaces (one transform per space, never mixed)

The sample's layers come from two different coordinate spaces, each with its
own locked uniform normalization; neither recipe is applied to the other
space's sources:

| Space | Sources | Locked transform |
| --- | --- | --- |
| candidate-01 raw space (1340x1174 stylized-concept output) | `loadout_common_candidate_01.png` | 155/24, window origin (227,715) -> (59,128) — checkpoint 1 |
| guide-edit space (both 1341x1173 precise-object-edit outputs against the packed 256x224 calibration guides) | `loadout_upper_candidate_01.png` (roof), `loadout_upper_candidate_02.png` (roof-off) | 419/80, window origin (209,668) -> (41,129) — checkpoint 2 |

The guide-edit normalization is **one shared transform for both upper
states** (full and revealed), applied unchanged to each; there is no
independent per-state fitting in either space.

Reproduce from the repository root in the approved portable environment:

```bash
source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
source scripts/project_env.sh
python3 -I -m unittest discover -s tools/art_pipeline/p1_town_modular_v01/tests
python3 -I tools/art_pipeline/p1_town_modular_v01/build_common.py
python3 -I tools/art_pipeline/p1_town_modular_v01/make_guides.py
```

## Checkpoint 1: measured source geometry (candidate 01, 1340x1174)

All measurements are threshold-named and read-only
(`inspect_geometry.py`, `measure_families.py`, `measure_features.py` in
`tools/art_pipeline/p1_town_modular_v01/`; raw JSON retained under
`build/current/p1-town-modular-v01/checkpoint-1/`).

At alpha >= 128 the drawn object is a **single 4-connected component**
(279,215 px, bbox px (227,715)-(1113,1036)); there are no stray opaque specks
to remove. The nonzero-alpha halo that spans the canvas is entirely below the
threshold and disappears in packing. Vertical structure by row-family
composition:

| Source rows | Logical y | Content |
| --- | --- | --- |
| 715..726 | 136.4..138.6 | snow lip (snow-family 45-99% of opaque px) |
| 727..737 | 138.8..140.7 | under-lip plate shading (timber + blue-gray mix) |
| 738..983 | 141.0..187.5 | dark timber wall body |
| 984..1036 | 187.7..197.7 | blue-gray stone/snow footing band (blue-family 13-70%) |

Wall columns (>= 50% coverage over wall rows): x 235..1105 (871 px); their
center x=670 is exactly logical 128.0 — the facade is already centered. The
alpha >= 128 extent is 3.4% off the spec rectangle's aspect (169.5 x 61.4
logical vs 128 x 48), so no uniform scale can hit every spec edge; the choice
below is documented with its alternatives.

## Locked transform (build_common.py RECIPE)

- Uniform nearest-neighbour scale **s = 155/24 ≈ 6.458333** source px per
  destination px, applied identically to both axes. Integer-exact:
  `src = origin_src + ((2*(d - origin_dst) + 1) * 155) // 48`.
- Source window origin **(227, 715)** -> destination origin **(59, 128)**,
  window **138 x 50** px: covers the whole alpha >= 128 extent; nothing is
  cropped away horizontally (the extent's flare rows collapse by sampling, as
  any 6.46:1 nearest-neighbour downscale does).
- Alpha binarization at the named threshold **128**: kept pixels keep their
  source RGB exactly with alpha forced to 255 (the source mass sits at alpha
  250..254); everything else becomes transparent black. No palette
  quantization (4,046 distinct RGBA colors retained; the ~24-color limit is
  not enforced at this checkpoint), no per-pixel color edits, no nonuniform
  stretching, no per-state refitting.

Why this scale: it anchors the **snow lip at rows 128..129** (spec allows at
most 2 px of lip at 128) and the **feet line at y 178** (last content row 177)
exactly, keeping the roof seam and ground contact authoritative, at the cost
of a facade 9 px wider than the 128 px band. Alternatives, for the parent's
explicit review if a different trade-off is preferred:

| Option | Scale | Exact wins | Deviation |
| --- | --- | --- | --- |
| chosen (seam-anchored) | 155/24 | lip 128..129, feet 178, center 128 | facade 137 px wide (x 59..195), ~4.5 px/side beyond x 64..192 |
| fit-width | 871/128 ≈ 6.805 | facade exactly x 64..192 | height 45.6 px, wall top ≈ 132.4 (2.4 px seam gap under eaves) |
| fit-height | 322/48 ≈ 6.708 | y 130..178 exactly (48 rows incl. lip) | facade 132 px wide; wall top ≈ 133.4 |

## Outputs (exact paths)

| Path | Size | SHA-256 |
| --- | --- | --- |
| `art/production/p1/town_modular_v01/loadout_common.png` | 256x224, 17,687 B | `8e734c20497e306110c53b05469059e64780d68e1f65701637cc148ceb95af78` |
| `art/production/p1/town_modular_v01/manifest.json` | recipe + facts | recorded beside the artifact |
| `build/current/p1-town-modular-v01/checkpoint-1/loadout_common_review_4x.png` | 3072x896, 41,779 B | `90c909147c50bcc39657764f3e1d2203c9c212eed66ef4da8947378796144cd6` |
| `build/current/p1-town-modular-v01/checkpoint-1/loadout_roof_guide_256x224.png` | 256x224, 18,285 B | `b16c8f8cd338b553b0d094e014c70361cd77adc6c54bea68fd7bfee1f45367bf` |
| `build/current/p1-town-modular-v01/checkpoint-1/loadout_stubs_guide_256x224.png` | 256x224, 17,737 B | `65bc0de03c0df16d298c72b492cadfd4dc8730b7719ee96211404bdc6b4d756d` |

The production PNG and manifest are the only repo-tracked outputs; the
review sheet and guides are ignored `build/` outputs. **Determinism**: a
second full run (retained under `checkpoint-1/run2-art/` and
`checkpoint-1/run2-guides/`) produced byte-identical PNGs — all three guide
hashes and the common layer hash match exactly; the manifests differ only in
the recorded output path.

Review sheet: the common layer enlarged 4x nearest-neighbour over neutral
gray, white, and black panels (brief section 6 fringe/contamination check —
no painted labels or borders). The guides are FIXED 256x224 canvases:

- **Roof guide** — the packed common layer with the greybox upper silhouette
  polygon [(40,128),(76,48),(180,48),(216,128)] rasterized underneath in the
  greybox plank banding (`(y-32) % 12 > 1` -> `#81584e` else `#a0775d`, rows
  48..127). The parent edits this with imagegen to produce the roof (`upper`)
  layer: roof only, facade pixels unchanged, eaves meeting the snow lip at
  y 128..130, ridge y 48, nothing above y 48 or inside the 8 px margin.
- **Stubs guide** — the common layer plus only the low corner stubs from the
  greybox revealed state shifted +32: caps rect (62,114,10,4) and
  (184,114,10,4) in `#a0775d`, posts rect (64,116,6,14) and (186,116,6,14) in
  `#887052`. This marks where the roof-off structure sits for the later
  revealed edit; it is not the roof request input.

Guide geometry is author-defined spec geometry rasterized in code; no
substitute generated artwork was drawn.

## Packed-layer facts (manifest measurements)

- Occupied bbox **(59,128)-(195,177)**; 6,748 opaque px; alpha values {0,255}
  only; no empty columns inside the span; lip width 106 px at row 128
  (tapered snow), full 137 px from row 129.
- Invariants asserted by the build: canvas exactly 256x224; binary alpha; no
  content above y 128, below row 177, or inside the 8 px edge margin
  (x 59..195 within [8,248), y 128..177 within [8,216)).
- Wall-top plate band lands at y 134..137 with dim under-lip shading at
  130..133: the spec's hard wall top y 130 appears as a 3-4 px soft
  transition under the eaves instead. The roof silhouette in the guide
  reaches down to y 127/128 and the real lip occupies 128..129, so the two
  layers meet with no gap at the seam.

## Decorative deviations (measured after the transform, reported not forced)

Draft rectangles are guides, not collision contracts; nothing below was
distorted to force a match.

| Feature | Draft (spec) | Measured in packed layer |
| --- | --- | --- |
| Facade band | x 64..192, y 130..178 | x 59..195 (137 px, centered ~128), content y 128..177 |
| Snow lip | <= 2 px at 128..130 | rows 128..129 (2 px) |
| Door | (115,142,26,36) | dark opening x 116..139, y 140..177 (24 x 38) with amber seam column x 119..128, y 141..176; bottom exactly at feet, centered ~127.5; 2 px narrower and starting 2 px higher than draft |
| Left window | (72,140,28,20) | frame ~x 75..101; single pane x 81..95, y 145..154; snow sill y 153..155; shutter panel below to y 168 |
| Right window | (156,140,28,20) | frame ~x 153..179; two 7-px panes x 159..165 / 167..173, y 145..154 with mullion; snow sill y 154..155; panel below to y 169 |
| Footing | narrow gray stone footing | blue-gray snow/stone band y 170..177 with amber light pooling at the door base (row 176) |

Windows sit ~3-5 px lower and narrower than draft and are not
mirror-symmetric (one pane left, two panes right); the door is very close to
draft. All deviations are within the parent's stated tolerance for review.

## Checkpoint 2: generation-stage normalization (build_upper.py RECIPE)

The parent's two guide edits (roof, roof-off) are in **guide coordinate
space** — the packed native 256x224 calibration sprite, enlarged by the
generator — so the checkpoint-1 candidate-01 transform (155/24, origin
(227,715)) does **not** apply. Both raws share one 1341x1173 canvas
(5.23828x / 5.23661x of 256x224 — measurably non-uniform by 0.03%, so the
actual dimensions are accounted explicitly below, not assumed to be a clean
5.25x). One shared transform normalizes both; no independent per-state
fitting, no nonuniform stretch.

- Uniform nearest-neighbour scale **s = 419/80 = 5.2375** source px per
  destination px, applied identically to both axes and both raws. Derived
  from content anchors: raw ridge row 249 -> y 48 and raw eaves plane-bottom
  row 668 -> y 128 (419 raw px over exactly 80 native rows); cross-checked
  against both canvas ratios (5.23828 / 5.23661, each within 0.04%).
- Window origin: **src (209, 668) -> dst (41, 129)** — the raw left
  roof-plane corner column and the eaves plane-bottom row anchor the seam.
  Integer-exact: `src = 668 + ((2*(d - 129) + 1) * 419) // 160` (and
  likewise x), so the first sampled index per axis is 670 / 211; source
  indices outside the raw canvas stay transparent.
- Alpha binarization at **128** (both raws' opaque mass sits at alpha
  250..254); kept pixels keep source RGB exactly, alpha forced to 255.
- **Seam cut (authored calibration, for parent review):** both layers keep
  native rows **<= 130** only — the spec seam band y 128..130. For `full`
  this discards the generator's hanging eaves-snow below the seam (raw rows
  ~681..695, about 3 native rows of overhang) together with the edited
  facade; the kept rows 128..130 carry the wide eaves snow meeting the
  common's lip with **no gap** (verified per column). For `revealed` it
  trims the post bottoms where they meet the edited plate, so the posts end
  standing on the accepted common's lip/plate at y <= 130.
- The accepted `common` layer is never rebuilt: `build_upper.py` pins its
  SHA-256 and re-verifies it at every run (still
  `8e734c20497e306110c53b05469059e64780d68e1f65701637cc148ceb95af78`).
- `shadow.contact` is authored in code, never generated: cold slab
  (26,32,46), outer rect (68,176,128,8) at alpha 56 plus core rect
  (70,177,122,5) at alpha 104 — one base level plus one dither step, offset
  lower-right of the footprint. Collision is only the authored polygons;
  never derived from alpha.

Reproduce (also runs the tests first):

```bash
source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
source scripts/project_env.sh
python3 -I -m unittest discover -s tools/art_pipeline/p1_town_modular_v01/tests
python3 -I tools/art_pipeline/p1_town_modular_v01/build_upper.py
```

## Checkpoint 2: outline and structural deviations (measured, not forced)

Roof plane vs the authoritative silhouette polygon (from the manifest's
outline rows; see `loadout_roof_outline_compare_4x.png`, cyan = packed edge,
magenta = polygon, white = coincide):

| Row | Polygon span | Packed span | Deviation |
| --- | --- | --- | --- |
| 48 (ridge) | 76..180 | (empty at 48) first content row 49 | ridge 1 px below spec; nothing above y 48 |
| 60 | 70..186 | 73..183 | inset ~3 px per side |
| 80 | 61..195 | 64..193 | inset 3 / 2 px |
| 100 | 52..204 | 55..202 | inset 3 / 2 px |
| 120 | 43..213 | 45..212 | inset 2 / 1 px |
| 127 | 40..216 | 42..215 | inset 2 / 1 px |
| 128..130 (eaves/overhang) | — (below polygon) | 41..216 | eaves snow meets the lip; corners within 1 px |

The drawn roof is slightly steeper/narrower than the polygon (the parent's
"roof edges a few logical pixels"); the eaves converge to within 1 px of the
corners and the seam join is gap-free, so it was kept as drawn — no
stretching, no per-state refit.

Revealed state: two posts at x 64..72 / 186..194 (spec caps 62..72 /
184..194, posts 64..70 / 186..192 — the drawn posts read at ~9 px wide, cap
flare on top), rows **122..130** against the requested 114..130: ~8 px
shorter, the "two short posts" the parent already saw and accepted for this
stage. Central bay transparent (asserted: all revealed content confined to
x 60..74 / 182..196). No stray content above the stubs anywhere in either
raw.

## Checkpoint 2: outputs (exact paths)

| Path | Size | SHA-256 |
| --- | --- | --- |
| `art/production/p1/town_modular_v01/loadout_upper_full.png` | 256x224, 32,451 B, bbox (41,49)-(216,130), 11,316 opaque px | `03c8ccc7a86e24c816d9bcca13630d3ba74cdd329cb2cec33416423b3a4ee86f` |
| `art/production/p1/town_modular_v01/loadout_upper_revealed.png` | 256x224, 982 B, stubs (64,122)-(72,130) and (186,122)-(194,130), 159 opaque px | `88681a92f18abda809c83d7422702458a5d96b7a37f762c812fe6076aa7ebde7` |
| `art/production/p1/town_modular_v01/loadout_shadow.png` | 256x224, 371 B, bbox (68,176)-(195,183), alpha 56/104 only | `75b6c9cfea866a3dd1a2aaed6cc7b8140f4120db05fc320e628a7f3994c4a6d2` |
| `art/production/p1/town_modular_v01/manifest_upper.json` | recipe + facts | recorded beside the artifacts |
| `content/environment_objects/town_loadout_v01.tres` | mechanical definition | part ids `common`, `upper` (revealed + mask = `upper_full` itself), `shadow.contact`, footprint (64,134)-(192,178), envelope (58,128)-(198,184), socket `door.service` (128,196) id `loadout` |
| `build/current/p1-town-modular-v01/checkpoint-2/loadout_assembled_review_4x.png` | 4096x896: full composite, revealed composite, mask, shadow | `89b26ec997cee7796d8a480ad964796db6940cd6df4393bdc95d205bc7671770` |
| `build/current/p1-town-modular-v01/checkpoint-2/loadout_upper_isolated_4x.png` | 3072x1792: full + revealed over gray/white/black | `fcb937f2b1bf201d8b6ee1d60b15176cedcaac1314bab01acfe148b9947637c4` |
| `build/current/p1-town-modular-v01/checkpoint-2/loadout_roof_outline_compare_4x.png` | 1024x896 outline overlay | `4bc8ee98d1c395c2ee11ef71ff580421c5c3f2ea7ef58b3dfe97b54c74de7f47` |

Invariants asserted by the build: both upper layers exactly 256x224 with
binary alpha; nothing above y 48, below y 130, or inside the 8 px margin; no
empty row inside either content band; revealed content confined to the stub
bands; shadow restricted to its two authored alpha levels with exact pixel
counts. The `.tres` was authored against the
`environment_object_definition.gd` / baker / placement sources (paths,
anchors, sort ranks, layer names, socket fields all cross-checked; the
hearthside facility entry parity holds); `validate()` itself has not been
executed — the parent runs the preview `--definition=` mount before any
runtime acceptance. **Determinism**: a second full run (retained under
`checkpoint-2-run2/`) produced byte-identical PNGs for all three layers and
all three review sheets; `manifest_upper.json` differs only in the recorded
output paths.

## Parent visual acceptance (checkpoint 2, 2026-10-22)

The parent visually reviewed the three checkpoint-2 sheets (exact files, with
the hashes above pinning what was seen):

- `build/current/p1-town-modular-v01/checkpoint-2/loadout_assembled_review_4x.png`
- `build/current/p1-town-modular-v01/checkpoint-2/loadout_upper_isolated_4x.png`
  (all gray/white/black panels)
- `build/current/p1-town-modular-v01/checkpoint-2/loadout_roof_outline_compare_4x.png`

Verdict, recorded as decided: **roof/facade seam clean; the outline's slight
inset and the cropped eaves overhang are accepted for the sample stage; the
short stubs are preferred for a clear central bay; no regeneration needed.**
The parent also re-ran all 30 synthetic tests (actual PASS) and read the
`.tres`. Scope of this acceptance: **advancing to the rendered sample ONLY.**
In-engine validation (`validate()` / the preview `--definition=` mount) and
shipped-town integration remain pending; no acceptance of runtime behavior
is claimed. The roof and stubs are accepted as drawn — with their measured
deviations above — not as spec-pixel-identical geometry.

## Pine common pack (pine checkpoint 1, 2026-10-22)

First independent package after the Loadout sample
([PINE_SPEC.md](PINE_SPEC.md)); one new source space, one locked uniform
transform, and no Loadout source or layer involved.

Source: `sources/pine_common_candidate_01.png` (1024x1536, exactly 2:3 -
the generator kept the 96x144 design canvas grid). Locked transform in
`build_pine.py` RECIPE: ONE uniform nearest-neighbour scale **exactly 32/3**
source px per design px over the whole canvas, origin (0,0) -> (0,0); no
content-anchor refit is needed or applied. Integer-exact sampling:
`src = ((2*d + 1) * 32) // 6`. Alpha binarization at the named threshold
**250**: the raw contains no alpha-255 pixel (its opaque band is 250..254),
and the 200..249 edge fringe plus the broad alpha <= 31 halo wash are
discarded wholesale - the halo the parent saw is absent from the packed
layer on every review background. No raw pixel is altered.

Measured (recorded calibration; extents, component count, trunk center and
the flare ratio are asserted on every run): single 4-connected component,
1843 design px, bbox x27..x68 y47..y138; trunk center column 48.0 at y80
(anchor contract (48,128) holds); trunk band 20 occupied columns vs root
band 40 - a genuine flare separation with the snow family present in the
root band; zero warm-amber pixels (one-off QC measurement). Deviations vs
the guide flats, reported as drawn and never clipped or re-fitted: trunk
top y47 vs spec y56 (9 px upward, fully behind the reserved canopy disc
rows y5..y90), feet y138 vs y140 (2 px high), widest stub rows 1 px left
(x27/x33 vs x28/x34); stub bands merge with the trunk into continuous
unions matching the guide unions within that 1 px.

Output: `art/production/p1/town_modular_v01/pine_common.png` (96x144,
binary alpha, 6498 bytes), SHA-256
`7aa70586ccd908d50ce97451534ff8f1f37c433ba3b9e72e13a7c2f8f50333a2` -
pinned in `build_pine.py` and re-verified on every build; the pack, review
sheets (1x triple-background and 4x with a marked guide/disc/bbox panel)
and manifest are byte-identical across double runs under
`build/current/p1-town-modular-v01/pine-checkpoint-1/`.

Parent visual acceptance (2026-10-22), recorded as decided and scoped to
the common layer for sample assembly: readable bark, branch stubs and
roots; halo absent on gray/white/black; the 9 px upward trunk top accepted
because the canopy covers it; the 2 px high feet and 1 px left drift
accepted - **as drawn, with the measured deviations above, not as
pixel-identical guide geometry.** Canopy, shadow and definition remain
pending: request B runs against the stage-2 guide
`pine_canopy_guide_96x144.png` (the accepted common with the reserved
canopy disc composited on top, built by `make_pine_guides.py`, which also
verifies the pinned common hash), and no canopy art has been generated.

Reproduce from the repository root in the approved portable environment:

```bash
python3 -I tools/art_pipeline/p1_town_modular_v01/build_pine.py
python3 -I tools/art_pipeline/p1_town_modular_v01/make_pine_guides.py
```

## Pine v02 compact-base assembly: accepted install (2026-10-22)

The parent visually reviewed the assembly 2x, common 4x and hero 2x sheets
and **accepted the assembly AS DRAWN for the rendered sample stage**:
compact base with its measured drift (top y94, feet y135 — 2 px above B's
y137), canopy meeting the cut row y96, no halo, and the hero head/upper
body legible behind the 25% canopy state. This acceptance is **static art
scope only — not engine/native acceptance**, and it was recorded without
any fulltownpass run; the mask/revealed acceptance framework is superseded
for these layers by the primitive-fade policy (the fading layer's own
alpha plus occlusion volumes), recorded as historical.

Installed at the runtime art paths by `build_pine_v02.py`, hashes verified
on write and byte-identical across double runs:

| Layer | Path (under `art/production/p1/town_modular_v01/`) | SHA-256 | Provenance |
| --- | --- | --- | --- |
| common v02 | `pine_common_v02.png` (96x144, 2696 B) | `815160150d4142c138ac0a789d68564d07e7565290d0fd4f995854fec8083392` | request C raw `sources/pine_common_v02_candidate_01.png` (`e2fd8701...`), same locked whole-canvas uniform 32/3 nearest transform, alpha binarized at 250 |
| canopy v02 | `pine_canopy_v02.png` (96x144, 13483 B) | `93833b1f79bcc5d4609f9078d15e0486a2190d9c7de07ff73fa7f41cd27947c0` | B upper region (pack `e32faebb...`) cut at its measured crown bottom row y96; B's trunk rows discarded wholesale — an explicit redesign cut, never a transfer of the tall v01 common |
| shadow v02 | `pine_shadow_v02.png` (96x144, 215 B) | `061aa4f895e0a1768a5855cb4b201a5295a4e8d2295ccacee1e4d6273222c42b` | **code-authored** (deterministic constants in `build_pine_v02.py`: slab x36..x68 y133..y139 with 1 px chamfered corners, 200 px at alpha 56 plus a 27 px trunk-contact dither at 104, RGB (26,32,46) sampled from the accepted `loadout_shadow.png` family); no generator involved |

Measured calibration (asserted every run): single component, 653 design
px, bbox x33..x63 y94..y135, trunk center column 47.5 at y112, flare
x33..x63, zero opaque pixels at or above y90 (the flat green guide mass
was removed cleanly). Seam: base top y94 overlaps the crown cut y96 on
rows y94..y96; rows y97+ are base-only by construction (no duplicate
trunk from B).

Two new definitions were authored under the explicit primitive-policy
interface (pending **ca** validation; the engine was not run):
`content/environment_objects/town_pine_v02.tres` (asset
`town.pine.v02`; common `reveal_policy="none"`, upper
`reveal_policy="primitive_fade"` with occlusion volume polygon
(48,8)-(91,97)-(8,97); anchors (48,128) ranks 0/1; footprint circle r10;
movement envelope circle r14 with part_id `envelope` per the preview pine
contract; `shadow.contact` ground part) and
`content/environment_objects/town_loadout_fade_v01.tres` (asset
`town.loadout.fade.v01`; a fade-policy sibling of `town_loadout_v01.tres`
copying its accepted art, geometry, sockets and anchors, with the upper's
`mask_path`/`revealed_path` removed and `reveal_policy="primitive_fade"`
over a rectangle covering the full upper measured bound (41,49)-(216,130)).
In the ca schema, `"none"` is an explicit valid policy (a solid base that
never enters the legacy silhouette fallback), so it is written literally
on both commons. `town_loadout_v01.tres` and all v01 runtime art
(`pine_common.png` `7aa70586...`, the four loadout layers) are unchanged.

Hero-readability sheets were corrected and rebuilt after the parent's
review note: the ACTUAL hero collision radius is 6 (not the 4 previously
approximated), so the preview layout (envelope r14) uses legal distance
21 (north feet (80,123), diagonal (95,129)) and a separately labelled
native-layout proposal uses the existing native circle r8.5 at distance
15 (north (80,129), diagonal (91,133)). Both rows are labelled in the
sheets; the native row documents the preferred preserve-native-movement
option (replacing the native circle with r14 would block T26) and is
visual positioning only — NOT collider authorization.

Reproduce from the repository root in the approved portable environment:

```bash
python3 -I tools/art_pipeline/p1_town_modular_v01/build_pine_v02.py
```

## Next steps

1. In-engine preview validation completed 2026-10-23 (63/63 checks; see the
   [acceptance record](../../playtest/TOWN_LOADOUT_SAMPLE_ACCEPTANCE_20261023.md)):
   the preview's `-- --definition=res://content/environment_objects/town_loadout_v01.tres`
   mount loaded this definition at placement (148,148) with no runtime,
   baker, or preview edits.
2. Shipped-town integration and the final contact render come after that;
   the authoritative geometry (footprint, envelope, anchors, socket) is
   already exact in the definition, and decorative trade-offs were settled
   by the acceptance above.
3. Pine v02: ca schema/engine validation of `town_pine_v02.tres` and
   `town_loadout_fade_v01.tres` is pending; the engine was not run for
   them. The accepted static scope above was recorded without a
   fulltownpass run — the new-policy supersession is documented, not
   re-proven across the town.
