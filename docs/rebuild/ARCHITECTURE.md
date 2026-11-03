# Make It Big runtime architecture

Current architecture of the clean rebuild. Compatibility adapters are not
carried: domain boundaries use typed records and fixed ports, and simulation
code does not look up the SceneTree or a global gameplay singleton. A general
ECS is unnecessary; typed stores plus stable spatial indexes provide the
required data locality without erasing ownership.

## Layers

Each directory under `src/` is a layer and may only depend on the layers to its
right:

| Layer | May depend on |
| --- | --- |
| `core` | nothing |
| `localization`, `persistence`, `content` | `core` |
| `systems` (pure rules) | `core`, `content` |
| `runtime` (room authority) | `core`, `content`, `systems` |
| `presentation` | `core`, `content`, `localization`, `systems`, `runtime` |
| `game` (composition, routes, application) | every other layer |

A dependency is a `res://src/<layer>/` path or a reference to another layer's
global `class_name`. `scripts/check_architecture.py` (run by `check.sh`)
enforces the table. It also ratchets string dispatch (`has_method("x")`,
`.call("x")`, `.call_deferred("x")`, `.callv("x")`) and private reach-ins
(`_root._x`, `_main._x`, `_screen._x`, `_owner._x`, `_host._x`), which typed
ports and owners' public APIs should replace. Existing debt is listed in `scripts/architecture_baseline.json` and
may only shrink: a new violation fails, an exception that is no longer needed
fails, and `--update-baseline` records reductions but never growth.

Placement follows the table: dependency-free geometry (`ArenaGeometry`,
`SpatialShape`, `SpatialSweep`, `CombatQuery`) lives in `src/core/geometry/`
so rules and runtime can share it; the room-authority combat code that drives
runtime state and ports (`CombatSystem`, `CombatSimulation`,
`PlayerCombatRules`, `PlayerMotionSystem`) lives in `src/runtime/combat/`; the
Ranger's authored action numbers (`RangerSkillRules`) are content, so the skill
registry can validate against them. The authored occlusion contract
(`OcclusionAuthoring`: policy ids, detection-rect containment, fade volumes)
and `TextureLoader` live in `src/content/art/`, so world mounts validate
authored art without importing the presentation controllers. The detached
projection of authoritative snapshots into draw order
(`RoomPresentationProjector`, `RoomPresentationBinding`, `PresentationFrame`,
`OcclusionPlan` and the sort relation in `occlusion_query.gd`) lives in
`src/runtime/projection/`: runtime publishes frames and plans through
`RoomPresentationPort`, and presentation only consumes them. `src/systems/`
keeps pure rules that read only core and content. The layer table currently
has no exceptions.

## App shell

`GameRoot` (`src/game/game_root.gd`) is the composition root: it owns the
services (`application_state`, `scene_router`, `save_store`, `playtest_log`), the
current route and screen, and the pixel stage. Its helper modules in
`src/game/root/` own their own state and use only GameRoot's public shell API
(`transition()`, `status_message`, `persist()`, `present_*()`,
`record_playtest()`, `request_exit()`, `is_test_session()`, ...):

| Module | Owns |
| --- | --- |
| `contract_flow` | contract launch/finish, the deferred defeat route, `last_contract` |
| `facility_actions` | facility action dispatch |
| `route_snapshots` | route snapshot builders |
| `display_settings` | language, menu scale, render quality, audio, window and stage lease |
| `test_console_host` | the F10 console and the session menu |
| `playtest_recorder` | playtest log session and timers |
| `auto_smoke_harness`, `capture_harness`, `prototype_debug` | test, evidence and `--mib-*` tooling |

`DiagnosticsPolicy` decides from the launch arguments whether the F10 console
and playtest logging start: always in debug builds, only with `--test-console`
/ `--playtest-log` in release exports. The planned room-level split is in
[ROOM_SESSION_DESIGN.md](ROOM_SESSION_DESIGN.md).

## Runtime graph

```text
Native room scenes (content/rooms/**/*.tscn) and content definitions
    -> tools/world_manifest bake (bake_core.gd, bake_spatial.gd)
    -> immutable WorldAsset (scene path, manifest path, gameplay and
       presentation digests) + generated SpatialManifest
        -> static spatial indexes, vision/projectile data, occlusion data,
           sockets
    -> RoomCatalog selects the asset for a layout
    -> GameRoot (routes, contracts, save)
        -> SceneRuntime (mounts one room)
            -> SimulationWorld
                -> SimKernel
                -> SimEntityStore
                -> SimHitBuffer and the other typed buffers
            -> DynamicSpatialIndex
            -> MovementResolver
            -> ContinuousHitResolver
            -> RoomEncounter
            -> DamageResolution
            -> StatusEffectLedger
            -> DeathSettlement
            -> CombatRoomLoot
        -> detached SimSnapshot
            -> PresentationFrame
                -> OcclusionController
```

`RoomDefinition` identifies a room and its rules. `WorldAsset` points to the
native `PackedScene` and the generated `SpatialManifest` — a build product,
never a second hand-edited map. Runtime state lives in `SimulationWorld` and
room state, never in shared Resources.

`SceneRuntime` assembles one world clock, registry and presenter per room:

```text
SceneRuntime
├── SimulationWorld
├── ActorRegistry
├── WorldPresenter
│   ├── Ground
│   ├── GroundEffects
│   ├── SortRoot (Y-sort)
│   └── Foreground
└── room-owned interaction and navigation nodes
```

`SimulationWorld` owns the room's fixed-tick accumulator and versioned command
boundary. A room supplies its gameplay phases after `step()` commits a tick;
rendering may continue to resolve presentation frames after the authority has
reached a terminal state. `MainArena` is initialized with that same configured
`SimulationWorld` for explicit test fixtures and mounted rooms; there is no
detached tick counter or implicit combat wave.

## Spatial truth

`WorldAsset` owns immutable authored data. `SpatialOverlay` owns runtime state
for doors, gates and destructible geometry and produces a new effective query
revision at a tick boundary. The baked asset is never mutated.

Static and dynamic indexes are separate:

- `StaticSpatialIndex` contains authored convex geometry indexed per semantic
  channel.
- `DynamicSpatialIndex` contains committed actor bodies, hurtboxes, projectiles
  and other runtime shapes; its buckets are rebuilt or updated at the movement
  commit boundary in stable entity order.

The public query surface is semantic, never a generic `is_blocked` call:

- movement: footprint sweep and contact resolution;
- navigation: region, portal and traversal-cost queries;
- vision: line of sight and attenuation;
- projectile: continuous environment contacts;
- attack: attack-path and area contacts;
- hurtbox: dynamic target shapes;
- occlusion: presentation-only foreground relationships.

Chapter-1 delivery status (2026-10-19 audit): `movement`, `projectile`,
`attack` and `hurtbox` are live production channels (authored combat static
blockers publish `movement` plus `projectile`). The `navigation` graph API,
a vision resolver (the unused first draft was removed) and runtime
`SpatialOverlay` producers are intentionally deferred for chapter 1: no encounter consumes them yet, and they
must not be wired without a gameplay slice that does. The presentation-side
occlusion channel stays art-box driven and never enters this spatial index as
a gameplay surface.

`ContinuousHitResolver` queries static and dynamic indexes together and
returns ordered contacts with `toi`, normal, surface/entity identity, channel
and response material. It never applies damage. An opaque world blocker wins a
tie with a target at the same `toi`; penetration and multi-hit behavior belong
to the attack definition.

`MovementResolver` is the only authority that commits an actor position. It
supports `solid`, `soft` and `ghost` dynamic body policies. Soft separation is
the default for the player/enemy crowd model; every separation displacement is
still validated by the static movement query. For outer-circle contact, the
motor constrains the projected continuation to the footprint circle and sweeps
that chord against the inner hole and static blockers, then validates final
clearance with the same query contract. `move()` reports `ok/error`;
`ActorRegistry` rejects invalid results before changing actor state or the
committed motor tick — it validates rather than clamping, and invalid authored
starts are not relocated.

`CombatQuery` owns pure attack-shape, line-sweep and segment-distance queries.
It does not decide damage or movement.

## Fixed-tick pipeline

Every room uses the same code-defined order:

1. begin tick and apply the previous structural commit;
2. build a read-only tick view;
3. collect player, AI and encounter intents;
4. commit actions, casts, projectiles and hazards;
5. resolve movement and dynamic contact;
6. refresh the dynamic spatial index from committed poses;
7. advance projectiles, attacks and hazards and fill `SimHitBuffer`;
8. sort and resolve damage, status applications and periodic effects;
9. mark deaths and produce settlement, loot and encounter commands;
10. commit spawns, removals, overlays and terminal state;
11. publish an authoritative snapshot.

The scheduler is fixed and explicit rather than configurable. Structural
changes never remove an entity in the middle of a query phase. Every entity
reference contains a generation and room revision; stale references fail
closed. A per-room `SimStableKey` is monotonic and never reused.

## Combat ownership

Kernel domains:

- `RoomEncounter` owns waves, spawn requests, active member accounting, clear
  conditions and room terminal state. It does not instantiate nodes or
  directly delete combatants.
- `CombatHazard` owns shape, lifetime, faction, periodic cadence and
  per-target hit suppression. It emits `CombatHitRecord` values only.
- `DamageResolution` is the only damage authority: it consumes ordered hit
  records, resolved stats and resistances, then emits damage, status and death
  results. It does not query the scene or decide room victory.
- `StatusEffectLedger` owns effect instances, stacking, refresh, expiry and
  periodic damage requests.
- `DeathSettlement` converts a death exactly once into loot, encounter and
  removal requests, keyed by `SimStableKey`. A death request carries room
  revision, committed tick, source and spawn identity, feet position,
  archetype and drop tags; repeating the same key returns the original
  receipt. It never rolls an item and never calls `RoomEncounter`.
- `CombatRoomLoot` receives spawn requests through a fixed port: authored
  slots are normalized and sorted, placement is checked through the movement/
  spatial query port, and item generation receives the room loot seed plus a
  stable slot stream key. Pickup is a command committed on a later tick after
  an alive/range/room-phase check. Victory turns unpicked items into
  `left_in_room` and picked ones into settlement items; defeat turns both into
  `forfeited_by_defeat`. Settlement is cached verbatim on repeat; the room
  domain never writes session inventory.

Room services and player domain:

- `CombatSimulation` owns the combat phase order after the world commits a
  tick: player preparation, room rules and hazards, command collection and
  routing, player rules and motion, encounters, projectiles, hazard damage,
  terminal checks and automation timeout. It calls `PlayerCombatRules`
  directly for player phases; its ports connect room, input, target, encounter
  and projectile services without handing player timers or damage authority
  back to `MainArena`.
- `PlayerCombatState` stores health, cooldowns, mobility, marks, talents and
  the action timeline for a frozen room build; `PlayerCombatRules` advances
  them and owns damage, cast requests and talent consumption. Position is read
  from `ActorRegistry`; there is no writable player position copy in `MainArena`.
- `PlayerMotionSystem` computes displacement and submits it to the shared
  registry/motor once per committed world tick, including stationary ticks. A
  repeated motor submission fails before state mutation.
  `release_input(tick)` clears only pending mobility input; it preserves an
  active dodge/dash, timeline, counters, command sequence and event stream.
- `CombatInputAdapter` owns physical input and pointer capture.
  `CombatCommandSource` turns manual input edges into device-free command
  dictionaries. `CombatCommandRouter` is the only adapter between an
  arbitrated command batch and player intent: rejected receipts are reported,
  accepted commands preserved, and a buffered dodge keeps its original tick so
  replay input is unchanged.
- `ProxyIntentSystem` is the Auto-only decision boundary: it consumes the
  published observation and proxy build and returns intent candidates; it does
  not read device input or move actors. `MainArena` remains the owner of the single
  command sequence. `SmokeInputDriver` is a separate diagnostic input policy
  over detached observations.
- `EncounterDirector` owns enemy intent execution, enemy action phases, boss
  transitions, hazard timing and elite rules. `CombatSystem` owns the ranger's
  projectile lifecycle, swept contact, damage application, impact traces and
  room totals; `reset_room()` is the explicit totals boundary and
  `outcome_snapshot()`/`remaining_boss_health()` are read-only. Encounter
  applies player damage through the same configured rules instance with an
  explicit source position.
- `CombatRoomRules` owns terminal decisions and reward calculation, including
  same-tick victory-before-defeat priority and loot RNG order. `MainArena` does not
  roll rewards or decide victory.
- `CombatRoomRuntime` owns room mounting, input relay, terminal observation
  and one-shot signal delivery through `MainArena.start_room()` and
  `return_requested`. `CombatRoomResult` is a pure result projection from the
  immutable room configuration and an authoritative snapshot; it filters
  internal reward fields and emits the public Law Tally shape.
- `CombatStateSnapshotBuilder` is the sole owner of the authoritative combat
  snapshot used for replay/state hashes. It orders actors and projectiles and
  excludes presentation state. Boss part pose, resolved pose and radius carry
  fixed big-endian IEEE-754 binary64 hex so sub-0.001 changes cannot disappear
  from the hash; this encoding does not quantize gameplay geometry.

Room-local combat records stay outside the scene entry point:
`CombatEnemyState` owns mutable enemy and boss fields while
`CombatArrowProjectile` and `CombatArrowTrace` are data records consumed by
`CombatSystem`. They do not draw, read input, or access the scene tree.

## Manifest and mounting

Native combat room assets are selected by the strict `RoomCatalog`;
presentation copy and spawn profiles are content data. Every shipped combat
scene contains a `RoomAssetRoot` with named Ground, GroundEffects, SortRoot,
Foreground, GeometrySources and Sockets groups. `SceneRuntime` validates room
identity and all six canonical manifest fields before mounting, then publishes
authored bounds, movement boundary and positioned spawn sockets — mounted
rooms must use them; missing data cannot fall back to layout formulas. The
manifest separates movement, navigation, vision, projectile and occlusion
channels; visual bounds do not define movement or attack shapes.

`tools/world_manifest/derive.gd` derives the manifest from the native scene;
the concave/hole/passage sample uses `NativeStaticRoomRoot` with the same
generic `static_blocker` bindings, whose convex pieces register before READY.

## Battlefields and proxy terrain navigation

Five campaign battlefields (`snowbound_road`, `river_crossing`, `ruined_village`,
`quarry_pass`, `colossus_approach`; `ArenaGeometry.BATTLEFIELDS`) are native
combat scenes in `content/rooms/combat/*.tscn` with baked
`*.spatial.json` manifests, registered in `room_catalog.json` like the other
combat rooms. They use the whole authored `arena_rect` as a rectangular movement
boundary — never an annular arena — and each scene's `Sockets/CombatSpawn`
marker positions the encounter. Terrain and structures are convex
`Polygon2D` static blockers under `GeometrySources/Static`, bound by
`binding_id`:

- `combat/terrain/water/*` and `combat/structure/ruin.low_pier#*` block
  movement only; arrows cross them.
- `combat/terrain/cliff/*` and wall-shaped structures (`ruin.gate`,
  `ruin.wall_corner`, `ruin.broken_wall`, `tower`) block movement and
  projectiles.
- Terrain and structure blockers publish no navigation, vision or occlusion
  channel; only the whole-map movement boundary does.

`tools/world_manifest/author_battlegrounds.py` authors these polygons from the
reviewed terrain contacts and the manifest is baked from the scene, so painted
art is never collision authority.

`BattlefieldScene` (`src/presentation/battlefield_scene.gd`) is a read-only
presentation loader used by `ArenaWorldView`. It resolves each battlefield
through `RoomCatalog`, instantiates the native scene, validates its
`RoomAssetRoot` contract, and records bounds, spawn socket, terrain polygons
(`combat/terrain/*`) and reused structure feet (`combat/structure/*`). It then
checks `art/production/p1/battlefields_v01/assets.json`: every field needs a
packed 1024x640 floor plate and a 1536x1024 `_extension` plate whose SHA256
matches the pack. Any failure leaves `pending_reason` set ("ASSETS PENDING")
and no partial state; missing art is a load error, not a fallback.
`ArenaWorldView` also uses a battlefield-specific camera that centres on the map
and allows a small overscan so the hero stays visible at the edge.

The proxy navigation script (`src/systems/proxy_navigation.gd`, preloaded by `ProxyDecision`
for Auto mode) is static, footprint-aware routing over the observation
snapshot's `walkable_geometry` and `static_blockers`; it does not read the
spatial manifest's navigation channel and the actor motor remains the only
authority on movement. `direction()` returns the straight line when the
segment is clear (arena boundary plus every blocker, swept with a 15-pixel
clearance circle). Otherwise it builds, and caches per geometry/blocker set, an
`AStarGrid2D` with 24-pixel cells whose blocked cells are solid, snaps start and
goal to the nearest connected cell within two cells, and steers to the furthest
path point still reachable by a clear segment. `retreat_direction()` does not
route to a goal: it takes the first clear local step from a stable angular
ordering of candidate directions (`ArenaGeometry.candidate_directions`) with a
caller-supplied side sign, so retreats are deterministic without per-tick
randomness. A sweep that merely starts in contact and moves away from the
surface is treated as clear so a legal actor touching a blocker can leave it.

## Presentation and occlusion

The presentation frame contains detached actor poses, feet anchors, baseline,
rank, stable key and actual art boxes. `OcclusionController`
calculates local cutaway and alpha transitions from that frame. Interpolation,
alpha and Y-sort never enter the authoritative hash and never feed back into
movement, vision or combat.

`PresentationFrame` is the only adapter from an authoritative snapshot to
occlusion data: it rejects entries without a real art box and rejects
collision/debug geometry as an implicit visual source. `OcclusionPlan` orders
the frame by baseline, rank and stable key, reports front art-box coverage,
and the controller interpolates only detached display feet and alpha. The
plan and controller expose no movement, vision or projectile query surface.

`ArenaPresenter` owns the static arena pass: it pulls a validated read-only
frame and presentation dependencies and draws backdrop, authored ground, room
concept, decals and structure shadows. `ArenaCombatPresenter` owns read-only
combat overlays: boundary guides, telegraphs, hazards, projectiles, transient
feedback, target markers and status marks. `ArenaActorPresenter` owns actor
shadows, sprite placement, boss parts and the shared actor occlusion prepass.
`CombatPresentationController` owns animation, feedback, HUD, frame building
and commit; it applies one gameplay transform and submits independent
actor/part views to `WorldPresenter.SortRoot` at the same z index as native
art. Leaving or unloading releases these views and rejects stale frame
commits. Neither presenter writes gameplay state.

Missing required art is a load error. Collision rectangles and debug geometry
are diagnostic layers only and never production actor fallbacks.

Boss projectile contacts query actual circle hurtboxes, stably sort
candidates and deduplicate by attack instance, logical target and damage
group. Body and hands share health/phase; visual sort feet are independent
from hurtboxes.

## Town chain and bake pipeline

Town uses `BaseHubScreen → TownController → TownRuntime/TownPresenter`. The
controller mounts SceneRuntime and injects its clock and registry; the runtime
owns fixed-tick movement, routes, travel and interaction state. TownPresenter
consumes snapshots and shares SortRoot with native buildings and residents.

The town is modular-only. `content/rooms/town/hearthside.tscn` is the gameplay
and authoring source of truth. Its root, `town_scene_root.gd`, is a
`TownSceneRoot` with `modular_environment_objects = true`: one opaque ground
(`world_expansion_v01/town_ground.png`), opaque bridge decks, and whole
sortable objects from `world_expansion_v01`, `generated_world_v02` and
`town_order_v01`. Each sortable object ships an aligned opaque PNG and a
half-alpha PNG on one canvas and anchor and uses the `paired_reveal` policy;
ground and decks use `reveal_policy = "none"`. There are no roof, trunk or
common-part slices and no static-layer town image chain.

Authoring and baking order:

1. Pack art with the deterministic packers in `tools/art_pipeline/`
   (`generated_world_v02`, `world_expansion_v01`, `town_order_v01`); recipes and
   source provenance live in `docs/art-production/`.
2. Place objects in the scene (`tools/world_manifest/author_town_expansion.py`
   writes the expansion-owned blocks idempotently from the reviewed recipe;
   `author_ground_footprints.py` authors ground-contact footprints).
3. Rebake `content/rooms/town/hearthside.spatial.json` with
   `tools/world_manifest/bake_spatial.gd`, which calls
   `TownSceneRoot.derive_spatial_manifest()`. Production never repairs a stale
   manifest; the runtime compares it with the scene and rejects drift.

Town static author coordinates use the declared 1/64-pixel canonical grid;
per-tick actor positions do not. Unsupported native transforms are rejected
rather than silently dropped.

Still-current authoring rules for environment objects:

- The footprint is the ground-contact body (wall bases, trunks, log bases), not
  the image bounds. Roofs, crowns and shadows never become movement blockers;
  the movement motor adds the hero radius, and the baker adds no second margin.
- A paired part opens while it sorts in front of a protected actor (the player
  or the current conversation resident) and its detection rectangle covers enough
  of that actor's readability box. Detection uses the full-state art box only;
  the controller outputs a transition weight between the opaque and half-alpha
  states and never feeds it back into detection, so a revealed object cannot
  flip itself closed.
- Every sortable part enters one SortRoot at mount with the same
  `(baseline, rank, binding_id)` tuple in drawing and in the occlusion plan.
- `TownRuntime.restore_travel()` rejects a saved position that now lies inside a
  blocker instead of relocating it; a layout change that moves facilities needs
  an explicit migration boundary.

## Evidence discipline

Each integration slice has a headless deterministic test before the next is
integrated. The delivery gate is `build.sh` (tests, 600/600 victory
matrix, export, Linux empty-directory smoke) plus real-machine GPU acceptance
recorded under `docs/playtest/`. Focused domain tests or an isolated
SceneRuntime stress harness do not prove the complete game flow.
