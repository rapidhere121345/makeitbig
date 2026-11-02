# Room Session Design (redesign Step 2-4)

Status: reviewed by the owner on 2026-11-02 (decisions below). Not implemented yet.

## Problem

A combat room has no single owner. `MainArena` (`src/game/main.gd`, a
`Node2D` of about 1300 lines) is the script on every combat room scene and at
the same time:

- owns the authoritative room state (player state and rules, `CombatSystem`,
  `EncounterDirector`, hazards, loot, terminal state, kernel bindings);
- runs the tick (`_process` -> `_simulate_tick` -> `CombatSimulation.step()`);
- owns presentation (`PresentationController`, `CombatInputAdapter`) and lets it
  leak into the tick: command collection reads the input adapter, feedback is
  written from authority, `gameplay_snapshot()` mixes authority and
  presentation geometry;
- is the de facto test fixture (28 test files, 2 subclass it).

Eight helpers in `src/game/combat_room/` and six adapters in `src/game/ports/`
hold `_main: MainArena` and reach into about 150 of its private members plus
about 400 public ones. `CombatRoomRuntime` drives `MainArena` through string
`get`/`set`/`call`. The player is hard-wired as the Ranger in about 70 files,
while the two planned classes are very different (melee, summoner).

## Goals and non-goals

- One owner of room authority that runs without a scene tree.
- Presentation reads authority and submits commands; it never writes
  authority and is never read during a tick.
- A player-class seam general enough for a projectile class (Ranger), a melee
  class (attack shapes, no projectiles) and a summoner (owned allied entities).
- Behavior freeze: every commit keeps the golden replay hash (`c7353c04...` at
  30/60/144 Hz and presentation-off) and the 600-room encounter matrix.
- Non-goals: no new class, enemy or rule in this step; `SimKernel`, the spatial
  indexes, `ActorRegistry`, damage/death/loot domains and `RoomEncounter` stay
  as they are (they are already clean and class-agnostic).

## Target components

```text
CombatRoomRuntime (Node)  validates config, mounts SceneRuntime, owns the session
 ├─ RoomSession (RefCounted, no Node)        room authority
 │   ├─ CombatSimulation (phase order, unchanged)
 │   ├─ ClassKit (Ranger now; melee/summoner later)
 │   │    player state + rules + combat resolution + flights + hash slice
 │   ├─ EncounterDirector, hazard domain, CombatRoomLoot, CombatRoomRules
 │   ├─ KernelBindings (boss domain, arrow/boss flights, stable keys, cursors)
 │   └─ event log (feedback, impact traces, corpses) drained after step()
 └─ RoomView (Node, the room scene script; today's MainArena shrinks into it)
     PresentationController, CombatInputAdapter, gameplay_snapshot projection
```

`RoomSession` API (typed, no string dispatch):

- `step(commands: Array) -> void` runs exactly one fixed tick;
- `snapshot() -> SimSnapshot`-style read model and `state_hash() -> String`
  (built by the unchanged `CombatStateSnapshotBuilder` over the session);
- `drain_events() -> Array` presentation events produced by the last ticks;
- `terminal() -> Dictionary` / `result()` for `CombatRoomRuntime`.

`RoomView` per frame: collect input into commands, call `session.step()` for
each due tick, drain events into feedback, build the presentation frame from
the snapshot. In presentation-off replays there is no view; the session runs
alone, which makes the existing presentation-off hash check a real boundary
test.

## ClassKit

A kit is the only place a player class lives. Interface (RefCounted):

| Member | Ranger today | Melee | Summoner |
| --- | --- | --- | --- |
| `actor_spec()` id, radius, collision class | ranger body | same shape | same + summon specs |
| `command_schema()` abilities and inputs | piercing arrow, hunter mark, dash, dodge | strikes, guard | commands to summons |
| `build_state(locked_build)` | PlayerCombatState + PiercingArrowModel | own state | own state |
| `advance(tick, routed_commands, targets) -> events` | PlayerCombatRules | own rules | own rules |
| `resolve_combat(tick, kernel_contacts)` | CombatSystem projectile lifecycle | CombatQuery attack shapes | delegates to summons |
| `flight_submitters()` | RangerArrowFlight | none | maybe summon projectiles |
| `summon_effects()` | none | none | light summons (see below) |
| `movement_policy(actor_id)` | ranger dash/dodge policies | own | own + summon AI |
| `hash_slice()` | `locked_p`, `payload_milli`, ... (identical keys) | own | own |
| view side: `animation_set()`, `hud_spec()`, input bindings | RangerAnimation, skill cells | own | own |

Summons are light effects, not kernel entities: a summon is a kit-owned,
time-limited effect with a position, a presentation and a damage or control
action that the kit resolves through the same combat queries as a player
attack. Enemies do not target summons, so `EncounterDirector` keeps assuming
"AI actor == enemy" and needs no faction model.

Commands are extensible per kit: the shared protocol keeps movement, dodge and
pickup, and each kit declares its own command kinds in `command_schema()`
(for example charge-and-release or combo inputs for the melee class). Input
mapping and the HUD come from the kit's view side.

A kit has a progression half next to its combat half: talents, growth model and
locked-build resolution differ per class. That half plugs into
`ApplicationState` and the build resolver (outside the room); the room only
receives the resolved, locked build. Today's Ranger talents and
`PiercingArrowModel` become the Ranger kit's progression half.

The Ranger kit wraps today's code verbatim; the literal `"ranger"` actor id
becomes `kit.actor_spec().id`.

## Migration (each line is one or a few commits, hash unchanged)

1. Delete evidence-only fields (`kernel_snapshot_publications`,
   `kernel_reconcile_events`, the Main-side `last_kernel_snapshot`): no readers.
2. Replace the private reach-ins from `combat_room/` and `ports/` with typed
   owner APIs per helper (`LootPort`, `GeometryPort`, `KernelBindings`,
   `RoomClock`); the ratchet drops toward zero.
3. Introduce `RoomSession` as a pure move of the authority fields and helpers;
   `MainArena` keeps the same property names as getters so the hash builder and
   tests are untouched.
4. Move `CombatSimulation` and the phase domain into the session.
5. Cut presentation out of the tick: commands come from a source the view hands
   in; feedback/impact/corpse calls become session events drained by the view;
   `gameplay_snapshot` moves to the view.
6. Extract `RoomView`; `MainArena` becomes the view script plus compatibility
   getters. `CombatRoomRuntime` talks to `session` with typed calls.
7. Introduce `ClassKit` with `RangerKit` as a wrapper; keep identical hash keys.
8. Move tests from `MainArena` privates (`_simulate_tick`, `_semantic_state_hash`,
   `_arena_rect`, `_enemy_by_entity_id`, ...) to the session, then delete the
   compatibility getters.
9. Split `EncounterDirector` into per-archetype behaviors (melee, charger,
   ranged, boss) behind one interface (Step 4 of the redesign).

The enemy records (`CombatEnemyState`) stay the session's own authoritative
records for now; turning them into views over `SimEntityStore` is a later,
separate decision because the hash builder reads them.

## Risks and verification

- Steps 3-4 (field move, tick order): context pushes depend on call order.
  Verify with the four replay hashes, the phase-trace tests and the matrix.
- Step 5 (presentation extraction): the presentation event cursor must read
  the same stream position. The presentation-off replay and
  `test_combat_presentation_boundary` / `test_main_presentation_closeout`
  catch a missed dependency.
- Step 7: `hash_slice()` must produce identical keys and values.
- Test migration is roughly a third of the work (167 `arena.enemies`, 161
  `arena.sim_tick`, 34 `_semantic_state_hash`, ...). A facade keeps them
  passing until step 8 moves them.

## Owner decisions (2026-11-02)

1. Summons are light kit-owned effects, not full kernel entities.
2. The melee class may introduce new command kinds; the command protocol is
   extensible per kit.
3. Per-class progression differs as much as combat; ClassKit has a progression
   half that plugs into `ApplicationState` and the build resolver.
