# Pine Sample Specification (first independent package after Loadout)

Current integration update, 2026-10-23: the visual-quality pass replaces the
v02 canopy's narrow triangular condition with a conservative local box
`(5,4)-(95,101)`. A real-input outer-bough capture showed visible foliage over
the hero while the old triangle reported only 2.7% coverage and stayed closed.
The bitmap layers and their packing recipes are unchanged. The native south
trunk now uses radius 14, matching the sample envelope; the previous native
r8.5/T26 positioning sheets below remain historical art evidence. A former
stand inside the enlarged blocker is deliberately no longer legal. Rendered
acceptance of this revision is recorded separately from the original package.

Date: 2026-10-22. Status: **v02 assembly parent-ACCEPTED AS DRAWN for the
rendered sample stage (static art scope only - not engine/native
acceptance; recorded without a fulltownpass run) and INSTALLED:
`pine_common_v02.png` (compact base, request C), `pine_canopy_v02.png`
(B crown cut at y96) and the code-authored `pine_shadow_v02.png` at
`art/production/p1/town_modular_v01/`, hashes pinned. The definitions
`content/environment_objects/town_pine_v02.tres` and
`town_loadout_fade_v01.tres` are authored under the primitive-fade policy
interface - **ca validation pending; the engine was not run.** v01 art and
definitions are preserved unchanged. The mask/revealed pair is superseded
(primitive fade via the upper layer's own alpha + occlusion volumes).**
This spec is small by design: shared conventions live in the
[delivery brief](../TOWN_MODULAR_ASSET_BRIEF.md) and the
[Loadout sample spec](../TOWN_LOADOUT_SAMPLE_SPEC.md); this file adds only
the pine-specific contract. Ground completion stays separate critical
integration work and is not finished by this package.

Owned files for this package: `tools/art_pipeline/p1_town_modular_v01/make_pine_guides.py`,
`build_pine.py`, `build_pine_upper.py`, and `build_pine_v02.py`, this spec,
and outputs under the ignored
`build/current/p1-town-modular-v01/pine-checkpoint-1/`. Accepted
Loadout art, recipes, tests, runtime, preview, and plan are not edited.

## Policy revision (2026-10-22, parent-directed)

The latest user direction: **roof/canopy layers fade; the base stays
solid.** The installed v01 common is a tall trunk (content y47..y138) that
can hide a whole hero behind an r14 movement collider, so its 2026-10-22
acceptance is understood as **sample-assembly only** and is under new
policy review; the file itself stays installed and unchanged as v01. The
agreed redesign is an EXPLICIT art regeneration - a compact solid lower
trunk/root base beginning around y96..100 (feet line y128 area, root bottom
y138 as drawn) with the canopy extended naturally to meet it around
y96..102 so an approaching hero's head remains readable - never a silent
repartition that moves opaque common pixels into a fading layer. Physical
base readability is the goal; pixel-exact silhouette matting is not
required.

## Geometry contract (parent-fixed, greybox parity)

Adopted from the greybox tree in `tools/modular_town_preview.gd` (the brief's
"about 96x128" is superseded by the calibrated 96x144 greybox canvas).

| Element | Value |
| --- | --- |
| Canvas | 96x144, one design pixel = one art pixel |
| Parts | `common` (rank 0), `upper` (rank 1), both sort anchor (48,128) |
| Footprint | circle center (48,128) radius 10 (raster rows y118..137) |
| Movement envelope | circle center (48,128) radius 14 (raster rows y114..141), **final**; the resolver adds the hero radius itself, never twice |
| Shared placements | (480,210) and (650,300) -> world centers (528,338) and (698,428) |
| Sockets | none; trees are not facilities |
| Proposed asset_id | `town.pine.v01` (definition authored only after art acceptance) |

## Layer contract

| part_id | Content |
| --- | --- |
| `common` | **v02 (policy revision):** compact solid lower trunk/root base - finished broken top around y96..100, trunk x40..x55, flare x31..x64, feet at the root band - the layer that stays opaque. (Historical v01: full tall trunk y47..138, installed and preserved unchanged but accepted for sample assembly only.) |
| `upper` | One single coherent snowy pine crown from the reserved disc down to the meet band y96..102, where it settles over the base top; drawn as one mass with the trunk in one sprite (candidate B) and cut from it. **Supersedes the full/revealed pair:** the primitive fade uses this layer's own alpha plus a fade volume - no revealed variant and no separate mask file are needed (the historical rows below are kept for the record). |
| `upper` (revealed) - HISTORICAL, superseded 2026-10-22 | Empty-file pattern from the pre-fade design; a fading upper makes a revealed variant unnecessary. |
| mask - HISTORICAL, superseded 2026-10-22 | The upper file's own alpha is the fade source; no separate mask file. |
| `shadow.contact` | Authored and installed 2026-10-22 (`pine_shadow_v02.png`, code-authored - never generated, never a cutout): flat cold translucent slab RGB (26,32,46) at the feet band (x36..x68, y133..y139, 1 px chamfered corners), offset lower-right, alpha 56 plus a 27 px trunk-contact dither at 104 (the measured `loadout_shadow.png` family), GroundEffects layer. |

Art direction: native 1:1 pixel density; cold gray-blue snow, dark
weathered timber/charcoal; **no amber on the tree** (it is not a light
source); due-south parallel projection with slight downward view, subtle
upper-left illumination, matching the accepted Loadout sample.

## Guide calibration regions (authored, code-rasterized, exact)

`make_pine_guides.py` rasterizes these flats; anchor, envelope, footprint,
and reserved-disc marks exist only on the review sheet's marked panel and
never enter an imagegen guide.

| Region | Extent | Guide flat |
| --- | --- | --- |
| Trunk | x42..54, y56..138 (13 px, symmetric about x48) | #887052 |
| Root band | x36..60, y130..140 | #a0775d |
| Upper stub pair | x34..44 and x52..62, y58..63 | #81584e |
| Lower stub pair | x28..46 and x50..68, y68..73 | #81584e |
| Reserved canopy disc | center (48,48) radius 43 -> rows y5..y90, widest x5..x90 | #4f6e5a |

Every stub row sits fully behind the reserved disc (disc spans x13..82 at
y73, x8..87 at y63), so the full state hides all branch stubs and the
revealed state exposes a complete trunk remnant. Greybox deviations are
recorded, not silent: greybox trunk x43..52 y52..136, one branch x30..65
y66..71, flare x38..57 y132..137; the pine regions above are authored
calibration derived from them.

## Generator limits read from prior work

Root-only `image_gen`; no model identifier exposed; use cases
`stylized-concept` / `precise-object-edit` with `transparent_background=true`
and `referenced_image_paths`. Outputs can return upscaled with slight aspect
non-uniformity (Loadout: 1341x1173 for an 8:7 guide, about 0.03%) and edits
can bleed outside the target region (Loadout facades were discarded at the
seam cut). One generator stage per variant. Pixel-exact generator output is
never promised: each pack derives ONE recorded uniform nearest transform per
source space from content anchors, cross-checked against the canvas ratio
(actual dimensions accounted explicitly), applies it unchanged to every
state sharing that space, and measures and reports deviations instead of
forcing them. Both requests below use `precise-object-edit` of fixed
guides - the flow that behaved best in the Loadout upper stage.

## Request templates (proposed, NOT executed)

Executed requests will be recorded verbatim in
[PROMPTS.md](PROMPTS.md) with their raw sources at run time.

### Request A - common (reference: `pine_common_guide_96x144.png`)

```text
Use case: precise-object-edit.
Edit target: the supplied 96x144 transparent pine calibration sprite. This is a pixel-art game tree split into reusable layers; this request draws ONLY the lower common layer.
Change ONLY the flat guide shapes (trunk column, root band, four low branch stubs) into finished dark weathered timber: a complete slightly tapering pine trunk with readable bark from y56 down to the root band, a wide root flare with snowy ground contact along the feet line, and short cut branch stubs exactly where the guides are. Keep their exact positions and sizes in logical canvas pixels: trunk x42..54 y56..138, root band x36..60 y130..140, upper stubs x34..44 and x52..62 at y58..63, lower stubs x28..46 and x50..68 at y68..73. The trunk top at y56 is intentionally hidden later by the canopy; end it in plausible cut or branched structure, not a floating square edge.
Everything above the branch stubs must remain completely transparent: no canopy, foliage, needles above the stubs, second tree, ground plane, streets, people, props, animals, text, frame, grid, guide marks or watermark. No cast shadow or ambient-occlusion halo outside the sprite; the contact shadow is a separate later layer.
Materials: dark weathered timber browns and charcoal, cold gray-blue snow patches on the root band and stub tops. No warm amber light on the tree; the tree is not a light source. Subtle upper-left illumination only. Crisp deliberately chunky low-resolution pixel clusters, roughly one logical pixel per native design pixel, consistent with the accepted snowy storehouse sample. Parallel projection, camera due south with slight downward view: vertical trunk, horizontal feet line, no perspective convergence.
INVARIANTS: the whole 96x144 logical canvas with wide transparent margins is locked; genuine alpha everywhere outside the sprite; the object uncropped, including the full root band. If output is larger, scale the entire canvas uniformly with crisp nearest-neighbor pixel blocks and keep every listed coordinate in the logical grid.
```

### Request B - upper/canopy (reference: `pine_canopy_guide_96x144.png`, built 2026-10-22 from the accepted common - see the stage-2 note below)

```text
Use case: precise-object-edit.
Edit target: the supplied 96x144 transparent pine calibration sprite (finished trunk, roots and branch stubs below; one flat canopy guide shape above). This request draws ONLY the upper canopy layer.
Change ONLY the flat guide canopy silhouette into a finished snowy pine canopy: a dense dark needle crown in cold blue-green tones with layered bough edges, thick off-white snow clusters on upper surfaces and cold slate-blue shadow sides. One single coherent crown mass with no floating leaf scraps or disconnected islands, settling over and visually merging with the trunk top it covers. Keep the overall silhouette inside the guide disc: center (48,48), radius 43, i.e. rows y5..y90 and never wider than x5..x90.
Materials: cold blue-green needles, off-white snow, slate-blue shadow tones; no warm amber light. Subtle upper-left illumination, same camera and pixel density as the finished trunk below.
INVARIANTS: the complete existing trunk, root flare and branch stubs must remain identical in design, size, color and position; only pixels inside the canopy guide region may change. The 96x144 canvas, transparent margins, camera, scale and origin are locked. No ground, cast shadow, trunk repaint, animals, people, text, frame or watermark. If upscaled, scale the entire canvas uniformly with crisp nearest-neighbor pixel blocks.
```

Tool settings for both: `image_gen` precise-object-edit,
`referenced_image_paths=[<guide path from pine-checkpoint-1>]`,
`transparent_background=true`; no model identifier exposed.

## QC criteria

Mechanical (tools; applied to raws read-only and to packed outputs):

1. Raw retention: verbatim copy, `cmp`-identical, SHA-256 and canvas
   recorded before inspection.
2. Pack: one uniform nearest transform per source space from content
   anchors (common: trunk edge columns + feet band; upper: disc widest row,
   top row, anchor column), cross-checked vs canvas ratio; integer-exact
   destination sampling; binary alpha at a recorded threshold;
   out-of-canvas source samples transparent.
3. `common`: exactly 96x144; opaque content confined to y56..y140; per-band
   spans within a recorded tolerance of the guide rects (target 3 px,
   measured and reported, never clipped to force a pass); no fully
   transparent row across the trunk width between y56 and the root band.
4. `upper` full: exactly 96x144; silhouette inside the reserved disc +3 px;
   a single connected opaque component (flood fill; zero floating islands);
   in the full state the canopy covers the trunk top on every trunk column
   (no gap row at the seam). Any generator bleed below the disc is
   discarded at the disc cut, exactly like the Loadout seam cut; the
   accepted common's hash stays pinned and is re-verified every build.
5. `upper` revealed - HISTORICAL, superseded 2026-10-22: the primitive
   fade (upper alpha + volume) removes the need for an empty revealed
   file; kept for the record of the pre-fade design.
6. Determinism: double-run byte-identical outputs; hashes in the manifest.

Visual (parent): isolated and triple-background sheets; trunk, roots and
stubs read at native scale; canopy is one snowy crown meeting the trunk
with no gap or halo; revealed remnant complete with no floating scraps;
palette family cold snow / dark timber with zero amber; density consistent
with the accepted Loadout; both shared placements sit on complete ground
with no residue or baked shadow.

Policy revision (2026-10-22), superseding parts of criterion 4 above: the
crown bottom now intentionally reaches the meet band y96..102 below the
reserved disc (the disc bound applies to the crown's width and top), and
"zero floating islands" is read as "no large islands" - tiny fringe specks
are measured and reported (upper candidate 01 carries four 1-px specks)
rather than silently matted away.

## Sequence

1. Done (this checkpoint): guides, review sheet, spec, templates.
2. Done 2026-10-22: request A executed once by the parent; raw retained
   byte-identical as `sources/pine_common_candidate_01.png` (SHA
   `b23b9675357c8e305d8a7e7ad4fb00885c432f0f53cf21bdf9dffa3856dde5fb`,
   canvas 1024x1536); provenance in [PROVENANCE.md](PROVENANCE.md),
   verbatim request in [PROMPTS.md](PROMPTS.md).
3. Done 2026-10-22: candidate QC and pack proposal (below) - parent review
   resolved the same day: accepted as drawn (record below).
4. Done 2026-10-22: `build_pine.py` pack installed at the runtime path
   `art/production/p1/town_modular_v01/pine_common.png`, accepted hash
   `7aa70586ccd908d50ce97451534ff8f1f37c433ba3b9e72e13a7c2f8f50333a2`
   pinned and re-verified on every run.
5. Done 2026-10-22: `make_pine_guides.py` stage 2 (verifies the pinned
   common) -> `pine_canopy_guide_96x144.png`; request B executed by the
   parent the same day.
6. Done 2026-10-22: upper raw retained; full-tree uniform pack proposal,
   seam/common risk assessment and the compact-base v02 guide + request C
   proposal (below) - awaiting parent review under the policy revision.
7. Done 2026-10-22: request C executed by the parent; raw retained
   (`sources/pine_common_v02_candidate_01.png`, SHA
   `e2fd870180d40b514d1558bd5949ff7efae991add5e664dc7d76cb71d5d3aadf`);
   compact-base QC, canopy cut and bounded assembly proposal (below) -
   awaiting parent review.
8. Done 2026-10-22: parent acceptance AS DRAWN (rendered sample stage,
   static scope) -> `build_pine_v02.py` installed the accepted v02 base
   (`pine_common_v02.png`, `81516015...`), canopy (`pine_canopy_v02.png`,
   `93833b1f...`) and the code-authored shadow (`pine_shadow_v02.png`,
   `061aa4f8...`) at the runtime art paths (new files; v01 preserved
   unchanged, hash re-verified); the readability sheets were corrected to
   the ACTUAL hero radius 6 with the labelled preview/native layouts
   (record below).
9. Done 2026-10-22 (authored, validation pending): the definitions
   `town_pine_v02.tres` and `town_loadout_fade_v01.tres` were written
   under the explicit primitive-policy interface (common
   `reveal_policy="none"`; upper `reveal_policy="primitive_fade"` +
   occlusion_volumes; no revealed/mask fields). **ca owns the schema and
   the engine: ca validation is pending and the engine was not run.** The
   accepted static scope was recorded without a fulltownpass run - the
   new-policy supersession is documented, not re-proven across the town.
   Rendered sample waits for an owner-side preview tree mount (the
   current `--definition` mount accepts only the 256x224 Loadout
   contract; `tools/modular_town_preview.gd` is not edited by this lane).

## Candidate 01 QC and pack proposal (2026-10-22; parent review resolved - accepted)

Alpha: no 255 exists; the generator's opaque band is 250..254 (13.33% of
canvas). A 200..249 ring (~12.6k px, about 0.4 design px thick) and a broad
faint wash at alpha <=31 (~17.9k px) form the halo seen in review; the pack
binarizes at 250 and discards both wholesale. No raw pixel is altered.

One uniform whole-canvas nearest transform, scale exactly 32/3, origin
(0,0) -> (0,0): the generator kept the canvas grid (1024/96 == 1536/144),
so no content-anchor refit is needed or applied. Measured packed content:

| Measurement | Value | vs guide |
| --- | --- | --- |
| Component count | 1 (no floating islands) | - |
| Content bbox | x27..x68, y47..y138, 1843 px | widest rows 1 px left of spec |
| Trunk center column | 48.0 at y80 (span x42..x54) | anchor contract (48,128) holds |
| Trunk band cols (y100..125) | 20 | trunk/root separation genuine: root band 40 cols, snow family present |
| Feet / root contact | y ~130..138 | spec y130..140; 2 px high |
| Trunk top | y47 | spec y56; 9 px upward, fully behind the reserved canopy disc (rows y5..y90) |
| Stub bands | upper x33..62, lower x27..x68 | match guide unions x34..62 / x28..x68 (1 px left) |

These deviations are reported as drawn; nothing is clipped or re-fitted to
force a spec-pixel claim. Proposal outputs (ignored build directory,
deterministic across double runs):
`build/current/p1-town-modular-v01/pine-checkpoint-1/pine_common_candidate_packed_96x144.png`
(SHA `7aa70586ccd908d50ce97451534ff8f1f37c433ba3b9e72e13a7c2f8f50333a2`),
`pine_common_candidate_review_1x.png` (288x144 neutral/white/black),
`pine_common_candidate_review_4x.png` (1536x576 neutral/white/black plus a
marked panel with guide rects, reserved disc, and measured bbox),
`pine_manifest_candidate.json` (recipe, calibration, hashes).

### Parent acceptance - common layer only (2026-10-22)

The parent inspected the native triple-background sheet, the 4x marked
sheet and the manifest, and accepted the packed common **as drawn** for
sample assembly: readable bark, stubs and roots; the halo absent on
gray/white/black; the 9 px upward trunk top accepted because the canopy
covers it; the 2 px high feet and 1 px left drift accepted. The layer is
accepted with its measured deviations above, not as pixel-identical guide
geometry. `build_pine.py` now installs the pack at
`art/production/p1/town_modular_v01/pine_common.png` (96x144, 6498 bytes)
with the accepted SHA-256 pinned and re-verified on every run; the recipe,
deviations and acceptance are also recorded in
[PROCESSING.md](PROCESSING.md) and [PROVENANCE.md](PROVENANCE.md). Scope:
the common layer only - canopy, shadow and definition remain pending.

### Stage 2: canopy guide (2026-10-22)

`make_pine_guides.py` verifies the installed common's pinned hash, then
composites the reserved canopy disc ON TOP of it (the canopy guide region
owns the trunk top it covers, rows y5..y90). Output:
`build/current/p1-town-modular-v01/pine-checkpoint-1/pine_canopy_guide_96x144.png`
(SHA `1dc59fd45842d654ba77cc3684573500a19a64d0de74c43296405b5fe97777a2`,
96x144, 4114 bytes, binary alpha; equals the accepted common plus the
exact disc rasterization, asserted pixel-exact). The review sheet
`pine_guide_review_4x.png` (1536x1728, SHA
`27e4c95e3230ed3f32d6036fde94a6d094bde225eaf6837ae2f7a81a18a66c89`) now
shows three rows: common guide, canopy silhouette, canopy guide. Both
tools are byte-identical across double runs. This canopy guide is the
reference for request B above; no canopy art has been generated.

## Upper candidate 01 QC and pack proposal (2026-10-22, parent review pending)

Request B returned a **complete repainted tree** (crown + trunk + roots in
one sprite), not the reference's v01 pixels: 0 of the 1843 v01-opaque
pixels are identical, 1683 are recolored, 160 are now transparent - the
same repaint behavior the Loadout uppers showed. The raw canvas is again
exactly 1024x1536 (2:3), so the SAME uniform whole-canvas transform applies
(scale 32/3, origin (0,0) -> (0,0), binarize at 250; the alpha structure
matches candidate A: no 255 anywhere, opaque band 250..254). No runtime
asset is written; the v01 common stays installed and pinned.

Measured packed full tree (deterministic, asserted by `build_pine_upper.py`):

| Measurement | Value | Note |
| --- | --- | --- |
| Content bbox | x9..x90, y8..y137, 4695 px | crown top y8 (1-px peak at x48) |
| Components | 1 main mass (4691 px) + 4 specks (1 px each) | specks at the crown's lower fringe, y92..y98; measured, not removed |
| Crown widest rows | x10..x88 (y80..y90) | inside the reserved disc x5..x90 with margin |
| Crown bottom | y96 continuous mass (28-px run); fragments to y98 | 6..8 px below the disc bottom y90 - the intended meet band, not a violation |
| Seam | y96 crown / y97..y98 fragments / y99 clean trunk (x41..x53) | meets the redesign band y96..102 directly |
| Base zone | y99..y137; trunk x40..x55, center col 47.0 at y112 (47.5 over y100..125); flare to x31..x64 | v01 measured 48.0; feet y137 vs v01 138 |

Seam/common risk assessment: the raw already contains the parent-proposed
geometry - crown mass to y96, clean compact trunk y99..y129, root flare and
feet y130..y137 - so the crown and the base come from ONE coherent sprite
and the seam aligns by construction. Taking the base from THIS raw (request
C below) avoids the 0.5 px center drift and full repaint mismatch a v01
crop would create at the seam. Residual risks, reported not forced: the
four 1-px fringe specks (acceptable as drawn or removable at pack time),
the feet 1 px higher than v01, and the trunk center 0.5 px left of the
anchor column - the footprint/envelope stay authored in the definition, so
art-side drift of this size is within the no-pixel-exact policy.

Proposal outputs (ignored build directory, byte-identical across double
runs): `pine_upper_candidate_packed_96x144.png` (SHA
`e32faebbb0dd41d7a2403ff2d8091b19c07ffe4e54e30ef87c9e2e5dfefb43cd`),
`pine_upper_candidate_review_1x.png` (288x144),
`pine_upper_candidate_review_4x.png` (1536x576; marked panel carries the
v01 guide rects, disc/envelope/footprint/anchor marks, the measured crown
bottom line and content bbox), `pine_upper_manifest_candidate.json`.

## Common v02 proposal: compact solid base (2026-10-22, awaiting parent review)

Derived guide (deterministic from the pinned pack above): every opaque
pixel at rows y <= 98 flattened to the crown guide tone (that flat mass
marks what request C must REMOVE), rows y99..y137 kept pixel-exact from the
candidate (the finished trunk, roots and feet it must PRESERVE). Output:
`build/current/p1-town-modular-v01/pine-checkpoint-1/pine_common_v02_guide_96x144.png`
(SHA `f79679ff0a9c3df0bca6eef4eded63f838a11e3ca48c8d5571e6de4052b03e5d`,
96x144, binary alpha; build rule and pin live in `make_pine_guides.py`
stage 3, validated row-exact). The review sheet's fourth row shows it
beside the other guides. Geometry: base top y99 (parent band y96..100),
trunk x40..x55, flare x31..x64, feet y137 - a compact solid base roughly
39 px tall with no invisible huge collider (the r14 envelope is unchanged
and stays authored in the definition).

### Request C - common v02 (short solid base; reference: `pine_common_v02_guide_96x144.png`) - PROPOSED, not executed

```text
Use case: precise-object-edit.
Edit target: supplied 96x144 transparent pine base-guide sprite: one flat green crown-shaped guide mass above a finished timber trunk with root flare and snowy feet below. This request draws ONLY the compact solid base layer (common v02).
Remove the entire flat green upper shape completely - every pixel of it becomes fully transparent, with no residue, scraps or halo. Keep the existing finished trunk, root flare and snowy feet contact EXACTLY as drawn: same positions, sizes, colors and camera, from the cut line at y98 down to the feet at y137..138 in logical canvas pixels.
Then finish the newly exposed trunk top around y96..y100 into a plausible complete short solid tree base: a naturally broken or briefly branched cut where the crown meets the trunk, so the base reads as one self-contained physical stump rather than a floating square edge or a sliced column. Keep it compact: solid timber only within roughly x31..x64, no tall trunk, no canopy, no needles, no second tree.
Materials: the same dark weathered timber, charcoal and cold gray-blue snow as the existing trunk and roots. No warm amber light; the tree is not a light source. Subtle upper-left illumination. Crisp chunky low-resolution pixel clusters matching the existing art.
INVARIANTS: the whole 96x144 logical canvas with wide transparent margins is locked; everything above the finished trunk top must be genuinely transparent; genuine alpha everywhere outside the sprite. No ground plane, streets, cast shadow, ambient halo, people, animals, props, text, frame, grid, guide marks or watermark. If output is larger, scale the entire canvas uniformly with crisp nearest-neighbor pixel blocks and do not zoom the object.
```

Tool settings: `image_gen` precise-object-edit,
`referenced_image_paths=[build/current/p1-town-modular-v01/pine-checkpoint-1/pine_common_v02_guide_96x144.png]`,
`transparent_background=true`; no model identifier exposed. QC intent:
readable physical base and preserved feet contact - not pixel-exact
matting.

## Common v02 candidate QC and bounded assembly proposal (2026-10-22; parent review resolved - accepted as drawn, installed)

Request C returned a clean compact base. Raw retained by the parent,
`cmp`-verified and hash-pinned (`e2fd8701...`, 709073 bytes); canvas
exactly 1024x1536 again, so the SAME uniform whole-canvas transform
applies (32/3, origin (0,0), binarize at 250; alpha structure matches the
earlier pine raws - no 255 anywhere, opaque band 250..254, fringe and wash
below threshold discarded; no halo survives on any review background).
Measured by `build_pine_v02.py` (deterministic, double-run
byte-identical):

| Measurement | Value | vs request C / guide |
| --- | --- | --- |
| Content bbox | x33..x63, y94..y135, 653 px, 1 component | compact, no islands |
| Opaque px at or above y90 | 0 | flat green guide mass removed cleanly; no crown, needles or residue |
| Finished top | broken tips y94..y97 over x39..x55 | guide band y96..100; tips 2 px above, inside the meet band |
| Trunk | x40..x55 at y112 x42..x53, center col 47.5 | anchor col 48; 0.5 px drift reported |
| Flare / feet | flare x33..x63 (y131..134), feet y135 | request said y96..138 / x31..x64; feet 2 px above B's y137 - drift reported, not forced |
| Preservation | 0 of the guide's B-derived base pixels identical (597 recolored, 105 vanished) | full repaint - the known generator behavior |

**Canopy cut (explicit, recorded):** the canopy layer is the B upper
region cut at its measured crown bottom row y96 - everything above is
crown; B's trunk rows are discarded wholesale. This is an explicit cut of
the B candidate consistent with the compact-base redesign, never a silent
transfer of the former tall v01 common (v01 stays installed, hash
re-verified each build).

**Seam QC:** base top y94 overlaps the crown cut y96 on rows y94..y96, so
the seam closes with overlap and no gap row; composite rows y97+ are
base-only by construction, which is the no-duplicate-trunk guarantee
(asserted, not assumed). The canopy carries no content below the cut.

**Bounded assembly proposal (ignored build directory):**
`pine_v02_common_candidate_96x144.png` (SHA
`815160150d4142c138ac0a789d68564d07e7565290d0fd4f995854fec8083392`) and
`pine_v02_canopy_candidate_96x144.png` (SHA
`93833b1f79bcc5d4609f9078d15e0486a2190d9c7de07ff73fa7f41cd27947c0`),
assembled in `pine_v02_assembly_review_1x.png` (384x288) and
`pine_v02_assembly_review_2x.png` (768x576): rows = canopy at full alpha
and at 25% (alpha 64), columns = gray / white / black / flat opaque sample
ground (#90a8c0 snow family, sheet-only tone). C base alone:
`pine_v02_common_review_1x.png` and `pine_v02_common_review_4x.png`
(marked panel carries envelope/footprint/anchor marks, content bbox, the
base-top line y94 and the crown-cut line y96).

**Approximate hero readability (visual composites, NOT engine evidence):**
`pine_v02_hero_readability_1x.png` / `_2x.png` place the existing actual
ranger sprite (`art/production/p1/combat_style_r13/v03/ranger.png`, north
idle cell, hash-pinned, feet anchor (24,44)) on the sample ground behind
the assembled tree at full and 25% canopy alpha. **Corrected 2026-10-22
after parent review: the ACTUAL hero collision radius is 6, not the 4 px
first approximated**, and every row is labelled in-sheet. Two layouts:
the preview layout (authored envelope r14 -> legal distance 21; north
feet (80,123), diagonal (95,129)) and a separately labelled native-layout
proposal (existing native circle r8.5 -> distance 15; north (80,129),
diagonal (91,133)). Columns: full / faded. The native row documents the
preferred preserve-native-movement option (replacing the native circle
with r14 would block T26); both layouts are visual positioning only -
NOT collider authorization. The sheets show the fade story the policy
wants: at full alpha the crown hides the ranger's head; at 25% the head
reads through the crown while the solid base still grounds the tree; the
hero's lower body stays hidden only where the narrow base actually is.

### Parent acceptance and install (2026-10-22)

The parent reviewed the assembly 2x, common 4x and hero 2x sheets and
accepted the assembly **AS DRAWN for the rendered sample stage**: compact
base with its measured drift (top y94, feet y135), canopy meeting the cut
row y96, no halo, head/upper body legible at 25% - **not engine/native
acceptance**. `build_pine_v02.py` then installed the reviewed bytes at
the runtime art paths with hashes pinned and verified on write (and
byte-identical across double runs): `pine_common_v02.png`
(`81516015...`, 2696 B), `pine_canopy_v02.png` (`93833b1f...`, 13483 B)
and the code-authored `pine_shadow_v02.png` (`061aa4f8...`, 215 B;
deterministic constants in the tool; color family sampled from the
accepted `loadout_shadow.png`; no generator involved). Full processing
record: [PROCESSING.md](PROCESSING.md), pine v02 section; provenance:
[PROVENANCE.md](PROVENANCE.md).

Two definitions were authored under the explicit primitive-policy
interface (sequence item 9): `content/environment_objects/town_pine_v02.tres`
and `content/environment_objects/town_loadout_fade_v01.tres` (fade-policy
sibling of the unchanged `town_loadout_v01.tres`). In the ca schema
`"none"` is an explicit valid policy - a solid base that never enters the
legacy silhouette fallback - so it is written literally on both commons.
The accepted static scope and the mask/revealed supersession were
recorded without a fulltownpass run; ca validation is pending and the
engine was not run.
