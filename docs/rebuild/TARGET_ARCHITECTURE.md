# Make It Big target runtime architecture

This is the target architecture for the clean rebuild. The rebuild is allowed
to replace existing runtime paths and does not carry compatibility adapters.

## Runtime graph

```text
Native world and content definitions
    -> WorldAssetBaker
    -> immutable WorldAsset
        -> static spatial indexes, navigation graph, vision/projectile data,
           occlusion data, sockets, gameplay/presentation digests
    -> GameApplication
        -> RoomRuntime
            -> SimulationKernel
            -> EntityStore
            -> DynamicSpatialIndex
            -> MovementResolver
            -> ContinuousHitResolver
            -> VisionResolver
            -> RoomEncounter
            -> DamageResolution
            -> StatusEffectLedger
            -> DeathSettlement
            -> CombatRoomLoot
        -> detached AuthoritativeSnapshot
            -> PresentationFrame
                -> OcclusionPresentationController
```

The runtime has no generic event bus, global gameplay singleton, SceneTree
lookup in simulation code, or string-keyed callback ABI. Domain boundaries use
typed records and fixed ports. A general ECS is unnecessary; typed stores plus
stable spatial indexes provide the required data locality without erasing
ownership.

## Spatial truth

`WorldAsset` owns immutable authored data. `SpatialOverlay` owns runtime state
for doors, gates and destructible geometry and produces a new effective query
revision at a tick boundary. The baked asset is never mutated.

Static and dynamic indexes are separate:

- `StaticSpatialIndex` contains authored convex geometry and is indexed per
  semantic channel.
- `DynamicSpatialIndex` contains committed Actor bodies, Hurtboxes, projectiles
  and other runtime shapes. Its buckets are rebuilt or updated at the movement
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
`attack` and `hurtbox` are live production channels (authored combat
static blockers publish `movement` plus `projectile`). The `navigation`
graph API, `VisionResolver` integration and runtime `SpatialOverlay`
producers are intentionally deferred for chapter 1: no encounter consumes
them yet, and they must not be wired without a gameplay slice that does.
The presentation-side occlusion channel stays art-box driven and never
enters this spatial index as a gameplay surface.

`ContinuousHitResolver` can query static and dynamic indexes together. It
returns ordered contacts with `toi`, normal, surface/entity identity, channel
and response material. It never applies damage. An opaque world blocker wins a
tie with a target at the same `toi`; penetration and multi-hit behavior belong
to the attack definition.

`MovementResolver` is the only authority that commits an Actor position. It
supports `solid`, `soft` and `ghost` dynamic body policies. Soft separation is
the default for the first-person player/enemy crowd model; every separation
displacement is still validated by the static movement query.

## Fixed-tick pipeline

Every room uses the same code-defined order:

1. begin tick and apply the previous structural commit;
2. build a read-only tick view;
3. collect player, AI and encounter intents;
4. commit actions, casts, projectiles and hazards;
5. resolve movement and dynamic contact;
6. refresh the dynamic spatial index from committed poses;
7. advance projectiles, attacks and hazards and fill `HitBuffer`;
8. sort and resolve damage, status applications and periodic effects;
9. mark deaths and produce settlement, loot and encounter commands;
10. commit spawns, removals, overlays and terminal state;
11. publish an authoritative snapshot.

The scheduler is fixed and explicit rather than configurable. Structural
changes never remove an entity in the middle of a query phase. Every entity
reference contains a generation and room revision; stale references fail
closed. A per-room `StableEntityKey` is monotonic and never reused.

## Combat ownership

`RoomEncounter` owns waves, spawn requests, active member accounting, clear
conditions and room terminal state. It does not instantiate Nodes or directly
delete combatants.

`CombatHazard` owns shape, lifetime, faction, periodic cadence and per-target
hit suppression. It emits `CombatHitRecord` values only.

`DamageResolution` is the only damage authority. It consumes ordered hit
records, resolved combat stats and resistances, then emits damage, status and
death results. It does not query the scene or decide room victory.

`StatusEffectLedger` owns effect instances, stacking, refresh, expiry and
periodic damage requests. `DeathSettlement` converts a death exactly once into
loot, encounter and removal requests. `CombatRoomLoot` owns room item state,
placement validation, pickup and settlement; loot never becomes a movement
blocker.

The death boundary is keyed by the never-reused `StableEntityKey`. A death
request carries the room revision, committed tick, source and spawn identity,
feet position, archetype and drop tags. `DeathSettlement` emits detached
removal, encounter-death and optional loot-spawn requests; repeating the same
stable key returns the original receipt and cannot enqueue another structural
change or drop. It never rolls an item and never calls `RoomEncounter`.

`CombatRoomLoot` receives those spawn requests through a fixed port. Authored
slots are normalized and sorted by slot ID, placement is checked through the
room's movement/spatial query port, and item generation receives the room loot
seed plus a stable slot stream key. Pickup is submitted as a command and
committed on a later tick after an alive/range/room-phase check. Victory changes
available items to `left_in_room` and picked items to settlement items; defeat
changes both to `forfeited_by_defeat`. Settlement is cached and returned
verbatim on repeat, with no inventory write inside the room domain.

## Presentation and occlusion

The presentation frame contains detached actor poses, feet anchors, baseline,
rank, stable key and actual art boxes. `OcclusionPresentationController`
calculates local cutaway and high-refresh alpha transitions from that frame.
Presentation interpolation, alpha and Y-sort never enter the authoritative
hash and never feed back into movement, vision or combat.

`PresentationFrame` is the only adapter from an authoritative snapshot to
occlusion data. It rejects an entry without a real art box and rejects
collision/debug geometry as an implicit visual source. `OcclusionPlan` orders
the frame by baseline, rank and stable key, reports front art-box coverage, and
the controller interpolates only detached display feet and alpha. The plan and
controller expose no movement, vision or projectile query surface.

Missing required art is a load error. Collision rectangles and debug geometry
are diagnostic layers only and are never production actor fallbacks.

## Initial vertical slices

The implementation order is:

1. spatial contracts and four pure geometry samples;
2. fixed-tick kernel, entity handles and structural buffers;
3. static/dynamic continuous hit resolution;
4. damage, status, death, loot and encounter domains;
5. native WorldAsset baking and room mounting;
6. detached presentation and occlusion;
7. authored multi-wave room and real-device acceptance.

Each slice must have a headless deterministic test before the next slice is
integrated. The final gate is a clean-room room run with recorded input,
stable per-tick state hashes, native GPU rendering and a real input device.
