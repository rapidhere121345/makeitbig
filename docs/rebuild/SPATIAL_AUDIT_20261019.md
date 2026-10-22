# Spatial Architecture Implementation Audit - 2026-10-19

Read-only audit against the former TARGET_ARCHITECTURE.md; current architecture reference: [ARCHITECTURE.md](ARCHITECTURE.md). Scope: `src/runtime/spatial`, `src/runtime/geometry`, `src/runtime/world`, `src/presentation/occlusion`, `src/presentation`, `content/rooms`, `tools/world_manifest`, `tests/`. All findings from static reading/search, no Godot execution. Background: poor character/background/entity collision and occlusion in hardware-GPU playtests; identify redesign gaps.

## 1. Implementation Matrix

| # | Promise | Status | Evidence |
|---|---|---|---|
|1| Separate immutable static and dynamic indexes, channel-indexed | Implemented | `static_spatial_index.gd:4-10` no mutation API, `:57-67` channel buckets; `dynamic_spatial_index.gd:4-12` |
|2| Seven semantic query channels, no generic is_blocked | Partial, all channels but incomplete consumers | `spatial_channels.gd:11-27`; no is_blocked callers. Movement: `movement_resolver.gd:247-275`; projectile/attack+hurtbox: `room_spatial_port.gd:326-347`→`continuous_hit_resolver.gd:80-97`. No production vision_resolver or occlusion_resolver calls. Navigation has constants but no query API. `spatial_manifest.gd:151-160` navigation_bindings()/vision_occluders()/projectile_blockers() have no callers |
|3| ContinuousHitResolver unifies static/overlay/dynamic, toi order, opaque priority on ties, no damage application | Implemented | `continuous_hit_resolver.gd:59-140`; fixed phase `room_spatial_port.gd:305-348`; `test_spatial_room_port.gd:33-42` |
|4| MovementResolver sole displacement authority, solid/soft/ghost, static recheck after soft separation | Implemented | `movement_resolver.gd:63-183` eight-iteration sweep-and-slide, `:186-229` soft separation/recheck, `:278-324` boundary reprojection. All production actors soft: `main.gd:1063`, `:1246-1250`, `encounter_director.gd:780,864` |
|5| SpatialOverlay runtime doors/destructibles, tick-boundary commits | Infrastructure only, unwired | Complete mechanism `spatial_overlay.gd:28-39,104-144`, `room_spatial_port.gd:265-271`; no production add_surface/suppress_static. Empty overlays `scene_runtime.gd:172`, `main.gd:1108`, no content data; no functioning door/destructible |
|6| WorldAsset bake, dual digest, mount validation | Implemented for town; combat minimal | `bake_core.gd:17-64`, `world_asset.gd:63-84`. Hearthside90 bindings,35 occlusion:true,162 static geometries. **Each of three combat rooms only one movement-boundary binding, occlusion:false, no static_geometry** |
|7| PresentationFrame sole adapter, requires art_box, rejects collision as visual source | Implemented | `presentation_frame.gd:44-46,66-76`; `room_presentation_binding.gd:43-46`; `room_presentation_projector.gd:87-130` |
|8| Stable OcclusionPlan sort, interpolation-only controller, no simulation writeback | Implemented | `occlusion_plan.gd:72-80,106-144` rectangle-only, not pixel masks; `occlusion_controller.gd:13-16,81-87,93-108` |
|9| Missing required art is load error, no placeholder | Implemented | `world_presenter.gd:231-236`; `town_presenter.gd:278-282`; `main.gd:1362-1382`; `town_scene_root.gd:20-44` |
|10| Occlusion presentation-only, no gameplay | Implemented without misuse | Presentation uses art-box plan, not spatial occlusion channel. Static-index occlusion channel/occlusion_rank are consequently dead runtime data; `scene_runtime.gd:941-949,963-971` hardcodes defaults |
|11| No generic event bus, SceneTree search, string-callback ABI | Mostly implemented | `combat_simulation.gd:1-59` typed CombatPhasePort; simulation has no get_node/SceneTree |

## 2. Scene Migration

Both paths migrated, no whole legacy path remains. Occlusion capability differs, however, and combat spatial content is a shell.

**Town, complete:** `town_controller.gd:19-58`→scene_runtime.mount();162 geometries indexed `scene_runtime.gd:953-971`;35 bindings→`scene_runtime.gd:357-393`→`room_presentation_projector.gd:87-130`→`town_presenter.gd:198-231` alpha. End-to-end `test_presentation_production_assembly.gd:156-205`. Correct y-sort `world_presenter.gd:42-46,93-100`.

**Combat, migrated architecture but data/presentation gaps:** same mounting/movement/hit pipeline; presentation wired `combat_presentation_controller.gd:336-398`→`arena_actor_presenter.gd:313-331`, but:

- No manifest occlusion bindings, so `scene_runtime.gd:363-364` returns early; static bindings always empty.
- Ruins/tower from layout.json (`arena_world_view.gd:28`),12 structures+tower_feet, **presentation-only; spatial index/manifest never see them**.
- Hero-only cutaway `arena_world_view.gd:785-844,875-881` runs alongside OcclusionPlan.

**Legacy hygiene:** actor_motor.gd, layout_blocker_loader.gd, native_static_room_root.gd, geometry_query.gd have no production calls but five regression tests and `content/rooms/samples/concave_hole_passage.tscn` still use them, preloaded by test_room_encounter_production.gd. **Do not mechanically delete**; migrate tests with movement redesign.

## 3. Suspected Visual Root Causes, by Impact

1. **R1 combat, largest: visible ruins/tower/gates absent from spatial truth**, yielding penetration and failed occlusion. Presentation alone reads 12 layout structures; three manifests have only movement boundary. `room_asset_root.gd:13,94` hardcodes occlusion:false. Players/enemies/arrows cross ruins; hidden enemies invisible because cutaway protects only hero and plan has no statics.
2. **R2 town: ghost subject instead of revealing occluder, rectangle-only tests.** Controller 81-87 sets alpha 0.4 for any cover>0 without gradient; plan 118,137 Rect2.intersects. Combat has pixel masks `arena_world_view.gd:713-750`. Target architecture's local cutaway exists only in combat.
3. **R3 combat: overlapping plan-alpha and hero cutaway**, unresolved. `arena_actor_presenter.gd:431-438` and `combat_presentation_controller.gd:385-393` process the same pair twice, possibly gray; melee rectangle overlap can constantly make rear actors alpha 0.4.
4. **R4: all-soft actors, footprints much smaller than art.** Town hero radius 6 `town_scene_root.gd:13`, combat14/16 vs 48×48+ sprite boxes. Y-sort cannot fix half-bodies entering walls/each other.
5. **R5: no production SpatialOverlay wiring**, despite infrastructure/tests.
6. **R6: no vision/navigation/spatial-occlusion/occlusion_rank consumers.** Only half the seven-channel promise lands; no direct visual effect but implementation incomplete.

## 4. Test Gaps

Covered: spatial kernel `test_spatial_kernel.gd:20-35`, room port `test_spatial_room_port.gd:33-42`, pipeline `test_world_asset_pipeline.gd:24-32`, town end-to-end `test_presentation_production_assembly.gd`, combat cutaway `test_world_occlusion.gd`.

Uncovered promises: combat statics in collision/occlusion, absent both functionality/data; real-room VisionResolver/OcclusionResolver; any navigation queries; production overlay writes; combat plan-alpha end-to-end when enemies are covered.

## 5. Recommended Minimal Steps

1. Bake ruins/tower into spatial truth: editable static/occlusion bindings in room_asset_root schema, or layout structures→static_geometry+occlusion bindings in manifests; change checks 13,94, rebake three rooms. Immediately gains walls/projectile blocks/static-plan entries.
2. Reuse town plan-alpha for combat enemies behind statics; consider generalizing cutaway_for beyond hero `arena_world_view.gd:834-844`.
3. Town: reuse pixel descriptor `arena_world_view.gd:690-707`; replace cover>0→0.4 with cover_fraction tiers or reveal.
4. Remove double handling: one pipeline per pair, retaining hero cutaway and disabling hero/enemy plan-alpha or taking min (`combat_presentation_controller.gd:357-398`).
5. Tune combat enemy radius and town hero 6→8-10; try hearthside.spatial.json hero_radius/main 1063,1246 with test_town_geometry_rebuild.gd routes.
6. Wire or explicitly defer overlay/vision/navigation in TARGET_ARCHITECTURE; if needed, begin with one town gate toggle.
7. Migrate/remove old geometry cluster with movement changes; clean import first to avoid duplicate global classes.

**Overall:** spatial kernel, fixed pipeline, dual mounting, town occlusion are real and tested. Poor collision/occlusion mainly comes from missing combat geometry data, town ghost-subject/rectangle semantics conflicting with cutaway expectations, and designed soft separation/small footprints. Prioritize steps 1/3 for maximum visual gain at minimum change.

## Addendum: Fix Status, 2026-10-20

- **R1 fixed:** all 13 layout-aligned ruins/tower represented as integer convex-octagon static_blockers under GeometrySources/Static in three rooms, pinned by `tests/test_combat_structure_blockers.gd`. Walls/gates/tower also block projectiles; low posts movement only. Deterministic ring clearance projection `main.gd _project_static_clear`; enemy candidate scoring considers static_blockers in enemy_tactics.gd, reducing straight-wall grinding 193 ticks→≤4.
- **R2 fixed, upgraded to occluder reveal:** hardware [initial](../playtest/GPU_VISUAL_2026-10-20.md) and [R2 stress](../playtest/GPU_VISUAL_2026-10-20-R2.md) showed dimming fully hidden subjects is ineffective. Foreground/nameplate reveal now uses cover_fraction: below 0.15 none, linear, ≥0.45 alpha 0.4/0.35; subjects remain opaque. R2 fixed lookup root after foreground reparenting: search SceneRuntime subtree. White blocker polygon rendering fixed with visible=false and fail-closed contract. Pixel descriptor still unwired; needs separate plan-input work.
- **R4 partial:** enemy 16→18 was reverted: soft separation 14+18=32 exceeded MELEE_ATTACK_RANGE 30.25, preventing all melee. Future changes must tune MELEE_ATTACK_RANGE/MELEE_RING_RADIUS and review tactics constants together. Player radius capped by ring spawn socket clearance 14.0. Town radius tightly coupled to baked digest, requiring rebake. Constraints documented for joint tuning; foot/wall-top visual alignment remains GPU backlog.
- **Deferred channels labeled:** TARGET_ARCHITECTURE.md marked navigation/vision/overlay explicitly deferred for chapter one.
