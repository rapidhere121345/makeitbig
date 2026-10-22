# Hearthside Spatial and Art Reconstruction Design

Date: 2026-10-22. Review baseline: `33cbd37`.

Status: initial review/design complete; authored reveal foundation and independent greybox subsequently implemented. **Production new assets, town migration, and finished acceptance remain incomplete.** Section 2 preserves baseline 33cbd37 evidence; current fixes/validation: [implementation record](../playtest/TOWN_MODULAR_FOUNDATION_20261022.md). Unfinished targets do not override current runtime facts in ARCHITECTURE.md.

## 1. Decision

Change environment production units from slices of one scene illustration to **complete ground + independent spatially meaningful objects + artist-designed revealed states**.

Preserve first-chapter gameplay, simulation kernel, movement authority, static spatial index, and presentation boundary. Rebuild asset contracts, native authoring, draw order, and occlusion presentation. No evidence supports discarding MovementResolver.

Pillars:

- **Readable routes:** painted roads, doorways, cliffs match walkable space.
- **Bodies occupy ground:** collision follows contact bodies and explicit clearance; actors do not enter visual solids.
- **Complete scene after reveal:** removing canopy/roof exposes genuinely painted lower layers, not holes.
- **Consistent pixels:** both normal/revealed states authored, avoiding gray fog holes that destroy materials.

Checklist:

- [x] Trace actual runtime layers to originals/offline generation.
- [x] Inspect original R4-D frames and independent PNGs, separating mechanism acceptance from art quality.
- [x] Independent GPT 6.1 Sol/medium review of runtime, collision, tests.
- [x] RTX numeric comparison proves shader color bug without holes.
- [x] Define delivery contract, responsibilities, sample scene, acceptance gates.
- [x] Implement authoring/reveal controller/independent greybox; actual GPU iterations.
- [ ] Produce first new production assets, migrate town, accept finished visuals.

## 2. Confirmed Problems

### 2.1 Assets lack formerly hidden content

Actual chain:

```text
art/production/p1/hamlet_town/town.png (whole-scene illustration)
  + layout.json foreground polygons
  -> tools/town_layers/bake.py
  -> content/rooms/town/layers/*.png
  -> hearthside.tscn Sprite2D
```

bake.py:25-64 assigns pixel ownership by foot order; overlapping pixels belong only to the last object. Ground retains only owner==0. verify():73-98 requires exact reconstruction and exactly one owner per pixel, proving complete segmentation, not complete independent assets.

Read-only Pillow count: of 1,474,560 ground.png pixels,361,105 have alpha 0, **24.49%**. Removing/fading objects leaves no ground beneath. Correct repainted scenes need complete layer overlap; ownership=once is not a general asset-validity criterion.

Direct inspection:

- layers/loadout.png combines building, snow, and clutter, with internal polygon voids.
- layers/tree_east.png combines slope, rock, and partial trees, not an independent tree.
- layers/ground.png has large object-shaped transparency, with shadows/environment still mixed into the base.

R4-D p2_01_loadout_eaves.png and p2_09_tree_east_mira.png show actors but mix dark architecture/rock around them, not proof of natural space. p2_24_tree_south_cover.png also makes actor/slope/canopy depth difficult to read. Existing screenshots were inspected, not a new live whole-town walk.

**Regenerating art is directly justified. Whole-scene art can be atmosphere reference, not a production master for movable/revealable objects.**

### 2.2 Darkening without cutout: GPU reproduced

occluder_cutout.gdshader:15-26:

```glsl
vec4 c = texture(TEXTURE, UV) * COLOR;
```

CanvasItem fragment COLOR already includes texture sampling, so multiplication darkens twice. TownPresenter assigns the material to registered native occluders even with hole_count=0.

Rendered the same solid texture three ways without holes: no material, current shader, and an in-memory shader replacing the expression with COLOR.

| Case | RGBA |
| --- | --- |
| No material | `(0.4980, 0.7490, 0.2471, 1.0)` |
| Current shader | `(0.2471, 0.5608, 0.0627, 1.0)` |
| Single sample | `(0.4980, 0.7490, 0.2471, 1.0)` |

Godot 4.7.2, Xvfb `:109`, X11, Compatibility/OpenGL 3.3, NVIDIA 595.91.07/RTX 4080 SUPER; exit 0, temporary display cleaned. Evidence: `build/current/town_shader_identity_review.gd`, `town_shader_identity_review_109.log`, `town_shader_identity_review.png`. Earlier `:98` failed display-lock conflict, not counted. Exit 0 means **defect reproduced and in-memory correction verified**, not product shader pass. Production shader unchanged in this initial review.

### 2.3 Declared capability differs from delivery

- tools/town_layers/bake.py:62 still emits supports_cutaway=false / supports_fade=false; README explicitly lacks a clean plate.
- Current layers/manifest.json sets both true but unknown_underplate remains transparent.
- town_scene_root.gd:69-74,192-195 requires/republishes true without checking underlying art.

`python3 tools/town_layers/bake.py --check` **failed**, `source/layout digest changed`. Original-image SHA matches; recorded layout SHA `8f740098…` vs actual `f7712d00…`. Early exit means later cold-generation checks did not pass this time. Capability contradiction is separate.

Do not run --author-scene as a fix: it overwrites collision revisions. New production must separately trace asset provenance and placement provenance; capabilities follow delivered data and checks.

### 2.4 Coverage is still rectangle overlap

OcclusionPlan.occluders_of():112-138 uses whole art-box overlap, ignoring branches, open doors, transparent corners. Full actor animation cells also include transparency. AABB is broad phase only, not final reveal authority.

- town_presenter.gd:228-241 takes min across actors; a 10%-grazing NPC can keep the same piece opaque for a fully hidden hero.
- Controller alpha floor 0.4 combined with presenter lerp(1,0.18,1-alpha) yields **0.508**, not 0.18. Two such fully covering pieces give combined foreground opacity≈75.8%.
- occlusion_plan.gd:143-155 sums areas without union, double-counting overlap. This affects coverage reports, distinct from per-piece min.

These are code-derived findings; only the color issue received a new GPU counterexample this round.

### 2.5 Authoring unit is not yet a spatial object

Visuals, polygons, sort feet, and interaction sockets occupy parallel lists. Moving a building does not naturally move footprint, standing positions, and occlusion. hearthside.tscn:1001-1023 wedge/cliff/south-bank seals are useful patches, not reusable spatial-design rules.

One composite containing front/side walls, roof, ground, and clutter has one Y baseline and cannot express every approach direction. Canopy, rock, and trunk should not share one whole-slice hole treatment.

A smaller same-Y determinism bug: town bindings give actor rank 1, actual node defaults 0 because consume() omits rank; native fallback sort names differ from plan binding IDs. Exact-baseline rendering can disagree with plan; this is not the explanation for all visual issues.

No new penetration or internal-triangle-edge stutter reproduced; do not call potential risks confirmed solver bugs.

## 3. Target Asset and Authoring Contract

Detailed delivery/generation brief: [TOWN_MODULAR_ASSET_BRIEF.md](../art-production/TOWN_MODULAR_ASSET_BRIEF.md).

### 3.1 Object prefab is the sole editing unit

```text
EnvironmentObject (translation-only instances; no arbitrary scale/rotation in v1)
|-- GroundParts        Ground decals, contact shadows
|-- VisualParts        Explicit sort anchor / rank / stable part ID per piece
|-- RevealParts        Full/revealed states, fixed shared canvas and anchors
|-- Footprint          Ground contact, independent of texture alpha
|-- MovementEnvelope   Explicit collision expansion, offline-derived
|-- InteractionSocket  Existing facility ID retained
`-- ApproachArea       Standing/route clearance checked during authoring
```

This is a proposed logical contract, not a claim that current scenes already support this node structure. Art packages deliver local resources; room .tscn owns instances/translations; offline baker expands to existing flat manifest/index. No second runtime collision authority for prefabs.

Current TownSceneRoot accepts only direct Sprite2D children and forbids translated geometry containers. Update traversal/validation and bake local to world coordinates; merely parenting nodes is not a finished prefab.

Expansion invariants:

- asset_id identifies reusable resources; placement_id identifies stable room-authored instances. Final bindings placement_id/part_id, never runtime Node instance IDs.
- Add instance translation exactly once to footprint, socket, mask position, sort anchor. Texture-canvas offsets stay local, not placement-added twice.
- Every sortable part enters one SortRoot at mount; do not sort a whole prefab by parent Y. Full/revealed are states of one part, not competing sort IDs.
- Test two instances of one resource at different positions, swapping insertion order.

Resource flow remains WorldAsset → native contract → RoomPresentationBinding / RoomPresentationProjector → plan / presenter. Occlusion-only bindings gain strictly validated presentation descriptors: full/revealed references and content SHA, mask reference/content SHA, local anchors, reveal policy. Extend closed schema/version checks and presentation_digest_input. No gameplay metadata; art changes alter presentation digest, not gameplay digest. Plan contains stable IDs, immutable coverage data, and spatial relationships, never nodes/runtime state.

### 3.2 Footprint, margins, walkable space

- Footprint is **ground-contact body**: roots, wall bases, log bases. Roofs/canopies/halos/shadows do not create movement blockers.
- One explicit expansion yields MovementEnvelope. Initial art-safety margin 3–6 design px, calibrated per sample object and recorded as author parameter.
- Runtime still sweeps hero radius 6. Foot-center stopping distance adds actor radius to expanded boundary; baker/resolver must not both expand.
- Route standards measure **distance between collision envelopes**. Begin sample main roads 64–96px, single-person branches≥48px. These are design starting points for playtesting, not existing measurements. Close narrower gaps by moving objects or adding visible solids.
- Simple large-wall contours; split long diagonal fences into segments with real feet. Offline route checks treat whole objects, not triangulation internal edges as visible boundaries.
- Separate cliff-top platforms from cliff faces. First-chapter bridge has one walkable plane, no implied under-bridge passage or multilevel height navigation.
- Invisible seals are transitional only. Final closed pockets need visible snow/fence/rock, not apparent paths blocked by air.

### 3.3 Two art states preserve solid space

| Category | Normal | Revealed |
| --- | --- | --- |
| Ground/bridge deck | Complete continuous base | Always present, not reveal participants |
| Tree | Roots/complete trunk + canopy | Retract canopy, retain painted trunk/low branches/ground |
| Facility | Base/lower structure + roof/upper | Authored low walls/beam-post sections, roof removed |
| Small logs/low fence/lamp | Complete independent sprite | Usually correct sorting only; readable layout |
| Long fence/high wall | Segmented objects | Authored reveal only on front-covering segments |
| Rock/cliff | Stable solid | No holes for actors; adjust walkable area, height, placement |

"Transparent version" means **authored revealed-art version**, not multiplying original alpha. Low walls remain solid, trunks remain, ground stays complete. Chapter-one interaction is in exterior service areas; roof removal does not add full accessible interiors.

## 4. Runtime Boundaries and Refactoring

Retain:

- SimulationWorld / MovementResolver fixed ticks and commit boundaries.
- WorldAsset, read-only spatial manifest, static index, stable bindings.
- Detached snapshots/presentation ports; presentation cannot write movement/vision/projectile facts.
- WorldPresenter shared sort domain/camera; unify sort inputs, not a parallel system.

Change:

1. **One sort truth:** same `(baseline, rank, binding_id)` for each sortable part in drawing and plan. Ground decals stay outside object-Y sorting.
2. **Explicit parts:** meaningful front/back components for deep buildings; full/revealed share anchors. Do not put every roof in highest Foreground, which would cover actors actually in front.
3. **Two-phase coverage:** AABB broad phase, offline mask/authored polygon precise phase. Exclude ground, halos, shadows. Actors have stable head/chest readable regions relative to feet, not transparent full animation rectangles as denominators. CPU bitmap/polygon queries avoid per-frame GPU readback; final visual acceptance still examines pixels. Always use **full-state mask**, position, sort to calculate demand; revealed state not covering must not auto-close. reveal_weight never alters detection inputs, or even hysteresis will oscillate.
4. **State switch, not generic circular holes:** OcclusionPlan supplies depth/coverage relations. Controller outputs reveal_weight only,0=full/1=revealed, not old actor-alpha reused as hole-alpha.
5. **Relevant subjects only:** always hero, current conversation NPC, not idle NPCs opening the whole town. Any protected demand opens a part; all clear before closing. Whole-part transitions take maximum demand; independent regions keep separate states.
6. **Presentation-only transitions:** initially 120–180ms, distinct enter/exit thresholds against leaf-edge oscillation; calibrate visually, no advance correctness claim. Draw common structure once. Mutually exclusive states use one premultiplied RGBA interpolation/composite or reviewed pixel dither, not two translucent sprites causing ghosts/dark edges.
7. **Capability checks:** revealed support requires complete lower art, shared canvas/anchor, legal mask, roof-off preview. Remove global hardcoded true. Missing assets fail production checks, not silent old-circle fallback or changed footprint.

Only one object definition/instance contract, baker extension, and shared reveal controller needed. No generic ECS, gameplay SceneTree queries, or extra navigation system.

## 5. Implementation Order and Retirement

| Stage | Delivery | Gate |
| --- | --- | --- |
| A: old baseline | Single-sample shader, sort tuple, image-backed identity regression, record asset deficits | Unrevealed colors match original sprite; not completed town remake |
| B: greybox |960×640 sample,640×360 viewport, existing Ranger, one building/tree/fence corner+gate/log pile, continuous ground | Natural four-side contact, doorway roundtrip, near-object interaction; humans can identify contact/walkable areas |
| C: new art sample | Independently regenerated full/revealed/lower/shadow assets per brief | Complete scene with all uppers off, no residue after moving objects, more natural in runtime |
| D: town replacement | Facilities, Training, trees/props, shoreline by region; preserve facility/save IDs | Each region passes, then complete player route/collision regression |
| E: retire old chain | Unreferenced whole-image cutouts, old hole path, ownership gates removed; provenance/build entry updated | Cold build/export pass, traceable new assets, no competing provenance explanations |

If sample fails, repair sample only, no mass town generation. Old assets support the existing version during migration only; after replacement clean by references, retaining necessary production sources, not abandoned candidates.

B/C use independent rooms. A D-region includes continuous base and every intersecting old cutout/new visual/collision/socket/route. Replace atomically as a closed unit; check old bordering pieces for embedded background. Never stack new ground with old hole-filled ground or replace only a tree above missing ground. If nonoverlapping boundaries cannot be defined, assemble an independent new town and switch whole scenes rather than force mixed regions.

Check layout compatibility separately: TownRuntime.travel_snapshot()/restore_travel() stores/restores in-memory positions/route cursors and currently rejects old positions inside blockers. Unchanged facility IDs do not prove safe migration. Add explicit layout/travel versions; validate restored position. For invalid cross-layout positions, an explicit migration boundary selects a verified entrance/safe exterior facility socket, clears old route cursor, records migration. Invalid same-layout positions still error. No silent nearest-walkable search. If persistent saves actually carry the same position payload, upgrade format/migration too; this audit did not establish persistent town-foot coordinates and must not invent existing fields.

## 6. New Acceptance Criteria

Existing tests still cover stable IDs, input, isolation, movement commit, native/manifest consistency. Test counts, screenshot counts, or modulate.a==1 do not replace visual acceptance.

| Check | Observable evidence / failure condition |
| --- | --- |
| Asset completeness |Inspect isolated object on neutral background; no residue after removal; all revealable uppers hidden leaves no unpainted areas |
| State alignment |Shared full/revealed structure pixel-identical, no foot drift, shadow jump, broken section |
| Reveal stability |Stand behind roof/canopy for seconds; full reveal never self-reverts; detection uses full mask only |
| GPU identity |reveal 0 matches original no-effect sprite; shader compile failure rejects |
| Real coverage |Open doors/transparent canopy corners do not trigger; solid head/chest coverage does; passing in front does not switch wrongly |
| Multiple objects/subjects |Hero readable behind two pieces; grazing NPC cannot close hero reveal; idle NPCs cause no unrelated switches |
| Sorting |Front/back/exact-Y traversal, swapped instance insertion; rendering remains plan-consistent |
| Instances/versions |Two resource instances translate independently; new building occupying old travel position invokes explicit migration, not old cursor |
| Collision feel |Four-side approach, diagonal edge travel, reverse escape, dash, corners, doorways; view collision overlay with visible base |
| Route topology |Same movement sweep for roundtrips; reachable-area/corner samples find dead pockets, not only cleared waypoints |
| Frame rate/camera |Fixed-tick same input under 30/60/144 render FPS, compare authoritative paths; no camera texture/reveal drift |
| Play feel |Without debug overlay, continuously enter town→Board→Loadout→Forge→Training→leave; no rock penetration/empty-road sticking, actors/objects identifiable |

Connectivity sampling finds errors, not mathematical proof. Key paths still need real sweeps and continuous play. Visual records include before/mid/after states, short sequences, GPU/display/exit information. Approve one sample's art quality before using it as town-wide consistency baseline.

## 7. Initial Review's Validation Boundary

Read source, alpha, existing screenshots, source SHA; ran offline reproduction check (**failed**) and independent RTX shader color probe (**defect reproduced**). GPT 6.1 Sol/medium subagent performed read-only technical review, no build/file changes.

No new production art, game-code changes, full rebuild, or new whole-town GPU playthrough occurred in that initial review. This design gives implementable, falsifiable production/acceptance contracts, not a delivery claim that collision/occlusion are solved.
