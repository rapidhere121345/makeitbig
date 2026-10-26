# 2.5D world traversal — 2026-10-24

Status: accepted and locally published. Targeted tests, rendered acceptance,
frozen full tests/exports/Linux smoke, and release deep verification all pass.
Earlier generated-world evidence is retained separately.

## Requested behavior and architecture

The user reported that the hero could not walk behind houses, then clarified
that the correction must apply to visual entities generally, including trees.
The previous full-image collision rule treated projected roofs and crowns as
walls on the ground. This pass replaces that rule for all 12 town scenery
families and all five battlefield families. Existing character bodies, including
ranged fan enemies, already collide using their feet and physical radii.

The three responsibilities now have independent contracts:

- Movement uses explicit ground-contact rectangles plus three native pixels of
  safety margin: 35 town placements and 13 structures in each of three arenas.
- Depth ordering continues to use the object's feet baseline. Tall projected art
  can cover a character standing on legal ground behind the object.
- Reveal detection still covers the complete artwork with eight pixels of margin.
  The aligned whole opaque/transparent PNG pair and its shader are unchanged;
  transparent texels use alpha 64/255 once and characters remain alpha 1.

The recipe is `docs/art-production/generated-world-v02/ground_footprints.json`.
`tools/world_manifest/author_ground_footprints.py` applies it to native scene
polygons without changing images, placements, channels, sockets or sort anchors.
`--check` runs in the syntax gate to detect stale authoring. Scenes remain runtime
authority; Godot derives their spatial manifests and combat catalog digests.
Combat retains its 0.72 coordinate conversion and absolute 1/16-pixel snapping.

Foundations, trunks, fence supports and stone bases remain solid. Rectangles are
conservative approximations, including the diagonal short fence and bent ruin;
this pass does not add detailed hollow interiors. Invisible world boundaries
remain authoritative, so perimeter decorations need not be reachable from outside
the map. No art is regenerated or split in this pass.

## Acceptance evidence

Fresh parent-owned logs in `build/current/town-2p5d-20261024/targeted/`
record real exit 0 and no script errors for combat authoring/bakes, mounted
walkable bounds, seven production spawn profiles, world occlusion, presentation
assembly, town layout, town runtime, and the hub regression. The initial direct
invocation of `test_base_hub_screen.gd` failed because it is a RefCounted test;
`hub_wrapper.gd` calls its real `run()` method and passes. Both logs are retained.
The coding lane's earlier test overshoot assertion was corrected to verify a
completed crossing rather than an exact endpoint under fixed-size movement.
Parent reran the town tests into this fresh evidence directory.

Arena render `arena-render/run-20261024T151746Z` passed 129 required checks
with 21 PNGs, actual engine exit 0, llvmpipe, zero script/shader errors and no
source drift. It verifies the tower back crossing, normal contact against its
foundation, immediate reversal, front-side opaque restoration, interior-ruin
behind poses, gate-side reveal, real enemy/boss telegraphs, ring circulation and
the corridor route at 1280×720 and 1600×900. GPU samples confirm alpha 64 from
the live paired shader; the hero stays alpha 1. The parent reviewed the tower
behind/front and interior ruin images. Perimeter gates do not claim traversal
outside the authored map boundary.

The arena has 17 informational passes and one informational roster shortfall:
the staged corridor encounter has one live enemy for two planned parking slots.
This is not counted as a two-enemy check. Raw shutdown diagnostics retain 57
ObjectDB instances and six resources in use, plus a VSync warning. Process/display
cleanup passed; this is not a clean-memory or hardware-performance claim.

The first town render `town-render/run-20261024T151544Z` passed 790 checks
and 31 captures. Parent and Luna reviewed the house/tree/board/proxy/fence/lamp
sequences. Its movement and whole-pair evidence is retained, but facility-label
readability is superseded: suspending the fixture's input collector also paused
the production landmark-window animation. The fixture now calls that existing
presentation-only update with elapsed time and checks its expected alpha. The second run, `run-20261024T151903Z`, exposed a real opacity easing bug:
nine label checks failed because the signed fixed step overshot its target and
oscillated instead of settling. Its 31 captures and failed report are preserved.
`BaseHubScreen` now uses `move_toward` to stop exactly at the target. A hub
regression checks covered settling, opaque restoration and stable subsequent
frames; `targeted/hub_opacity_fix.log` passes with true exit 0.

Final town run `town-render/run-20261024T152326Z` passes all 810 checks with
31 captures and 4,266 moved ticks, actual engine exit 0, llvmpipe, no script/shader
errors and no drift in its declared source snapshot. It covers seven continuous
behind/base-contact/reverse/cross/front sequences, repeated twice, all five
facility routes and resident dialogues, invisible boundary contact/slide/reverse,
and both window sizes. Live pine/loadout shader probes render alpha 64; Ranger
alpha stays 1. Parent reviewed final loadout behind/front and pine behind images. Luna
independently reviewed contract, loadout, forge, proxy and pine behind/front
pairs and found no remaining obstruction or regression. Contract/loadout/forge
label checks settle at 0.35 while covering the hero and 1.0 once clear; proxy
labels correctly remain 1.0 when they do not overlap. The label source is separately
pinned in `LABEL_FIX_PROVENANCE.json` after the run (not silently claimed as part
of the wrapper before/after snapshot); the full gate freezes it independently.
Both accepted renderers use controlled production-mounted fixtures, not an OS
input usability or hardware-performance benchmark. Cleanup JSON confirms owned
engine/display processes reaped and private auth/override/socket/lock removed.

## Frozen delivery gate

Gate `20261024T152502Z` passed with authoritative `gate.exit` 0. Syntax/check
stage exited 0 in 3 seconds; `container_build.sh` exited 0 in 599 seconds. Both
owned stage groups ended with zero leftover processes. Freeze before and after:
`272daf74e7526dbc09b91dd57afcdfb6e9d0b6b0ab1e29ef2b3e1d16db4f3618`.
`freeze.diff` is empty. Runtime, authored data, tests, tools, generated art/imports
and the new ground-footprint recipe are included in this exact-input manifest.

The complete suite passed, including 600/600 encounter victories across seeds
0–99 (32,737 ticks), seven production spawn-profile checks, world occlusion,
ground footprints and route regressions, and 37 exact imported RGBA8 textures.
Historical-geometry replay remains `b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b`
at 30/60/144 Hz and presentation-off 60 Hz. These are explicitly historical
replay pins; the current geometry is exercised by the production room/matrix
and traversal tests. Both exports completed and the Linux binary passed
`SCENE_SMOKE_PASS` from an empty directory.

Raw full-gate logs contain zero script/parse/shader errors. They retain 45
resource-in-use shutdown diagnostics plus three intentional rejected-fixture
errors from encounter-director negative tests. No globally clean-log or
clean-memory claim is made. Earlier render resource warnings remain documented.

Fresh exports, after old outputs were moved aside and preserved:

| Platform | Bytes | SHA-256 |
| --- | ---: | --- |
| Linux | 128820200 | `f95ae8b987fcb98d5a121d42030b6153cdcca998ab53b9e032ea40ad94f99b1b` |
| Windows | 164428472 | `7814e7a505e9b79c40123e17181bd8d101774e4081c32a6e34d47c3808a32eb5` |

Gate evidence: `build/current/native-fade-final-gate-prep/runs/20261024T152502Z/`.
## Local publication

Build `20261024-153604-5f4edd733ff5` is packaged in `release-online/`. Before packaging,
both payload hashes and the exact freeze manifest were reconfirmed against the
passed gate. The build metadata discloses the dirty working tree at commit
`5f4edd733ff5`; provenance sidecars identify the exact certified inputs.
Non-pruning package/index/site/deep-verify, Tailscale static validation, and
canonical staging `--check` passed. All three earlier release builds remain;
no release artifact was deleted. Both packaged payloads match the export hashes
above. Evidence lives in `build/current/town-2p5d-20261024/publication/`.
The final acceptance report is copied into this build's provenance directory.

Current publish URL: `http://192.0.2.10:18080/`. It will not be probed, as
instructed by the user. Local verification must not be described as live endpoint
verification or native Windows execution.

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
