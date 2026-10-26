# Generated world v02 acceptance — 2026-10-23

Status: town and battlefield rendered acceptance, the fresh frozen full gate,
and local publication pass. Build `20261023-195126-5f4edd733ff5` contains this
replacement. Live endpoint access was not probed, as requested.

## What changed

The live town and battlefield use newly generated terrain and whole scenery
objects. The reference supplied style, palette and materials; its object pixels
were not extracted. [Source records](../art-production/generated-world-v02/README.md)
retain 24 generated images, exact prompts and source/reference hashes: two ground
plates, 17 scenery families and five four-pose resident sheets. The environment
compiler verifies 19 entries byte-for-byte; its 28 unit tests pass. All 20 new
resident frames are distinct and rebuild identically.

Each scenery object has matching opaque and transparent PNGs: occupied alpha
255 or 64, identical RGB/canvas/anchor, zero alpha outside. The runtime blends the
two images once; it does not additionally multiply sprite opacity. Complete
objects fade, including their foundations. Actors retain opacity 1.0. There are
no live roof/base/common slices in the new scenery. Detection uses the occupied
rectangle grown by eight native pixels; collision uses the whole occupied
rectangle grown by three, with simple invisible perimeter bounds.

Ranger, combat enemy and articulated boss animation artwork is retained, as are
UI portraits/icons and the historical return-panel artwork. This is not a claim
that those animation sets were regenerated. Previous sources and reports remain
available; no old asset or release was deleted.

## Town integration and rendered evidence

The production scene has one opaque ground and 35 whole paired sprites. Its 35
collision rectangles bake into 70 triangles. Five facility identities, ordering,
locks, resident positions, interaction radius 48, spawn and seven routes remain
intact. Twelve prop placements moved to leave those routes clear. The obsolete
river geometry and all old split visual companions are absent from the live scene.

The spatial bake and `test_generated_town_layout`, `test_town_runtime`,
`unit/test_town_geometry` and `test_town_geometry_rebuild` passed with actual
exit 0. The runtime test traverses all seven routes continuously and checks
whole-pine/building contact, perimeter sliding, reversal and atomic save behavior.
Logs: `build/current/generated-world-v02/town/logs/`.

Rendered run: `build/current/generated-world-v02/town-render/run-20261023T190037Z/`.
The production hub passed 118 checks with 16 PNGs on authenticated private Xvfb
and CPU llvmpipe, at 1280×720 and 1600×900. Evidence includes all five facility
routes/dialogues, repeated legal-edge entry/hold/exit for pine and house, and
perimeter contact/slide/reversal. `REPORT.json`, `state.jsonl` and the SHA256
capture inventory retain the exact observations.

Two transparent SubViewport probes copied the live house/pine materials at
settled weight 1. Parent independently compared every output alpha pixel against
the baked transparent PNG: exact equality, maximum error zero. Upper and lower
occupied pixels both have alpha 64; object modulate and actor alpha remain 1.
These probes test GPU appearance only; authority remains the production hub.

Parent reviewed arrival, loadout, proxy, Mira dialogue, pine/house open and house
restored captures. New art is visibly different and coherent; ground remains
continuous behind whole-object fades, actors remain readable, and exit restores
the opaque object. Facility labels remain UI elements by design.

The preceding `185921Z` run is retained as a fixture failure: the input collector
was disabled before the first authority frame. An explicit zero-input town tick
fixed the ignored fixture; no runtime change was needed. Successful cleanup
records engine/Xvfb exit 0, reaping, and owned auth/override/socket/lock removal.
The lane's `FINAL_REPORT.json` records the capture matrix and provenance.

## Battlefield collision, spawning and movement

All three combat rooms mount 13 complete-object rectangle blockers, including
the tower. They derive from the generated occupied bounds and native/gameplay
scale 0.72. Absolute edges snap to 1/16 gameplay pixel for manifest round-trip
stability; inward rounding is at most 0.03125 gameplay pixel, leaving at least
approximately 2.97 native pixels of padding without exposing occupied art.

Two ring objects move outward: wall corner #1 to `(814.1,663.2)` and low pier #2
to `(563.8,666.1)`. The shared wall corner moves five pixels right to `(738,557)`
to clear the encounter-origin socket; the ring override takes precedence.
Mounted winding regression proves a complete circulation path. Offline winding
also survives hero radius 17, three above the actual 14; the narrowest measured
physical opening is 39 gameplay pixels for a 28-pixel hero diameter.

All three manifests were rebaked and catalog gameplay digests refreshed. Bake,
`test_combat_structure_blockers` and `test_arena_walkable_bounds` pass. Evidence:
`build/current/generated-world-v02/geometry-validation/`.

The first spawn report replicated a search algorithm; it was corrected to say
algorithm-model evidence, not production proof. The subsequent regression mounts
real `CombatRoomRuntime` sessions for seven layout/profile combinations and reads
actual registry feet. It exposed overlaps because the original spawn projection
queried only static obstacles. Initial placement now also excludes registered
movement bodies, preserving the existing soft-body movement policy after spawn.
All seven cases pass static radius-16 clearance, enemy separation at least 32,
and hero separation at least 30, with actual positions logged.

The new long rectangles also exposed overly conservative AI steering: enclosing
circles covered legal narrow lanes. Polygon blockers now supply their actual
edges for steering penalties; collision authority is unchanged. A two-wall
regression proves the legal lane remains preferred while entering a wall is
penalized. Actual first-hunt runs defeat all six enemies in 15.43 seconds
stationary and 17.17 seconds reactive, within the unchanged 15–25-second gate;
damage is 50 versus 5, with real dodge/movement input. The first room's authored
angles are `[-69,-24,14]` at the original radius 350, placing its seeds outside
whole-object blockers. No health, damage or pacing assertion was relaxed.

Older action-lane and boss tests had positions inside the enlarged objects.
Their setup positions were moved to legal floor while preserving attack distances,
timing and outcome assertions. Actual exits and retained failures are under
`build/current/generated-world-v02/parent-validation/`.

## Arena rendered evidence

Initial mounted run `arena-render/run-20261023T191014Z` produced 20 PNGs and
passed 120 required checks. Its 18 informational rows include one qualification:
the corridor's staged encounter had one live enemy for two park slots. No
two-enemy park is claimed. It verifies exact movement binding sets in all three
rooms, all five whole-pair families, tower GPU alpha 64, actor opacity, real enemy
windup, a production boss slam, a full 36-leg ring circuit and corridor traversal.

Parent reviewed the tower closed/open/restored states, wall corner, enemy/boss
telegraphs, ring and corridor. Legacy blue snow/foundation stamps were visibly
coarser than the new art, so generated terrain now omits those historical decals.
The original atlas fixture path retains them.

Final run `arena-render/run-20261023T191858Z` includes that polish and the spawn/
steering corrections: 121 required checks pass, 20 PNGs, actual engine exit 0.
Seventeen informational checks pass; the same one-live-enemy/two-park-slots
qualification remains. Source hashes match before and after. Parent reviewed
the new entry, tower open/restored and wall-corner captures: the coarse decals
are gone and terrain remains continuous. Every PNG hash was independently
rechecked; every pixel of the tower GPU alpha image exactly matches its baked
transparent PNG. The final run retains the same exit resource diagnostics and
verified owned process/display cleanup. Both runs and their reports are preserved.
These are controlled mounted fixtures, separate from the seven-profile actual
spawn regression.

The initial rendered run has no script/shader failures, but its exit log retains
57 ObjectDB leak and six resource-in-use diagnostics. Process/display cleanup
is verified separately; this is not described as an error-free engine log.

The full gate and local publication are recorded below. Canonical publish URL:
`http://192.0.2.10:18080/`. Live access is not probed, per user instruction.

## Import consistency correction

Gate attempt `20261023T192207Z` correctly failed after import: all 35 town
object fingerprints differed, while ground, geometry, sockets and routes matched.
Godot's default alpha-border repair had changed invisible RGB pixels. Offline
cache comparison found 4,973 such pixels in each forge state and 2,348 in pine;
alpha and visible RGB were unchanged. All 37 generated texture sidecars now pin
`process/fix_alpha_border=false`. After reimport, the derived town manifest is
byte-identical to the original, with no rebake or fingerprint weakening. The new
post-import regression requires all 37 imported RGBA8 images to exactly match
their source PNGs and passes. This also restores the pixel inputs used by the
accepted rendered captures.

The prior launcher attempt `192107Z` completed syntax checks but exited before
the build stage with its detached output stream unavailable. Relaunching with
durable stdout/stderr redirection exposed the import failure above; neither
attempt is counted as a successful gate. Both records remain in place.

Attempt `192807Z` passed import identity and the unit suite, then failed the
enemy-death deregistration fixture: its target stand was inside a new whole
wall collider. Moving the entire 120-pixel projectile lane 36 pixels north
preserved its distance, actual projectile death and registry/loot assertions.
The targeted regression then passed with exit 0; the failed gate is retained.

Attempt `193136Z` stopped at the analogous mounted-kernel combat setup. A
diagnostic sweep then executed 136 remaining scripts independently, preserving
raw output and exit codes in `parent-validation/remaining-sweep/`. It exposed
stale whole-layout counts/coordinates and combat fixture positions, including
script errors when the skill fixture assumed a rejected cast had produced an
arrow. These results are failures, not acceptance. The matrix alone reached its
diagnostic 90-second bound after 300 rooms; the full gate retains its normal
1,800-second suite allowance. That partial matrix is not a 600-room pass.

Corrections keep attack offsets and outcome assertions, moving the affected
mounted lanes onto legal floor. Layout pins now require exactly 35 town visuals
and 70 collision triangles, plus the actual ring placements. The historical
style packer also reproduces the sole five-pixel shared wall move explicitly;
all other shared layout fields must still match the retained source.

All nine failing sweep scripts pass after fixture corrections, with raw logs
under `fixture-retest/` and `skill-fixture-retest/`. Skill and input fixtures now
record rejected teleport setups explicitly. Parent review also caught a camera
coverage overclaim: the relocated "top-left" stand did not clamp horizontally.
The final test uses a legal vertical target at the original top-left stand and
asserts both clamp axes. At the lower-right legal edge, the 1280x720 camera's
upward framing permits only a right-axis clamp; that case now names and asserts
the actual coverage, preserving the screen/gameplay round trip and click target.


## Frozen final gate and publication

Gate `20261023T194229Z` passed with exit 0: syntax/check stage 3 seconds,
full `scripts/container_build.sh` stage 507 seconds, both with zero leftover
process-group members. The 1,479-entry manifest, including active untracked
sources, generated raw images/prompts and import settings, is identical before
and after; `freeze.diff` is empty. Certified SHA256:

`bfa815257ea5ddf1b7d75a3b01f0001da59e707874fe25ea5cd561bf1d4d6ef6`

The full suite passed, including all 600 encounter rooms over seeds 0..99,
600 victories and 28,745 simulation ticks. The historical-geometry replay golden
`b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b`
matched at 30/60/144 Hz and presentation-off 60 Hz. Game-flow, Auto and packaged
Linux scene smoke passed; Linux smoke ran from an empty temporary directory.
Windows export passed, but native Windows execution is not claimed.

The raw build log contains no `SCRIPT ERROR:`. Its 48 `ERROR:` lines comprise
45 resource-in-use shutdown diagnostics and three deliberate negative-path
encounter-dependency diagnostics. These are retained, not described as a clean
memory/leak audit. Full evidence is in
`build/current/native-fade-final-gate-prep/runs/20261023T194229Z/`.

| Export | Bytes | SHA256 |
| --- | ---: | --- |
| Linux x86_64 | 128816032 | `a8d1038c8cfea4a99b5f2560c4100fc7ccf09aaf006f79e96660a308968bc70d` |
| Windows x86_64 | 164424304 | `686b1f0b72d61194686ff557957bd05125e74a7bcce820a9fc3229cf06ae70a4` |

Before packaging, the entire freeze manifest and both export hashes/sizes were
recomputed and matched. Build `20261023-195126-5f4edd733ff5` is now in the
canonical `release-online/` root. Its metadata explicitly identifies the dirty
working tree at `5f4edd733ff5`, certified gate/freeze and retained combat animation
artwork. Provenance sidecars retain the exact input manifest, gate result,
export hashes and this acceptance record.

Package, index, site, deep SHA256 verification, deployment static validation and
staging `--check` all passed. All three release builds remain; no pruning ran.
Evidence: `build/current/generated-world-v02/publication/`. No network request,
Tailscale command, host-service change or endpoint verification was performed.

This pass accepts new terrain/scenery and resident artwork, whole-object reveal,
conservative collision and the exercised chapter-one behavior. Controlled
render fixtures are not an uninterrupted human campaign playthrough; CPU
llvmpipe results do not certify hardware performance. Ranger/enemy/boss animation
regeneration remains outside this delivered asset set, as disclosed above.

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
