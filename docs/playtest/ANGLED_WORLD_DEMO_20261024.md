# Angled-world demo acceptance — 2026-10-24

Status: mounted visual acceptance and frozen full gate PASS; local publication complete as `20261024-172341-5f4edd733ff5`.

## Scope

The user rejected the coarse, front-facing scenery. Seventeen new scenery families
and two terrain plates now use an elevated three-quarter view with visible top
and side planes and a finer pixel scale. The runtime camera transform is unchanged.
The Last Spell informed the visual direction; no assets were extracted from it and
no exact Diablo III camera elevation is claimed.

New sources, exact prompts and SHA256 provenance are retained in
[the perspective recipe](../art-production/generated-world-v02/perspective-20261024/DIRECTION.md)
and its `PROVENANCE.json`. The deterministic pack reproduces all 19 entries;
31 packer tests pass. Earlier bright/coarse drafts and failed runs remain retained.

The original generated resident work animations remain active. Ranger, enemy and
articulated boss animation artwork is retained; this pass does not claim new
character animation sets.

## Collision and reveal contract

Scenery uses separate ground footprints and full-art reveal detection. All
footprints retain five native pixels of padding. Reviewed angled bases required
recipe changes for the board, loadout, forge, long/short fences, cart, wall corner
and broken wall. No instance feet, facility IDs or interaction radii moved.
An offline town census passed 3,778 route/resident/facility samples. That census
is supporting geometry evidence, not a substitute for mounted movement tests.

The whole opaque/faded sprite pairs share geometry and RGB; occupied alpha is
255/128. Actors remain opaque. Detection contains every padded footprint; the
woodpile uses 11px detection padding to cover its unchanged broader footing.
Godot import sidecars retain `fix_alpha_border=false` to preserve strict RGBA
identity, including invisible pixels.

## Prior failed gate

The rejected coarse-art gate `20261024T164129Z` exited 1 with zero source drift.
Its authored-room fixture checked a feet-to-feet projectile line instead of the
actual release-to-aim-anchor path, then cast during a charger's strafe. The fixture
now checks the production flight geometry and waits for committed idle; real cast,
damage, reinforcement, loot and victory assertions remain. An isolated rerun
passed; only a fresh full gate can certify the current demo.

## Targeted integration checks

Raw geometry logs are retained at
`build/current/perspective-pass-20261024/geometry-validation/20261024T100735/`.
They show 37 exact texture imports, successful town/three-room derivation, town
layout/runtime/native-contract passes, arena winding/blocker passes, all seven
spawn profiles and authored-room combat. The worker reported true exit 0 from
its command transcript; it did not persist an exit ledger. Its initially reported
`20261024T103149Z` path was incorrect and is not used as evidence.

Parent-run occlusion, production assembly, hub UI and scene-atmosphere targets
passed with saved exit files in `perspective-pass-20261024/parent-targets/`.
The first hub invocation used a RefCounted suite as a SceneTree script and failed
before testing; the corrected thin SceneTree runner calls its existing `run()`
method and passes. Both graphical harnesses parsed successfully.

## Mounted rendered acceptance

Town run `20261024T171223Z`: PASS, 810 checks, 31 PNGs, 4,246 moved
ticks. Actual production hub and town runtime exercise seven continuous
behind/front routes, footprint contact/reversal, five facilities and dialogues,
perimeter contact and both window sizes. Offscreen copies of the live materials verify four upper/lower pixels at alpha
128 on both house and pine; mounted actor reports retain alpha 1.0. No script/shader errors or source drift.

Arena run `20261024T171334Z`: PASS, 129 required checks, 21 PNGs. Mounted
production rectangle/ring/corridor rooms verify behind-tower traversal, base
contact/reversal, all five scenery families, full ring circulation, corridor
movement, enemy windup, boss telegraph and actual GPU alpha 128. Seventeen
informational checks pass; one records only one live corridor enemy for two
planned parking positions. No two-enemy parking claim is made. No script/shader
errors or source drift. Shutdown retains 57 ObjectDB instances and six resources;
this is not a clean-memory claim. Both engines exited 0; owned engine/Xvfb
processes were reaped and auth, overrides, sockets and locks were removed.

Evidence roots are `build/current/perspective-pass-20261024/town-render/` and
`arena-render/`, including run gate/cleanup JSON, raw logs, state traces, source
hashes and SHA256 capture inventories. Parent reviewed actual town loadout/forge,
behind-house/tree and front-fence frames plus arena entry, held tower, enemy
windup and production boss telegraph.
The new top/side planes remain consistent in the game; characters and combat
cues remain distinguishable against the dark terrain.

## Independent visual review

The read-only reviewer found no clear perspective or ground-contact defect in
the town or arena frames. The Ranger and combat cues remain distinguishable.
Two polish limitations remain: fine ground mottling competes with the Ranger
near the feet, and the light cloak blends somewhat with snowy pine branches
while behind the tree. These are recorded as contrast tradeoffs, not hidden as
perfect readability. The movement claim comes from runtime traces and checks,
not from still images alone.

## Frozen full gate

Run `20261024T171449Z` passed with exit 0: syntax/check stage 3s and complete
container build stage 499s, both with zero leftover process-group members.
All 1,571 frozen input entries remained identical before/after:
`a805513e13303228d07a80cd8b1424c006f0711a842ee567ce5a99c4ae06e7b5`.

The encounter matrix completed 600/600 victories across seeds 0..99 (28,382 ticks).
The full chapter game-flow smoke reached the ending and returned to town. Replay
hash `b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b`
matched at 30/60/144Hz and presentation-off 60Hz. Fresh Linux and Windows exports
completed, followed by `SCENE_SMOKE_PASS` from the Linux artifact in an empty
working directory. No script errors occurred. The raw build log retains 45
resource-at-exit error lines and three expected negative-path diagnostics; there
is no blanket clean-log claim.

Gate evidence: `build/current/native-fade-final-gate-prep/runs/20261024T171449Z/`
contains RESULT.json, stage logs, manifests, empty freeze.diff and exports.json.
Old exports were archived before the gate; they were not repackaged.

## Local publication

Build **20261024-172341-5f4edd733ff5** is newest in `release-online/index.json`
and embedded in the regenerated page. Its metadata explicitly identifies the
dirty working tree at `5f4edd733ff5`, the gate and certified freeze. Packaged
provenance includes the exact input manifest, gate result, export records and
checksums. Reconfirmation matched the freeze immediately before packaging.

| Platform | Bytes | SHA256 |
| --- | ---: | --- |
| Linux | 128265344 | `64b8ddf5c72f23859ebb400d925b872ec186bc59f38ddd183bab4386895bf354` |
| Windows | 163873616 | `0a4ef856a623f7e47f452d59947fa612c06596b3c0d7820c0a3e4f812fd9b60d` |

Package/index/site, `release.sh verify --deep`, deploy static validation and
`stage_release_page.sh --check` all passed. Parent independently rehashed both
packaged payloads against the gate. All four prior builds remain; no pruning or
deletion occurred. Evidence: `build/current/perspective-pass-20261024/publication/`.

The release URL is `http://192.0.2.10:18080/`; endpoint probing is explicitly excluded by the
user. CPU llvmpipe renders provide correctness evidence, not hardware-performance
measurements. Native Windows execution is not claimed.

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
