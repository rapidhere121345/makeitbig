# Town and battlefield visual-quality pass — 2026-10-23

Status: accepted for the bounded town and battlefield cases below. The fresh
full test/export/Linux-smoke gate passed. Local publication is complete; the
operator-supplied endpoint was not probed.

The operator permits conservative collision and occlusion volumes to avoid
visible overlap. Bases and actors remain opaque; covering upper structure bands
fade physically. The current publish URL is `http://192.0.2.10:18080/`.
It was supplied by the operator and was not probed.

## Town

The south pine's triangular condition missed its outer boughs: an actual-input
baseline at `(780.801,700.913)` reported only 0.0268 coverage and stayed opaque.
The new box covers the crown with a small margin and opens from a closed state
in the matching outer-bough approach case, reaching alpha 0.25. The Loadout roof condition
also has a small margin. Both retain the 0.18-second transition and front/back
ordering; the base and actors stay opaque.

Native tree trunks now use radius 14, except tree_east at radius 12 to retain
Mira's clearance. Facility sockets, resident positions, routes and spawn are
unchanged. Headless checks exercise actual resolver contact and reversal,
resident clearance, all seven routes, and atomic rejection of stale travel
positions now inside a blocker. The sample pine's movement radius remains 14.

Rendered evidence is under
`build/current/visual-quality-pass-20261023/town-after/`:

- `run-A-town`: 33 passing checks and one failed contact approach. Outer-bough
  opening, three enter/exit cycles and holds, roof cycles, Mira dialogue,
  five facility open/return smoke checks, and both viewport sizes passed.
- `run-B-contact-retry`: 7/7. A due-north approach reaches the same trunk at
  0.001 radial clearance, holds without penetration, and reverses out.
  The first run's off-axis approach missed the required contact band; its
  failure remains recorded and is not counted as contact evidence.
- `preview-both`: 144/144, including the independent 0.25 opacity contract,
  outer-bough opening from closed, and live base/actor checks. No script or
  shader error was found in its log.

The parent inspected the outer-bough, north approach, contact-end and 1600-wide
roof PNGs. The character remains recognizable, the solid bases remain visible,
and the revealed ground has no exposed transparent hole in these captures.
Pixel differences from baseline describe changed pixels, not a visibility score.

These are CPU llvmpipe captures from a retained progression fixture, not human
quest progression or hardware performance evidence. The other town pieces
retain their legacy reveal policy. The facility checks are smoke coverage;
only the south trunk received the new rendered contact probe. Launcher failures
and cleanup corrections remain in `TOWN_AFTER_REPORT.md` and the raw evidence.

## Battlefield implementation and targeted checks

Ruins use their existing source pixels as two adjacent bands: rows 0–83 fade,
rows 84–127 stay solid. The tower retains its authored upper/base regions.
Simple padded upper rectangles drive the shared primitive-fade transition.
The hero and live enemies can trigger a covering upper; actors' sort-view
opacity remains 1. Actor-over-actor local cutouts retain their separate budget.
Updates occur once per committed presentation frame, not during draw callbacks.
Lights derive from the drawn tower and ruin positions. No PNG is repainted.
The layout retains the original default placements and adds explicit ring-only
placements: low_pier#1 `(832,326)`, wall_corner#1 `(782,621)`, and low_pier#2
`(576,629)`. These positions are shared by the renderer and authored collision;
the render-list regression checks all three and verifies they do not leak into
the corridor. The packing recipe merges the retained original layout with a
separate authored override file; the art recipe unit test passed.

All twelve ruin colliders per room now cover the solid base band with modest
margins; the tower retains its radius-58 octagon. The three room manifests were
rebaked and their gameplay digests updated. The blocker regression and mounted
ring circulation regression passed. The latter samples a hero-eroded polar grid
and requires a free cycle around the beacon, not merely connected endpoints.
Offline geometry also retains a cycle with three extra units of clearance;
the old ring failed that winding test. This is sampled route evidence, with
actual motor traversal still subject to the rendered gate.

Changing blockers changes steering and deterministic spawn relocation. The
ring's old `(640,609)` spawn candidate is now blocked and must use the existing
relocation authority. No replay golden was changed to accommodate this work.

Geometry-lane evidence is retained in `battlefield/engine_evidence.md`.
Derivations have direct successful exits. The two targeted tests printed their
PASS markers, but that lane's shell exit echoes followed `tail` and do not
independently establish engine exit status. Earlier test-only failures (a
constant/type parse error and a fixture without production blockers) were
corrected and retained in that record. The fresh full gate remains authoritative
for their final process exits. All three spatial files changed; an earlier
claim that the corridor file was unchanged was retracted after inspecting it.

`build/current/visual-quality-pass-20261023/arena-checks/targeted-results.json`
records the successful targeted runs, including the new arena fade test,
world occlusion, boss parts, production assembly, atmosphere, town runtime,
actor presenter, arena presenter and presentation/occlusion boundary. The new
fade test pins 0.625 at half transition, 0.25 settled, solid bases, enemy-only
coverage, front restoration and reset. The world test checks all twelve ruin
placements and the tower's source/destination seams.

The first new-test run found a typed-array assignment error. It was stopped,
the owned temporary override was removed after verifying its hash, and the
corrected test passed. Corrected logs contain no script/parse/shader errors;
production assembly and atmosphere retain cached-resource exit warnings.

## Superseded standalone battlefield evidence

`arena-render/run-20261023T133010Z/` retains 15 PNGs. The parent inspected
tower quarter/mid/front, wall and gate quarter states, and the 1600-wide view:
the actor remains recognizable and the base bands remain solid. The enemy-only
state assertions passed, but its PNG is obscured by the room-entry card and is
not accepted as enemy readability evidence.

This first fixture instantiated standalone `Main`, whose static index contains
the room boundary but no authored structure surfaces. Its screenshots therefore
establish presentation only. Optional contact observations, including a
13.17-unit gap against an assumed radius 14, establish no production collision
PASS. A required fixture walk stopped 50.4 units short; its cause is not proven
to be actor collision. The continuation must mount `CombatRoomRuntime` and
verify the actual authored index before accepting movement or room traversal.
Earlier parser and empty-encounter fixture failures are retained separately;
production startup validation was not relaxed.

## Mounted battlefield review

The production-mounted continuation uses fresh `CombatRoomRuntime` instances,
authored campaign encounters, the shared actor registry and the exact movement
surface ID set from each room manifest (all 13 structures plus its boundary).
Calibrated poses are validated teleports; route legs use the real actor motor.
Static poses freeze the enemy-update callback, while windup captures restore
real AI. This is a controlled rendered fixture, not a complete user-input
playthrough. Contact probes are informational, not penetration proof.

- `arena-render/run-20261023T134829Z/`: 76 required passes, one required
  failure, 42 informational passes, 23 PNGs. Rectangle structure fades and
  restores, controlled half-transition, enemy windup, boss parts/slam, resize
  and ring arc movement passed. The final corridor park at `(500,270)`
  correctly rejected outside the authored corridor band.
- `arena-render/run-20261023T135555Z/`: 18 required passes, one required
  failure, eight informational passes and one informational failure, four
  PNGs. Corrected corridor parks were legal; movement reached the center and
  continued to X=1012.5 but missed the final X=1060 waypoint before its
  render-frame budget ended. That endpoint is not accepted. One live parked
  enemy versus two configured roster entries is recorded as an encounter
  staging limitation, not a claim that both enemies were frozen.

The parent inspected mounted tower quarter/mid/restore, ruin wall/gate,
1280/1600 views, enemy windup, boss parts/slam and ring overview/arc captures.
The Ranger remains readable, upper structures fade while their bases stay
solid, warning marks are visible, and no obvious backing holes or split-band
seams were observed in these views. Ring circulation beyond the sampled arc
is covered by the geometry regression, not by a claimed full rendered lap.

The original mounted `11_enemy_only_upper.png` placed its subject offscreen;
its strict state assertions remain useful but that image is not readability
evidence. The same named image in `135555Z` places the gate and enemy on camera
with the hero outside the gate condition. The parent inspected it: the enemy
and hero remain opaque, and the gate fades from the enemy's overlap alone.
`18_corridor_overview.png` and `19_corridor_route_mid.png` were also inspected.
Both rendered runs used Mesa llvmpipe (LLVM 21.1.8), providing correctness
evidence rather than hardware-performance evidence. Both retain cleanup
records with reaped processes and removed authority;
the recorded Xvfb exit is null, so no Xvfb exit-code claim is made.

## Full gate

The existing bounded runner is reused under
`build/current/native-fade-final-gate-prep/runs/`. Attempt `133432Z` ended after
the syntax stage with no build, exports or after-freeze. Its emitted PASS is
invalid and explicitly rejected in `ACCEPTANCE_REJECTED.json`; no artifact is
certified by it. The precise early-termination cause is not established. The
ignored runner now requires a completion sentinel, and attempt `133550Z` uses
a durable redirected launcher log. That attempt failed in the production Boss
regression: the death position `(750,488)` was clear for radii 14 and 16 but
blocked for the drop's radius 18, so no loot materialized. The failure was real.

The mounted placement adapter now keeps clear drops unchanged and searches a
bounded deterministic neighborhood for drops at legal origins lacking pickup
clearance. It checks the intervening floor, rejects blocked origins and does
not cross a separating wall. The domain still validates the final placement
before creating loot. The production Boss regression, mainline pickup test,
and death/loot tests pass with direct logged exits 0; the latter also pins
deterministic relocation, unchanged clear drops, blocked-origin refusal and
no relocation across a wall. Logs are `arena-checks/08-*.log` and
`arena-checks/09-death-loot.log`. The next frozen gate `134309Z` passed those regressions but stopped after
142 seconds at `test_enemy_runtime.gd`: action-lane and antipodal-pair
assertions failed after fixture teleports near the enlarged/moved blockers.
Its before/after freeze matches (`4d27115f...`), with no leftover process groups.
The old tests did not check their teleport results. Geometry review confirmed the player at `(640,494)` had only 6 units of
clearance, the waiting fan at `(790,494)` only 11, and the south ring charger
was inside the moved pier. Those teleports correctly rejected and left actors
at their spawns. The action-lane trio now starts 20 units north with the same
150-unit standoffs. The antipodal ring pair uses radius 120 instead of 185,
remaining outside attack range with a clear approach. Explicit teleport-result
checks now fail before behavior assertions if a fixture cannot be placed.
Attack timing, damage, lane handoff, antipodal and stall predicates are
unchanged. The targeted rerun passed with an actual logged exit 0 in
`arena-checks/10-enemy-runtime.log`: action-lane timing/damage checks pass,
ring fan starts at tick 31 and the longest requested-but-stalled run is one
tick. The final frozen gate `135928Z` passed:

- `scripts/check.sh`: exit 0, 3 seconds.
- `scripts/container_build.sh`: exit 0, 465 seconds; full tests, both exports
  and the Linux smoke run completed, with zero leftover process groups.
- All 600 repeated encounters (seeds 0–99) finished in victory, 28,597 ticks.
- Replay hash `b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b`
  matches at 30/60/144 Hz and presentation-off 60 Hz; no golden was changed.
- All 1,336 frozen entries match before and after, aggregate
  `be0c7633b06485fb303c933a47f55434386053fffbc2fb0aaf82852a816963f3`.
- Linux: `ca9523d42639d5ecef8d2f4ddc63e84e3cc6ffef9e9232b38fc08e4ef8b5d293`
  (124,266,264 bytes); Windows:
  `a8223f67e79d453bbeef1656126b983bd870a6712ecd6bd6b7d0d8b2d9245563`
  (159,874,536 bytes).

The full log contains no GDScript runtime error. Its 47 `ERROR:` lines consist
of 44 cached-resource exit diagnostics and three expected negative-fixture
encounter diagnostics; this is not a claim of a globally empty error log.
Previous exports were archived by the runner and were not reused.

## Final corridor continuation and scope

`arena-render/run-20261023T140908Z/` runs only the mounted corridor probe.
The corrected driver budgets simulation ticks, stops after 30 simulation ticks
without progress, and has a 30-second wall watchdog. Required arrival tolerance
remains eight units. It reached `(636.83,434)` from `(400,434)` in 30 ticks
(3.17 units from the center target), then `(1053.33,434)` in 52 ticks (6.67
units from the far target). Both traces report no stall or timeout. Engine
exit 0, raw script/shader scan clean, auth removed and processes reaped.
The run has no PNGs; the accepted corridor images remain in `135555Z`.
The one-live-enemy roster note remains informational. This closes the missing
endpoint without turning earlier failed runs into passes.

This acceptance covers the changed town pine/roof regions and battlefield
structure policy in rectangle, corridor and ring rooms. Other town pieces
retain their existing reveal policy. The battlefield captures use mounted
controlled fixtures; they are not an uninterrupted manual campaign playthrough.
The ring visual run covers a partial arc; full circulation is a sampled
geometry regression. Software rendering is not hardware-performance evidence.
No user save, old release or failed evidence was deleted.


## Local publication

Build `20261023-141101-5f4edd733ff5` is packaged under the canonical
`release-online/` root. Before packaging, both export hashes and the entire
frozen input manifest were recomputed and matched gate `135928Z`. The package
includes the dirty-tree provenance, freeze manifest, gate result/export list
and this acceptance record. Index/site generation, deep SHA256 verification
of both retained builds, deployment static validation and staging `--check`
all passed. The previous build remains available; no pruning ran.

Current operator-supplied URL: <http://192.0.2.10:18080/>. No endpoint
request or host-network change was made. Evidence logs are under
`build/current/visual-quality-pass-20261023/publication/`.

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
