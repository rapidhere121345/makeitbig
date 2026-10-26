# Town responsiveness and street layout — 2026-10-26

Status: complete. Final rendered acceptance, frozen full build and no-prune
publication passed. Build `20261026-081845-5f4edd733ff5` is packaged on the
existing release page.

## Scope

The user reported sluggish play on Windows, repeated building facings and
cluttered trees/walls, especially a tree at a bridge landing. No measured Windows
FPS or GPU specification was supplied. Priorities are responsive traversal,
clear bridge approaches, road-facing buildings and deliberate tree/wall groups.

The Forge and Loadout now use separately authored orientation variants with
unchanged facility bindings, interaction sockets and radius. North-east and
south-west houses face their roads. The west landing tree moved to the middle
river-bank group; the landing has a lamp pair. The east boundary uses three
joined vertical wall sections instead of thirteen pines and two fence stubs,
with a small tree pair inside. Unnecessary north-west wall and overlapping north
house placements were removed. Original asset files remain retained.

The west bridge stayed in place: measured relocation trials could not improve
both painted road connections while retaining dry landings. Its entry route and
nearby props were cleaned up. Layout, measured footprints, capture stands and
this decision are recorded in the town recipe. New art provenance and exact
prompts live in `docs/art-production/town-order-20261026/provenance.json`.

## CPU changes and bounded measurements

The static spatial index precomputes conservative bounds, rejecting distant
surfaces before exact overlap/sweep tests. Narrowphase, ordering and tolerances
are unchanged. The resolver avoids a redundant endpoint overlap query only
when its endpoint equals its already-validated start. Moved endpoints retain
the guard against rounded-corner penetration.

Occlusion plans and immutable query results are reused within a presentation
frame. Mutable array-form input geometry is copied into the saved cache key,
so in-place changes invalidate it. Town computes subject coverage only for
actors; scenery reveal still uses coverage over actors. Static ground shadows
and pools retain their draw commands while actor contacts redraw separately.

Headless CPU probes in `build/current/performance-layout-20261026/` report:

| Mean milliseconds | Warm baseline | Final optimization probe |
| --- | ---: | ---: |
| Town idle tick with presentation | 13.223 | 4.475 |
| Repeated-frame presenter processing | 4.602 | 0.673 |
| Static overlap query | 2.954 | 0.113 |
| Zero-displacement resolver call | 5.979 | 0.162 |

These are CPU timings, not rendered FPS or native Windows performance. The
final optimization probe predates the final reduction in scenery count. Cache
reuse alone improved repeated-frame processing; it did not improve the fresh
plan built on every simulation tick. Actor-only coverage, redundant-query
removal and spatial bounds account for the subsequent tick improvements.

Evidence files: `cpu-warm-baseline.json`, `cpu-cached.json`,
`cpu-after-control.json`, `cpu-bp.json`, and `cpu-control-bp.json`.

## Regression design

The spatial differential compares 700 seeded queries across 90 mixed surfaces
against brute-force narrowphase results, including tangency, zero displacement
and channel filtering. Existing real-town traversal tests exercise the larger
production geometry. The zero-net blocked regression preserves mode, contacts
and remaining motion at large coordinates where the skin rounds back to start.

The original house/tree wedge no longer exists in the tidied town. Its exact
historical triangulated and snapped geometry is retained in a separate fixture
through real TownRuntime/Simulation commands: 96 contacts and 40 reverse ticks
remain clear. An ignored in-memory counterfactual removes the endpoint guard
and reproduces the original invalid endpoint at tick 64, (173.0761, 839.5388).
The live-town tests still check current routes, bridge edges and footprints.

The new pack uses explicit expanded detection bounds for the Loadout's actual
padded plinth. Overrides must contain the automatic bounds and remain inside
the canvas; narrowing the physical footprint to satisfy a detection test is
not used. Old packs remain byte-identical. Exact import coverage is 77 images.

## Final targeted validation

`build/current/world-expansion-v01/town-layout/logs/final/exit_ledger.txt`
records eighteen steps captured at execution, all exit zero. Authoring verifies
4,046 checks with no stale scene; import and spatial bake pass. Generated layout,
live town runtime, town geometry/rebuild/native contract, gateway, world
occlusion, grounding, all 77 exact texture imports, presentation boundary and
spatial kernel suites pass. `check.sh` and `git diff --check` pass. The raw logs
contain no script, parse or compile errors. Final scene: 55 sortable objects and
two flat bridge sprites. Five facilities, residents and spawn remain unchanged.

The reopened Loadout and relocated pine use valid current-world stands in the
reveal tests; closed/open/front and actor-alpha assertions are unchanged.

## Rendered acceptance and pacing

`build/current/town-order-20261026/render/run-20261026T080459Z/GATE.json`
passes all 27 captures: town 16, arena seven and pacing four. All three engine
exits are zero, raw runtime/shader errors are zero, and all 849 snapshot inputs
remain unchanged. Private display/auth/socket/lock and resource overrides are
cleaned up. Town passes 578 checks across 2,664 moved ticks. Arena required
checks pass; one optional corridor roster-parking diagnostic had only one enemy
available for two stands.

The clear west bridge landing, road-facing Loadout/Forge front and behind views,
grouped trees, continuous east wall and gate prompt are captured. The wall stand
at (1455,470) identifies `wall_east_1`; the blocked probe (1490,470) hits the two
overlapping wall footprints. Nearby pine identity is checked independently.
Both bridge traversals and the production E-to-Contract route pass. The earlier
080329 town set was independently visually accepted; the final packet refreshes
it with the same frozen product inputs. Independent matching review found
13/16 town images byte-identical and only Ranger animation differences in the
other three; the final combined render packet is accepted. Prior failed attempts are retained:
errors were type inference in the ignored capture scripts, not production edits.

Normal production-loop samples use five seconds each, without forced frame cap
or manual simulation ticks, under Mesa llvmpipe software rendering:

| Sample | Mean frame ms | p95 ms | Observed FPS |
| --- | ---: | ---: | ---: |
| 1280×720 idle | 19.10 | 21.43 | 52.37 |
| 1280×720 walking | 19.39 | 21.75 | 51.58 |
| 1920×1080 idle | 39.02 | 43.08 | 25.63 |
| 1920×1080 walking | 39.65 | 43.80 | 25.22 |

At 720p, 112/262 idle frames and 108/258 walking frames reuse a presentation
tick; at 1080p none do. This establishes an opportunity for same-frame caching,
not a measured cache hit count. The driver only reads latest_frame; it never
calls the planner to manufacture hits. Its `latest_frame_instance_changes`
field is unreliable (zero despite 150 distinct instances): a nonnegative
sentinel comparison suppresses signed RefCounted IDs. The unique-instance and
tick/reuse counts remain consistent and are the evidence used here.

These are software-renderer diagnostics, not Windows hardware FPS or a
before/after rendered comparison. Native Windows performance remains unmeasured.

## Full gate and publication

`build/current/native-fade-final-gate-prep/runs/20261026T080823Z/RESULT.json`
records PASS: check exit zero in six seconds, container build exit zero in
531 seconds, no leftover process groups and no freeze drift. Certified freeze:
`1d4dc1d09a021567c58ab19de90bf05ecfe724467f3332122d7b2afb25c9d603`.
The full raw log contains no SCRIPT ERROR, Parse Error or Compile Error.
Expected capture-contract negative cases and shutdown resource diagnostics are
retained; this is not a claim of clean shutdown memory.

The gate recaptured spatial/actor/town collision, historical wedge, native
contract, both facility reveals, gateway, grounding, display and combat checks.
All 77 exact RGBA8 imports and deterministic art packs pass; pack tests total 21.
The encounter matrix wins all 600 cases. Four automation smoke/replay runs,
including 30/60/144 Hz and presentation disabled, retain state hash
`b98adeadd44d9fb428f1cb762304f8e09c252b2f00ce00583efb40bc8147200b`.
Three ward-frame states preserve authority. Both platform exports complete and
the Linux export passes its empty-directory scene smoke test. Independent final
review accepted the frozen gate together with the rendered packet.

| Export | Bytes | SHA256 |
| --- | ---: | --- |
| Linux | 134,911,088 | `96017a84c57a72a771c66c62e900d3104e2ef1066849e6acc959f7a33c92b299` |
| Windows | 170,519,360 | `c768162ea080c75a4383685928323636544b3390a9d478a37a78b0a71848ad07` |

`build/current/performance-layout-20261026/publication/publication.json`
records build `20261026-081845-5f4edd733ff5` and these exact export hashes.
Publication preserved all nine prior builds. Release deep verification and
Tailscale static/staging validation pass. The existing download page remains
<http://192.0.2.10:18080/>; networking was not changed and the live endpoint
was not probed. Native Windows execution and hardware GPU performance remain
unverified. All evidence is for the current dirty working tree, not a new commit.

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
