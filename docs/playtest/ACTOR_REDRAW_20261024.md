# Chapter-one actor redraw — 2026-10-24

Status: actor integration, rendered acceptance and frozen full gate PASS. Local release `20261025-054740-5f4edd733ff5` published and deep-verified.

## Scope and provenance

The Ranger, all five town residents, three enemy families and the articulated
Threshold Colossus now use original artwork matching the angled dark-fantasy
scenery. Sources, generation briefs and hashes are retained in
[the actor production record](../art-production/actor-redraw-20261024/README.md).
No pixels were extracted from external games. Sixteen selected source images
feed the deterministic compiler at `tools/art_pipeline/actors_v02/build.py`.
The rejected first Mira draft remains retained and is not compiled.

The published contracts contain 68 Ranger frame IDs in 28 clips, 39 enemy frame
IDs in 21 clips, 20 resident work frames in five clips, and six boss part sprites
(body/core in two phases plus two hands). The enemy contract aliases each idle
frame to its recover frame: 39 IDs represent 36 distinct final drawings. Four
static Ranger views and twelve compatibility enemy views also use the new art.

The compiler finds whitespace cuts around generated pose grids, verifies full
opaque-pixel coverage, uses a shared rational scale per facing/role, and grounds
frames at the existing anchors. It preserves crouched and dead pose proportions.
Alpha is binary; imported RGBA pixels remain exact with `fix_alpha_border=false`.
Historical source-atlas metadata describes the retained animation contract;
`render_provenance` separately describes the new RGBA artwork.

## Integration boundaries

The live Ranger/enemy/resident readers, arena atlas and tutorial use `actors_v02`.
The ending panel's Mira and Leia now use new resident work loops, fitted to that
panel's existing two-second cycle. Gameplay frame timing, action rules, arrow
release sockets, body radii and boss-part pose authority are unchanged. The
accepted scenery, five-pixel ground-footprint padding and alpha-128 reveal remain.

Historical art stays on disk. Fire/steam effects and scenery are retained.
The title's explicit provisional fallback remains available when its produced
plate is absent; this is not a claim that every historical path was deleted.

## Targeted evidence

`build/current/actor-redraw-20261024/engine-validation/20261025T051139/`
contains raw attempt logs and `exits.tsv`. Final runs passed import, syntax,
45-image exact RGBA import, Ranger, enemy, resident, style-contract, tutorial,
ending, production assembly and world-occlusion checks. Parent inspection
confirmed the final pass markers and absence of script/parse errors in those
final logs. Earlier failing attempts remain preserved.

Those attempts caught contract-shape mismatches, an enemy idle/recover alias,
incorrect import destination hashes and an ending-loop mismatch. Fixes preserve
the original contract assertions. The historical recolor regression remains on
its original v03 files; new redraw assertions independently inspect actors_v02.

## Actor rendered acceptance

`build/current/actor-redraw-20261024/render/run-20261025T052342Z/` passed:
15 expected PNGs, 208 checks (140 town, 68 arena), both engine exits 0,
no script/shader errors and no source drift. The real town runtime moved the
Ranger through 178 fixed ticks behind and around the loadout. Actor alpha stayed
1; four live-material scenery samples read alpha 128. Private display, auth,
process and resource-override cleanup passed.

The galleries display all four Ranger facings, resident work frames, enemy
windup/active/death and both boss art phases across slam/sweep/lane pose stages.
They use production readers and boss pose functions, but are controlled
presentation fixtures. In particular, sealed-phase sweep/lane galleries are
art stress cases, not attacks used by that gameplay phase. Earlier parse and
caption-overlap attempts remain preserved. Parent review confirmed coherent
assembled boss parts, complete resident poses, and the mounted front/behind
views. The separate live arena run is recorded below when complete.

## Mounted combat acceptance

`build/current/actor-redraw-20261024/arena-live/run-20261025T052533Z/` passed
129 required checks with 21 PNGs, actual engine exit 0, zero script/shader errors
and no source drift. It mounted production rooms with exact authored movement
bindings, exercised behind/front restoration, live enemy windup, a production
boss telegraph, ring circulation and corridor traversal. Parent review of the
windup, boss and ring images found the new actors and telegraphs readable.

Seventeen informational checks passed; one reported a single live corridor enemy
for two planned parking positions. It is not evidence of a two-enemy freeze.
Both display runs cleaned their owned processes, auth and temporary state.
The actor-gallery log retains 17 ObjectDB and six resource shutdown diagnostics;
the live arena log retains 57 ObjectDB and six resources, plus VSync warnings.
These are not represented as clean-memory runs.

## First full gate: metadata drift

Gate `20261025T052633Z` failed certification despite check exit 0 and build
exit 0 (498 seconds). Tests, both exports and Linux smoke completed, but Godot
added UID lines to eight actor PNG import sidecars. Parent removed only those
lines in memory and hashed the remaining bytes: every hash matched the frozen
before-state exactly. All other frozen inputs were unchanged. This is a retained
failed gate, not a release certificate. The compiler now retains
existing valid import UIDs for the same source. Parent independently confirmed
all eight sidecars remain byte-identical across rebuilds. A temporary-fixture
test covers first generation, retained IDs and rejection of a foreign source ID
without rewriting the active pack; it passes. A fresh full gate follows.

## Final frozen gate

Gate `20261025T053843Z` PASS, actual exit 0: syntax stage 2 seconds, complete
build stage 495 seconds, no leftover processes. All 1,632 frozen entries are
unchanged; `freeze.diff` is empty. Certified SHA256 aggregate:
`45c529fd7a88522fe0da98299c69213ec7ba0cf8d11e2832782a0c4282d413e1`.

The full suite includes actor deterministic rebuilds, 45 exact RGBA imports,
600/600 encounter victories across seeds 0–99 (28,382 ticks), complete automation
at 30/60/144 Hz and presentation-off at 60 Hz. All replay hashes match:
`b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b`.
Both exports and the Linux scene smoke from an empty directory pass.

The log contains zero SCRIPT ERROR lines and 48 ERROR lines: 45 resource-shutdown
diagnostics and three intentional negative-path encounter dependency diagnostics.
There is no clean-memory claim. Earlier exports were archived and not reused.

| Export | Bytes | SHA256 |
| --- | ---: | --- |
| Linux | 128621512 | `2a70c700689fd87f5e08d9e02d2df12432a1057e1257188cf7ca61fb2cfe6da9` |
| Windows | 164229784 | `4bb65f9fdaec8dd362c84b7e11ac7ba43b38f4a220b294a0f5d6ab22f5765714` |

## Publication and limits

Local build `20261025-054740-5f4edd733ff5` is present in canonical
`release-online/`, with all five previous builds retained. Package, index, site,
deep verification, deployment validation and staging checks passed. The index
and build metadata carry the exact export hashes/sizes and disclose the dirty
working tree, frozen gate and manifest. Provenance sidecars include the gate
result, export record, per-file freeze, aggregate and checksums.

Publication evidence: `build/current/actor-redraw-20261024/publication/`.
The operator-supplied address is [the release page](http://192.0.2.10:18080/).
It was not probed, as requested. Windows was exported and package-verified, not
executed natively here. Mesa llvmpipe captures establish visual correctness;
they are not a discrete-GPU frame-rate or long-run memory certification.

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
